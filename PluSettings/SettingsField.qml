import QtQuick
import qs.Common

// Pole tekstowe (z IslandTextField wyspy, bez hasła). Zapis dopiero przy
// Enterze albo wyjściu z pola (`committed`) — zapis po każdej literze
// podmieniałby terminal w połowie wpisywanej nazwy.
//
// Pole jest źródłem prawdy dla swojej treści (pułapka `text:` z wyspy):
// `value` wpisujemy do niego tylko wtedy, gdy nikt w nim nie pisze —
// inaczej zmiana pliku z zewnątrz skasowałaby to, co wpisujesz.
Item {
    id: field

    property string value: ""
    property string placeholder: ""
    property bool invalid: false

    signal committed(string text)

    readonly property bool focused: input.activeFocus

    implicitWidth: 240
    implicitHeight: 32
    opacity: enabled ? 1 : 0.4

    onValueChanged: if (!input.activeFocus) input.text = value
    Component.onCompleted: input.text = value

    Rectangle {
        anchors.fill: parent
        radius: 10
        antialiasing: true
        // Na karcie (surfaceRaised) pole jest wklęsłe: tło okna.
        color: Theme.surface
        border.width: 1
        border.color: field.invalid ? Theme.danger
            : field.focused ? Theme.accent
            : Qt.rgba(1, 1, 1, boxMouse.containsMouse ? 0.18 : 0.08)

        Behavior on border.color { ColorAnimation { duration: Theme.quickMs } }

        TextInput {
            id: input

            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            font.pixelSize: 13
            selectionColor: Theme.accent
            selectedTextColor: "#ffffff"
            selectByMouse: true
            clip: true
            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase

            onEditingFinished: if (text !== field.value) field.committed(text)

            // Esc cofa wpisane i wychodzi z pola. Połknięty tutaj, żeby nie
            // zamknął przy okazji całego okna.
            Keys.onEscapePressed: event => {
                text = field.value;
                focus = false;
                event.accepted = true;
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: field.placeholder
                color: Theme.textFaint
                font: input.font
                visible: input.text === "" && !input.activeFocus
            }
        }

        MouseArea {
            id: boxMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.IBeamCursor
            // Tylko hover i kursor; klik idzie dalej do TextInputa.
            acceptedButtons: Qt.NoButton
        }
    }
}
