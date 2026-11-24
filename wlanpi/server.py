#!/usr/bin/env python3
"""
WLAN Pi Hybrid Dual-Radio RF Survey Server (Cisco Prime 2D / DNA 3D + AP Deep Inspector + Client Vendor Tracker)
Zero-dependency Python 3 server providing:
  - Radio 1 (wlan0): Continuous dual-band (2.4 / 5 / 6 GHz) `iw scan -u` + Deep Beacon IE Inspector:
      Vendor (OUI + sibling BSSID match), Model (WPS/Cisco IE), Streams (NxN), Max PHY Mbps,
      802.11k / 802.11v / 802.11r, PMF (802.11w), BSS Color, Basic Rates, DTIM, Beacon Interval,
      Country, Physical AP Multi-SSID Grouping, CCI/ACI Audit Warnings, QBSS Load & Station Count
  - Radio 2 (Monitor-capable USB radio, auto-hotplug detected): True Monitor Mode raw Radiotap + 802.11
      sniffer -> Per-Channel & Per-BSSID Retry %, Frame Rates, AND Live Client Table (MAC, Vendor OUI,
      Randomized MAC detection, Data vs Probe classification, RSSI, Associated AP)
  - REST API (/api/health, /api/scan, /api/monitor, /api/surveys) + SSE (/api/stream)
"""

import collections
import json
import os
import re
import socket
import struct
import subprocess
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

PORT = int(os.environ.get("SURVEY_PORT", "8090"))
SCAN_IFACE_ENV = os.environ.get("SURVEY_SCAN_IFACE", "")
MON_IFACE_ENV = os.environ.get("SURVEY_MON_IFACE", "")
SCAN_INTERVAL_SEC = float(os.environ.get("SURVEY_INTERVAL", "0.5"))
DATA_DIR = Path(os.environ.get("SURVEY_DATA_DIR", "/var/lib/wifi-survey/sessions"))
STATIC_DIR = Path(__file__).resolve().parent
IW_BIN = "/usr/sbin/iw" if os.path.exists("/usr/sbin/iw") else "iw"

RADIOTAP_FIELDS = [
    (0, 8, 8),   # TSFT
    (1, 1, 1),   # Flags
    (2, 1, 1),   # Rate
    (3, 2, 4),   # Channel (freq, flags)
    (4, 2, 2),   # FHSS
    (5, 1, 1),   # dBm Antenna Signal
    (6, 1, 1),   # dBm Antenna Noise
]


def load_oui_db() -> dict[str, str]:
    db: dict[str, str] = {}
    nmap_path = Path("/usr/share/nmap/nmap-mac-prefixes")
    if nmap_path.exists():
        try:
            for line in nmap_path.read_text(encoding="utf-8", errors="ignore").splitlines():
                if not line or line.startswith("#") or len(line) < 8:
                    continue
                parts = line.split(None, 1)
                if len(parts) == 2 and len(parts[0]) == 6:
                    db[parts[0].upper()] = parts[1].strip()
        except Exception:
            pass
    if not db:
        oui_path = Path("/usr/share/ieee-data/oui.txt")
        if oui_path.exists():
            try:
                for line in oui_path.read_text(encoding="utf-8", errors="ignore").splitlines():
                    if "(base 16)" in line:
                        parts = line.split("(base 16)", 1)
                        k = parts[0].strip().upper()
                        if len(k) == 6:
                            db[k] = parts[1].strip()
            except Exception:
                pass
    return db


OUI_DB = load_oui_db()


def shorten_vendor(name: str) -> str:
    n = name.strip()
    low = n.lower()
    for short, keys in [
        ("Cisco Meraki", ("meraki",)),
        ("Cisco", ("cisco",)),
        ("Huawei", ("huawei",)),
        ("Aruba (HPE)", ("aruba", "hewlett packard enterprise")),
        ("Ubiquiti", ("ubiquiti",)),
        ("TP-Link", ("tp-link",)),
        ("Ruckus", ("ruckus",)),
        ("Juniper Mist", ("mist systems", "juniper")),
        ("Fortinet", ("fortinet",)),
        ("Ruijie", ("ruijie",)),
        ("MikroTik", ("routerboard", "mikrotik")),
        ("Extreme", ("extreme networks", "aerohive")),
        ("ASUS", ("asustek",)),
        ("Netgear", ("netgear",)),
        ("D-Link", ("d-link",)),
        ("Apple", ("apple",)),
        ("Samsung", ("samsung",)),
        ("Intel", ("intel corporate", "intel corp")),
        ("Xiaomi", ("xiaomi",)),
        ("OPPO", ("oppo",)),
        ("Vivo", ("vivo",)),
        ("Google", ("google",)),
        ("Espressif (IoT)", ("espressif",)),
        ("Raspberry Pi", ("raspberry pi",)),
        ("Brother", ("brother",)),
        ("HP", ("hp inc", "hewlett-packard")),
        ("Dell", ("dell",)),
        ("Lenovo", ("lenovo",)),
        ("MediaTek", ("mediatek",)),
        ("Qualcomm", ("qualcomm",)),
        ("Realtek", ("realtek",)),
        ("Broadcom", ("broadcom",)),
    ]:
        if any(k in low for k in keys):
            return short
    return n[:24]


def is_laa_mac(mac: str) -> bool:
    try:
        return (int(mac.replace(":", "")[:2], 16) & 0x02) != 0
    except Exception:
        return False


def lookup_vendor_strict(bssid: str) -> str | None:
    """Strict OUI lookup (exact match or clear ONLY IEEE LAA bit 0x02 — zero random XOR false positives!)."""
    clean = bssid.replace(":", "").upper()
    if len(clean) < 6:
        return None
    prefix = clean[:6]
    if prefix in OUI_DB:
        return shorten_vendor(OUI_DB[prefix])
    try:
        b0 = int(prefix[:2], 16)
        if b0 & 0x02:
            un_laa = f"{b0 & 0xFC:02X}{prefix[2:6]}"
            if un_laa in OUI_DB:
                return shorten_vendor(OUI_DB[un_laa])
    except ValueError:
        pass
    return None


def lookup_client_vendor(mac: str) -> tuple[str, bool]:
    """Identify client device manufacturer from MAC OUI, flagging Randomized/Private MACs cleanly."""
    clean = mac.replace(":", "").upper()
    if len(clean) < 6:
        return "Unknown", False
    prefix = clean[:6]
    if prefix in OUI_DB:
        return shorten_vendor(OUI_DB[prefix]), False
    if is_laa_mac(mac):
        return "Private / Random MAC (iOS/Android/Win)", True
    return "Unknown Vendor", False


