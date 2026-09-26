import QtQuick
import qs.Common

// Lista wyboru. Rozwinięta lista to wspólny ChoiceMenu okna ustawień
// (SettingsApp.menu), rysowany w oknie, a nie osobny popup — powód
// w ChoiceMenu.qml.
Item {
    id: choice

    // [{ value, label }]
    property var model: []
    property var value: null

    // Jak przełącznik: sama nie ustawia value, tylko zgłasza wybór.
    signal picked(var value)

    readonly property bool expanded: SettingsApp.menu !== null && SettingsApp.menu.owner === choice

    readonly property string valueLabel: {
        for (let i = 0; i < model.length; i++)
            if (model[i].value === value) return model[i].label;
        return "—";
    }

    implicitWidth: 240
    implicitHeight: 32
    opacity: enabled ? 1 : 0.4

    // Wyłączona albo znikająca lista (np. zmiana monitora) zamyka menu.
    onEnabledChanged: if (!enabled && expanded) SettingsApp.menu.close()
    onVisibleChanged: if (!visible && expanded) SettingsApp.menu.close()
    Component.onDestruction: if (expanded) SettingsApp.menu.close()

    Rectangle {
        anchors.fill: parent
        radius: 10
        antialiasing: true
        color: Theme.surface
        border.width: 1
        border.color: choice.expanded ? Theme.accent
            : Qt.rgba(1, 1, 1, mouse.containsMouse ? 0.18 : 0.08)

        Behavior on border.color { ColorAnimation { duration: Theme.quickMs } }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: arrow.left
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: choice.valueLabel
            color: Theme.text
            font.pixelSize: 13
        }

        Icon {
            id: arrow
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            kind: "expand"
            size: 16
            color: mouse.containsMouse || choice.expanded ? Theme.text : Theme.textDim
            rotation: choice.expanded ? 180 : 0

            Behavior on rotation { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.OutCubic } }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Zamykanie drugim klikiem łapie ChoiceMenu (klik w pole, które
        // listę otworzyło), więc tutaj tylko otwarcie.
        onClicked: if (SettingsApp.menu && choice.model.length > 0) SettingsApp.menu.show(choice, choice.model, choice.value)
    }
}
