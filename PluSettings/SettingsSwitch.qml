import QtQuick
import qs.Common

// Przełącznik (tor + gałka), przepisany z IslandSwitch wyspy. Nie zmienia
// `checked` sam — zgłasza `toggled`, a stan ustawia właściciel. Dzięki temu
// przełącznik nie kłamie, kiedy zapis się nie uda.
Item {
    id: sw

    property bool checked: false
    // Jak w wyspie: zielony = „włączone, działa”.
    property color accent: Theme.success
    signal toggled()

    readonly property bool hovering: mouse.containsMouse && sw.enabled

    implicitWidth: 34
    implicitHeight: 20
    opacity: enabled ? 1 : 0.35

    Behavior on opacity { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        antialiasing: true
        color: sw.checked ? sw.accent : Qt.rgba(1, 1, 1, sw.hovering ? 0.22 : 0.14)

        Behavior on color { ColorAnimation { duration: Theme.fadeMs; easing.type: Easing.OutCubic } }

        Rectangle {
            // Gałka 16 w torze 20: po 2 px luzu, parzyste rozmiary, nic nie
            // ląduje na pół piksela.
            width: 16
            height: 16
            radius: 8
            antialiasing: true
            y: 2
            x: sw.checked ? parent.width - width - 2 : 2
            color: "#ffffff"
            scale: mouse.pressed ? 0.9 : 1

            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
            Behavior on scale { NumberAnimation { duration: Theme.quickMs; easing.type: Easing.OutQuad } }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled()
    }
}
