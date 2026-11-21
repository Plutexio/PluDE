import QtQuick

// Zaznaczenie w siatce i liście (GridView / ListView.highlight): pełne
// tło w odcieniu akcentu przechodzącym w drugi akcent, obrys w akcencie
// i poświata pod spodem.
Item {
    id: root

    property real radius: 18

    SoftGlow {
        anchors.fill: parent
        radius: root.radius
        color: Theme.accent
        blur: 20
        strength: 0.35
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.mix(Theme.surface, Theme.accent, 0.22) }
            GradientStop { position: 1; color: Theme.mix(Theme.surface, Theme.accent2, 0.2) }
        }
        border.width: 1
        border.color: Theme.alpha(Theme.accentBright, 0.45)
    }
}
