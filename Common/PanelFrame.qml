import QtQuick

// Tło dużego panelu (launcher, schowek): poświata w kolorze akcentu wokół,
// obrys 1 px w gradiencie akcent → drugi akcent i tło z ledwie widocznym
// odcieniem akcentu u góry.
//
// Obrys gradientem to dwa prostokąty: zewnętrzny w gradiencie, wewnętrzny
// 1 px mniejszy w kolorze tła (Rectangle nie ma obrysu gradientem).
Item {
    id: root

    property real radius: 30
    // Siła poświaty (0 = bez); launcher wiąże ją z postępem otwarcia.
    property real glow: 1

    SoftGlow {
        anchors.fill: parent
        radius: root.radius
        color: Theme.accent
        blur: 64
        spread: 4
        strength: 0.28 * root.glow
    }

    SoftGlow {
        anchors.fill: parent
        radius: root.radius
        offsetY: 14
        blur: 48
        strength: 0.6 * root.glow
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.alpha(Theme.accent, 0.55) }
            GradientStop { position: 0.5; color: Theme.border }
            GradientStop { position: 1; color: Theme.alpha(Theme.accent2, 0.55) }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: root.radius - 1
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.mix(Theme.surface, Theme.accent, 0.05) }
            GradientStop { position: 0.35; color: Theme.surface }
        }
    }
}
