import QtQuick
import qs.Common

// „Zachować?” po zmianie monitorów. Widoczne, dopóki MonitorService czeka
// na potwierdzenie; bez odpowiedzi serwis sam cofa zmianę (i strażnik poza
// procesem, gdyby powłoka zniknęła). Enter zachowuje, Esc cofa.
//
// Wzorzec panelu pełnoekranowego z DESIGN.md: przyciemnienie 0.45, karta
// wchodzi sprężyście, wychodzi krótko i bez odbicia.
FocusScope {
    id: root

    property int cardWidth: 400

    readonly property bool on: MonitorService.pending

    // Jedna wartość dla przyciemnienia, skali i krycia karty.
    property real reveal: 0

    visible: reveal > 0.001

    onOnChanged: {
        if (on) {
            hideAnim.stop();
            showAnim.restart();
            progressAnim.restart();
            root.forceActiveFocus();
        } else {
            showAnim.stop();
            hideAnim.restart();
            progressAnim.stop();
            // Fokus wraca do okna — inaczej Esc (zamknij okno) by nie działał.
            if (root.parent) root.parent.forceActiveFocus();
        }
    }

    NumberAnimation {
        id: showAnim
        target: root
        property: "reveal"
        to: 1
        duration: 440
        easing.type: Easing.OutBack
        easing.overshoot: 1.1
    }

    NumberAnimation {
        id: hideAnim
        target: root
        property: "reveal"
        to: 0
        duration: 170
        easing.type: Easing.InCubic
    }

    Keys.onReturnPressed: MonitorService.confirm()
    Keys.onEnterPressed: MonitorService.confirm()
    Keys.onEscapePressed: MonitorService.revert()

    Rectangle {
        anchors.fill: parent
        color: "black"
        // Przycięte do 1: przestrzał sprężyny nie przyciemnia mocniej.
        opacity: 0.45 * Math.min(1, root.reveal)
    }

    // Klik obok karty nic nie robi (i nie dochodzi do strony pod spodem):
    // decyzja ma być świadoma.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPressed: root.forceActiveFocus()
    }

    Rectangle {
        id: card

        anchors.centerIn: parent
        anchors.verticalCenterOffset: (1 - root.reveal) * 28
        width: root.cardWidth
        height: body.implicitHeight + 48
        radius: 22
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
        opacity: Math.min(1, root.reveal)
        scale: 0.9 + 0.1 * root.reveal

        Column {
            id: body

            x: 24
            y: 24
            width: parent.width - 48
            spacing: 14

            Text {
                width: parent.width
                text: "Zachować ustawienia monitorów?"
                color: Theme.text
                font.pixelSize: 16
                font.bold: true
                wrapMode: Text.Wrap
            }

            Text {
                width: parent.width
                text: "Bez odpowiedzi wracam do poprzednich za "
                    + MonitorService.confirmRemaining + " s."
                color: Theme.textDim
                font.pixelSize: 13
                wrapMode: Text.Wrap
            }

            // Upływ czasu płynnie, nie skokami co sekundę.
            Rectangle {
                width: parent.width
                height: 4
                radius: 2
                color: Theme.surfaceRaised

                Rectangle {
                    id: progress
                    property real remaining: 1
                    width: parent.width * remaining
                    height: parent.height
                    radius: 2
                    color: Theme.warning
                }

                NumberAnimation {
                    id: progressAnim
                    target: progress
                    property: "remaining"
                    from: 1
                    to: 0
                    duration: MonitorService.confirmSeconds * 1000
                }
            }

            Item {
                width: parent.width
                height: buttons.height

                // Klawisze jak w podpowiedziach PluDE: enter w akcencie,
                // esc w kolorze ostrzeżenia.
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.StyledText
                    text: "<font color='" + Theme.accent + "'>enter</font> zachowaj · "
                        + "<font color='" + Theme.warning + "'>esc</font> cofnij"
                    color: Theme.textFaint
                    font.pixelSize: 11
                }

                Row {
                    id: buttons
                    anchors.right: parent.right
                    spacing: 8

                    SettingsButton {
                        text: "Cofnij"
                        tint: Theme.warning
                        onClicked: MonitorService.revert()
                    }

                    SettingsButton {
                        text: "Zachowaj"
                        primary: true
                        onClicked: MonitorService.confirm()
                    }
                }
            }
        }
    }
}
