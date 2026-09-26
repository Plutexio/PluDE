import QtQuick
import qs.Common

// Układ monitorów do przeciągania. Rysuje szkic (MonitorDraft) w skali
// dopasowanej do okna; przeciąganie zmienia pozycje w szkicu, przyciągając
// krawędzie do sąsiadów.
Item {
    id: canvas

    required property var draft

    property int padding: 28
    // Przyciąganie krawędzi bliżej niż tyle px ekranu (przeliczane na px
    // logiczne układu przez bieżącą skalę widoku).
    property int snapPx: 16
    // Klon rysujemy na monitorze źródłowym, przesunięty o tyle.
    property int mirrorOffset: 8
    // Tyle px ruchu, zanim klik zamieni się w przeciąganie.
    property int dragThreshold: 3

    // ---- widok ----

    readonly property var fit: {
        const b = draft.bounds(draft.items);
        const bw = Math.max(b.width, 1), bh = Math.max(b.height, 1);
        const s = Math.min((width - 2 * padding) / bw, (height - 2 * padding) / bh);
        return { s: s, ox: (width - bw * s) / 2 - b.x * s, oy: (height - bh * s) / 2 - b.y * s };
    }
    // W trakcie przeciągania widok stoi: dopasowanie do zmieniającego się
    // układu przeskalowałoby płótno pod kursorem (sprzężenie jak w docku).
    property var frozen: null
    readonly property var view: frozen ?? fit

    // ---- monitory ----

    // Repeater na liczbie, nie na tablicy szkicu: każda zmiana tablicy
    // (każdy ruch myszy przy przeciąganiu) tworzyłaby delegaty od nowa
    // i przeciąganie urywałoby się po pierwszym kroku.
    Repeater {
        model: canvas.draft.items.length

        Rectangle {
            id: mon

            required property int index
            readonly property var e: canvas.draft.items[index] ?? null
            readonly property var source: e && e.mirror !== "" ? canvas.draft.find(e.mirror) : null
            // Klon stoi tam, gdzie jego źródło.
            readonly property var at: source ?? e
            readonly property bool isMirror: source !== null
            readonly property bool selected: e !== null && canvas.draft.selected === e.name
            readonly property bool bad: e !== null && canvas.draft.problems.overlap.indexOf(e.name) >= 0
            readonly property bool draggable: e !== null && !isMirror && canvas.draft.placed().length > 1
            readonly property bool moving: mouse.pressed && canvas.frozen !== null

            visible: e !== null && !e.disabled && at !== null
            z: moving ? 3 : selected ? 2 : isMirror ? 1 : 0

            x: at ? canvas.view.ox + at.x * canvas.view.s + (isMirror ? canvas.mirrorOffset : 0) : 0
            y: at ? canvas.view.oy + at.y * canvas.view.s + (isMirror ? canvas.mirrorOffset : 0) : 0
            width: e ? canvas.draft.logicalWidth(e) * canvas.view.s : 0
            height: e ? canvas.draft.logicalHeight(e) * canvas.view.s : 0

            // Dopasowanie po zmianie (upuszczenie, skala, obrót) płynnie;
            // pod kursorem bez opóźnienia.
            Behavior on x { enabled: !canvas.frozen; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: !canvas.frozen; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            radius: 8
            antialiasing: true
            color: selected ? Qt.tint(Theme.surface, Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22))
                : mouse.containsMouse ? Qt.tint(Theme.surface, Qt.rgba(1, 1, 1, 0.06)) : Theme.surface
            border.width: selected || bad ? 2 : 1
            border.color: bad ? Theme.danger : selected ? Theme.accent : Qt.rgba(1, 1, 1, 0.18)
            opacity: isMirror ? 0.85 : 1

            Behavior on color { ColorAnimation { duration: Theme.quickMs } }

            Column {
                anchors.centerIn: parent
                width: parent.width - 12
                spacing: 2

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: mon.e ? mon.e.name : ""
                    color: Theme.text
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: mon.height > 44
                    text: !mon.e ? ""
                        : mon.isMirror ? "klon " + mon.e.mirror
                        : canvas.draft.logicalWidth(mon.e) + " × " + canvas.draft.logicalHeight(mon.e)
                    color: Theme.textDim
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                // Na którym ekranie stoją dock i pasek.
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: mon.height > 64 && mon.e !== null && Settings.screen !== null
                        && Settings.screen.name === mon.e.name
                    text: "dock i pasek"
                    color: Theme.textFaint
                    font.pixelSize: 10
                }
            }

            MouseArea {
                id: mouse

                property point press
                property real startX
                property real startY

                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                cursorShape: mon.draggable ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.PointingHandCursor

                onPressed: m => {
                    canvas.draft.selected = mon.e.name;
                    press = mapToItem(canvas, m.x, m.y);
                    startX = mon.e.x;
                    startY = mon.e.y;
                }
                onPositionChanged: m => {
                    if (!pressed || !mon.draggable) return;
                    // Pozycja w układzie płótna, nie delegata — delegat
                    // jedzie razem z myszą.
                    const p = mapToItem(canvas, m.x, m.y);
                    if (!canvas.frozen) {
                        if (Math.abs(p.x - press.x) + Math.abs(p.y - press.y) < canvas.dragThreshold) return;
                        canvas.frozen = canvas.fit;
                        canvas.draft.dragging = true;
                    }
                    const s = canvas.view.s;
                    canvas.draft.moveTo(mon.e.name, startX + (p.x - press.x) / s,
                                        startY + (p.y - press.y) / s, canvas.snapPx / s);
                }
                onReleased: canvas.endDrag()
                onCanceled: canvas.endDrag()
            }
        }
    }

    function endDrag() {
        frozen = null;
        draft.dragging = false;
    }
}
