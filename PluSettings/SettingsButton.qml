import QtQuick
import qs.Common

// Przycisk z napisem (z IslandTextButton wyspy). primary = wypełniony
// akcentem (akcja domyślna), zwykły = obrysowany. tint zmienia kolor
// akcentu, np. Theme.warning dla „Cofnij”.
Item {
    id: btn

    property string text: ""
    property bool primary: false
    property color tint: Theme.accent

    signal clicked()

    readonly property bool hovering: mouse.containsMouse && btn.enabled

    implicitWidth: Math.max(96, label.implicitWidth + 32)
    implicitHeight: 32
    opacity: enabled ? 1 : 0.35

    Behavior on opacity { NumberAnimation { duration: Theme.fadeMs } }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        antialiasing: true
        color: btn.primary
            ? (btn.hovering ? Qt.lighter(btn.tint, 1.15) : btn.tint)
            : (btn.hovering ? Qt.tint(Theme.surfaceRaised, Qt.rgba(btn.tint.r, btn.tint.g, btn.tint.b, 0.2))
                            : Theme.surfaceRaised)
        border.width: btn.primary ? 0 : 1
        border.color: btn.hovering ? btn.tint : Qt.rgba(1, 1, 1, 0.1)
        scale: mouse.pressed ? 0.95 : 1

        Behavior on color { ColorAnimation { duration: Theme.quickMs } }
        Behavior on border.color { ColorAnimation { duration: Theme.quickMs } }
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

        Text {
            id: label
            anchors.centerIn: parent
            text: btn.text
            color: btn.primary ? "#ffffff" : Theme.text
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
