#!/usr/bin/env python3
"""
Wi-Fi dla strony ustawień PluDE: odczyt stanu i akcje, przy których
nmcli nie wystarcza. Rozmawia z NetworkManagerem przez libnm (gi).

  nm-wifi.py state       -> jeden JSON ze stanem (patrz state_of())
  nm-wifi.py watch       -> ten sam JSON po każdej zmianie, linia na stan
  nm-wifi.py < prośba    -> akcja, jedna linia JSON na stdout

Prośba to JSON na STDIN, nie argumenty: hasło w argv widziałby każdy
proces tego użytkownika (/proc/<pid>/cmdline). Akcje:

  {"action": "add", "ssid", "security", "psk", "hidden", "autoconnect",
   "bssid", "eap", "identity", "anonymousIdentity", "password", "phase2"}
      nowa sieć: profil + połączenie, czeka na wynik. Nieudana próba
      kasuje założony profil (złe hasło nie zostaje w „zapisanych”).
  {"action": "up", "uuid", "bssid"}     zapisana sieć, czeka na wynik
  {"action": "secret", "uuid"}          -> {"ok", "secret"} hasło profilu
  {"action": "setSecret", "uuid", "secret"}
  {"action": "scan"}

Wynik: {"ok": true, ...} albo {"ok": false, "error": "zdanie dla człowieka"}.
Kod wyjścia: 0 zawsze, gdy JSON poszedł; 2 = brak libnm / NetworkManagera.

Pozostałe zmiany profilu (autołączenie, IP, DNS, MAC) robi nmcli
connection modify: nie dotyczą sekretów, a nmcli sam parsuje adresy.
"""

import json
import sys
import warnings

try:
    import gi
    gi.require_version("NM", "1.0")
    from gi.repository import GLib, NM
except (ImportError, ValueError) as exc:
    sys.stdout.write(json.dumps({"ok": False, "error": f"brak libnm: {exc}"}) + "\n")
    sys.exit(2)

# Wywołania synchroniczne libnm (request_scan, get_secrets, commit_changes)
# są oznaczone jako przestarzałe, ale w jednorazowym procesie są tym,
# czego trzeba. Ostrzeżenie szłoby na stderr, a ten trafia do logu powłoki.
# Filtr dopiero po imporcie gi: gi przy imporcie dokłada własny przed nim.
warnings.filterwarnings("ignore", category=DeprecationWarning)

# Ile czekamy na wynik połączenia. NetworkManager przy złym haśle próbuje
# kilka razy, zanim się podda (zmierzone w wyspie: do ~25 s).
ACTIVATE_TIMEOUT_S = 40

# NM80211ApSecurityFlags
KEY_MGMT_PSK = 0x100
KEY_MGMT_8021X = 0x200
KEY_MGMT_SAE = 0x400
KEY_MGMT_OWE = 0x800
KEY_MGMT_OWE_TM = 0x1000
KEY_MGMT_SUITE_B = 0x2000
AP_FLAGS_PRIVACY = 0x1

# Powody z NMDeviceStateReason, które da się powiedzieć po ludzku.
DEVICE_REASONS = {
    7: "Złe hasło.",                                   # NO_SECRETS
    8: "Sieć odrzuciła połączenie (złe hasło?).",      # SUPPLICANT_DISCONNECT
    9: "Nieprawidłowe ustawienia zabezpieczeń.",       # SUPPLICANT_CONFIG_FAILED
    10: "Uwierzytelnianie nie powiodło się.",          # SUPPLICANT_FAILED
    11: "Uwierzytelnianie przekroczyło czas (złe hasło?).",  # SUPPLICANT_TIMEOUT
    5: "Nie udało się dostać adresu IP.",              # CONFIG_FAILED
    15: "Serwer DHCP nie odpowiada.",                  # DHCP_START_FAILED
    16: "Błąd DHCP.",                                  # DHCP_ERROR
    17: "Serwer DHCP nie przydzielił adresu.",         # DHCP_FAILED
    53: "Sieci nie ma w zasięgu.",                     # SSID_NOT_FOUND
}


