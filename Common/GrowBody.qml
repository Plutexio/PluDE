import QtQuick

// Tło panelu, które wyrasta z kontrolki: zaczyna jako mała pigułka pod
// nią (originX) i rozrasta się do pełnego prostokąta. Treść stoi w miejscu
// (w układzie okna), a rosnące tło ją odsłania; pojawia się, kiedy tło
// jest już prawie całe.
//
// Wszystko z jednej wartości `reveal` (DESIGN.md), którą animuje okno
// panelu (OutBack: przestrzał rozciąga też tło, nie tylko treść).
//
// Wokół tła jest margines na cień (sidePad / bottomPad), więc okno panelu
// ma implicitWidth / implicitHeight z tego elementu, nie z treści.
Item {
    id: root

    property real reveal: 1
    // Środek kontrolki w układzie tego elementu (x), od którego rośnie tło.
    property real originX: width / 2
    // Docelowy rozmiar tła (treść + jej marginesy).
    property real contentWidth: 280
    property real contentHeight: 100
    property real radius: 16

    // Ziarenko, z którego rośnie tło: pigułka szerokości kontrolki.
    property real seedWidth: 30
    property real seedHeight: 10

    property int sidePad: 18
    property int topPad: 2
    property int bottomPad: 26

    default property alias content: inner.data
    readonly property alias body: body

    implicitWidth: contentWidth + 2 * sidePad
    implicitHeight: contentHeight + topPad + bottomPad

    // Szerokość rusza od razu, wysokość chwilę później: najpierw pigułka
    // rozlewa się na boki, potem opada w dół.
    readonly property real ew: reveal
    readonly property real eh: Math.max(0, (reveal - 0.12) / 0.88)
    readonly property real seedX: originX - seedWidth / 2

    SoftGlow {
        x: body.x
        y: body.y
        width: body.width
        height: body.height
        radius: body.radius
        offsetY: 6
        blur: 28
        strength: 0.6 * Math.min(1, root.reveal)
    }

    Rectangle {
        id: body

        x: root.seedX + (root.sidePad - root.seedX) * root.ew
        y: root.topPad
        width: Math.max(root.seedWidth * 0.6, root.seedWidth + (root.contentWidth - root.seedWidth) * root.ew)
        height: Math.max(4, root.seedHeight + (root.contentHeight - root.seedHeight) * root.eh)
        radius: Math.min(root.radius, height / 2)
        color: Theme.surface
        border.width: 1
        border.color: Theme.mix(Theme.border, Theme.accent, 0.25)
        clip: true
        opacity: Math.min(1, root.reveal * 3)

        Item {
            id: inner
            // Treść w stałym miejscu okna, niezależnie od rosnącego tła.
            x: root.sidePad - body.x
            width: root.contentWidth
            height: root.contentHeight
            opacity: Math.max(0, Math.min(1, (root.reveal - 0.45) / 0.4))
            transform: Translate { y: -6 * (1 - Math.min(1, root.reveal)) }
        }
    }
}
