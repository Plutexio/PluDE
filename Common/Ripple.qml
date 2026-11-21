import QtQuick

// Fala od miejsca kliknięcia: koło w kolorze rośnie z punktu i blednie.
//
// Bez własnego przycinania. Fala wychodzi poza element i przycina ją
// rodzic (pigułka paska to ClippingRectangle), więc w pasku wygląda jak
// rozlanie po pigułce, a nie kółko w kwadracie.
//
// Kilka kliknięć pod rząd = kilka fal naraz (każda to osobny obiekt,
// niszczony po animacji).
Item {
    id: root

    property color color: Theme.accent
    // Krycie fali na starcie; potem spada do zera.
    property real strength: 0.4
    // Promień, do którego dorasta fala (px). 0 = do najdalszego rogu.
    property real reach: 0
    property int duration: 560

    function burst(px, py) {
        const far = reach > 0 ? reach
            : Math.max(Math.hypot(px, py), Math.hypot(width - px, py),
                       Math.hypot(px, height - py), Math.hypot(width - px, height - py));
        wave.createObject(root, { cx: px, cy: py, target: far });
    }

    Component {
        id: wave

        Rectangle {
            id: w
            property real cx: 0
            property real cy: 0
            property real target: 40
            property real t: 0

            x: cx - width / 2
            y: cy - height / 2
            width: 2 * target * (0.15 + 0.85 * t)
            height: width
            radius: width / 2
            color: root.color
            // Szybko rośnie, wolniej blednie: zanik zaczyna się w połowie.
            opacity: root.strength * Math.min(1, 2 * (1 - t))

            NumberAnimation on t {
                from: 0; to: 1
                duration: root.duration
                easing.type: Easing.OutCubic
                onFinished: w.destroy()
            }
        }
    }
}
