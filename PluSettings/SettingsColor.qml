import QtQuick
import qs.Common

// Wybór koloru z rzędu próbek. Jak przełącznik: sama nie zmienia `value`,
// tylko zgłasza `picked`. Kolor spoza próbek (wpisany ręcznie w pliku)
// staje na początku rzędu jako zaznaczony, zamiast zniknąć z widoku.
Row {
    id: picker

    property string value: ""
    property var presets: ["#f2f2f2", "#38d47a", "#30d158", "#5b8cff", "#bf5af2", "#ff9f0a", "#f0b232", "#ff453a"]

    signal picked(string value)

    readonly property var swatches: {
        const v = value.toLowerCase();
        const known = presets.some(p => p.toLowerCase() === v);
        return known || v === "" ? presets : [value].concat(presets);
    }

    spacing: 6
    opacity: enabled ? 1 : 0.35

    Repeater {
        model: picker.swatches

        Item {
            id: swatch

            required property string modelData
            readonly property bool current: modelData.toLowerCase() === picker.value.toLowerCase()

            // 22 z pierścieniem 2 px w środku i 2 px odstępu — parzyście,
            // żeby koło nie siadało na pół piksela.
            width: 22
            height: 22

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                antialiasing: true
                color: "transparent"
                border.width: 2
                border.color: swatch.current ? Theme.text
                    : mouse.containsMouse ? Theme.textFaint : "transparent"

                Behavior on border.color { ColorAnimation { duration: Theme.quickMs } }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 14
                height: 14
                radius: 7
                antialiasing: true
                color: swatch.modelData
                scale: mouse.pressed ? 0.85 : 1

                Behavior on scale { NumberAnimation { duration: Theme.quickMs; easing.type: Easing.OutQuad } }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (!swatch.current) picker.picked(swatch.modelData)
            }
        }
    }
}
