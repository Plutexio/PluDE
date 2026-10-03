import QtQuick
import qs.Common

// Jedno ustawienie: nazwa i opis po lewej, kontrolka po prawej.
Item {
    id: row

    property string title: ""
    property string description: ""
    // Kontrolka (przełącznik, pole, lista).
    default property alias control: slot.data

    property int padding: 16
    property int minHeight: 56

    // Opcjonalny reset do wartości domyślnej (strona „Wyspa”): mała
    // strzałka przed kontrolką, widoczna tylko przy `modified`. Miejsce na
    // nią jest zarezerwowane przy `resettable`, żeby opis nie przelewał się
    // w chwili, gdy strzałka się pojawia.
    property bool resettable: false
    property bool modified: false
    signal reset()
    readonly property int resetSpace: resettable ? resetButton.width + 8 : 0

    width: parent ? parent.width : 0
    implicitHeight: Math.max(minHeight, texts.implicitHeight + 2 * 14, slot.height + 2 * 12)

    // Kreska nad każdym wierszem oprócz pierwszego w karcie.
    Rectangle {
        visible: row.Positioner.index > 0
        x: row.padding
        width: row.width - 2 * row.padding
        height: 1
        color: Theme.border
    }

    Column {
        id: texts
        x: row.padding
        anchors.verticalCenter: parent.verticalCenter
        width: row.width - 3 * row.padding - slot.width - row.resetSpace
        spacing: 3

        Text {
            width: parent.width
            text: row.title
            color: Theme.text
            font.pixelSize: 13
            elide: Text.ElideRight
        }

        Text {
            visible: text !== ""
            width: parent.width
            text: row.description
            color: Theme.textDim
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
    }

    Item {
        id: resetButton

        // 24 przy kontrolkach 20–32: środek wypada na pełnym pikselu.
        width: 24
        height: 24
        anchors.right: slot.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        visible: row.resettable && opacity > 0.01
        opacity: row.modified ? 1 : 0
        scale: row.modified ? (resetMouse.pressed ? 0.85 : 1) : 0.6

        Behavior on opacity { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            antialiasing: true
            color: resetMouse.containsMouse ? Theme.surface : "transparent"

            Behavior on color { ColorAnimation { duration: Theme.quickMs } }
        }

        Icon {
            anchors.centerIn: parent
            kind: "undo"
            size: 16
            color: resetMouse.containsMouse ? Theme.accent : Theme.textDim

            Behavior on color { ColorAnimation { duration: Theme.quickMs } }
        }

        MouseArea {
            id: resetMouse
            anchors.fill: parent
            enabled: row.modified
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.reset()
        }
    }

    Item {
        id: slot
        anchors.right: parent.right
        anchors.rightMargin: row.padding
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}
