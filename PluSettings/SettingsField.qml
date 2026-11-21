import QtQuick
import qs.Common

// Pole tekstowe (z IslandTextField wyspy). Zapis dopiero przy Enterze
// albo wyjściu z pola (`committed`) — zapis po każdej literze podmieniałby
// terminal w połowie wpisywanej nazwy.
//
// Formularze (hasło do sieci) czytają `text` i reagują na `accepted`
// (sam Enter), a `secret` zamienia pole w hasło z okiem do podglądu.
//
// Pole jest źródłem prawdy dla swojej treści (pułapka `text:` z wyspy):
// `value` wpisujemy do niego tylko wtedy, gdy nikt w nim nie pisze —
// inaczej zmiana pliku z zewnątrz skasowałaby to, co wpisujesz.
Item {
    id: field

    property string value: ""
    property string placeholder: ""
    property bool invalid: false
    property bool secret: false
    property bool revealed: false
    // Bez zapisu przy wyjściu z pola: formularz sam decyduje, kiedy wysłać.
    property bool commitOnBlur: true
    property alias text: input.text

    signal committed(string text)
    signal accepted()
    // Pierwsze odsłonięcie hasła: strona może wtedy dopiero je wczytać.
    signal revealRequested()

    readonly property bool focused: input.activeFocus

    function focusInput() { input.forceActiveFocus(); }

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
            : Theme.alpha(Theme.text, boxMouse.containsMouse ? 0.18 : 0.08)

        Behavior on border.color { ColorAnimation { duration: Theme.quickMs } }

        TextInput {
            id: input

            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: field.secret ? eye.width + 6 : 10
            verticalAlignment: TextInput.AlignVCenter
            echoMode: field.secret && !field.revealed ? TextInput.Password : TextInput.Normal
            passwordCharacter: "•"
            color: Theme.text
            font.pixelSize: 13
            selectionColor: Theme.accent
            selectedTextColor: Theme.accentInk
            selectByMouse: true
            clip: true
            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase

            onEditingFinished: if ((field.commitOnBlur || activeFocus) && text !== field.value) field.committed(text)
            onAccepted: field.accepted()

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

        // Podgląd hasła.
        Item {
            id: eye

            visible: field.secret
            width: 30
            height: parent.height
            anchors.right: parent.right

            Icon {
                anchors.centerIn: parent
                kind: field.revealed ? "eyeOff" : "eye"
                size: 16
                color: eyeMouse.containsMouse ? Theme.text : Theme.textDim

                Behavior on color { ColorAnimation { duration: Theme.quickMs } }
            }

            MouseArea {
                id: eyeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!field.revealed) field.revealRequested();
                    field.revealed = !field.revealed;
                }
            }
        }
    }
}