def calc_max_phy_mbps(wifi_gen: str, width_mhz: int, nss: int) -> int | None:
    if nss <= 0:
        nss = 1
    w = width_mhz if width_mhz in (20, 40, 80, 160, 320) else 20
    table = {
        "Legacy":   {20: 54.0},
        "Wi-Fi 4":  {20: 72.2,  40: 150.0},
        "Wi-Fi 5":  {20: 86.7,  40: 200.0, 80: 433.3, 160: 866.7},
        "Wi-Fi 6":  {20: 143.4, 40: 286.8, 80: 600.5, 160: 1201.0},
        "Wi-Fi 6E": {20: 143.4, 40: 286.8, 80: 600.5, 160: 1201.0},
        "Wi-Fi 7":  {20: 172.1, 40: 344.1, 80: 720.6, 160: 1441.2, 320: 2882.4},
    }
    row = table.get(wifi_gen)
    if not row:
        return None
    per_ss = row.get(w) or row.get(max(k for k in row if k <= w), 54.0)
    return int(round(per_ss * nss))


def freq_to_channel(freq_mhz: int) -> tuple[str, int]:
    if 2412 <= freq_mhz <= 2472:
        return "2.4GHz", (freq_mhz - 2407) // 5
    if freq_mhz == 2484:
        return "2.4GHz", 14
    if 5000 <= freq_mhz <= 5895:
        return "5GHz", (freq_mhz - 5000) // 5
    if 5955 <= freq_mhz <= 7115:
        return "6GHz", (freq_mhz - 5950) // 5
    if freq_mhz == 5935:
        return "6GHz", 2
    return "Unknown", 0


def format_mac(b: bytes) -> str:
    return ":".join(f"{x:02x}" for x in b)


def is_unicast_mac(b: bytes) -> bool:
    return len(b) == 6 and (b[0] & 1) == 0 and b != b"\x00\x00\x00\x00\x00\x00"


def parse_radiotap_and_80211(pkt: bytes) -> dict | None:
    if len(pkt) < 12:
        return None
    ver, _pad, rt_len, present = struct.unpack_from("<BBHI", pkt, 0)
    if ver != 0 or rt_len < 8 or rt_len + 2 > len(pkt):
        return None

    off = 8
    first_present = present
    cur_present = present
    while cur_present & 0x80000000:
        if off + 4 > rt_len:
            return None
        cur_present = struct.unpack_from("<I", pkt, off)[0]
        off += 4

    freq_mhz = 0
    rssi_dbm = None
    noise_dbm = None

    for bit, align, size in RADIOTAP_FIELDS:
        if first_present & (1 << bit):
            rem = off % align
            if rem:
                off += align - rem
            if off + size > rt_len:
                break
            if bit == 3:
                freq_mhz = struct.unpack_from("<H", pkt, off)[0]
            elif bit == 5:
                rssi_dbm = struct.unpack_from("<b", pkt, off)[0]
            elif bit == 6:
                noise_dbm = struct.unpack_from("<b", pkt, off)[0]
            off += size

    dot11 = pkt[rt_len:]
    if len(dot11) < 10:
        return None
    fc = struct.unpack_from("<H", dot11, 0)[0]
    ftype = (fc >> 2) & 0x3
    subtype = (fc >> 4) & 0xF
    to_ds = (fc >> 8) & 1
    from_ds = (fc >> 9) & 1
    retry = bool((fc >> 11) & 1)

    bssid = None
    client = None
    is_probe_req = (ftype == 0 and subtype == 4)

    if len(dot11) >= 24 and ftype in (0, 2):
        a1, a2, a3 = dot11[4:10], dot11[10:16], dot11[16:22]
        if ftype == 0:
            if is_unicast_mac(a3):
                bssid = format_mac(a3)
            if is_probe_req and is_unicast_mac(a2):
                client = format_mac(a2)
        elif ftype == 2:
            if to_ds == 0 and from_ds == 1:
                if is_unicast_mac(a2): bssid = format_mac(a2)
                if is_unicast_mac(a1): client = format_mac(a1)
            elif to_ds == 1 and from_ds == 0:
                if is_unicast_mac(a1): bssid = format_mac(a1)
                if is_unicast_mac(a2): client = format_mac(a2)
            elif to_ds == 0 and from_ds == 0:
                if is_unicast_mac(a3): bssid = format_mac(a3)

    return {
        "freq_mhz": freq_mhz, "rssi_dbm": rssi_dbm, "noise_dbm": noise_dbm,
        "ftype": ftype, "subtype": subtype, "retry": retry,
        "bssid": bssid, "client": client, "is_probe_req": is_probe_req,
    }


def unescape_iw_ssid(raw: str) -> str:
    if "\\x" not in raw:
        return raw.strip()
    out = bytearray()
    i = 0
    while i < len(raw):
        if raw[i : i + 2] == "\\x" and i + 4 <= len(raw):
            try:
                out.append(int(raw[i + 2 : i + 4], 16))
                i += 4
                continue
            except ValueError:
                pass
        out.extend(raw[i].encode("utf-8", errors="ignore"))
        i += 1
    try:
        return out.decode("utf-8", errors="replace").replace("\x00", "").strip()
    except Exception:
        return raw.strip()


def parse_cisco_aironet_name(hex_str: str) -> str | None:
    try:
        raw = bytes.fromhex(hex_str.replace(" ", ""))
        if len(raw) >= 12:
            chunk = raw[10:26].split(b"\x00", 1)[0]
            txt = chunk.decode("ascii", errors="ignore").strip()
            if len(txt) >= 2 and all(32 <= ord(c) < 127 for c in txt):
                return txt
    except Exception:
        pass
    return None


