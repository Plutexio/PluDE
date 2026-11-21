import QtQuick
import qs.Common

// Sieć w zasięgu na stronie Wi-Fi. Klik rozwija wiersz: zapisana sieć
// łączy się od razu, nowa pokazuje pola, których potrzebuje (hasło,
// login sieci firmowej). `manual` to wiersz „Inna sieć” na końcu listy:
// nazwa i zabezpieczenia wpisywane ręcznie (sieć ukryta).
//
// Stan rozwinięcia trzyma strona (`expanded`), bo otwarty może być tylko
// jeden wiersz. Wpisane hasło żyje w polu, więc strona nie może tworzyć
// delegatów od nowa przy każdym odczycie (WifiPage.syncKeys).
Item {
    id: row

    // Pozycja z WifiService.networks albo null przy `manual`.
    property var network: null
    property bool manual: false
    property bool expanded: false

    signal toggle()
    signal openProfile(var profile)

    property int padding: 16
    readonly property int headerHeight: 54
    // Formularz zaczyna się pod nazwą, nie pod ikoną.
    readonly property int formX: padding + 20 + 12

    readonly property var profile: network ? network.profile : null
    readonly property string ssid: manual ? ssidField.text.trim() : (network ? network.ssid : "")
    readonly property string securityKey: manual ? securityChoice.value : (network ? network.securityKey : "open")
    readonly property bool needsPsk: profile === null && WifiService.needsSecret(securityKey)
    readonly property bool needsEap: profile === null && securityKey === "wpa-eap"

    readonly property bool connecting: WifiService.connecting !== "" && WifiService.connecting === ssid
    readonly property string error: WifiService.connectErrorFor !== "" && WifiService.connectErrorFor === ssid
        ? WifiService.connectError : ""

    readonly property bool canConnect: !WifiService.busy && ssid !== ""
        && (!needsPsk || pskField.text.length >= (securityKey === "wep" ? 1 : 8))
        && (!needsEap || (identityField.text !== "" && eapPassword.text !== ""))

    width: parent ? parent.width : 0
    height: headerHeight + (expanded ? form.implicitHeight + 16 : 0)
    clip: true

    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    onExpandedChanged: {
        if (!expanded) return;
        // Fokus od razu tam, gdzie się pisze.
        if (manual) ssidField.focusInput();
        else if (needsPsk) pskField.focusInput();
        else if (needsEap) identityField.focusInput();
    }

    function connect() {
        if (!canConnect) return;
        if (profile !== null) {
            WifiService.connectSaved(profile, network ? network.bssid : "");
            return;
        }
        const req = {
            ssid: ssid,
            security: securityKey,
            hidden: manual,
            autoconnect: autoSwitch.checked
        };
        if (needsPsk) req.psk = pskField.text;
        if (needsEap) {
            req.eap = eapChoice.value;
            req.identity = identityField.text;
            req.password = eapPassword.text;
        }
        WifiService.connectNew(req);
    }

    // Po udanym połączeniu wiersz znika z listy (sieć idzie do sekcji
    // „Połączenie”), a pole hasła nie powinno go przeżyć.
    Connections {
        target: WifiService
        function onConnectingChanged() {
            if (WifiService.connecting === "" && row.error === "" && row.expanded) {
                pskField.text = "";
                eapPassword.text = "";
                if (row.manual) row.toggle();
            }
        }
    }

    // ---- nagłówek ----

    Rectangle {
        visible: row.Positioner.index > 0
        x: row.padding
        width: row.width - 2 * row.padding
        height: 1
        color: Theme.border
    }

    Item {
        id: header
        width: row.width
        height: row.headerHeight

        Rectangle {
            x: 4
            y: 3
            width: parent.width - 8
            height: parent.height - 6
            radius: 10
            color: Theme.surface
            opacity: headerMouse.containsMouse && !row.expanded ? 1 : 0

            Behavior on opacity { NumberAnimation { duration: Theme.quickMs } }
        }

        Icon {
            x: row.padding
            anchors.verticalCenter: parent.verticalCenter
            size: 20
            kind: row.manual ? "wifi" : WifiService.signalIcon(row.network ? row.network.signal : 0)
            ghost: row.manual ? "" : "wifi"
            color: row.manual ? Theme.textDim : Theme.text
            ghostColor: Theme.alpha(Theme.text, 0.16)
        }

        Column {
            x: row.formX
            anchors.verticalCenter: parent.verticalCenter
            width: tail.x - x - 12
            spacing: 3

            Text {
                width: parent.width
                text: row.manual ? "Inna sieć…" : row.network ? row.network.ssid : ""
                color: Theme.text
                font.pixelSize: 13
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                color: row.connecting ? Theme.accent : Theme.textDim
                font.pixelSize: 12
                elide: Text.ElideRight
                text: {
                    if (row.connecting) return "Łączę…";
                    if (row.manual) return "Sieć ukryta albo spoza listy";
                    const n = row.network;
                    if (!n) return "";
                    const parts = [n.security !== "" ? n.security : "Otwarta", WifiService.bandsLabel(n.bands)];
                    if (row.profile) parts.push("zapisana");
                    return parts.join(" · ");
                }
            }
        }

        Row {
            id: tail
            anchors.right: parent.right
            anchors.rightMargin: row.padding - 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                visible: !row.manual
                anchors.verticalCenter: parent.verticalCenter
                text: row.network ? row.network.signal + "%" : ""
                color: Theme.textFaint
                font.pixelSize: 12
            }

            Icon {
                visible: !row.manual && row.network !== null && row.network.securityKey !== "open"
                anchors.verticalCenter: parent.verticalCenter
                kind: "lock"
                size: 14
                color: Theme.textFaint
            }

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                kind: "expand"
                size: 20
                rotation: row.expanded ? 180 : 0
                color: headerMouse.containsMouse ? Theme.text : Theme.textFaint

                Behavior on rotation { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.OutCubic } }
            }
        }

        MouseArea {
            id: headerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.toggle()
        }
    }

    // ---- formularz ----

    Column {
        id: form

        x: row.formX
        y: row.headerHeight
        width: row.width - x - row.padding
        spacing: 10
        opacity: row.expanded ? 1 : 0
        enabled: row.expanded && !row.connecting

        Behavior on opacity { NumberAnimation { duration: Theme.fadeMs } }

        // Sieć ukryta: nazwa i zabezpieczenia.
        Row {
            visible: row.manual
            spacing: 8

            SettingsField {
                id: ssidField
                width: 220
                placeholder: "Nazwa sieci (SSID)"
                commitOnBlur: false
                onAccepted: row.needsPsk ? pskField.focusInput() : row.connect()
            }

            SettingsChoice {
                id: securityChoice
                width: 200
                value: "wpa-psk"
                model: [
                    { value: "wpa-psk", label: "WPA/WPA2 Personal" },
                    { value: "sae", label: "WPA3 Personal" },
                    { value: "wpa-eap", label: "WPA/WPA2 Enterprise" },
                    { value: "wep", label: "WEP" },
                    { value: "owe", label: "Otwarta, szyfrowana (OWE)" },
                    { value: "open", label: "Otwarta" }
                ]
                onPicked: v => value = v
            }
        }

        // Sieć firmowa (802.1X): metoda, login, hasło.
        Row {
            visible: row.needsEap
            spacing: 8

            SettingsChoice {
                id: eapChoice
                width: 110
                value: "peap"
                model: [
                    { value: "peap", label: "PEAP" },
                    { value: "ttls", label: "TTLS" },
                    { value: "pwd", label: "PWD" }
                ]
                onPicked: v => value = v
            }

            SettingsField {
                id: identityField
                width: 150
                placeholder: "Login"
                commitOnBlur: false
                onAccepted: eapPassword.focusInput()
            }

            SettingsField {
                id: eapPassword
                width: 150
                secret: true
                placeholder: "Hasło"
                commitOnBlur: false
                onAccepted: row.connect()
            }
        }

        SettingsField {
            id: pskField
            visible: row.needsPsk
            width: 260
            secret: true
            placeholder: row.securityKey === "wep" ? "Klucz WEP" : "Hasło (co najmniej 8 znaków)"
            commitOnBlur: false
            onAccepted: row.connect()
        }

        Text {
            visible: !row.manual && row.profile === null && row.securityKey === "open"
            width: parent.width
            wrapMode: Text.Wrap
            text: "Sieć otwarta: to, co wysyłasz, nie jest szyfrowane."
            color: Theme.warning
            font.pixelSize: 12
        }

        Row {
            visible: row.profile === null
            spacing: 10

            SettingsSwitch {
                id: autoSwitch
                anchors.verticalCenter: parent.verticalCenter
                checked: true
                onToggled: checked = !checked
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Łącz automatycznie"
                color: Theme.textDim
                font.pixelSize: 12
            }
        }

        Row {
            spacing: 8

            SettingsButton {
                text: row.connecting ? "Łączę…" : "Połącz"
                primary: true
                enabled: row.canConnect
                onClicked: row.connect()
            }

            SettingsButton {
                visible: row.profile !== null
                text: "Ustawienia sieci"
                onClicked: row.openProfile(row.profile)
            }
        }

        Text {
            visible: row.error !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: row.error
            color: Theme.danger
            font.pixelSize: 12
        }
    }
}
