import QtQuick
import QtQuick.Effects

// Miękki cień albo poświata pod elementem: rozmyty prostokąt w kolorze.
//
// Rozmywamy osobny, płaski prostokąt, a nie sam element (MultiEffect na
// pigułce czy panelu rysowałby całą treść drugi raz przy każdej zmianie).
// Stawiać POD elementem, z tym samym kształtem (anchors.fill + radius);
// środek zasłania element, widać tylko rozmyty brzeg.
//
// Kolor czarny = cień, akcent = poświata.
Item {
    id: root

    property color color: "black"
    property real radius: 0
    // Jak daleko sięga rozmycie (px).
    property int blur: 24
    // Rozdęcie kształtu przed rozmyciem (px na stronę).
    property real spread: 0
    // Przesunięcie (cień pada w dół).
    property real offsetY: 0
    property real strength: 0.5

    Rectangle {
        id: shape
        x: -root.spread
        y: -root.spread + root.offsetY
        width: root.width + 2 * root.spread
        height: root.height + 2 * root.spread
        radius: root.radius + root.spread
        color: root.color
        visible: false
    }

    MultiEffect {
        source: shape
        x: shape.x
        y: shape.y
        width: shape.width
        height: shape.height
        autoPaddingEnabled: true
        blurEnabled: true
        blur: 1
        blurMax: root.blur
        opacity: root.strength
    }
}
