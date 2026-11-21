import QtQuick
import qs.Common

// Wiersz, który coś otwiera (podstronę, rozwinięcie listy): ikona, nazwa,
// opis, po prawej krótka wartość i strzałka. Cały wiersz jest klikalny.
Item {
    id: row

    property string title: ""
    property string description: ""
    property string icon: ""
    property string ghost: ""
    property color iconColor: Theme.textDim
    property string trailing: ""
    property bool chevron: true
    property color titleColor: Theme.text

    signal clicked()

    property int padding: 16
    property int minHeight: 52

    readonly property bool hovering: mouse.containsMouse && row.enabled

    width: parent ? parent.width : 0
    implicitHeight: Math.max(minHeight, texts.implicitHeight + 2 * 12)
    opacity: enabled ? 1 : 0.4

    // Kreska nad każdym wierszem oprócz pierwszego w karcie (jak SettingsRow).
    Rectangle {
        visible: row.Positioner.index > 0
        x: row.padding
        width: row.width - 2 * row.padding
        height: 1
        color: Theme.border
    }

    // Podświetlenie wcięte w kartę, żeby nie wystawało za jej zaokrąglenie.
    Rectangle {
        x: 4
        y: 3
        width: row.width - 8
        height: row.height - 6
        radius: 10
        color: Theme.surface
        opacity: row.hovering ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: Theme.quickMs } }
    }

    Icon {
        id: leading
        visible: row.icon !== ""
        x: row.padding
        anchors.verticalCenter: parent.verticalCenter
        kind: row.icon
        ghost: row.ghost
        size: 20
        color: row.iconColor
    }

    Column {
        id: texts
        x: row.icon !== "" ? leading.x + leading.width + 12 : row.padding
        anchors.verticalCenter: parent.verticalCenter
        width: tail.x - x - 12
        spacing: 3

        Text {
            width: parent.width
            text: row.title
            color: row.titleColor
            font.pixelSize: 13
            elide: Text.ElideRight
        }

        Text {
            visible: text !== ""
            width: parent.width
            text: row.description
            color: Theme.textDim
            font.pixelSize: 12
            elide: Text.ElideRight
        }
    }

    Row {
        id: tail
        anchors.right: parent.right
        anchors.rightMargin: row.padding - (row.chevron ? 4 : 0)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Text {
            visible: text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: row.trailing
            color: Theme.textFaint
            font.pixelSize: 12
        }

        Icon {
            visible: row.chevron
            anchors.verticalCenter: parent.verticalCenter
            kind: "chevronRight"
            size: 20
            color: row.hovering ? Theme.text : Theme.textFaint

            Behavior on color { ColorAnimation { duration: Theme.quickMs } }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.clicked()
    }
}