def parse_iw_scan(output: str) -> list[dict]:
    aps: list[dict] = []
    cur: dict | None = None
    section = ""
    has_ht = has_vht = has_he = has_eht = False
    rsn_auth: set[str] = set()
    rsn_ciphers: set[str] = set()
    has_rsn = has_wpa = has_privacy = False
    ht_width = 20
    vht_width = he_width = eht_width = 0
    sec_offset = ""
    max_nss = 0
    wps_mfr = wps_model = wps_dev = ap_name = ""
    dot11k = dot11v = dot11r = False
    pmf = "Disabled"
    bss_color: int | None = None
    basic_rates: list[float] = []
    all_rates: list[float] = []
    beacon_tus: int | None = None
    dtim_period: int | None = None
    country = ""

    def finalize():
        nonlocal cur
        if not cur:
            return
        freq = cur.get("freq_mhz", 0)
        band, derived_ch = freq_to_channel(freq)
        cur["band"] = band
        if not cur.get("channel") and derived_ch:
            cur["channel"] = derived_ch

        width = 20
        if eht_width: width = eht_width
        elif he_width: width = he_width
        elif vht_width: width = vht_width
        elif ht_width == 40 or sec_offset in ("above", "below"): width = 40
        cur["width_mhz"] = width

        if has_eht: gen = "Wi-Fi 7"
        elif has_he: gen = "Wi-Fi 6E" if band == "6GHz" else "Wi-Fi 6"
        elif has_vht: gen = "Wi-Fi 5"
        elif has_ht: gen = "Wi-Fi 4"
        else: gen = "Legacy"
        cur["wifi_gen"] = gen

        auth_upper = {a.upper() for a in rsn_auth}
        if any("FT/" in a or a.startswith("FT-") for a in auth_upper):
            cur["dot11r"] = True
        else:
            cur["dot11r"] = dot11r

        if has_rsn:
            has_sae = any("SAE" in a for a in auth_upper)
            has_psk = any("PSK" in a for a in auth_upper)
            has_eap = any("802.1X" in a or "EAP" in a for a in auth_upper)
            has_owe = any("OWE" in a for a in auth_upper)
            if has_sae and has_psk: sec = "WPA2/WPA3"
            elif has_sae: sec = "WPA3-SAE"
            elif has_eap: sec = "WPA2/3-Enterprise"
            elif has_owe: sec = "OWE"
            elif has_psk: sec = "WPA2-PSK"
            else: sec = "WPA2/WPA3"
        elif has_wpa: sec = "WPA"
        elif has_privacy: sec = "WEP"
        else: sec = "Open"
        cur["security"] = sec
        cur["ciphers"] = sorted(rsn_ciphers)
        cur["akm"] = sorted(rsn_auth)
        cur["dot11k"] = dot11k
        cur["dot11v"] = dot11v
        cur["pmf"] = pmf
        cur["bss_color"] = bss_color
        cur["country"] = country
        cur["beacon_interval_ms"] = round(beacon_tus * 1.024, 1) if beacon_tus else None
        cur["dtim_period"] = dtim_period

        br = sorted(set(basic_rates))
        cur["basic_rates_mbps"] = br
        cur["min_basic_rate_mbps"] = br[0] if br else None
        cur["legacy_rates_enabled"] = any(r in (1.0, 2.0, 5.5, 11.0) for r in br)
        cur["max_phy_mbps"] = calc_max_phy_mbps(gen, width, max_nss if max_nss > 0 else 1)

        strict_v = shorten_vendor(wps_mfr) if wps_mfr else lookup_vendor_strict(cur["bssid"])
        cur["vendor"] = strict_v or "Unknown"
        cur["streams"] = f"{max_nss}x{max_nss}" if max_nss > 0 else ""
        cur["_wps_model"] = wps_model
        cur["ap_name"] = ap_name or wps_dev or ""

        # Physical AP fingerprint: middle 4 bytes of BSSID + band (groups multi-SSID virtual BSSIDs on same physical radio!)
        parts = cur["bssid"].split(":")
        cur["physical_ap_id"] = ":".join(parts[1:5]) + f"@{band}" if len(parts) == 6 else cur["bssid"]

        aps.append(cur)
        cur = None

    bss_re = re.compile(r"^BSS\s+([0-9a-fA-F:]{17})")

    for raw_line in output.splitlines():
        m_bss = bss_re.match(raw_line)
        if m_bss:
            finalize()
            cur = {
                "bssid": m_bss.group(1).lower(),
                "ssid": "",
                "rssi_dbm": -100.0,
                "freq_mhz": 0,
                "band": "Unknown",
                "channel": 0,
                "width_mhz": 20,
                "wifi_gen": "Legacy",
                "security": "Open",
                "vendor": "Unknown",
                "ap_model": "",
                "ap_name": "",
                "streams": "",
                "max_phy_mbps": None,
                "qbss_util_pct": None,
                "qbss_stations": None,
                "tx_power_dbm": None,
                "last_seen_ms": None,
            }
            section = ""
            has_ht = has_vht = has_he = has_eht = False
            rsn_auth = set(); rsn_ciphers = set()
            has_rsn = has_wpa = has_privacy = False
            ht_width = 20; vht_width = he_width = eht_width = 0; sec_offset = ""
            max_nss = 0
            wps_mfr = wps_model = wps_dev = ap_name = ""
            dot11k = dot11v = dot11r = False
            pmf = "Disabled"
            bss_color = None
            basic_rates = []; all_rates = []
            beacon_tus = None; dtim_period = None; country = ""
            continue

        if cur is None:
            continue

        line = raw_line.strip()
        if not line:
            continue

        if raw_line.startswith("\t") and not raw_line.startswith("\t\t") and not raw_line.startswith("\t "):
            if line.startswith("freq:"):
                try: cur["freq_mhz"] = int(float(line.split(":", 1)[1].strip()))
                except ValueError: pass
                section = ""
            elif line.startswith("signal:"):
                try: cur["rssi_dbm"] = round(float(line.split(":", 1)[1].split()[0]), 1)
                except ValueError: pass
                section = ""
            elif line.startswith("SSID:"):
                cur["ssid"] = unescape_iw_ssid(line.split(":", 1)[1].strip())
                section = ""
            elif line.startswith("beacon interval:"):
                m_bi = re.search(r"(\d+)", line)
                if m_bi: beacon_tus = int(m_bi.group(1))
                section = ""
            elif line.startswith("last seen:") and "ms ago" in line:
                m_ms = re.search(r"(\d+)\s*ms ago", line)
                if m_ms: cur["last_seen_ms"] = int(m_ms.group(1))
                section = ""
            elif line.startswith("capability:"):
                if "Privacy" in line: has_privacy = True
                if "RadioMeasure" in line: dot11k = True
                section = ""
            elif line.startswith("Supported rates:") or line.startswith("Extended supported rates:"):
                for tok in line.split(":", 1)[1].split():
                    is_basic = tok.endswith("*")
                    try:
                        val = float(tok.rstrip("*"))
                        all_rates.append(val)
                        if is_basic: basic_rates.append(val)
                    except ValueError:
                        pass
                section = ""
            elif line.startswith("TIM:"):
                m_dt = re.search(r"DTIM Period\s+(\d+)", line)
                if m_dt: dtim_period = int(m_dt.group(1))
                section = ""
            elif line.startswith("Country:"):
                parts = line.split(":", 1)[1].strip().split()
                if parts: country = parts[0]
                section = ""
            elif line.startswith("DS Parameter set: channel"):
                m_ch = re.search(r"channel\s+(\d+)", line)
                if m_ch: cur["channel"] = int(m_ch.group(1))
                section = ""
            elif line.startswith("TPC report:"):
                m_tx = re.search(r"TX power:\s*(-?\d+)", line)
                if m_tx: cur["tx_power_dbm"] = int(m_tx.group(1))
                section = ""
            elif line.startswith("RM enabled capabilities:"):
                dot11k = True; section = ""
            elif line.startswith("Mobility Domain:") or line.startswith("MDIE:"):
                dot11r = True; section = ""
            elif line.startswith("Extended capabilities:"):
                section = "EXT_CAP"
            elif line.startswith("Unknown IE (133):"):
                parsed_name = parse_cisco_aironet_name(line.split(":", 1)[1].strip())
                if parsed_name: ap_name = parsed_name
                section = ""
            elif line.startswith("RSN:"):
                has_rsn = True; section = "RSN"
            elif line.startswith("WPA:"):
                has_wpa = True; section = "WPA"
            elif line.startswith("WPS:"):
                section = "WPS"
            elif line.startswith("HT capabilities:"):
                has_ht = True; section = "HT_CAP"
            elif line.startswith("HT operation:"):
                has_ht = True; section = "HT_OP"
            elif line.startswith("VHT capabilities:") or line.startswith("VHT operation:"):
                has_vht = True; section = "VHT_OP" if "operation" in line else "VHT_CAP"
            elif line.startswith("HE capabilities:") or line.startswith("HE Operation:") or line.startswith("HE operation:"):
                has_he = True; section = "HE_OP" if "peration" in line else "HE_CAP"
            elif line.startswith("EHT capabilities:") or line.startswith("EHT Operation:") or line.startswith("EHT operation:"):
                has_eht = True; section = "EHT_OP" if "peration" in line else "EHT_CAP"
            elif line.startswith("BSS Load:"):
                section = "BSS_LOAD"
            else:
                section = ""
            continue

        if section == "RSN":
            if "Authentication suites:" in line:
                rsn_auth.update(line.split(":", 1)[1].strip().split())
            elif "Pairwise ciphers:" in line:
                rsn_ciphers.update(line.split(":", 1)[1].strip().split())
            elif "Capabilities:" in line:
                if "MFP-required" in line: pmf = "Required"
                elif "MFP-capable" in line and pmf != "Required": pmf = "Capable"
        elif section == "EXT_CAP":
            if "BSS Transition" in line:
                dot11v = True
        elif section == "WPS":
            if "Manufacturer:" in line: wps_mfr = line.split("Manufacturer:", 1)[1].strip()
            elif "Model Number:" in line and not wps_model: wps_model = line.split("Model Number:", 1)[1].strip()
            elif "Model:" in line and "Number" not in line: wps_model = line.split("Model:", 1)[1].strip()
            elif "Device name:" in line: wps_dev = line.split("Device name:", 1)[1].strip()
        elif section == "HT_CAP":
            if "HT RX MCS rate indexes supported:" in line:
                nums = [int(x) for x in re.findall(r"\d+", line) if int(x) < 32]
                if nums: max_nss = max(max_nss, (max(nums) // 8) + 1)
        elif section == "HT_OP":
            if "primary channel:" in line:
                m = re.search(r"primary channel:\s*(\d+)", line)
                if m: cur["channel"] = int(m.group(1))
            elif "secondary channel offset:" in line:
                val = line.split(":", 1)[1].strip().lower()
                if "above" in val: sec_offset = "above"
                elif "below" in val: sec_offset = "below"
            elif "STA channel width:" in line and "any" in line.lower():
                ht_width = 40
        elif section == "VHT_CAP":
            m_st = re.search(r"(\d+)\s+streams:\s*MCS\s+0-", line)
            if m_st: max_nss = max(max_nss, int(m_st.group(1)))
        elif section == "VHT_OP":
            if "channel width:" in line:
                m = re.search(r"channel width:\s*(\d+)", line)
                if m:
                    code = int(m.group(1))
                    if code == 1: vht_width = 80
                    elif code in (2, 3): vht_width = 160
        elif section == "HE_CAP":
            m_st = re.search(r"(\d+)\s+streams:\s*MCS\s+0-", line)
            if m_st: max_nss = max(max_nss, int(m_st.group(1)))
        elif section == "HE_OP":
            if "BSS Color:" in line:
                m_bc = re.search(r"BSS Color:\s*(\d+)", line)
                if m_bc: bss_color = int(m_bc.group(1))
            if "320 MHz" in line: he_width = 320
            elif "160 MHz" in line: he_width = 160
            elif "80 MHz" in line: he_width = max(he_width, 80)
            elif "40 MHz" in line: he_width = max(he_width, 40)
        elif section == "EHT_OP":
            if "320 MHz" in line: eht_width = 320
            elif "160 MHz" in line: eht_width = max(eht_width, 160)
            elif "80 MHz" in line: eht_width = max(eht_width, 80)
        elif section == "BSS_LOAD":
            if "station count:" in line:
                m = re.search(r"station count:\s*(\d+)", line)
                if m: cur["qbss_stations"] = int(m.group(1))
            elif "channel utilisation:" in line or "channel utilization:" in line:
                m = re.search(r"(\d+)\s*/\s*255", line)
                if m: cur["qbss_util_pct"] = round(int(m.group(1)) * 100.0 / 255.0, 1)

    finalize()

    # Second pass: Cross-match virtual BSSIDs (e.g. b6:8b:a9:d2:fc:97 -> ac:8b:a9:d2:fc:96 Ubiquiti) by middle 4 MAC bytes!
    mid4_vendor: dict[str, str] = {}
    for ap in aps:
        if ap["vendor"] != "Unknown":
            parts = ap["bssid"].split(":")
            if len(parts) == 6:
                mid4_vendor[":".join(parts[1:5])] = ap["vendor"]

    # Group physical APs & compute CCI (unique physical APs per channel)
    phys_groups: dict[str, list[dict]] = collections.defaultdict(list)
    ch_phys_aps: dict[tuple[str, int], set[str]] = collections.defaultdict(set)
    for ap in aps:
        if ap["vendor"] == "Unknown":
            parts = ap["bssid"].split(":")
            if len(parts) == 6 and ":".join(parts[1:5]) in mid4_vendor:
                ap["vendor"] = mid4_vendor[":".join(parts[1:5])]
        wps_m = ap.pop("_wps_model", "")
        gen = ap["wifi_gen"]
        st = ap["streams"]
        if wps_m:
            ap["ap_model"] = f"{ap['vendor']} {wps_m}".strip() if ap["vendor"].lower() not in wps_m.lower() else wps_m
        else:
            spec = f"{gen} {st}".strip()
            ap["ap_model"] = f"{ap['vendor']} ({spec})" if ap["vendor"] != "Unknown" else spec

        phys_groups[ap["physical_ap_id"]].append(ap)
        ch_phys_aps[(ap["band"], ap["channel"])].add(ap["physical_ap_id"])

    # Populate co-BSSID counts, CCI/ACI, and Ekahau-grade health warnings
    for ap in aps:
        siblings = phys_groups[ap["physical_ap_id"]]
        ap["co_bssid_count"] = len(siblings)
        ap["sibling_ssids"] = [s["ssid"] or "<hidden>" for s in siblings]
        cci = max(0, len(ch_phys_aps[(ap["band"], ap["channel"])]) - 1)
        ap["cci_count"] = cci
        aci = (ap["band"] == "2.4GHz" and ap["channel"] not in (1, 6, 11) and ap["channel"] > 0)
        ap["aci_warning"] = aci

        warns = []
        if ap["band"] == "2.4GHz" and ap["legacy_rates_enabled"]:
            warns.append("Legacy 1/2/5.5/11 Mbps basic rates enabled (high beacon airtime overhead)")
        if aci:
            warns.append(f"Non-standard 2.4GHz Ch {ap['channel']} causes Adjacent-Channel Interference (use Ch 1/6/11)")
        if cci >= 3:
            warns.append(f"Co-Channel congestion: {cci + 1} physical APs sharing Ch {ap['channel']}")
        if ap["co_bssid_count"] >= 4:
            warns.append(f"{ap['co_bssid_count']} SSIDs on same physical radio (beacon overhead)")
        if ap["security"] in ("Open", "WEP", "WPA"):
            warns.append(f"Weak/Legacy security ({ap['security']})")
        ap["health_warnings"] = warns

    aps.sort(key=lambda a: a["rssi_dbm"], reverse=True)
    return aps


def inspect_wifi_radios() -> list[dict]:
    radios = []
    try:
        dev_out = subprocess.run([IW_BIN, "dev"], capture_output=True, text=True, timeout=5).stdout
        list_out = subprocess.run([IW_BIN, "list"], capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return radios

    phy_caps: dict[str, dict] = {}
    cur_phy = None
    in_modes = False
    for line in list_out.splitlines():
        m_phy = re.match(r"^Wiphy\s+(phy\d+)", line)
        if m_phy:
            cur_phy = m_phy.group(1)
            phy_caps[cur_phy] = {"monitor": False, "bands": set(), "channels": []}
            in_modes = False
            continue
        if not cur_phy:
            continue
        if "Supported interface modes:" in line:
            in_modes = True; continue
        if in_modes:
            if line.startswith("\t\t * "):
                if "monitor" in line: phy_caps[cur_phy]["monitor"] = True
            elif not line.startswith("\t\t"):
                in_modes = False
        m_freq = re.search(r"\*\s+(\d+(?:\.\d+)?)\s+MHz\s+\[(\d+)\]", line)
        if m_freq and "(disabled)" not in line:
            f = int(float(m_freq.group(1)))
            ch = int(m_freq.group(2))
            band, _ = freq_to_channel(f)
            if band != "Unknown":
                phy_caps[cur_phy]["bands"].add(band)
                phy_caps[cur_phy]["channels"].append(ch)

    cur_phy = None
    for line in dev_out.splitlines():
        m_p = re.match(r"^phy#(\d+)", line)
        if m_p:
            cur_phy = f"phy{m_p.group(1)}"; continue
        m_i = re.match(r"^\s+Interface\s+(\S+)", line)
        if m_i and cur_phy:
            iface = m_i.group(1)
            caps = phy_caps.get(cur_phy, {"monitor": False, "bands": set(), "channels": []})
            radios.append({
                "iface": iface, "phy": cur_phy, "monitor": caps["monitor"],
                "bands": sorted(caps["bands"]), "channels": sorted(set(caps["channels"])),
            })
    return radios


class MonitorEngine:
    """True Monitor Mode Radiotap + 802.11 sniffer with Auto-Hotplug & Client Vendor Identification."""

    WINDOW_SEC = 10.0
    CLIENT_WINDOW_SEC = 30.0

    def __init__(self):
        self.lock = threading.Lock()
        self.running = True
        self.active = False
        self.interface: str | None = None
        self.scan_iface: str = "wlan0"
        self.channels: list[int] = []
        self.current_channel: int = 0
        self.error: str | None = None
        self.events: collections.deque = collections.deque()
        # Detailed per-client tracking over last 30s
        self.client_records: dict[str, dict] = {}
        self._watch_thread = threading.Thread(target=self._watch_loop, daemon=True)
        self._hop_thread = threading.Thread(target=self._hop_loop, daemon=True)
        self._sniff_thread = threading.Thread(target=self._sniff_loop, daemon=True)

    def start(self, scan_iface: str):
        self.scan_iface = scan_iface
        self._try_attach()
        self._watch_thread.start()
        self._hop_thread.start()
        self._sniff_thread.start()

    def _try_attach(self) -> bool:
        radios = inspect_wifi_radios()
        cand = None
        if MON_IFACE_ENV:
            for r in radios:
                if r["iface"] == MON_IFACE_ENV: cand = r; break
        else:
            for r in radios:
                if r["monitor"] and r["iface"] != self.scan_iface:
                    cand = r; break
        if not cand:
            self.active = False
            self.interface = None
            return False
        iface = cand["iface"]
        ch24 = [c for c in [1, 6, 11, 2, 3, 4, 5, 7, 8, 9, 10, 12, 13] if c in cand["channels"]]
        ch5 = [c for c in cand["channels"] if c >= 36]
        self.channels = ch24 + ch5 if (ch24 or ch5) else [1, 6, 11]
        if self._setup_monitor_mode(iface):
            self.interface = iface
            self.active = True
            print(f"[wifi-survey] Monitor Mode attached on {iface} (channels={len(self.channels)})", flush=True)
            return True
        return False

    def _setup_monitor_mode(self, iface: str) -> bool:
        try:
            subprocess.run(["nmcli", "dev", "set", iface, "managed", "no"], capture_output=True, timeout=5)
        except Exception:
            pass
        try:
            subprocess.run(["ip", "link", "set", iface, "down"], check=True, capture_output=True, timeout=5)
            subprocess.run([IW_BIN, "dev", iface, "set", "monitor", "none"], check=True, capture_output=True, timeout=5)
            subprocess.run(["ip", "link", "set", iface, "up"], check=True, capture_output=True, timeout=5)
            self.error = None
            return True
        except Exception as exc:
            self.error = f"monitor setup failed: {exc}"
            self.active = False
            return False

    def _watch_loop(self):
        """Auto-detect USB monitor adapter plug/unplug dynamically."""
        while self.running:
            if self.active and self.interface:
                if not os.path.exists(f"/sys/class/net/{self.interface}"):
                    print(f"[wifi-survey] Monitor adapter {self.interface} unplugged", flush=True)
                    self.active = False
                    self.interface = None
                    with self.lock:
                        self.events.clear()
                        self.client_records.clear()
            else:
                self._try_attach()
            time.sleep(4.0)

    def _hop_loop(self):
        idx = 0
        while self.running:
            if not (self.active and self.interface and self.channels):
                time.sleep(1.0)
                continue
            ch = self.channels[idx % len(self.channels)]
            idx += 1
            try:
                r = subprocess.run([IW_BIN, "dev", self.interface, "set", "channel", str(ch)], capture_output=True, timeout=3)
                if r.returncode == 0:
                    self.current_channel = ch
            except Exception:
                pass
            time.sleep(0.28 if ch in (1, 6, 11) else 0.14)

    def _sniff_loop(self):
        while self.running:
            if not (self.active and self.interface):
                time.sleep(1.0)
                continue
            iface = self.interface
            sock = None
            try:
                sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x0003))
                sock.bind((iface, 0))
                sock.settimeout(1.0)
                while self.running and self.active and self.interface == iface:
                    try:
                        raw = sock.recv(4096)
                    except socket.timeout:
                        self._prune()
                        continue
                    parsed = parse_radiotap_and_80211(raw)
                    if not parsed:
                        continue
                    now = time.monotonic()
                    ch = freq_to_channel(parsed["freq_mhz"])[1] if parsed["freq_mhz"] else self.current_channel
                    client = parsed["client"]
                    bssid = parsed["bssid"]
                    is_probe = parsed["is_probe_req"]
                    rssi = parsed["rssi_dbm"]
                    retry = parsed["retry"]

                    ev = (now, ch, parsed["ftype"], retry, bssid, client, is_probe, rssi, parsed["noise_dbm"])
                    with self.lock:
                        self.events.append(ev)
                        if len(self.events) > 25000:
                            self.events.popleft()
                        if client:
                            cr = self.client_records.get(client)
                            if cr is None:
                                v_name, is_rand = lookup_client_vendor(client)
                                cr = {
                                    "mac": client,
                                    "vendor": v_name,
                                    "is_random_mac": is_rand,
                                    "type": "Probing" if is_probe else "Associated (Data)",
                                    "bssid": bssid if not is_probe else None,
                                    "channel": ch,
                                    "rssi_dbm": rssi,
                                    "frames": 0,
                                    "retries": 0,
                                    "last_mono": now,
                                }
                                self.client_records[client] = cr
                            cr["frames"] += 1
                            if retry: cr["retries"] += 1
                            cr["last_mono"] = now
                            cr["channel"] = ch
                            if rssi is not None and -110 <= rssi <= 0:
                                cr["rssi_dbm"] = rssi
                            if not is_probe:
                                cr["type"] = "Associated (Data)"
                                if bssid:
                                    cr["bssid"] = bssid
                        self._prune_unlocked(now)
            except Exception as exc:
                self.error = str(exc)
                if not os.path.exists(f"/sys/class/net/{iface}"):
                    self.active = False
                    self.interface = None
                time.sleep(1.5)
            finally:
                if sock:
                    try: sock.close()
                    except Exception: pass

    def _prune_unlocked(self, now: float):
        cutoff = now - self.WINDOW_SEC
        while self.events and self.events[0][0] < cutoff:
            self.events.popleft()
        c_cut = now - self.CLIENT_WINDOW_SEC
        stale = [m for m, cr in self.client_records.items() if cr["last_mono"] < c_cut]
        for m in stale:
            del self.client_records[m]

    def _prune(self):
        with self.lock:
            self._prune_unlocked(time.monotonic())

    def snapshot(self, bssid_to_ssid: dict[str, str] | None = None) -> tuple[dict, dict[str, dict]]:
        self._prune()
        now = time.monotonic()
        with self.lock:
            evs = list(self.events)
            c_list_raw = [dict(v) for v in self.client_records.values()]

        bssid_to_ssid = bssid_to_ssid or {}
        total = len(evs)
        retries = probe_reqs = 0
        data_clients: set[str] = set()
        probe_clients: set[str] = set()
        per_ch: dict[str, dict] = {}
        per_bssid: dict[str, dict] = {}

        for _ts, ch, ftype, retry, bssid, client, is_probe, rssi, noise in evs:
            if retry: retries += 1
            if is_probe: probe_reqs += 1
            if client:
                if is_probe: probe_clients.add(client)
                else: data_clients.add(client)

            ck = str(ch)
            cs = per_ch.get(ck)
            if cs is None:
                cs = {"frames": 0, "retries": 0, "mgmt": 0, "ctrl": 0, "data": 0, "clients": set(), "noise_sum": 0, "noise_cnt": 0}
                per_ch[ck] = cs
            cs["frames"] += 1
            if retry: cs["retries"] += 1
            if ftype == 0: cs["mgmt"] += 1
            elif ftype == 1: cs["ctrl"] += 1
            elif ftype == 2: cs["data"] += 1
            if client: cs["clients"].add(client)
            if noise is not None and -120 <= noise <= -40:
                cs["noise_sum"] += noise; cs["noise_cnt"] += 1

            if bssid:
                bs = per_bssid.get(bssid)
                if bs is None:
                    bs = {"frames": 0, "retries": 0, "clients": set(), "rssi_max": None, "noise_sum": 0, "noise_cnt": 0}
                    per_bssid[bssid] = bs
                bs["frames"] += 1
                if retry: bs["retries"] += 1
                if client and not is_probe: bs["clients"].add(client)
                if rssi is not None and -110 <= rssi <= 0:
                    if bs["rssi_max"] is None or rssi > bs["rssi_max"]:
                        bs["rssi_max"] = rssi
                if noise is not None and -120 <= noise <= -40:
                    bs["noise_sum"] += noise; bs["noise_cnt"] += 1

        # Build detailed client list (with Vendor, Random MAC flag, Connected AP SSID!)
        clients_out = []
        clients_by_bssid: dict[str, list[dict]] = collections.defaultdict(list)
        for cr in c_list_raw:
            f = cr["frames"]
            ap_b = cr.get("bssid")
            item = {
                "mac": cr["mac"],
                "vendor": cr["vendor"],
                "is_random_mac": cr["is_random_mac"],
                "type": cr["type"],
                "bssid": ap_b,
                "ap_ssid": bssid_to_ssid.get(ap_b, "") if ap_b else "",
                "channel": cr["channel"],
                "rssi_dbm": cr["rssi_dbm"],
                "frames": f,
                "retry_pct": round(cr["retries"] * 100.0 / f, 1) if f else 0.0,
                "age_sec": round(max(0.0, now - cr["last_mono"]), 1),
            }
            clients_out.append(item)
            if ap_b:
                clients_by_bssid[ap_b].append(item)
        clients_out.sort(key=lambda c: (c["type"] != "Associated (Data)", -(c["frames"])))

        ch_out = {}
        for ck, cs in sorted(per_ch.items(), key=lambda kv: int(kv[0]) if kv[0].isdigit() else 999):
            f = cs["frames"]
            ch_out[ck] = {
                "frames": f, "retries": cs["retries"],
                "retry_pct": round(cs["retries"] * 100.0 / f, 1) if f else 0.0,
                "mgmt": cs["mgmt"], "ctrl": cs["ctrl"], "data": cs["data"],
                "clients": len(cs["clients"]),
                "noise_dbm": round(cs["noise_sum"] / cs["noise_cnt"], 1) if cs["noise_cnt"] else None,
            }

        bssid_out = {}
        for bssid, bs in per_bssid.items():
            f = bs["frames"]
            noise_avg = round(bs["noise_sum"] / bs["noise_cnt"], 1) if bs["noise_cnt"] else None
            snr = round(bs["rssi_max"] - noise_avg, 1) if (bs["rssi_max"] is not None and noise_avg is not None) else None
            bssid_out[bssid] = {
                "mon_frames": f,
                "mon_retry_pct": round(bs["retries"] * 100.0 / f, 1) if f else 0.0,
                "mon_clients": len(bs["clients"]),
                "mon_client_list": clients_by_bssid.get(bssid, [])[:20],
                "mon_rssi_dbm": bs["rssi_max"],
                "mon_noise_dbm": noise_avg,
                "mon_snr_db": snr,
            }

        summary = {
            "active": self.active,
            "interface": self.interface,
            "mode": "monitor" if self.active else "unplugged",
            "window_sec": self.WINDOW_SEC,
            "client_window_sec": self.CLIENT_WINDOW_SEC,
            "current_channel": self.current_channel,
            "channels": self.channels,
            "total_frames_10s": total,
            "fps": round(total / self.WINDOW_SEC, 1),
            "retry_pct_10s": round(retries * 100.0 / total, 1) if total else 0.0,
            "data_clients_10s": len(data_clients),
            "probe_clients_10s": len(probe_clients),
            "unique_clients_10s": len(data_clients | probe_clients),
            "probe_requests_10s": probe_reqs,
            "per_channel": ch_out,
            "clients": clients_out[:120],
            "error": self.error,
        }
        return summary, bssid_out


class ScannerEngine:
    def __init__(self, monitor: MonitorEngine):
        self.monitor = monitor
        self.lock = threading.Lock()
        self.cond = threading.Condition(self.lock)
        self.running = True
        self.scan_id = 0
        self.radios = inspect_wifi_radios()
        self.interface = self._pick_scan_interface()
        self.regdomain = self._get_regdomain()
        self.last_error: str | None = None
        self.last_scan: dict = {
            "scan_id": 0, "hostname": socket.gethostname(), "interface": self.interface,
            "timestamp_unix": 0.0, "timestamp_iso": "", "scan_duration_ms": 0,
            "ap_count": 0, "qbss_total_clients": 0,
            "band_counts": {"2.4GHz": 0, "5GHz": 0, "6GHz": 0},
            "channel_counts": {}, "strongest_rssi": None, "monitor": {}, "aps": [],
        }
        self._thread = threading.Thread(target=self._loop, daemon=True)

    def _pick_scan_interface(self) -> str:
        if SCAN_IFACE_ENV:
            return SCAN_IFACE_ENV
        if not self.radios:
            return "wlan0"
        best = max(self.radios, key=lambda r: (len(r["bands"]), "6GHz" in r["bands"], "5GHz" in r["bands"], r["iface"]))
        return best["iface"]

    def _get_regdomain(self) -> str:
        try:
            r = subprocess.run([IW_BIN, "reg", "get"], capture_output=True, text=True, timeout=5)
            m = re.search(r"country\s+([A-Z0-9]{2}):", r.stdout)
            return m.group(1) if m else "UNKNOWN"
        except Exception:
            return "UNKNOWN"

    def _ensure_up(self, iface: str):
        try: subprocess.run(["ip", "link", "set", iface, "up"], capture_output=True, timeout=4)
        except Exception: pass

    def start(self):
        try: subprocess.run([IW_BIN, "reg", "set", "TH"], capture_output=True, timeout=4)
        except Exception: pass
        self.regdomain = self._get_regdomain()
        self.radios = inspect_wifi_radios()
        self.interface = self._pick_scan_interface()
        self._ensure_up(self.interface)
        self.monitor.start(self.interface)
        self._thread.start()

    def _loop(self):
        while self.running:
            iface = self.interface
            t0 = time.monotonic()
            try:
                r = subprocess.run([IW_BIN, "dev", iface, "scan", "-u"], capture_output=True, text=True, timeout=12)
                out = r.stdout
                if r.returncode != 0:
                    err = (r.stderr or "").strip()
                    if "Network is down" in err:
                        self._ensure_up(iface); time.sleep(0.5); continue
                    if "Device or resource busy" in err:
                        r2 = subprocess.run([IW_BIN, "dev", iface, "scan", "dump", "-u"], capture_output=True, text=True, timeout=6)
                        out = r2.stdout
                    else:
                        with self.lock: self.last_error = err or f"iw scan rc={r.returncode}"
                        time.sleep(1.5); continue

                duration_ms = int((time.monotonic() - t0) * 1000)
                aps = parse_iw_scan(out)
                fresh_aps = [ap for ap in aps if ap["last_seen_ms"] is None or ap["last_seen_ms"] <= 15000]
                if fresh_aps:
                    aps = fresh_aps

                bssid_to_ssid = {ap["bssid"]: (ap["ssid"] or "<hidden>") for ap in aps}
                mon_summary, mon_by_bssid = self.monitor.snapshot(bssid_to_ssid)

                qbss_total = 0
                band_counts = {"2.4GHz": 0, "5GHz": 0, "6GHz": 0}
                ch_counts: dict[str, int] = {}
                for ap in aps:
                    ms = mon_by_bssid.get(ap["bssid"])
                    if ms:
                        ap.update(ms)
                    else:
                        ap["mon_frames"] = 0
                        ap["mon_retry_pct"] = None
                        ap["mon_clients"] = 0
                        ap["mon_client_list"] = []
                        ap["mon_rssi_dbm"] = None
                        ap["mon_noise_dbm"] = None
                        ap["mon_snr_db"] = None
                    if ap["qbss_stations"] is not None:
                        qbss_total += ap["qbss_stations"]
                    b = ap["band"]
                    if b in band_counts: band_counts[b] += 1
                    ch_key = str(ap["channel"])
                    ch_counts[ch_key] = ch_counts.get(ch_key, 0) + 1

                now = time.time()
                with self.cond:
                    self.scan_id += 1
                    self.last_error = None
                    self.last_scan = {
                        "scan_id": self.scan_id,
                        "hostname": socket.gethostname(),
                        "interface": iface,
                        "timestamp_unix": round(now, 3),
                        "timestamp_iso": datetime.fromtimestamp(now, tz=timezone.utc).isoformat(),
                        "scan_duration_ms": duration_ms,
                        "ap_count": len(aps),
                        "qbss_total_clients": qbss_total,
                        "band_counts": band_counts,
                        "channel_counts": ch_counts,
                        "strongest_rssi": aps[0]["rssi_dbm"] if aps else None,
                        "monitor": mon_summary,
                        "aps": aps,
                    }
                    self.cond.notify_all()
            except Exception as exc:
                with self.lock: self.last_error = str(exc)
                time.sleep(1.5)
            time.sleep(SCAN_INTERVAL_SEC)

    def get_latest(self, wait_fresh: bool = False, timeout: float = 5.0) -> dict:
        with self.cond:
            if wait_fresh:
                cur_id = self.scan_id
                self.cond.wait_for(lambda: self.scan_id > cur_id, timeout=timeout)
            return dict(self.last_scan)

    def wait_next(self, after_id: int, timeout: float = 15.0) -> dict | None:
        with self.cond:
            ok = self.cond.wait_for(lambda: self.scan_id > after_id, timeout=timeout)
            return dict(self.last_scan) if ok else None

    def health(self) -> dict:
        mon_summary, _ = self.monitor.snapshot()
        with self.lock:
            ts = self.last_scan["timestamp_unix"]
            age_ms = int((time.time() - ts) * 1000) if ts > 0 else None
            return {
                "status": "ok" if not self.last_error else "degraded",
                "hostname": socket.gethostname(),
                "interface": self.interface,
                "monitor_interface": self.monitor.interface,
                "monitor_active": self.monitor.active,
                "monitor_frames_10s": mon_summary["total_frames_10s"],
                "monitor_retry_pct": mon_summary["retry_pct_10s"],
                "monitor_clients_10s": mon_summary["unique_clients_10s"],
                "qbss_total_clients": self.last_scan.get("qbss_total_clients", 0),
                "oui_entries": len(OUI_DB),
                "interfaces": [r["iface"] for r in inspect_wifi_radios()],
                "regdomain": self.regdomain,
                "scan_id": self.scan_id,
                "ap_count": self.last_scan["ap_count"],
                "band_counts": self.last_scan["band_counts"],
                "last_scan_age_ms": age_ms,
                "scan_duration_ms": self.last_scan["scan_duration_ms"],
                "error": self.last_error,
            }


MONITOR = MonitorEngine()
ENGINE = ScannerEngine(MONITOR)


def safe_survey_id(raw: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9_-]", "", raw or "")
    return cleaned[:64] or f"survey_{int(time.time())}"


class SurveyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, fmt, *args): pass

    def _send_cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def _send_json(self, data, status: int = 200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self._send_cors()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204); self._send_cors(); self.send_header("Content-Length", "0"); self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        qs = parse_qs(parsed.query)

        if path == "/" or path == "/index.html":
            dash = STATIC_DIR / "dashboard.html"
            if dash.exists():
                body = dash.read_bytes()
                self.send_response(200); self._send_cors()
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers(); self.wfile.write(body)
            else:
                self._send_json({"service": "WLAN Pi RF Survey"})
            return

        if path in ("/wlanpi-lidar-survey.ipa", "/LidarTest-survey.ipa"):
            ipa = STATIC_DIR / "wlanpi-lidar-survey.ipa"
            if not ipa.exists():
                ipa = STATIC_DIR / "LidarTest-survey.ipa"
            if ipa.exists():
                body = ipa.read_bytes()
                self.send_response(200); self._send_cors()
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Disposition", f'attachment; filename="{ipa.name}"')
                self.send_header("Content-Length", str(len(body)))
                self.end_headers(); self.wfile.write(body)
                return

        if path == "/api/health": self._send_json(ENGINE.health()); return
        if path == "/api/monitor":
            cur = ENGINE.get_latest()
            bssid_map = {a["bssid"]: (a["ssid"] or "<hidden>") for a in cur.get("aps", [])}
            summary, by_bssid = MONITOR.snapshot(bssid_map)
            self._send_json({"monitor": summary, "bssids": by_bssid}); return
        if path == "/api/scan":
            fresh = qs.get("fresh", ["0"])[0] in ("1", "true", "yes")
            self._send_json(ENGINE.get_latest(wait_fresh=fresh)); return

        if path == "/api/stream":
            self.send_response(200); self._send_cors()
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            try:
                cur = ENGINE.get_latest()
                last_id = cur["scan_id"]
                if last_id > 0:
                    self.wfile.write(f"event: scan\ndata: {json.dumps(cur, ensure_ascii=False)}\n\n".encode("utf-8"))
                    self.wfile.flush()
                while True:
                    nxt = ENGINE.wait_next(last_id, timeout=15.0)
                    if nxt:
                        last_id = nxt["scan_id"]
                        self.wfile.write(f"event: scan\ndata: {json.dumps(nxt, ensure_ascii=False)}\n\n".encode("utf-8"))
                        self.wfile.flush()
                    else:
                        self.wfile.write(b": keepalive\n\n"); self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError, OSError):
                return

        if path == "/api/surveys":
            DATA_DIR.mkdir(parents=True, exist_ok=True)
            items = []
            for p in sorted(DATA_DIR.glob("*.json"), key=lambda f: f.stat().st_mtime, reverse=True):
                try:
                    d = json.loads(p.read_text(encoding="utf-8"))
                    items.append({
                        "id": d.get("id", p.stem), "name": d.get("name", p.stem),
                        "created_at": d.get("created_at", ""),
                        "point_count": len(d.get("points", [])),
                        "wall_count": len(d.get("walls", [])),
                    })
                except Exception: continue
            self._send_json({"surveys": items}); return

        if path.startswith("/api/surveys/"):
            sid = safe_survey_id(path.split("/api/surveys/", 1)[1])
            fp = DATA_DIR / f"{sid}.json"
            if not fp.exists(): self._send_json({"error": "Not found"}, status=404); return
            self._send_json(json.loads(fp.read_text(encoding="utf-8"))); return

        self._send_json({"error": "Not found"}, status=404)

    def do_POST(self):
        if urlparse(self.path).path != "/api/surveys":
            self._send_json({"error": "Not found"}, status=404); return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(min(length, 50 * 1024 * 1024)).decode("utf-8"))
        except Exception as exc:
            self._send_json({"error": f"Invalid JSON: {exc}"}, status=400); return
        sid = safe_survey_id(payload.get("id") or f"survey_{int(time.time())}")
        payload["id"] = sid
        payload.setdefault("name", sid)
        payload.setdefault("created_at", datetime.now(tz=timezone.utc).isoformat())
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        (DATA_DIR / f"{sid}.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        self._send_json({"status": "saved", "id": sid, "point_count": len(payload.get("points", []))}, status=201)

    def do_DELETE(self):
        parsed = urlparse(self.path)
        if parsed.path.startswith("/api/surveys/"):
            sid = safe_survey_id(parsed.path.split("/api/surveys/", 1)[1])
            fp = DATA_DIR / f"{sid}.json"
            if fp.exists(): fp.unlink(); self._send_json({"status": "deleted", "id": sid})
            else: self._send_json({"error": "Not found"}, status=404)
            return
        self._send_json({"error": "Not found"}, status=404)


def main():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    ENGINE.start()
    httpd = ThreadingHTTPServer(("0.0.0.0", PORT), SurveyHandler)
    httpd.daemon_threads = True
    print(f"[wifi-survey] Listening on 0.0.0.0:{PORT} (scan={ENGINE.interface}, mon={MONITOR.interface}:{MONITOR.active}, oui={len(OUI_DB)})", flush=True)
    try: httpd.serve_forever()
    except KeyboardInterrupt: pass
    finally:
        ENGINE.running = False; MONITOR.running = False; httpd.server_close()


if __name__ == "__main__":
    main()
