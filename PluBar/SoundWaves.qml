import QtQuick
import QtQuick.Shapes
import qs.Common

// Fale dźwięku przy ikonie głośnika: przy zmianie głośności łuki z prawej
// strony ikony. Głośniej = rozchodzą się od głośnika na zewnątrz,
// ciszej = zbiegają do niego. Kilka kroków pod rząd = kilka fal.
//
// Środek łuków to stożek głośnika w ikonie (x 12 z 24 w siatce Icon),
// przeliczony na rozmiar ikony.
Item {
    id: root

    property color color: Theme.accent
    property real iconSize: 16
    // Promienie łuków w px: od tuż za stożkiem do poza przyciskiem.
    property real nearRadius: 5
    property real farRadius: 15
    property int duration: 520
    // Rozwarcie łuku w stopniach (symetrycznie wokół poziomu).
    property real sweep: 76

    // Środek łuków względem środka elementu.
    readonly property real centerX: width / 2 - iconSize * 1.5 / 24
    readonly property real centerY: height / 2

    function burst(louder) {
        arc.createObject(root, { outward: louder });
    }

    Component {
        id: arc

        Shape {
            id: s
            property bool outward: true
            property real t: 0
            readonly property real r: outward
                ? root.nearRadius + (root.farRadius - root.nearRadius) * t
                : root.farRadius - (root.farRadius - root.nearRadius) * t

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            // Wyraźnie na starcie, zanika pod koniec.
            opacity: Math.min(1, 3 * (1 - t)) * Math.min(1, 4 * t)

            ShapePath {
                strokeColor: root.color
                strokeWidth: 1.8
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: root.centerX
                    centerY: root.centerY
                    radiusX: s.r
                    radiusY: s.r
                    startAngle: -root.sweep / 2
                    sweepAngle: root.sweep
                }
            }

            NumberAnimation on t {
                from: 0; to: 1
                duration: root.duration
                easing.type: Easing.OutCubic
                onFinished: s.destroy()
            }
        }
    }
}