def out(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def fail(message):
    out({"ok": False, "error": message})
    return 0


def text(b):
    """GLib.Bytes (SSID) -> tekst. SSID to bajty, nie zawsze UTF-8."""
    if b is None:
        return ""
    data = b.get_data() if hasattr(b, "get_data") else bytes(b)
    return data.decode("utf-8", "replace")


def band(freq):
    return "2.4" if freq < 3000 else "5" if freq < 5925 else "6"


def ap_security(ap):
    """Zabezpieczenia punktu dostępowego: (klucz dla „add”, nazwa)."""
    flags, wpa, rsn = ap.get_flags(), ap.get_wpa_flags(), ap.get_rsn_flags()
    both = wpa | rsn
    if both & (KEY_MGMT_8021X | KEY_MGMT_SUITE_B):
        return "wpa-eap", "WPA3 Enterprise" if both & KEY_MGMT_SUITE_B else (
            "WPA2 Enterprise" if rsn else "WPA Enterprise")
    if rsn & KEY_MGMT_SAE:
        # Tryb mieszany WPA2/WPA3: łączymy przez PSK, które zna każda karta.
        return ("wpa-psk", "WPA2/WPA3") if rsn & KEY_MGMT_PSK else ("sae", "WPA3")
    if both & KEY_MGMT_PSK:
        return "wpa-psk", "WPA2" if rsn else "WPA"
    if both & (KEY_MGMT_OWE | KEY_MGMT_OWE_TM):
        return "owe", "OWE"
    if flags & AP_FLAGS_PRIVACY:
        return "wep", "WEP"
    return "open", ""


def client():
    try:
        c = NM.Client.new(None)
    except GLib.Error as exc:
        out({"ok": False, "error": f"NetworkManager nie odpowiada: {exc.message}"})
        sys.exit(2)
    return c


def wifi_device(c):
    for d in c.get_devices():
        if isinstance(d, NM.DeviceWifi):
            return d
    return None


def ip_info(cfg):
    if cfg is None:
        return None
    return {
        "addresses": [f"{a.get_address()}/{a.get_prefix()}" for a in cfg.get_addresses()],
        "gateway": cfg.get_gateway() or "",
        "dns": list(cfg.get_nameservers() or []),
    }


def profile_info(rc):
    s_con = rc.get_setting_connection()
    s_wifi = rc.get_setting_wireless()
    s_sec = rc.get_setting_wireless_security()
    s_ip4 = rc.get_setting_ip4_config()
    s_ip6 = rc.get_setting_ip6_config()
    s_1x = rc.get_setting_802_1x()

    def ip(s):
        if s is None:
            return {"method": "auto", "addresses": [], "gateway": "", "dns": [], "ignoreAutoDns": False}
        return {
            "method": s.get_method() or "auto",
            "addresses": [f"{s.get_address(i).get_address()}/{s.get_address(i).get_prefix()}"
                          for i in range(s.get_num_addresses())],
            "gateway": s.get_gateway() or "",
            "dns": [s.get_dns(i) for i in range(s.get_num_dns())],
            "ignoreAutoDns": bool(s.get_ignore_auto_dns()),
        }

    return {
        "uuid": s_con.get_uuid(),
        "name": s_con.get_id(),
        "ssid": text(s_wifi.get_ssid()) if s_wifi else "",
        "mode": (s_wifi.get_mode() or "infrastructure") if s_wifi else "infrastructure",
        "hidden": bool(s_wifi.get_hidden()) if s_wifi else False,
        # "" = domyślne NetworkManagera (globalne wifi.cloned-mac-address).
        "mac": (s_wifi.get_cloned_mac_address() or "") if s_wifi else "",
        "powersave": int(s_wifi.get_powersave()) if s_wifi else 0,
        "autoconnect": bool(s_con.get_autoconnect()),
        "priority": int(s_con.get_autoconnect_priority()),
        "metered": int(s_con.get_metered()),
        "timestamp": int(s_con.get_timestamp()),
        "security": (s_sec.get_key_mgmt() or "") if s_sec else "open",
        "eap": s_1x.get_eap_method(0) if s_1x and s_1x.get_num_eap_methods() > 0 else "",
        "identity": (s_1x.get_identity() or "") if s_1x else "",
        "ipv4": ip(s_ip4),
        "ipv6": ip(s_ip6),
    }


def state_of(c):
    dev = wifi_device(c)
    res = {
        "ok": True,
        "enabled": bool(c.wireless_get_enabled()),
        "hardwareEnabled": bool(c.wireless_hardware_get_enabled()),
        "connectivity": int(c.get_connectivity()),
        "device": None,
        "active": None,
        "aps": [],
        "profiles": [],
    }

    profiles = [profile_info(rc) for rc in c.get_connections()
                if rc.get_connection_type() == "802-11-wireless"]

    if dev is not None:
        active_ap = dev.get_active_access_point()
        res["device"] = {
            "iface": dev.get_iface(),
            "state": int(dev.get_state()),
            "mac": dev.get_hw_address() or "",
            "permanentMac": dev.get_permanent_hw_address() or "",
            "bitrate": int(dev.get_bitrate()),   # kbit/s
            "driver": dev.get_driver() or "",
        }
        for ap in dev.get_access_points():
            key, label = ap_security(ap)
            freq = int(ap.get_frequency())
            res["aps"].append({
                "ssid": text(ap.get_ssid()),
                "bssid": ap.get_bssid() or "",
                "freq": freq,
                "band": band(freq),
                "channel": int(NM.utils_wifi_freq_to_channel(freq)),
                "signal": int(ap.get_strength()),
                "maxBitrate": int(ap.get_max_bitrate()),
                "securityKey": key,
                "security": label,
                "active": active_ap is not None and ap.get_path() == active_ap.get_path(),
            })

        ac = dev.get_active_connection()
        if ac is not None and ac.get_connection_type() == "802-11-wireless":
            ap = active_ap
            res["active"] = {
                "uuid": ac.get_uuid(),
                "name": ac.get_id(),
                "state": int(ac.get_state()),
                "ssid": text(ap.get_ssid()) if ap else "",
                "bssid": (ap.get_bssid() or "") if ap else "",
                "ipv4": ip_info(ac.get_ip4_config()),
                "ipv6": ip_info(ac.get_ip6_config()),
            }

    res["profiles"] = profiles
    return res


# ---------------------------------------------------------------
# Nasłuch
# ---------------------------------------------------------------

# Seria sygnałów (skanowanie zmienia siłę kilkudziesięciu sieci naraz)
# -> jeden stan po tylu ms ciszy.
WATCH_SETTLE_MS = 400
# Zapas: stan także bez sygnałów (np. adres IP, którego zmiany nie
# podpinamy obiekt po obiekcie).
WATCH_PERIOD_S = 20


def watch():
    """Jeden proces na czas otwartej strony zamiast odpytywania: sam
    import gi to ~0,4 s procesora na każdy odczyt."""
    c = client()
    hooked = {}
    pending = [0]

    def emit():
        pending[0] = 0
        hook_all()
        try:
            out(state_of(c))
        except BrokenPipeError:
            loop.quit()
        return False

    def poke(*_):
        if pending[0]:
            GLib.source_remove(pending[0])
        pending[0] = GLib.timeout_add(WATCH_SETTLE_MS, emit)

    def hook(obj, *signals):
        key = (type(obj).__name__, obj.get_path() if hasattr(obj, "get_path") else id(obj))
        if key in hooked:
            return
        hooked[key] = obj
        for sig in signals:
            obj.connect(sig, poke)

    def hook_all():
        for d in c.get_devices():
            if isinstance(d, NM.DeviceWifi):
                hook(d, "notify", "access-point-added", "access-point-removed")
                for ap in d.get_access_points():
                    hook(ap, "notify::strength")
        for rc in c.get_connections():
            hook(rc, "changed")
        for ac in c.get_active_connections():
            hook(ac, "notify")

    for sig in ("notify", "device-added", "device-removed", "connection-added",
                "connection-removed", "active-connection-added", "active-connection-removed"):
        c.connect(sig, poke)

    def periodic():
        poke()
        return True

    GLib.timeout_add_seconds(WATCH_PERIOD_S, periodic)
    loop = GLib.MainLoop()
    emit()
    loop.run()


# ---------------------------------------------------------------
# Łączenie
# ---------------------------------------------------------------

def wait_for(c, dev, start):
    """start(callback) zleca połączenie; czekamy na ACTIVATED albo porażkę.
    Zwraca (ok, błąd, aktywne połączenie)."""
    loop = GLib.MainLoop()
    res = {"ok": None, "error": "", "ac": None, "reason": 0}

    def finish(ok, error=""):
        if res["ok"] is None:
            res["ok"], res["error"] = ok, error
            loop.quit()

    def on_dev(_d, new, _old, reason):
        if new == NM.DeviceState.FAILED:
            res["reason"] = int(reason)

    def on_state(ac, *_):
        st = ac.get_state()
        if st == NM.ActiveConnectionState.ACTIVATED:
            finish(True)
        elif st == NM.ActiveConnectionState.DEACTIVATED:
            finish(False, DEVICE_REASONS.get(res["reason"], "Nie udało się połączyć."))

    def started(ac, error):
        if error:
            finish(False, error)
            return
        res["ac"] = ac
        ac.connect("notify::state", on_state)
        on_state(ac)

    if dev is not None:
        dev.connect("state-changed", on_dev)
    GLib.timeout_add_seconds(ACTIVATE_TIMEOUT_S,
                             lambda: finish(False, "Brak odpowiedzi — sprawdź hasło albo zasięg.") or False)
    start(started)
    if res["ok"] is None:
        loop.run()
    return res["ok"], res["error"], res["ac"]


def specific_ap(dev, bssid):
    if not bssid or dev is None:
        return None
    for ap in dev.get_access_points():
        if (ap.get_bssid() or "").lower() == bssid.lower():
            return ap.get_path()
    return None


def nm_error(exc):
    msg = exc.message if isinstance(exc, GLib.Error) else str(exc)
    return f"NetworkManager odmówił: {msg}"


def build_connection(req):
    ssid = str(req.get("ssid") or "")
    if not ssid:
        raise ValueError("Podaj nazwę sieci.")
    security = str(req.get("security") or "open")

    con = NM.SimpleConnection.new()
    s_con = NM.SettingConnection.new()
    s_con.set_property(NM.SETTING_CONNECTION_ID, ssid)
    s_con.set_property(NM.SETTING_CONNECTION_UUID, NM.utils_uuid_generate())
    s_con.set_property(NM.SETTING_CONNECTION_TYPE, "802-11-wireless")
    s_con.set_property(NM.SETTING_CONNECTION_AUTOCONNECT, bool(req.get("autoconnect", True)))
    con.add_setting(s_con)

    s_wifi = NM.SettingWireless.new()
    s_wifi.set_property(NM.SETTING_WIRELESS_SSID, GLib.Bytes.new(ssid.encode("utf-8")))
    s_wifi.set_property(NM.SETTING_WIRELESS_MODE, "infrastructure")
    # Ukryta sieć: NM musi pytać o nią po nazwie, inaczej jej nie zobaczy.
    s_wifi.set_property(NM.SETTING_WIRELESS_HIDDEN, bool(req.get("hidden", False)))
    con.add_setting(s_wifi)

    if security != "open":
        s_sec = NM.SettingWirelessSecurity.new()
        if security in ("wpa-psk", "sae"):
            psk = str(req.get("psk") or "")
            # 8–63 znaki albo 64 znaki szesnastkowe; NM odrzuciłby inne
            # komunikatem, który nic nie mówi.
            if not (8 <= len(psk) <= 63 or len(psk) == 64):
                raise ValueError("Hasło WPA ma od 8 do 63 znaków.")
            s_sec.set_property(NM.SETTING_WIRELESS_SECURITY_KEY_MGMT, security)
            s_sec.set_property(NM.SETTING_WIRELESS_SECURITY_PSK, psk)
        elif security == "wep":
            key = str(req.get("psk") or "")
            if not key:
                raise ValueError("Podaj klucz WEP.")
            s_sec.set_property(NM.SETTING_WIRELESS_SECURITY_KEY_MGMT, "none")
            s_sec.set_property(NM.SETTING_WIRELESS_SECURITY_WEP_KEY0, key)
            # Klucz ma 5, 10, 13 albo 26 znaków; inaczej to hasło do przeliczenia.
            s_sec.set_property(NM.SETTING_WIRELESS_SECURITY_WEP_KEY_TYPE,
                               NM.WepKeyType.KEY if len(key) in (5, 10, 13, 26) else NM.WepKeyType.PASSPHRASE)
        elif security == "owe":
            s_sec.set_property(NM.SETTING_WIRELESS_SECURITY_KEY_MGMT, "owe")
        elif security == "wpa-eap":
            identity = str(req.get("identity") or "")
            password = str(req.get("password") or "")
            if not identity or not password:
                raise ValueError("Podaj login i hasło sieci firmowej.")
            s_sec.set_property(NM.SETTING_WIRELESS_SECURITY_KEY_MGMT, "wpa-eap")
            s_1x = NM.Setting8021x.new()
            s_1x.set_property(NM.SETTING_802_1X_EAP, [str(req.get("eap") or "peap")])
            s_1x.set_property(NM.SETTING_802_1X_IDENTITY, identity)
            s_1x.set_property(NM.SETTING_802_1X_PASSWORD, password)
            if req.get("anonymousIdentity"):
                s_1x.set_property(NM.SETTING_802_1X_ANONYMOUS_IDENTITY, str(req["anonymousIdentity"]))
            phase2 = str(req.get("phase2") or "mschapv2")
            if phase2:
                s_1x.set_property(NM.SETTING_802_1X_PHASE2_AUTH, phase2)
            con.add_setting(s_1x)
        else:
            raise ValueError(f"Nieznane zabezpieczenia: {security}")
        con.add_setting(s_sec)

    s_ip4 = NM.SettingIP4Config.new()
    s_ip4.set_property(NM.SETTING_IP_CONFIG_METHOD, "auto")
    con.add_setting(s_ip4)
    s_ip6 = NM.SettingIP6Config.new()
    s_ip6.set_property(NM.SETTING_IP_CONFIG_METHOD, "auto")
    con.add_setting(s_ip6)
    return con


def action_add(req):
    try:
        con = build_connection(req)
    except ValueError as exc:
        return fail(str(exc))
    c = client()
    dev = wifi_device(c)
    if dev is None:
        return fail("Brak karty Wi-Fi.")

    def start(done):
        def cb(cl, result, _data):
            try:
                done(cl.add_and_activate_connection_finish(result), "")
            except GLib.Error as exc:
                done(None, nm_error(exc))
        c.add_and_activate_connection_async(con, dev, specific_ap(dev, req.get("bssid")), None, cb, None)

    ok, error, ac = wait_for(c, dev, start)
    if not ok and ac is not None:
        rc = ac.get_connection()
        if rc is not None:
            try:
                rc.delete(None)
            except GLib.Error:
                pass
    return out({"ok": True}) if ok else fail(error)


def remote(c, uuid):
    rc = c.get_connection_by_uuid(str(uuid or ""))
    if rc is None:
        raise LookupError("Nie ma takiej zapisanej sieci.")
    return rc


def action_up(req):
    c = client()
    dev = wifi_device(c)
    try:
        rc = remote(c, req.get("uuid"))
    except LookupError as exc:
        return fail(str(exc))

    def start(done):
        def cb(cl, result, _data):
            try:
                done(cl.activate_connection_finish(result), "")
            except GLib.Error as exc:
                done(None, nm_error(exc))
        c.activate_connection_async(rc, dev, specific_ap(dev, req.get("bssid")), None, cb, None)

    ok, error, _ac = wait_for(c, dev, start)
    return out({"ok": True}) if ok else fail(error)


def secret_target(rc):
    """(ustawienie, klucz) z hasłem profilu albo None."""
    s_sec = rc.get_setting_wireless_security()
    if s_sec is None:
        return None
    km = s_sec.get_key_mgmt()
    if km in ("wpa-psk", "sae"):
        return "802-11-wireless-security", "psk"
    if km == "none":
        return "802-11-wireless-security", "wep-key0"
    if km == "wpa-eap":
        return "802-1x", "password"
    return None


def action_secret(req):
    c = client()
    try:
        rc = remote(c, req.get("uuid"))
    except LookupError as exc:
        return fail(str(exc))
    target = secret_target(rc)
    if target is None:
        return out({"ok": True, "secret": ""})
    try:
        secrets = rc.get_secrets(target[0], None).unpack()
    except GLib.Error as exc:
        return fail(nm_error(exc))
    return out({"ok": True, "secret": str(secrets.get(target[0], {}).get(target[1], ""))})


def action_set_secret(req):
    c = client()
    try:
        rc = remote(c, req.get("uuid"))
    except LookupError as exc:
        return fail(str(exc))
    target = secret_target(rc)
    if target is None:
        return fail("Ta sieć nie ma hasła.")
    value = str(req.get("secret") or "")
    if target[1] == "psk" and not (8 <= len(value) <= 63 or len(value) == 64):
        return fail("Hasło WPA ma od 8 do 63 znaków.")
    if value == "":
        return fail("Hasło nie może być puste.")
    try:
        # commit_changes zastępuje CAŁY profil: bez wczytania sekretów
        # zapis skasowałby pozostałe (np. hasło klucza prywatnego).
        for setting in ("802-11-wireless-security", "802-1x"):
            if rc.get_setting_by_name(setting) is not None:
                rc.update_secrets(setting, rc.get_secrets(setting, None))
        rc.get_setting_by_name(target[0]).set_property(target[1], value)
        rc.commit_changes(True, None)
    except GLib.Error as exc:
        return fail(nm_error(exc))
    return out({"ok": True})


def action_scan(_req):
    c = client()
    dev = wifi_device(c)
    if dev is None:
        return fail("Brak karty Wi-Fi.")
    try:
        dev.request_scan(None)
    except GLib.Error as exc:
        # NM ogranicza skanowanie („Scanning not allowed immediately
        # following previous scan”): to nie błąd dla użytkownika.
        return out({"ok": True, "note": exc.message})
    return out({"ok": True})


ACTIONS = {
    "add": action_add,
    "up": action_up,
    "secret": action_secret,
    "setSecret": action_set_secret,
    "scan": action_scan,
}


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "state":
        out(state_of(client()))
        return 0
    if len(sys.argv) > 1 and sys.argv[1] == "watch":
        watch()
        return 0
    try:
        req = json.loads(sys.stdin.read() or "{}")
    except ValueError as exc:
        return fail(f"zepsuty JSON na wejściu: {exc}")
    fn = ACTIONS.get(req.get("action"))
    if fn is None:
        return fail(f"nieznana akcja: {req.get('action')}")
    return fn(req) or 0


if __name__ == "__main__":
    sys.exit(main())
