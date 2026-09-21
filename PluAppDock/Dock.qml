import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Common
import qs.PluLauncher

// Dock na dole ekranu: launcher | przypięte | separator | uruchomione.
//
// Chowa się sam i wysuwa, gdy kursor dotknie dolnej krawędzi pod nim.
// Zostaje wysunięty na pustym obszarze roboczym, przy otwartym menu i w
// trakcie przeciągania; znika przy oknie na pełnym ekranie.
//
// Myszą rządzi JEDNA MouseArea (hitArea) nad całym dockiem, a element pod
// kursorem wyznaczamy z pozycji. Tak omijamy pułapkę opisaną w wyspie:
// Qt daje hover tylko najwyższemu elementowi, więc MouseArea na każdej
// ikonie zabierałaby hover dockowi i ten chowałby się pod kursorem.
PanelWindow {
    id: root

    // ---------------------------------------------------------------
    // Ustawienia
    // ---------------------------------------------------------------

    // Rozmiar ikony decyduje o reszcie: komórka i wysokość docka rosną
    // razem z nią. Parzyste liczby — patrz pułapka centerIn w DockItem.
    property int iconSize: 54
    property int cellWidth: iconSize + 12
    property int separatorWidth: 14
    property int dockPadding: 6         // poziomy margines wewnątrz tła
    property int dockHeight: iconSize + 22
    property int dockRadius: 26
    property int bottomMargin: 8        // przerwa między dockiem a krawędzią ekranu
    // Zapas nad dockiem na powiększoną ikonę, podpowiedź i skok przy
    // uruchamianiu. Wchodzi w wysokość okna — okno ma stały rozmiar.
    // Powiększona ikona wystaje ~iconSize × magnification − 9 px nad dock
    // (przy 54 i 0,6: ~23 px, z plakietką ~28), podpowiedź stoi nad nią.
    property int headroom: 76

    // Powiększanie jak w macOS: ikona pod kursorem rośnie do
    // (1 + magnification) rozmiaru, sąsiednie mniej, a rząd się rozsuwa.
    // 0 = wyłączone. magRange: na ile px od środka ikony sięga powiększenie.
    property real magnification: 0.6
    property real magRange: cellWidth * 2.4
    property int magFadeMs: 170         // wejście / zejście kursora z docka

    // Pasek przy krawędzi ekranu, który wysuwa schowany dock. 2 px logiczne
    // = 4 fizyczne przy skali 2; kursor dociśnięty do krawędzi stoi na
    // ostatnim wierszu, więc więcej nie trzeba, a mniej zabiera oknom.
    property int revealHeight: 2
    property int revealDelay: 120       // ms na krawędzi, zanim dock wyjedzie
    property int hideDelay: 450         // ms po zjechaniu kursorem, zanim się schowa

    property int wheelStepDelta: 120    // jeden ząbek kółka; touchpad przysyła drobne porcje
    property int dragThreshold: 6       // px ruchu z wciśniętym przyciskiem, zanim to przeciąganie
    // Upuszczenie ikony tyle px nad górną krawędzią docka ją odpina.
    property int unpinDistance: 40
    // Wysuwanie: ikony wskakują od środka na zewnątrz, co tyle ms na krok.
    property int appearStagger: 45
    // Chowanie: ikony zapadają się od krawędzi do środka co tyle ms, a tło
    // docka rusza bodyHideLead ms po pierwszej — gdy skrajne już znikają,
    // a środkowe jeszcze stoją.
    property int hideStagger: 28
    property int bodyHideLead: 140

    // ---------------------------------------------------------------
    // Okno
    // ---------------------------------------------------------------

    screen: Settings.screen

    anchors {
        bottom: true
        left: true
        right: true
    }

    implicitHeight: headroom + dockHeight + bottomMargin
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "plude-dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // ---------------------------------------------------------------
    // Kiedy dock jest widoczny
    // ---------------------------------------------------------------

    readonly property var hyprMonitor: Hyprland.monitorFor(root.screen)
    readonly property var workspace: hyprMonitor ? hyprMonitor.activeWorkspace : null

    readonly property bool fullscreen: workspace !== null && workspace.hasFullscreen
    // Na pustym obszarze roboczym nic nie zasłaniamy — dock stoi na widoku.
    readonly property bool emptyWorkspace: workspace !== null && workspace.toplevels.values.length === 0

    readonly property bool pointerInside: hitArea.containsMouse
    readonly property bool menuOpen: menu.visible
    readonly property bool holdOpen: menuOpen || drag.active || emptyWorkspace

    // Pełny ekran i ukrycie wyspy skrótem biją wszystko, także pusty pulpit.
    readonly property bool suppressed: fullscreen
        || (Settings.hideWithIsland && IslandLink.islandHidden)

    property bool revealed: false
    readonly property bool shown: !suppressed && (revealed || holdOpen)

    onShownChanged: {
        bodyShow.stop();
        bodyHide.stop();
        if (shown) bodyShow.start(); else bodyHide.start();
        if (!shown) pointerU = NaN;
    }

    onPointerInsideChanged: {
        if (pointerInside) {
            hideTimer.stop();
            // Dock już widać (pusty pulpit, menu) → od razu; schowany → po
            // chwili na krawędzi, żeby przelot kursora po dole nie wysuwał go.
            if (shown) revealed = true; else revealTimer.restart();
        } else {
            revealTimer.stop();
            hideTimer.restart();
        }
    }

    Timer {
        id: revealTimer
        interval: root.revealDelay
        onTriggered: if (root.pointerInside) root.revealed = true
    }

    Timer {
        id: hideTimer
        interval: root.hideDelay
        onTriggered: if (!root.pointerInside && !root.holdOpen) root.revealed = false
    }

    // Menu zamknięte kliknięciem gdzieś w oknie aplikacji — kursora nad
    // dockiem nie ma, więc chowamy go tak, jak po zjechaniu.
    onHoldOpenChanged: if (!holdOpen && !pointerInside) hideTimer.restart()

    // ---------------------------------------------------------------
    // Geometria
    // ---------------------------------------------------------------
    //
    // Dwa układy rzędu:
    //
    // BAZOWY (baseLayout) — bez powiększenia. Z niego liczymy kursor (pointerU),
    // trafianie myszą (keyAt) i przeciąganie. Nie zależy od powiększenia, więc
    // rosnące ikony nie przesuwają kursora względem rzędu — nie ma sprzężenia
    // zwrotnego, od którego rząd by drgał.
    //
    // POWIĘKSZONY (magLayout) — to, co widać. Każda ikona dostaje skalę z dzwonu
    // wokół kursora, szerokość elementu rośnie razem z nią, a cały rząd jest
    // przesunięty tak, żeby punkt pod kursorem został w miejscu (jak w macOS:
    // dock rośnie w obie strony od kursora). Dzięki temu element pod kursorem
    // w obu układach jest ten sam i keyAt może liczyć z bazowego.

    function baseWidthOf(key) { return key === DockService.separatorKey ? separatorWidth : cellWidth; }

    readonly property var baseLayout: {
        const keys = displayItems;
        const xs = [];
        let x = 0;
        for (let i = 0; i < keys.length; i++) {
            xs.push(x);
            x += baseWidthOf(keys[i]);
        }
        return { keys: keys, xs: xs, total: x };
    }

    // x pierwszego elementu w oknie przy układzie bazowym (dock wyśrodkowany).
    readonly property real baseOrigin: Math.round((width - baseLayout.total) / 2)

    // Kursor w układzie bazowym (px od początku rzędu), NaN = brak powiększenia.
    // lastU zostaje po zejściu kursora, żeby powiększenie gasło w miejscu.
    property real pointerU: NaN
    property real lastU: 0
    property real magStrength: isNaN(pointerU) ? 0 : 1
    Behavior on magStrength { NumberAnimation { duration: root.magFadeMs; easing.type: Easing.OutCubic } }

    // Indeks elementu bazowego pod u; -1 poza rzędem.
    function baseIndexAt(u) {
        const b = baseLayout;
        if (u < 0 || u >= b.total) return -1;
        for (let i = 0; i < b.keys.length; i++)
            if (u < b.xs[i] + baseWidthOf(b.keys[i])) return i;
        return -1;
    }

    readonly property var magLayout: {
        const b = baseLayout;
        const n = b.keys.length;
        const scales = [], widths = [], xs = [];
        const strength = magnification * magStrength;
        let x = 0;

        for (let i = 0; i < n; i++) {
            const w = baseWidthOf(b.keys[i]);
            let sc = 1;
            if (strength > 0 && b.keys[i] !== DockService.separatorKey) {
                const d = Math.abs(lastU - (b.xs[i] + w / 2)) / magRange;
                // Dzwon kosinusowy: gładko do zera na brzegu zasięgu, bez uskoku.
                if (d < 1) sc = 1 + strength * 0.5 * (1 + Math.cos(Math.PI * d));
            }
            scales.push(sc);
            widths.push(w * sc);
            xs.push(x);
            x += w * sc;
        }

        // Przesunięcie, przy którym punkt pod kursorem stoi w miejscu.
        let shift = 0;
        if (strength > 0 && n > 0) {
            const u = Math.max(0, Math.min(b.total - 0.001, lastU));
            const k = Math.max(0, baseIndexAt(u));
            const f = (u - b.xs[k]) / baseWidthOf(b.keys[k]);
            shift = u - (xs[k] + f * widths[k]);
        }

        return { keys: b.keys, scales: scales, widths: widths, xs: xs, total: x, shift: shift };
    }

    // Tło docka tam, gdzie powinno być (animowane jest body.x / body.width).
    readonly property real targetX: Math.round(baseOrigin + magLayout.shift - dockPadding)
    readonly property real targetWidth: Math.round(magLayout.total + dockPadding * 2)

    // Przy dodaniu / zdjęciu ikony tło i ikony dojeżdżają animacją. Pod
    // kursorem — nie: powiększenie ma iść za kursorem bez opóźnienia, a
    // Behavior restartowany przy każdym ruchu myszy wlókłby się za nim.
    readonly property bool layoutAnimated: magStrength === 0

    // Jak w wyspie: szerokość WIZUALNA (animowana) i ZASIĘG (suma z docelową).
    // Maska wejścia i obszar myszy idą za zasięgiem, żeby kursor na skrajnej
    // ikonie nie wypadał poza maskę w trakcie rozszerzania docka.
    readonly property int reachX: Math.floor(Math.min(body.x, targetX))
    readonly property int reachWidth: Math.ceil(Math.max(body.x + body.width, targetX + targetWidth)) - reachX
    readonly property int dockTop: headroom                 // górna krawędź wysuniętego docka
    // O tyle nad dock sięgają powiększone ikony — maska rośnie w górę razem
    // z nimi, żeby kursor na górnej części powiększonej ikony był dalej "w docku".
    readonly property int growTop: Math.ceil(iconSize * magnification * magStrength)

    mask: Region {
        x: root.reachX
        width: root.reachWidth
        // Schowany: tylko pasek przy krawędzi. Wysunięty: dock, przerwa pod
        // nim (zjazd ku krawędzi nie może go chować) i powiększone ikony nad nim.
        y: root.shown ? root.dockTop - root.growTop : root.height - root.revealHeight
        height: root.shown ? root.dockHeight + root.bottomMargin + root.growTop : root.revealHeight
    }

    // ---------------------------------------------------------------
    // Model rzędu
    // ---------------------------------------------------------------
    //
    // ListModel synchronizowany ruchami (move/insert/remove), a nie tablica
    // JS podana wprost do Repeatera: przy tablicy każda zmiana tworzy
    // wszystkie delegaty od nowa — ikony mrugają, a przejścia Row (move, add)
    // nie mają czego animować.

    // Podczas przeciągania rząd pokazuje podgląd kolejności, nie stan usługi.
    readonly property var displayItems: drag.active ? drag.previewItems : DockService.items

    ListModel { id: rowModel }

    function syncModel(keys) {
        for (let i = rowModel.count - 1; i >= 0; i--)
            if (keys.indexOf(rowModel.get(i).key) < 0) rowModel.remove(i);

        for (let i = 0; i < keys.length; i++) {
            if (i < rowModel.count && rowModel.get(i).key === keys[i]) continue;
            let from = -1;
            for (let j = i + 1; j < rowModel.count; j++)
                if (rowModel.get(j).key === keys[i]) { from = j; break; }
            if (from >= 0) rowModel.move(from, i, 1);
            else rowModel.insert(i, { key: keys[i] });
        }
    }

    onDisplayItemsChanged: syncModel(displayItems)
    Component.onCompleted: {
        syncModel(displayItems);
        if (shown) body.open = 1;   // dock wysunięty od startu (pusty pulpit) — bez animacji
    }

    // ---------------------------------------------------------------
    // Dock
    // ---------------------------------------------------------------

    Rectangle {
        id: body

        width: root.targetWidth
        height: root.dockHeight
        x: root.targetX
        // open: 1 = wysunięty, 0 = całkiem pod krawędzią ekranu (łącznie
        // z obrysem). Pozycja, zwężenie i przygaśnięcie idą z jednej wartości,
        // więc przy wysuwaniu odbicie OutBack bierze je wszystkie naraz.
        property real open: 0
        y: root.dockTop + (1 - open) * (root.height - root.dockTop + 2)
        opacity: 0.4 + 0.6 * Math.min(1, open)
        transform: Scale {
            origin.x: body.width / 2
            origin.y: body.height
            xScale: 0.8 + 0.2 * body.open
        }

        radius: root.dockRadius
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        Behavior on width {
            enabled: root.layoutAnimated
            NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
        }
        Behavior on x {
            enabled: root.layoutAnimated
            NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
        }
        // Wyjazd sprężyście (jak wyspa). Chowanie z opóźnieniem — najpierw
        // ikony zapadają się falą — i z krótkim zamachem w górę.
        NumberAnimation {
            id: bodyShow
            target: body; property: "open"; to: 1
            duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.8
        }
        SequentialAnimation {
            id: bodyHide
            PauseAnimation { duration: root.bodyHideLead }
            NumberAnimation {
                target: body; property: "open"; to: 0
                duration: 260; easing.type: Easing.InBack; easing.overshoot: 1.2
            }
        }

        // Pozycje liczymy sami (magLayout), bez Row: Row uruchamia przejście
        // move przy KAŻDEJ zmianie szerokości sąsiada, czyli przy każdym ruchu
        // myszy nad powiększonym dockiem.
        Item {
            id: strip

            anchors.fill: parent

            Repeater {
                model: rowModel

                DockItem {
                    id: cell

                    // Po kluczu, nie po index: magLayout liczy się z displayItems,
                    // a rowModel dogania je dopiero w onDisplayItemsChanged.
                    readonly property int slot: root.magLayout.keys.indexOf(key)

                    x: slot < 0 ? 0 : Math.round(root.dockPadding + root.magLayout.xs[slot])
                    width: slot < 0 ? root.baseWidthOf(key) : root.magLayout.widths[slot]
                    magScale: slot < 0 ? 1 : root.magLayout.scales[slot]
                    maxScale: 1 + root.magnification

                    Behavior on x {
                        enabled: root.layoutAnimated
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }

                    iconSize: root.iconSize
                    cellWidth: root.cellWidth
                    separatorWidth: root.separatorWidth
                    hovered: root.hoveredKey === key && !drag.active
                    pressed: hitArea.pressedKey === key && hitArea.pressed && !drag.active
                    placeholder: drag.active && drag.key === key
                    shown: root.shown
                    appearDelay: Math.round(Math.abs(index - (rowModel.count - 1) / 2) * root.appearStagger)
                    disappearDelay: Math.round(((rowModel.count - 1) / 2 - Math.abs(index - (rowModel.count - 1) / 2)) * root.hideStagger)
                }
            }
        }
    }

    // ---------------------------------------------------------------
    // Podpowiedź z nazwą
    // ---------------------------------------------------------------

    readonly property var hoveredItem: itemFor(hoveredKey)

    Rectangle {
        id: tooltip

        readonly property bool wanted: root.shown && root.hoveredItem !== null
            && !root.menuOpen && !drag.active && root.hoveredKey !== DockService.separatorKey

        width: tipText.implicitWidth + 20
        height: 26
        radius: 13
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        // Pozycja zapamiętana: przy gaszeniu podpowiedź zostaje, gdzie była,
        // zamiast odjeżdżać do (0, 0) za znikającym elementem.
        property real cx: 0
        property real lift: 0
        x: Math.round(Math.max(4, Math.min(root.width - width - 4, cx - width / 2)))
        // Nad powiększoną ikoną (razem z plakietką, która wystaje 5 px nad nią).
        y: Math.round(root.dockTop + (root.dockHeight - root.iconSize) / 2 - 2 - lift - 5 - height - 8)

        opacity: wanted ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.quickMs } }

        Text {
            id: tipText
            anchors.centerIn: parent
            color: Theme.text
            font.pixelSize: 12
        }

        function follow() {
            const it = root.hoveredItem;
            if (!it || it.isSeparator) return;
            cx = body.x + it.x + it.width / 2;
            lift = root.iconSize * (it.magScale - 1);
            tipText.text = DockService.nameFor(it.key);
        }

        Connections {
            target: root
            function onHoveredItemChanged() { tooltip.follow(); }
            function onMagLayoutChanged() { tooltip.follow(); }
        }
    }

    // ---------------------------------------------------------------
    // Mysz
    // ---------------------------------------------------------------

    property string hoveredKey: ""

    // Kursor → pointerU. Powiększamy tylko nad samym dockiem (tło), nie nad
    // całą maską; w trakcie przeciągania nie — rząd pod duchem ikony ma stać.
    function trackPointer(mx) {
        const wx = hitArea.x + mx;
        if (shown && !drag.active && hitArea.containsMouse && wx >= body.x && wx <= body.x + body.width) {
            pointerU = wx - baseOrigin;
            lastU = pointerU;
        } else {
            pointerU = NaN;
        }
    }

    function itemFor(key) {
        if (key === "") return null;
        for (let i = 0; i < strip.children.length; i++) {
            const c = strip.children[i];
            if (c.key === key) return c;
        }
        return null;
    }

    // Element pod kursorem, z układu BAZOWEGO (patrz Geometria). Wysokość
    // kursora nie gra roli — liczy się kolumna, także w przerwie pod dockiem.
    function keyAt(mx) {
        if (!shown) return "";
        const i = baseIndexAt(hitArea.x + mx - baseOrigin);
        return i < 0 ? "" : baseLayout.keys[i];
    }

    MouseArea {
        id: hitArea

        x: root.reachX
        width: root.reachWidth
        y: root.dockTop - root.growTop
        height: root.dockHeight + root.bottomMargin + root.growTop

        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        property string pressedKey: ""
        property real pressX: 0
        property real pressY: 0
        property real wheelAccum: 0

        onPositionChanged: mouse => {
            if (pressed && pressedButtons & Qt.LeftButton) {
                if (!drag.active && pressedKey !== "" && drag.canDrag(pressedKey)
                        && Math.hypot(mouse.x - pressX, mouse.y - pressY) > root.dragThreshold)
                    drag.start(pressedKey, mouse);
                if (drag.active) drag.update(mouse);
                return;
            }
            root.hoveredKey = root.keyAt(mouse.x);
            root.trackPointer(mouse.x);
        }

        onContainsMouseChanged: {
            if (!containsMouse && !pressed) root.hoveredKey = "";
            if (!containsMouse) root.pointerU = NaN;
        }

        onPressed: mouse => {
            pressedKey = root.keyAt(mouse.x);
            pressX = mouse.x;
            pressY = mouse.y;
        }

        onReleased: mouse => {
            const key = pressedKey;
            pressedKey = "";

            if (drag.active) {
                drag.finish(mouse);
                root.hoveredKey = containsMouse ? root.keyAt(mouse.x) : "";
                return;
            }
            // Puszczenie gdzie indziej niż nad tym samym elementem = rezygnacja.
            if (key === "" || root.keyAt(mouse.x) !== key) return;
            root.activateItem(key, mouse);
        }

        onWheel: wheel => {
            const key = root.keyAt(wheel.x);
            if (key === "" || DockService.isSpecial(key)) return;
            // Sumujemy do pełnego ząbka: touchpad przysyła ~10 jednostek na
            // zdarzenie i bez sumowania jedno machnięcie przeskoczyłoby okna
            // kilkanaście razy (ta sama pułapka co głośność w wyspie).
            wheelAccum += wheel.angleDelta.y !== 0 ? -wheel.angleDelta.y : wheel.angleDelta.x;
            if (Math.abs(wheelAccum) >= root.wheelStepDelta) {
                DockService.cycle(key, wheelAccum > 0 ? 1 : -1);
                wheelAccum = 0;
            }
        }
    }

    function activateItem(key, mouse) {
        if (key === DockService.separatorKey) return;

        if (key === DockService.launcherKey) {
            if (mouse.button === Qt.LeftButton) LauncherService.toggle();
            return;
        }

        if (mouse.button === Qt.MiddleButton) {
            DockService.launch(key);
            return;
        }

        if (mouse.button === Qt.RightButton) {
            openContextMenu(key);
            return;
        }

        // Klik w plakietkę = powiadomienia tej aplikacji w wyspie.
        const it = itemFor(key);
        if (it && it.unseen > 0) {
            const p = hitArea.mapToItem(it, mouse.x, mouse.y);
            if (it.badgeContains(p.x, p.y)) {
                IslandLink.showNotifications(key);
                return;
            }
        }

        if (DockService.primaryAction(key) === "list") openWindowList(key);
    }

    // ---------------------------------------------------------------
    // Menu
    // ---------------------------------------------------------------

    PopupMenu { id: menu }

    function openMenuFor(key, entries) {
        const it = itemFor(key);
        if (!it) return;
        const p = it.mapToItem(root.contentItem, it.width / 2, 0);
        menu.openAt(root, p.x, root.dockTop - 6, entries);
    }

    function windowEntries(key) {
        const out = [];
        const wins = DockService.windowsFor(key);
        for (let i = 0; i < wins.length; i++) {
            const t = wins[i];
            out.push({
                text: t.title !== "" ? t.title : DockService.nameFor(key),
                checked: t === DockService.activeToplevel,
                run: () => t.activate()
            });
        }
        return out;
    }

    function openWindowList(key) {
        openMenuFor(key, [{ header: DockService.nameFor(key) }].concat(windowEntries(key)));
    }

    function openContextMenu(key) {
        const e = DockService.entryFor(key);
        const wins = DockService.windowsFor(key);
        const it = itemFor(key);
        let out = [{ header: DockService.nameFor(key) }];

        if (wins.length > 0) out = out.concat(windowEntries(key));

        const actions = e ? e.actions : [];
        if (e) {
            out.push({ separator: true });
            out.push({ text: wins.length > 0 ? "Nowe okno" : "Uruchom", run: () => DockService.launch(key) });
            for (let i = 0; i < actions.length; i++) {
                const a = actions[i];
                out.push({ text: a.name, icon: a.icon ? Quickshell.iconPath(a.icon, true) : "", run: () => DockService.launch(key, a) });
            }
        }

        if (it && (it.unseen > 0 || IslandLink.notificationTimes(key).length > 0)) {
            out.push({ separator: true });
            out.push({
                text: it.unseen > 0 ? "Powiadomienia (" + it.unseen + ")" : "Powiadomienia",
                run: () => IslandLink.showNotifications(key)
            });
        }

        if (DockService.canPin(key) || wins.length > 0) out.push({ separator: true });
        if (DockService.canPin(key)) {
            const pinned = DockService.isPinned(key);
            out.push({ text: pinned ? "Odepnij z docka" : "Przypnij do docka", run: () => Pins.toggle(key) });
        }
        if (wins.length > 0) {
            out.push({
                text: wins.length > 1 ? "Zamknij wszystkie (" + wins.length + ")" : "Zamknij",
                danger: true,
                run: () => DockService.closeAll(key)
            });
        }

        openMenuFor(key, out);
    }

    // ---------------------------------------------------------------
    // Przeciąganie
    // ---------------------------------------------------------------
    //
    // Przeciągać można przypięte i uruchomione (z wpisem .desktop).
    // Upuszczenie w strefie przypiętych = przypięcie na tym miejscu,
    // upuszczenie wysoko nad dockiem = odpięcie.
    //
    // Miejsce wstawienia liczymy z geometrii ZAMROŻONEJ na starcie
    // przeciągania, nie z bieżących pozycji delegatów — te animują się
    // w odpowiedzi na nasz własny podgląd i liczenie z nich dawało
    // sprzężenie zwrotne: szczelina skakała tam i z powrotem.

    QtObject {
        id: drag

        property bool active: false
        property string key: ""
        property real originX: 0        // x początku strefy przypiętych (okno) w chwili startu
        property int slot: 0            // miejsce wśród przypiętych (bez przeciąganego)
        property bool unpinZone: false
        // Czy upuszczenie tu zostawi aplikację przypiętą. Nieprzypiętą
        // przypinamy tylko po wciągnięciu w strefę przypiętych — lekkie
        // szarpnięcie ikony uruchomionej aplikacji nie ma jej przypinać.
        property bool willPin: false
        property var previewItems: []

        function canDrag(k) { return DockService.canPin(k); }

        function start(k, mouse) {
            key = k;
            root.pointerU = NaN;
            // Strefa przypiętych zaczyna się za launcherem (pierwsza komórka),
            // liczona z układu bazowego — powiększenie właśnie gaśnie.
            originX = root.baseOrigin + root.baseWidthOf(DockService.launcherKey);
            active = true;
            update(mouse);
        }

        function update(mouse) {
            const p = hitArea.mapToItem(root.contentItem, mouse.x, mouse.y);
            ghost.x = p.x - ghost.width / 2;
            ghost.y = p.y - ghost.height / 2;

            const others = DockService.visiblePinned.filter(k => k !== key);
            unpinZone = p.y < root.dockTop - root.unpinDistance;
            const s = Math.round((p.x - originX - root.cellWidth / 2) / root.cellWidth);
            slot = Math.max(0, Math.min(others.length, s));
            const inPinnedZone = p.x < originX + (others.length + 1) * root.cellWidth;
            willPin = !unpinZone && (DockService.isPinned(key) || inPinnedZone);

            previewItems = buildPreview(others);
        }

        function buildPreview(others) {
            const out = [DockService.launcherKey];
            const pins = others.slice();
            if (willPin) pins.splice(slot, 0, key);
            for (let i = 0; i < pins.length; i++) out.push(pins[i]);

            // Odpinana aplikacja, która ma okna, wraca do uruchomionych.
            const extra = DockService.runningOrder.filter(k =>
                pins.indexOf(k) < 0 && DockService.isRunning(k));
            if (extra.length > 0) {
                out.push(DockService.separatorKey);
                for (let i = 0; i < extra.length; i++) out.push(extra[i]);
            }
            return out;
        }

        function finish(mouse) {
            update(mouse);
            if (!willPin) {
                Pins.unpin(key);   // nieprzypiętej nic nie robi
            } else {
                const others = DockService.visiblePinned.filter(k => k !== key);
                Pins.place(key, slot < others.length ? others[slot] : "");
            }
            active = false;
            key = "";
        }
    }

    // Ikona niesiona pod kursorem.
    Image {
        id: ghost

        visible: drag.active
        width: root.iconSize
        height: root.iconSize
        source: drag.active ? DockService.iconFor(drag.key) : ""
        sourceSize: Qt.size(root.iconSize, root.iconSize)
        asynchronous: false
        // W strefie odpinania ikona blednie — widać, że upuszczenie ją zdejmie.
        opacity: drag.unpinZone ? 0.45 : 1
        scale: drag.unpinZone ? 0.85 : 1.08
        Behavior on opacity { NumberAnimation { duration: Theme.quickMs } }
        Behavior on scale { NumberAnimation { duration: Theme.quickMs } }
    }
}
