import QtQuick
import qs.Common

// Grupa ustawień: mały nagłówek nad kartą (jak nagłówki w menu), w karcie
// wiersze SettingsRow rozdzielone kreską.
Column {
    id: section

    property string title: ""
    default property alias rows: rowsColumn.data

    spacing: 8

    Text {
        visible: section.title !== ""
        x: 4
        text: section.title
        color: Theme.textDim
        font.pixelSize: 11
        font.bold: true
    }

    Rectangle {
        width: section.width
        height: rowsColumn.implicitHeight
        radius: 14
        color: Theme.surfaceRaised
        border.width: 1
        border.color: Theme.border

        Column {
            id: rowsColumn
            width: parent.width
        }
    }
}
