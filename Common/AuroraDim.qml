import QtQuick
import QtQuick.Shapes

// Przyciemnienie ekranu pod pełnoekranowym panelem (launcher, schowek),
// a za panelem „zorza”: dwie miękkie plamy w kolorach tapety, akcent
// u góry z lewej, drugi akcent u dołu z prawej. Rosną razem z panelem.
//
// Bez rozmycia Hyprlanda (30 fps na 4K, DESIGN.md): plamy to gradienty
// promieniste, rysowane raz, bez efektów.
Item {
    id: root

    // Postęp otwarcia panelu (reveal; przycinany do 1, przestrzał nie
    // przyciemnia mocniej).
    property real progress: 0
    property real dim: 0.45
    // Panel, wokół którego stoją plamy.
    property Item panel: null
    property real strength: 0.32

    readonly property real p: Math.max(0, Math.min(1, progress))
    readonly property real cx: panel ? panel.x + panel.width / 2 : width / 2
    readonly property real cy: panel ? panel.y + panel.height / 2 : height / 2
    readonly property real blob: panel ? Math.max(panel.width, panel.height) * 0.85 : 600

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, root.dim * root.p)
    }

    component Blob: Shape {
        id: b
        property color color
        property real bx
        property real by
        property real r: root.blob * (0.6 + 0.4 * root.p)

        anchors.fill: parent
        opacity: root.p
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: b.bx; centerY: b.by; centerRadius: b.r
                focalX: b.bx; focalY: b.by
                GradientStop { position: 0; color: Qt.rgba(b.color.r, b.color.g, b.color.b, root.strength) }
                GradientStop { position: 0.45; color: Qt.rgba(b.color.r, b.color.g, b.color.b, root.strength * 0.4) }
                GradientStop { position: 1; color: "transparent" }
            }
            startX: b.bx - b.r; startY: b.by - b.r
            PathLine { x: b.bx + b.r; y: b.by - b.r }
            PathLine { x: b.bx + b.r; y: b.by + b.r }
            PathLine { x: b.bx - b.r; y: b.by + b.r }
            PathLine { x: b.bx - b.r; y: b.by - b.r }
        }
    }

    Blob {
        color: Theme.accent
        bx: root.cx - (root.panel ? root.panel.width * 0.35 : 0)
        by: root.cy - (root.panel ? root.panel.height * 0.3 : 0)
    }

    Blob {
        color: Theme.accent2
        bx: root.cx + (root.panel ? root.panel.width * 0.35 : 0)
        by: root.cy + (root.panel ? root.panel.height * 0.3 : 0)
    }
}
