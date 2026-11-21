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
    // Kolor najechania, fali i aktywnej ikony. Zasilanie: danger.
    property color tint: Theme.accent
    property color tintBright: Theme.accentBright
    // Obrót ikony w stopniach (słońce jasności kręci się z wartością).
    property real iconRotation: 0
    Behavior on iconRotation { NumberAnimation { duration: 480; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

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
    // Warstwa nad ikoną, w środku przycisku (fale głośnika). Nie skaluje
    // się z wciśnięciem, żeby fale nie drgały razem z ikoną.
    property alias overlay: overlayItem.data

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

    // ---- reakcje ----
    // kick: ikona podskakuje (zmiana stanu: wyciszenie, nowe połączenie,
    // tryb energii). shake: kręci „nie” (wyłączenie, błąd). Z zewnątrz, bo
    // tylko właściciel wie, co znaczy zmiana.
    property real kickScale: 1
    property real shakeX: 0

    function kick() { kickAnim.restart(); }
    function shake() { shakeAnim.restart(); }

    SequentialAnimation {
        id: kickAnim
        NumberAnimation { target: root; property: "kickScale"; to: 1.32; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "kickScale"; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 3 }
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "shakeX"; to: -3.5; duration: 55; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 3; duration: 90; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: -2; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 1; duration: 70; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 60; easing.type: Easing.OutQuad }
    }

    // ---- wygląd ----

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        // Pełne kolory: akcent zmieszany z tłem pigułki (DESIGN.md: bez alfy
        // na elementach, inaczej prześwituje).
        color: root.pressed ? Theme.mix(Theme.surface, root.tint, 0.3)
             : root.active ? Theme.mix(Theme.surface, root.tint, 0.22)
             : root.hovered ? Theme.mix(Theme.surface, root.tint, 0.13)
             : Theme.surface
        opacity: root.pressed || root.active || root.hovered ? 1 : 0
        Behavior on color { ColorAnimation { duration: Theme.quickMs } }
        Behavior on opacity { NumberAnimation { duration: Theme.quickMs } }
    }

    // Fala od kliknięcia. Wychodzi poza przycisk, a przycina ją pigułka
    // (ClippingRectangle), więc rozlewa się po pasku.
    Ripple {
        id: ripple
        anchors.fill: parent
        color: root.tint
        reach: root.size * 1.6
    }

    // Ikona w kolorze akcentu przy najechaniu i otwartym panelu, chyba że
    // ma własny kolor stanu (wyciszony mikrofon, tryb energii).
    readonly property bool plainIcon: Qt.colorEqual(iconColor, Theme.text)
    readonly property color shownIconColor: plainIcon && (hovered || active) ? tintBright : iconColor

    Item {
        id: body
        anchors.fill: parent
        transform: Translate { x: root.shakeX }
        // Wciśnięcie: zapada się szybko, po puszczeniu odbija sprężyście
        // (pressScale z Behavior, osobno od wskakiwania i kick).
        property real pressScale: root.pressed ? 0.82 : 1
        Behavior on pressScale {
            NumberAnimation {
                duration: root.pressed ? 90 : 460
                easing.type: root.pressed ? Easing.OutQuad : Easing.OutBack
                easing.overshoot: 3.2
            }
        }
        scale: (0.4 + 0.6 * root.appear) * pressScale * root.kickScale
        opacity: Math.min(1, root.appear)

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
                color: root.shownIconColor
                rotation: root.iconRotation
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
                font.features: { "tnum": 1 }
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
            border.width: 1.5
            border.color: Theme.surface
        }
    }

    Item {
        id: overlayItem
        anchors.fill: parent
        opacity: Math.min(1, root.appear)
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onPressed: event => ripple.burst(event.x, event.y)
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
