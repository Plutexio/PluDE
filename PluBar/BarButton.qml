import QtQuick
import qs.Common

// Jedna kontrolka paska: ikona (albo własna treść) w zaokrąglonym polu.
//
// Własna MouseArea na każdej kontrolce jest tu w porządku, inaczej niż
// w docku: pasek się nie chowa, więc „kradzież” hovera przez element
// wyżej niczego nie zwija. Najechanie liczy Bar, żeby pokazać podpowiedź.
Item {
    id: root

    property string icon: ""
    property string ghost: ""
    property color iconColor: Theme.text
    property string label: ""
    property color labelColor: Theme.text
    // Podpowiedź: tytuł (stan) i druga linia z tym, co robią kliknięcia.
    property string tip: ""
    property string hint: ""
    // Kropka stanu w rogu (np. sieć bez internetu).
    property color dotColor: "transparent"
    // Kontrolka „włączona” (otwarty panel): tło jak przy najechaniu.
    property bool active: false

    // Wskakiwanie przy pokazaniu paska: Bar ustawia shown i opóźnienie
    // z odległości od wyspy (fala od środka ekranu na zewnątrz).
    property bool shown: true
    property int delay: 0

    // Pasek, któremu zgłaszamy najechanie (podpowiedź). null = bez podpowiedzi.
    property var bar: null

    property int size: 30
    property int iconSize: 16
    property int wheelStepDelta: 120

    // Własna treść zamiast ikony (bateria).
    default property alias content: custom.data

    readonly property bool hovered: mouse.containsMouse
    readonly property bool pressed: mouse.pressed

    onHoveredChanged: if (bar) bar.noteHover(root, hovered)

    signal clicked()
    signal rightClicked()
    signal middleClicked()
    // Pełne ząbki kółka: +1 w górę, −1 w dół.
    signal stepped(int steps)

    implicitWidth: Math.ceil(Math.max(size, row.implicitWidth + (label !== "" ? 16 : 0)))
    implicitHeight: size

    // ---- wskakiwanie ----
    // Zwykła wartość, nie powiązanie shown ? 1 : 0 — pułapka z docka:
    // animacja powiązania nie zrywa i czekające elementy znikały bez animacji.
    property real appear: 0
    Component.onCompleted: if (shown) appearIn.start()
    onShownChanged: {
        appearIn.stop();
        appearOut.stop();
        if (shown) appearIn.start(); else appearOut.start();
    }

    SequentialAnimation {
        id: appearIn
        PauseAnimation { duration: root.delay }
        NumberAnimation {
            target: root; property: "appear"; to: 1
            duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.6
        }
    }

    NumberAnimation {
        id: appearOut
        target: root; property: "appear"; to: 0
        duration: 170; easing.type: Easing.InCubic
    }

    // ---- wygląd ----

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        // Pełne kolory, bez alfy (DESIGN.md): odcienie policzone do tła paska.
        color: root.pressed ? "#2a2a2c"
             : (root.hovered || root.active) ? Theme.surfaceRaised
             : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.quickMs } }
    }

    Item {
        anchors.fill: parent
        scale: (0.4 + 0.6 * root.appear) * (root.pressed ? 0.9 : 1)
        opacity: Math.min(1, root.appear)
        Behavior on scale { enabled: root.appear >= 1; NumberAnimation { duration: Theme.quickMs } }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 5

            Icon {
                visible: root.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                kind: root.icon
                ghost: root.ghost
                size: root.iconSize
                color: root.iconColor
                Behavior on color { ColorAnimation { duration: Theme.fadeMs } }
            }

            Item {
                id: custom
                visible: children.length > 0
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: childrenRect.width
                implicitHeight: childrenRect.height
                width: implicitWidth
                height: implicitHeight
            }

            Text {
                visible: root.label !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                color: root.labelColor
                font.pixelSize: 12
                font.bold: true
            }
        }

        Rectangle {
            visible: root.dotColor.a > 0
            x: parent.width / 2 + root.iconSize / 2 - 4
            y: parent.height / 2 - root.iconSize / 2 - 1
            width: 6
            height: 6
            radius: 3
            color: root.dotColor
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onClicked: event => {
            if (event.button === Qt.RightButton) root.rightClicked();
            else if (event.button === Qt.MiddleButton) root.middleClicked();
            else root.clicked();
        }

        // Sumowanie do pełnego ząbka: touchpad przysyła ~10 jednostek na
        // zdarzenie i bez tego jedno machnięcie dawało kilkanaście kroków
        // (zmierzone w wyspie: +60% zamiast +3%).
        property real acc: 0
        onWheel: event => {
            acc += event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x;
            const n = Math.trunc(acc / root.wheelStepDelta);
            if (n !== 0) {
                acc -= n * root.wheelStepDelta;
                root.stepped(n);
            }
        }
        onExited: acc = 0
    }
}
