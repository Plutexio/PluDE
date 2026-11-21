import QtQuick
import Quickshell
import Quickshell.Networking
import qs.Common

// Strona „Wi-Fi”: włącznik, bieżące połączenie, sieci w zasięgu (z
// łączeniem i siecią ukrytą) i zapisane sieci. Ustawienia jednej sieci
// są na podstronie (WifiProfilePage, SettingsApp.detail = uuid).
//
// Wszystko idzie prosto do NetworkManagera: te same profile widzą nmcli,
// nmtui i nakładka Wi-Fi w wyspie.
Column {
    id: page

    spacing: 22

    // Ile sieci w zasięgu i zapisanych pokazać przed „Pokaż wszystkie”.
    property int collapsedNetworks: 8
    property int collapsedSaved: 6

    property string openKey: ""
    property bool allNetworks: false
    property bool allSaved: false

    Component.onCompleted: {
        WifiService.watchers++;
        WifiService.scan();
        syncKeys(networkModel, networkKeys, false);
        syncKeys(savedModel, savedKeys, false);
    }
    Component.onDestruction: WifiService.watchers--

    readonly property var current: WifiService.current
    readonly property bool on: WifiService.enabled && WifiService.hardwareEnabled

    // ---------------------------------------------------------------
    // Listy jako ListModel synchronizowany ruchami (jak dock i launcher):
    // stan przychodzi co kilka sekund (siła sygnału), a nowe delegaty
    // zgubiłyby rozwinięty wiersz i wpisywane hasło.
    // ---------------------------------------------------------------

    readonly property var others: WifiService.networks.filter(n => !n.active)
    readonly property var networkKeys: {
        const keys = others.map(n => n.ssid);
        return allNetworks ? keys : keys.slice(0, collapsedNetworks);
    }
    readonly property var networkByKey: {
        const out = {};
        others.forEach(n => out[n.ssid] = n);
        return out;
    }

    readonly property var savedKeys: {
        const keys = WifiService.savedProfiles.map(p => p.uuid);
        return allSaved ? keys : keys.slice(0, collapsedSaved);
    }
    readonly property var savedByKey: {
        const out = {};
        WifiService.savedProfiles.forEach(p => out[p.uuid] = p);
        return out;
    }

    // Przy rozwiniętym wierszu kolejność stoi (zmiana siły sygnału
    // przesuwałaby go spod kursora); dochodzą tylko nowe na końcu.
    function syncKeys(m, keys, freeze) {
        for (let i = m.count - 1; i >= 0; i--)
            if (keys.indexOf(m.get(i).key) < 0) m.remove(i);
        if (freeze) {
            const have = [];
            for (let i = 0; i < m.count; i++) have.push(m.get(i).key);
            keys.forEach(k => { if (have.indexOf(k) < 0) m.append({ key: k }); });
            return;
        }
        for (let i = 0; i < keys.length; i++) {
            let j = -1;
            for (let k = i; k < m.count; k++) if (m.get(k).key === keys[i]) { j = k; break; }
            if (j < 0) m.insert(i, { key: keys[i] });
            else if (j !== i) m.move(j, i, 1);
        }
    }

    ListModel { id: networkModel }
    ListModel { id: savedModel }

    onNetworkKeysChanged: syncKeys(networkModel, networkKeys, openKey !== "" && networkKeys.indexOf(openKey) >= 0)
    onOpenKeyChanged: if (openKey === "") syncKeys(networkModel, networkKeys, false)
    onSavedKeysChanged: syncKeys(savedModel, savedKeys, false)

    function toggleRow(key) { openKey = openKey === key ? "" : key; }

    function openProfile(p) {
        if (p) SettingsApp.openDetail(p.uuid, p.name);
    }

    // ---------------------------------------------------------------
    // Włącznik
    // ---------------------------------------------------------------

    SettingsSection {
        width: page.width

        SettingsRow {
            title: "Wi-Fi"
            description: !WifiService.hardwareEnabled ? "Zablokowane sprzętowo: przełącznik albo tryb samolotowy."
                : !WifiService.enabled ? "Wyłączone."
                : WifiService.ready && !WifiService.available ? "Nie widzę karty Wi-Fi."
                : WifiService.busy ? "Łączę z siecią " + WifiService.connecting + "…"
                : page.current && page.current.connected ? "Połączono z siecią " + page.current.name + "."
                : page.current ? "Łączę z siecią " + page.current.name + "…"
                : "Nie połączono."

            SettingsSwitch {
                checked: WifiService.enabled
                enabled: WifiService.hardwareEnabled
                onToggled: WifiService.setEnabled(!WifiService.enabled)
            }
        }
    }

    // ---------------------------------------------------------------
    // Bieżące połączenie
    // ---------------------------------------------------------------

    SettingsSection {
        width: page.width
        visible: page.on && page.current !== null
        title: "Połączenie"

        Item {
            width: parent.width
            height: 70

            Icon {
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                size: 28
                kind: WifiService.signalIcon(page.current ? page.current.signal : 0)
                ghost: "wifi"
                color: Theme.accent
                ghostColor: Qt.rgba(1, 1, 1, 0.16)
            }

            Column {
                x: 16 + 28 + 14
                anchors.verticalCenter: parent.verticalCenter
                width: disconnectButton.x - x - 12
                spacing: 4

                Text {
                    width: parent.width
                    text: page.current ? page.current.name : ""
                    color: Theme.text
                    font.pixelSize: 15
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    color: Theme.textDim
                    font.pixelSize: 12
                    text: {
                        const c = page.current;
                        if (!c) return "";
                        if (!c.connected) return "Łączę…";
                        const parts = [];
                        if (c.security !== "") parts.push(c.security);
                        if (c.band !== "") parts.push(WifiService.bandLabel(c.band) + ", kanał " + c.channel);
                        if (c.bitrate > 0) parts.push(WifiService.rateLabel(c.bitrate));
                        parts.push("sygnał " + c.signal + "%");
                        return parts.join(" · ");
                    }
                }
            }

            SettingsButton {
                id: disconnectButton
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "Rozłącz"
                onClicked: WifiService.disconnect()
            }
        }

        SettingsRow {
            title: "Internet"
            description: WifiService.connectivityLabel

            Row {
                spacing: 8

                // Portal: dowolna strona po http przekierowuje na logowanie.
                SettingsButton {
                    visible: WifiService.connectivity === 2
                    text: "Zaloguj się"
                    primary: true
                    onClicked: Quickshell.execDetached(["xdg-open", "http://neverssl.com"])
                }

                SettingsButton {
                    visible: Networking.canCheckConnectivity
                    text: "Sprawdź"
                    onClicked: Networking.checkConnectivity()
                }
            }
        }

        SettingsRow {
            visible: page.current !== null && page.current.ipv4 !== null
            title: "Adres IP"

            TextEdit {
                readOnly: true
                selectByMouse: true
                text: page.current && page.current.ipv4 ? page.current.ipv4.addresses.map(a => a.split("/")[0]).join(", ") : ""
                color: Theme.textDim
                selectionColor: Theme.accent
                font.pixelSize: 13
            }
        }

        SettingsNavRow {
            title: "Ustawienia tej sieci"
            description: "Hasło, IP i DNS, adres MAC, autołączenie, szczegóły połączenia"
            onClicked: {
                const p = page.current ? WifiService.profile(page.current.uuid) : null;
                page.openProfile(p);
            }
        }
    }

    // ---------------------------------------------------------------
    // Sieci w zasięgu
    // ---------------------------------------------------------------

    Column {
        width: page.width
        visible: page.on && WifiService.available
        spacing: 8

        Item {
            width: parent.width
            height: 18

            Text {
                x: 4
                anchors.verticalCenter: parent.verticalCenter
                text: "Dostępne sieci"
                color: Theme.textDim
                font.pixelSize: 11
                font.bold: true
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Icon {
                    id: refreshIcon
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "refresh"
                    size: 14
                    color: refreshMouse.containsMouse ? Theme.text : Theme.textDim

                    RotationAnimation on rotation {
                        running: WifiService.scanning
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                        // Po skanowaniu ikona wraca do zera, a nie staje w pół obrotu.
                        onRunningChanged: if (!running) refreshIcon.rotation = 0
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: WifiService.scanning ? "Szukam…" : "Odśwież"
                    color: refreshMouse.containsMouse ? Theme.text : Theme.textDim
                    font.pixelSize: 11
                }
            }

            MouseArea {
                id: refreshMouse
                anchors.right: parent.right
                width: 90
                height: parent.height
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: WifiService.scan()
            }
        }

        SettingsSection {
            width: parent.width

            Repeater {
                model: networkModel

                WifiNetworkRow {
                    required property string key
                    network: page.networkByKey[key] ?? null
                    expanded: page.openKey === key
                    onToggle: page.toggleRow(key)
                    onOpenProfile: p => page.openProfile(p)
                }
            }

            SettingsNavRow {
                visible: page.others.length > page.collapsedNetworks
                title: page.allNetworks ? "Pokaż mniej" : "Pokaż wszystkie (" + page.others.length + ")"
                titleColor: Theme.accent
                chevron: false
                minHeight: 44
                onClicked: page.allNetworks = !page.allNetworks
            }

            Text {
                visible: page.others.length === 0
                width: parent.width
                height: 48
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: WifiService.ready ? "Nie widzę innych sieci." : "Szukam sieci…"
                color: Theme.textFaint
                font.pixelSize: 12
            }

            WifiNetworkRow {
                manual: true
                expanded: page.openKey === "\u0000manual"
                onToggle: page.toggleRow("\u0000manual")
            }
        }
    }

    // ---------------------------------------------------------------
    // Zapisane sieci
    // ---------------------------------------------------------------

    SettingsSection {
        width: page.width
        visible: WifiService.savedProfiles.length > 0
        title: "Zapisane sieci (" + WifiService.savedProfiles.length + ")"

        Repeater {
            model: savedModel

            SettingsNavRow {
                required property string key
                readonly property var p: page.savedByKey[key] ?? null
                readonly property bool live: page.current !== null && p !== null && page.current.uuid === p.uuid

                icon: "wifi"
                iconColor: live ? Theme.accent : Theme.textFaint
                title: p ? p.name : ""
                description: !p ? ""
                    : (live ? "połączona teraz" : "ostatnio: " + WifiService.ago(p.timestamp))
                      + (p.autoconnect ? "" : " · tylko ręcznie")
                      + (p.metered === 1 ? " · taryfowa" : "")
                trailing: p ? WifiService.profileSecurity(p).replace(/ Personal$/, "") : ""
                onClicked: page.openProfile(p)
            }
        }

        SettingsNavRow {
            visible: WifiService.savedProfiles.length > page.collapsedSaved
            title: page.allSaved ? "Pokaż mniej" : "Pokaż wszystkie (" + WifiService.savedProfiles.length + ")"
            titleColor: Theme.accent
            chevron: false
            minHeight: 44
            onClicked: page.allSaved = !page.allSaved
        }
    }

    Text {
        visible: WifiService.error !== ""
        x: 4
        width: page.width - 8
        wrapMode: Text.Wrap
        text: WifiService.error
        color: Theme.danger
        font.pixelSize: 12
    }

    Text {
        x: 4
        width: page.width - 8
        text: "Zmiany idą prosto do NetworkManagera: te same sieci widzą nmcli, nmtui i nakładka Wi-Fi w wyspie."
        color: Theme.textFaint
        font.pixelSize: 11
        wrapMode: Text.Wrap
    }
}
