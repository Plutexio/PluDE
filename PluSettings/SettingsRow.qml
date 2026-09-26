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
        width: row.width - 3 * row.padding - slot.width
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
        id: slot
        anchors.right: parent.right
        anchors.rightMargin: row.padding
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}
