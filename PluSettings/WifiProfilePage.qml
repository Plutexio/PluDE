import QtQuick
import qs.Common

// Podstrona jednej zapisanej sieci Wi-Fi (SettingsApp.detail = uuid):
// połączenie, hasło i kod QR, autołączenie, prywatność (adres MAC), IPv4,
// DNS, IPv6, szczegóły bieżącego połączenia, zapomnienie.
//
// Każda zmiana to od razu `nmcli connection modify` (WifiService.modify),
// a w aktywnej sieci także reapply. Wartość w kontrolce zmienia się od
// razu (`pending`), zanim nasłuch przyniesie nowy stan profilu.
Column {
    id: page

    property string uuid: ""

    spacing: 22

    Component.onCompleted: WifiService.watchers++
    Component.onDestruction: WifiService.watchers--

    readonly property var p: WifiService.profile(uuid)
    readonly property bool live: WifiService.current !== null && WifiService.current.uuid === uuid
    readonly property var c: live ? WifiService.current : null
    // Ta sieć w zasięgu (do „Połącz”).
    readonly property var inRange: p ? (WifiService.networks.find(n => n.ssid === p.ssid) ?? null) : null

    // Zapomniana (tutaj albo w nmcli) → z powrotem na listę.
    onPChanged: {
        pending = ({});
        if (p === null && WifiService.ready) SettingsApp.back();
        else if (p !== null) SettingsApp.detailTitle = p.name;
    }

    // ---- zmiany ----

    // { klucz: wartość } wysłane, a jeszcze niepotwierdzone przez nasłuch.
    property var pending: ({})

    function value(key, actual) { return pending[key] !== undefined ? pending[key] : actual; }

    function set(key, shown, pairs) {
        const n = Object.assign({}, pending);
        n[key] = shown;
        pending = n;
        WifiService.modify(uuid, pairs);
    }

    // Błąd zapisu: kontrolki wracają do stanu z NetworkManagera.
    Connections {
        target: WifiService
        function onErrorChanged() { if (WifiService.error !== "") page.pending = ({}); }
    }

    // ---- hasło i kod QR ----

    property string secret: ""
    property bool secretLoaded: false
    property string qr: ""
    property bool qrShown: false

    function withSecret(done) {
        if (secretLoaded) { done(secret); return; }
        WifiService.readSecret(uuid, s => {
            if (s === null) return;
            page.secret = s;
            page.secretLoaded = true;
            done(s);
        });
    }

    function toggleQr() {
        if (qrShown) { qrShown = false; qr = ""; return; }
        withSecret(s => WifiService.qrSvg(page.p, s, url => {
            page.qr = url;
            page.qrShown = url !== "";
        }));
    }

    // ---- listy wyboru ----

    function withCurrent(list, current, label) {
        return list.some(o => o.value === current) ? list : list.concat([{ value: current, label: label }]);
    }

    readonly property var priorityChoices: p ? withCurrent([
        { value: -10, label: "Niski" },
        { value: 0, label: "Zwykły" },
        { value: 10, label: "Wysoki" },
        { value: 50, label: "Najwyższy" }
    ], value("priority", p.priority), "Własny (" + value("priority", p.priority) + ")") : []

    readonly property var meteredChoices: [
        { value: 0, label: "Wykrywaj" },
        { value: 1, label: "Tak" },
        { value: 2, label: "Nie" }
    ]

    // Pusty = domyślne NetworkManagera (globalne wifi.cloned-mac-address).
    readonly property var macChoices: p ? withCurrent([
        { value: "", label: "Domyślny systemu" },
        { value: "permanent", label: "Sprzętowy" },
        { value: "stable", label: "Losowy, stały dla tej sieci" },
        { value: "random", label: "Losowy przy każdym połączeniu" }
    ], value("mac", p.mac), p.mac === "preserve" ? "Bez zmian (preserve)" : p.mac) : []

    readonly property var powerChoices: p ? withCurrent([
        { value: 0, label: "Domyślne" },
        { value: 2, label: "Wyłączone" },
        { value: 3, label: "Włączone" }
    ], value("powersave", p.powersave), "Bez zmian") : []

    readonly property var ip4Choices: p ? withCurrent([
        { value: "auto", label: "Automatycznie (DHCP)" },
        { value: "manual", label: "Ręcznie" },
        { value: "disabled", label: "Wyłączone" }
    ], value("ip4", p.ipv4.method), p.ipv4.method) : []

    readonly property var ip6Choices: p ? withCurrent([
        { value: "auto", label: "Automatycznie" },
        { value: "link-local", label: "Tylko adres lokalny" },
        { value: "disabled", label: "Wyłączone" }
    ], value("ip6", p.ipv6.method), p.ipv6.method) : []

    readonly property var dnsPresets: [
        { value: "cloudflare", label: "Cloudflare (1.1.1.1)", v4: ["1.1.1.1", "1.0.0.1"],
          v6: ["2606:4700:4700::1111", "2606:4700:4700::1001"] },
        { value: "google", label: "Google (8.8.8.8)", v4: ["8.8.8.8", "8.8.4.4"],
          v6: ["2001:4860:4860::8888", "2001:4860:4860::8844"] },
        { value: "quad9", label: "Quad9 (9.9.9.9)", v4: ["9.9.9.9", "149.112.112.112"],
          v6: ["2620:fe::fe", "2620:fe::9"] }
    ]

    readonly property var dnsChoices: [{ value: "auto", label: "Z sieci (DHCP)" }]
        .concat(dnsPresets.map(d => ({ value: d.value, label: d.label })))
        .concat([{ value: "custom", label: "Własne" }])

    readonly property string dnsMode: {
        if (!p) return "auto";
        const v4 = p.ipv4.dns;
        if (v4.length === 0 && p.ipv6.dns.length === 0 && !p.ipv4.ignoreAutoDns) return "auto";
        const preset = dnsPresets.find(d => d.v4.join(",") === v4.join(","));
        return preset ? preset.value : "custom";
    }

    // ipv6.dns przy wyłączonym IPv6 NetworkManager odrzuca.
    readonly property bool ip6Configurable: p !== null && p.ipv6.method !== "disabled" && p.ipv6.method !== "ignore"

    function applyDns(v4, v6, ignoreAuto) {
        const pairs = ["ipv4.dns", v4.join(","), "ipv4.ignore-auto-dns", ignoreAuto ? "yes" : "no"];
        if (ip6Configurable) pairs.push("ipv6.dns", v6.join(","), "ipv6.ignore-auto-dns", ignoreAuto ? "yes" : "no");
        return pairs;
    }

    function pickDns(mode) {
        if (mode === "custom") { customDns = true; return; }
        customDns = false;
        if (mode === "auto") { set("dns", mode, applyDns([], [], false)); return; }
        const d = dnsPresets.find(x => x.value === mode);
        set("dns", mode, applyDns(d.v4, d.v6, true));
    }

    function commitCustomDns(text) {
        const all = text.split(/[\s,;]+/).filter(s => s !== "");
        if (all.length === 0) { pickDns("auto"); return; }
        set("dns", "custom", applyDns(all.filter(s => s.indexOf(":") < 0), all.filter(s => s.indexOf(":") >= 0), true));
    }

    // Lista „Własne” wybrana, a serwery jeszcze niewpisane.
    property bool customDns: false
    // „Ręcznie” wybrane, a adres jeszcze niewpisany: NetworkManager nie
    // przyjmie metody manual bez adresu.
    property bool manualDraft: false
    readonly property bool manualShown: p !== null && (p.ipv4.method === "manual" || manualDraft)

    function pickIp4(method) {
        if (method === "manual") {
            if (p.ipv4.method !== "manual") manualDraft = true;
            return;
        }
        manualDraft = false;
        set("ip4", method, ["ipv4.method", method, "ipv4.addresses", "", "ipv4.gateway", ""]);
    }

    function applyManual() {
        const addr = addressField.text.trim();
        if (addr === "") return;
        // Bez maski NetworkManager przyjmuje /32, czyli brak sieci lokalnej.
        const full = addr.indexOf("/") < 0 ? addr + "/24" : addr;
        manualDraft = false;
        set("ip4", "manual", ["ipv4.method", "manual", "ipv4.addresses", full, "ipv4.gateway", gatewayField.text.trim()]);
    }

    // ---- zapomnienie ----

    property bool confirmForget: false
    Timer { id: forgetTimer; interval: 3000; onTriggered: page.confirmForget = false }

    // ---------------------------------------------------------------
    // Połączenie
    // ---------------------------------------------------------------

    SettingsSection {
        width: page.width
        visible: page.p !== null

        SettingsRow {
            title: page.live ? (page.c.connected ? "Połączona" : "Łączę…")
                : WifiService.connecting === (page.p ? page.p.ssid : "") ? "Łączę…"
                : page.inRange ? "W zasięgu" : "Poza zasięgiem"
            description: {
                if (!page.p) return "";
                if (WifiService.connectErrorFor === page.p.ssid && WifiService.connectError !== "")
                    return WifiService.connectError;
                if (page.live) return WifiService.connectivityLabel + ".";
                const parts = ["Ostatnio: " + WifiService.ago(page.p.timestamp)];
                if (page.inRange) parts.push("sygnał " + page.inRange.signal + "%");
                return parts.join(" · ");
            }

            SettingsButton {
                visible: page.live || page.inRange !== null
                text: page.live ? "Rozłącz" : "Połącz"
                primary: !page.live
                enabled: !WifiService.busy
                onClicked: page.live ? WifiService.disconnect()
                    : WifiService.connectSaved(page.p, page.inRange ? page.inRange.bssid : "")
            }
        }

        SettingsRow {
            title: "Łącz automatycznie"
            description: "W zasięgu NetworkManager łączy się sam, w kolejności priorytetów."

            SettingsSwitch {
                checked: page.p ? page.value("autoconnect", page.p.autoconnect) : false
                onToggled: {
                    const on = !page.value("autoconnect", page.p.autoconnect);
                    page.set("autoconnect", on, ["connection.autoconnect", on ? "yes" : "no"]);
                }
            }
        }

        SettingsRow {
            title: "Priorytet"
            description: "Z kilku sieci w zasięgu wygrywa ta z wyższym."
            enabled: page.p !== null && page.value("autoconnect", page.p.autoconnect)

            SettingsChoice {
                width: 180
                model: page.priorityChoices
                value: page.p ? page.value("priority", page.p.priority) : null
                onPicked: v => page.set("priority", v, ["connection.autoconnect-priority", String(v)])
            }
        }

        SettingsRow {
            title: "Połączenie taryfowe"
            description: "Limitowany transfer (np. hotspot w telefonie): aktualizacje i synchronizacja w tle mogą czekać."

            SettingsChoice {
                width: 180
                model: page.meteredChoices
                value: page.p ? page.value("metered", page.p.metered > 2 ? 0 : page.p.metered) : null
                onPicked: v => page.set("metered", v, ["connection.metered", v === 1 ? "yes" : v === 2 ? "no" : "unknown"])
            }
        }

        SettingsRow {
            title: "Sieć ukryta"
            description: "Sieć nie ogłasza nazwy, więc karta pyta o nią sama."

            SettingsSwitch {
                checked: page.p ? page.value("hidden", page.p.hidden) : false
                onToggled: {
                    const on = !page.value("hidden", page.p.hidden);
                    page.set("hidden", on, ["802-11-wireless.hidden", on ? "yes" : "no"]);
                }
            }
        }
    }

    // ---------------------------------------------------------------
    // Zabezpieczenia
    // ---------------------------------------------------------------

    SettingsSection {
        width: page.width
        visible: page.p !== null
        title: "Zabezpieczenia"

        SettingsRow {
            title: "Typ"
            description: page.p && page.p.identity !== "" ? "Login: " + page.p.identity : ""

            Text {
                text: page.p ? WifiService.profileSecurity(page.p) : ""
                color: Theme.textDim
                font.pixelSize: 13
            }
        }

        SettingsRow {
            visible: WifiService.hasSecret(page.p)
            title: "Hasło"
            description: page.live ? "Nowe hasło obowiązuje od następnego połączenia." : "Enter zapisuje nowe hasło."

            SettingsField {
                width: 240
                secret: true
                value: page.secret
                placeholder: page.secretLoaded ? "" : "••••••••"
                onRevealRequested: page.withSecret(s => {})
                onCommitted: t => {
                    if (t === "") { text = page.secret; return; }
                    WifiService.setSecret(page.uuid, t, ok => { if (ok) { page.secret = t; page.secretLoaded = true; } });
                }
            }
        }

        SettingsRow {
            visible: page.p !== null && page.p.security !== "wpa-eap"
            title: "Udostępnij"
            description: "Kod QR z nazwą i hasłem: aparat w telefonie połączy się od razu."

            SettingsButton {
                text: page.qrShown ? "Schowaj" : "Kod QR"
                onClicked: page.toggleQr()
            }
        }

        Item {
            visible: page.qrShown
            width: parent.width
            height: visible ? 236 : 0

            // Kod ciemny na jasnym: aparaty nie zawsze czytają odwrócony.
            Rectangle {
                anchors.centerIn: parent
                width: 208
                height: 208
                radius: 14
                color: "#ffffff"

                Image {
                    anchors.fill: parent
                    anchors.margins: 10
                    source: page.qr
                    sourceSize: Qt.size(188, 188)
                    smooth: false
                    fillMode: Image.PreserveAspectFit
                }
            }
        }
    }

    // ---------------------------------------------------------------
    // Prywatność i energia
    // ---------------------------------------------------------------

    SettingsSection {
        width: page.width
        visible: page.p !== null
        title: "Prywatność i energia"

        SettingsRow {
            title: "Adres MAC"
            description: "Losowy utrudnia śledzenie między sieciami. Stały losowy nie psuje sieci, które pamiętają urządzenia."

            SettingsChoice {
                width: 240
                model: page.macChoices
                value: page.p ? page.value("mac", page.p.mac) : null
                onPicked: v => page.set("mac", v, ["802-11-wireless.cloned-mac-address", v])
            }
        }

        SettingsRow {
            title: "Oszczędzanie energii karty"
            description: "Wyłączone: mniejsze opóźnienia kosztem baterii."

            SettingsChoice {
                width: 180
                model: page.powerChoices
                value: page.p ? page.value("powersave", page.p.powersave) : null
                onPicked: v => page.set("powersave", v, ["802-11-wireless.powersave", String(v)])
            }
        }
    }

    // ---------------------------------------------------------------
    // IP i DNS
    // ---------------------------------------------------------------

    SettingsSection {
        width: page.width
        visible: page.p !== null
        title: "IPv4"

        SettingsRow {
            title: "Adresowanie"

            SettingsChoice {
                width: 220
                model: page.ip4Choices
                value: page.p ? (page.manualDraft ? "manual" : page.value("ip4", page.p.ipv4.method)) : null
                onPicked: v => page.pickIp4(v)
            }
        }

        SettingsRow {
            visible: page.manualShown
            title: "Adres"
            description: "Z maską, np. 192.168.1.20/24 (bez maski: /24)."

            SettingsField {
                id: addressField
                width: 220
                value: page.p && page.p.ipv4.addresses.length > 0 ? page.p.ipv4.addresses[0] : ""
                placeholder: "192.168.1.20/24"
                commitOnBlur: false
                onAccepted: gatewayField.focusInput()
            }
        }

        SettingsRow {
            visible: page.manualShown
            title: "Brama"

            SettingsField {
                id: gatewayField
                width: 220
                value: page.p ? page.p.ipv4.gateway : ""
                placeholder: "192.168.1.1"
                commitOnBlur: false
                onAccepted: page.applyManual()
            }
        }

        SettingsRow {
            visible: page.manualShown
            title: ""

            Row {
                spacing: 8

                SettingsButton {
                    visible: page.manualDraft
                    text: "Anuluj"
                    onClicked: page.manualDraft = false
                }

                SettingsButton {
                    text: "Zastosuj"
                    primary: true
                    onClicked: page.applyManual()
                }
            }
        }

        SettingsRow {
            title: "DNS"
            description: page.dnsMode === "custom" && page.p ? page.p.ipv4.dns.concat(page.p.ipv6.dns).join(", ") : ""

            SettingsChoice {
                width: 220
                model: page.dnsChoices
                value: page.customDns ? "custom" : page.value("dns", page.dnsMode)
                onPicked: v => page.pickDns(v)
            }
        }

        SettingsRow {
            visible: page.customDns || page.value("dns", page.dnsMode) === "custom"
            title: "Serwery DNS"
            description: "Oddzielone przecinkami; IPv6 też. Enter zapisuje."

            SettingsField {
                width: 260
                value: page.p ? page.p.ipv4.dns.concat(page.p.ipv6.dns).join(", ") : ""
                placeholder: "1.1.1.1, 9.9.9.9"
                onCommitted: t => page.commitCustomDns(t)
            }
        }
    }

    SettingsSection {
        width: page.width
        visible: page.p !== null
        title: "IPv6"

        SettingsRow {
            title: "Adresowanie"
            description: "Wyłącz, jeśli sieć ma zepsute IPv6 i strony ładują się z opóźnieniem."

            SettingsChoice {
                width: 220
                model: page.ip6Choices
                value: page.p ? page.value("ip6", page.p.ipv6.method) : null
                onPicked: v => page.set("ip6", v, ["ipv6.method", v])
            }
        }
    }

    // ---------------------------------------------------------------
    // Szczegóły bieżącego połączenia
    // ---------------------------------------------------------------

    component Value: TextEdit {
        readOnly: true
        selectByMouse: true
        color: Theme.textDim
        selectionColor: Theme.accent
        font.pixelSize: 13
        horizontalAlignment: TextEdit.AlignRight
    }

    SettingsSection {
        width: page.width
        visible: page.c !== null && page.c.connected
        title: "Szczegóły połączenia"

        SettingsRow {
            title: "Adres IPv4"
            Value { text: page.c && page.c.ipv4 ? page.c.ipv4.addresses.join("\n") : "—" }
        }

        SettingsRow {
            title: "Brama"
            Value { text: page.c && page.c.ipv4 && page.c.ipv4.gateway !== "" ? page.c.ipv4.gateway : "—" }
        }

        SettingsRow {
            title: "DNS"
            Value {
                text: {
                    const c = page.c;
                    if (!c) return "—";
                    const all = (c.ipv4 ? c.ipv4.dns : []).concat(c.ipv6 ? c.ipv6.dns : []);
                    return all.length > 0 ? all.join("\n") : "—";
                }
            }
        }

        SettingsRow {
            title: "Adres IPv6"
            Value { text: page.c && page.c.ipv6 && page.c.ipv6.addresses.length > 0 ? page.c.ipv6.addresses.join("\n") : "—" }
        }

        SettingsRow {
            id: macRow
            readonly property var d: WifiService.device
            title: "Adres MAC"
            description: d && d.mac !== d.permanentMac ? "Losowy; sprzętowy: " + d.permanentMac : "Sprzętowy"
            Value { text: macRow.d ? macRow.d.mac : "—" }
        }

        SettingsRow {
            title: "Punkt dostępowy"
            description: page.c ? WifiService.bandLabel(page.c.band) + ", kanał " + page.c.channel : ""
            Value { text: page.c ? page.c.bssid : "—" }
        }

        SettingsRow {
            title: "Szybkość łącza"
            description: WifiService.device && WifiService.device.driver !== "" ? "Sterownik " + WifiService.device.driver : ""
            Value { text: page.c ? WifiService.rateLabel(page.c.bitrate) + " · sygnał " + page.c.signal + "%" : "—" }
        }
    }

    // ---------------------------------------------------------------
    // Zapomnienie
    // ---------------------------------------------------------------

    Item {
        width: page.width
        height: forgetButton.height
        visible: page.p !== null

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.right: forgetButton.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.Wrap
            font.pixelSize: 12
            color: WifiService.error !== "" ? Theme.danger : Theme.textFaint
            text: WifiService.error !== "" ? WifiService.error
                : page.confirmForget ? "Hasło i ustawienia tej sieci znikną. Kliknij jeszcze raz."
                : page.p ? "Profil NetworkManagera „" + page.p.name + "”." : ""
        }

        SettingsButton {
            id: forgetButton
            anchors.right: parent.right
            text: page.confirmForget ? "Na pewno?" : "Zapomnij sieć"
            tint: Theme.danger
            primary: page.confirmForget
            onClicked: {
                if (!page.confirmForget) {
                    page.confirmForget = true;
                    forgetTimer.restart();
                    return;
                }
                forgetTimer.stop();
                WifiService.forget(page.uuid);
            }
        }
    }
}
