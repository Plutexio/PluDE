import QtQuick

// ---------------------------------------------------------------
// Szkic ustawień monitorów na stronie „Monitory”: edytowana kopia stanu
// z MonitorService. Nic nie idzie do Hyprlanda, dopóki strona nie zawoła
// apply(). Bez interfejsu, żeby sonda mogła sprawdzić logikę bez klikania.
//
// Pozycje i rozmiary w pikselach LOGICZNYCH układu Hyprlanda (piksele
// fizyczne / skala, z obrotem) — w tym układzie Hyprland trzyma pozycje.
// ---------------------------------------------------------------
QtObject {
    id: draft

    // [{ name, description, width, height, refresh, x, y, scale, transform,
    //    disabled, mirror, modes }]
    property var items: []
    property string selected: ""
    // W trakcie przeciągania stan z Hyprlanda nie nadpisuje szkicu.
    property bool dragging: false

    readonly property var live: build(MonitorService.monitors)

    // Każda zmiana stanu (po apply, podłączenie monitora) zaczyna szkic od
    // nowa: zmiany sprzed podłączenia monitora i tak nie pasują do nowego układu.
    onLiveChanged: if (!dragging) reset()
    onDraggingChanged: if (!dragging && !dirty) reset()

    function reset() {
        items = live.map(e => Object.assign({}, e));
        if (!items.some(e => e.name === selected))
            selected = items.length > 0 ? items[0].name : "";
    }

    // ---------------------------------------------------------------
    // Odczyt
    // ---------------------------------------------------------------

    function build(monitors) {
        return monitors.map(m => ({
            name: m.name,
            description: m.description,
            width: m.width,
            height: m.height,
            // Hyprland podaje zmierzone odświeżanie (59.997), lista trybów
            // zaokrąglone (60.00). Bez dociągnięcia do trybu lista wyboru
            // nie znalazłaby bieżącej wartości.
            refresh: nearestRefresh(m.modes, m.width, m.height, m.refreshRate),
            x: m.x,
            y: m.y,
            scale: m.scale,
            transform: m.transform,
            disabled: m.disabled,
            mirror: m.mirrorOf,
            modes: m.modes
        }));
    }

    function nearestRefresh(modes, width, height, refresh) {
        let best = refresh;
        let bestD = Infinity;
        modes.forEach(md => {
            if (md.width !== width || md.height !== height) return;
            const d = Math.abs(md.refresh - refresh);
            if (d < bestD) { bestD = d; best = md.refresh; }
        });
        return best;
    }

    function find(name) {
        for (let i = 0; i < items.length; i++) if (items[i].name === name) return items[i];
        return null;
    }

    readonly property var current: {
        items;
        return find(selected);
    }

    function logicalWidth(e) {
        return Math.round((MonitorService.isRotated(e.transform) ? e.height : e.width) / e.scale);
    }
    function logicalHeight(e) {
        return Math.round((MonitorService.isRotated(e.transform) ? e.width : e.height) / e.scale);
    }

    // Monitory, które zajmują miejsce w układzie: włączone i nie klony.
    function placed(list) {
        return (list || items).filter(e => !e.disabled && e.mirror === "");
    }

    function bounds(list) {
        const p = placed(list);
        if (p.length === 0) return { x: 0, y: 0, width: 0, height: 0 };
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        p.forEach(e => {
            x0 = Math.min(x0, e.x);
            y0 = Math.min(y0, e.y);
            x1 = Math.max(x1, e.x + logicalWidth(e));
            y1 = Math.max(y1, e.y + logicalHeight(e));
        });
        return { x: x0, y: y0, width: x1 - x0, height: y1 - y0 };
    }

    // ---------------------------------------------------------------
    // Zmiany
    // ---------------------------------------------------------------

    function patch(name, fields) {
        items = items.map(e => e.name === name ? Object.assign({}, e, fields) : e);
    }

    // Zmiana rozmiaru logicznego (tryb, skala, obrót) przesuwa sąsiadów
    // stojących na prawo i poniżej, żeby układ się nie rozjechał: bez tego
    // większy monitor wszedłby na sąsiada, a mniejszy zostawiłby przerwę.
    function resize(name, fields) {
        const before = find(name);
        if (!before) return;
        const oldW = logicalWidth(before), oldH = logicalHeight(before);
        const after = Object.assign({}, before, fields);
        const dw = logicalWidth(after) - oldW;
        const dh = logicalHeight(after) - oldH;
        const placedNow = !before.disabled && before.mirror === "";
        items = items.map(e => {
            if (e.name === name) return after;
            if (!placedNow || e.disabled || e.mirror !== "") return e;
            const moved = Object.assign({}, e);
            if (e.x >= before.x + oldW) moved.x += dw;
            if (e.y >= before.y + oldH) moved.y += dh;
            return moved;
        });
    }

    // Nowa rozdzielczość: najwyższe odświeżanie dla niej, a skala, jeśli
    // przestała pasować (rozmiar logiczny nie w całych pikselach), na
    // najbliższą poprawną — inaczej Hyprland poprawiłby ją po cichu.
    function setResolution(name, width, height) {
        const e = find(name);
        if (!e) return;
        let refresh = 0;
        e.modes.forEach(md => {
            if (md.width === width && md.height === height) refresh = Math.max(refresh, md.refresh);
        });
        const scale = MonitorService.isValidScale(width, height, e.scale)
            ? e.scale : MonitorService.nearestValidScale(width, height, e.scale);
        resize(name, { width: width, height: height, refresh: refresh, scale: scale });
    }

    function setRefresh(name, refresh) { patch(name, { refresh: refresh }); }
    function setScale(name, scale) { resize(name, { scale: scale }); }
    function setTransform(name, transform) { resize(name, { transform: transform }); }

    function setEnabled(name, on) {
        const e = find(name);
        if (!e || e.disabled === !on) return;
        if (!on) {
            // Ostatniego włączonego nie wyłączamy — nie byłoby czym cofnąć.
            if (items.filter(o => !o.disabled && o.name !== name).length === 0) return;
            // Klony wyłączanego monitora wracają do układu.
            items = items.map(o => o.mirror === name ? Object.assign({}, o, { mirror: "" }) : o);
            // Pozycja zostaje: wyłączony monitor i tak nie stoi w układzie.
            patch(name, { disabled: true });
            return;
        }
        patch(name, { disabled: false });
        items = placeRight(name, items);
    }

    function setMirror(name, target) {
        const e = find(name);
        if (!e || e.mirror === target) return;
        patch(name, { mirror: target });
        // Klon wraca do układu: na prawo od reszty.
        if (target === "") items = placeRight(name, items);
    }

    // Monitor wracający do układu staje na prawo od pozostałych, górą
    // w linii z nimi.
    function placeRight(name, list) {
        const b = bounds(list.filter(e => e.name !== name));
        return list.map(e => e.name === name ? Object.assign({}, e, { x: b.x + b.width, y: b.y }) : e);
    }

    // Przeciąganie: pozycja z przyciąganiem krawędzi do sąsiadów, jeśli są
    // bliżej niż threshold (w px logicznych — płótno przelicza go z px ekranu).
    function moveTo(name, x, y, threshold) {
        const e = find(name);
        if (!e) return;
        const w = logicalWidth(e), h = logicalHeight(e);
        let bx = Math.round(x), by = Math.round(y);
        let dx = threshold, dy = threshold;
        placed().forEach(o => {
            if (o.name === name) return;
            const ow = logicalWidth(o), oh = logicalHeight(o);
            // Obok siebie (prawa do lewej, lewa do prawej) i równo (lewa do
            // lewej, prawa do prawej).
            [o.x - w, o.x + ow, o.x, o.x + ow - w].forEach(t => {
                if (Math.abs(t - x) < dx) { dx = Math.abs(t - x); bx = t; }
            });
            [o.y - h, o.y + oh, o.y, o.y + oh - h].forEach(t => {
                if (Math.abs(t - y) < dy) { dy = Math.abs(t - y); by = t; }
            });
        });
        patch(name, { x: bx, y: by });
    }

    // ---------------------------------------------------------------
    // Sprawdzenie
    // ---------------------------------------------------------------

    function overlaps(a, b) {
        return a.x < b.x + logicalWidth(b) && b.x < a.x + logicalWidth(a)
            && a.y < b.y + logicalHeight(b) && b.y < a.y + logicalHeight(a);
    }

    // Stykają się krawędzią (odcinek, nie sam róg) — tędy przejdzie kursor.
    function touches(a, b) {
        const ax1 = a.x + logicalWidth(a), ay1 = a.y + logicalHeight(a);
        const bx1 = b.x + logicalWidth(b), by1 = b.y + logicalHeight(b);
        const vertical = (ax1 === b.x || bx1 === a.x) && Math.min(ay1, by1) > Math.max(a.y, b.y);
        const horizontal = (ay1 === b.y || by1 === a.y) && Math.min(ax1, bx1) > Math.max(a.x, b.x);
        return vertical || horizontal;
    }

    // { overlap: [nazwy], detached: bool, noneEnabled: bool }
    readonly property var problems: {
        const p = placed(items);
        const overlap = [];
        for (let i = 0; i < p.length; i++)
            for (let j = i + 1; j < p.length; j++)
                if (overlaps(p[i], p[j])) overlap.push(p[i].name, p[j].name);

        // Spójność: od pierwszego monitora po stykających się krawędziach.
        const seen = p.length > 0 ? [p[0]] : [];
        for (let k = 0; k < seen.length; k++)
            p.forEach(o => { if (seen.indexOf(o) < 0 && touches(seen[k], o)) seen.push(o); });

        return {
            overlap: overlap.filter((n, i) => overlap.indexOf(n) === i),
            detached: seen.length < p.length,
            noneEnabled: items.length > 0 && items.every(e => e.disabled)
        };
    }

    readonly property bool valid: problems.overlap.length === 0 && !problems.noneEnabled

    // ---------------------------------------------------------------
    // Zastosowanie
    // ---------------------------------------------------------------

    // Lewy górny róg układu w (0,0): automat wyboru ekranu docka szuka
    // monitora w (0,0), a przeciąganie łatwo przesuwa cały układ.
    function normalized(list) {
        const b = bounds(list);
        return list.map(e => (e.disabled || e.mirror !== "") ? e
            : Object.assign({}, e, { x: e.x - b.x, y: e.y - b.y }));
    }

    function specOf(e) {
        return {
            output: MonitorService.outputKey(e),
            mode: MonitorService.modeString(e.width, e.height, e.refresh),
            position: e.x + "x" + e.y,
            scale: Math.round(e.scale * MonitorService.scaleDenominator) / MonitorService.scaleDenominator,
            transform: e.transform,
            disabled: e.disabled,
            mirror: e.mirror
        };
    }

    function differing(list) {
        const liveSpecs = {};
        live.forEach(e => liveSpecs[e.name] = JSON.stringify(specOf(e)));
        return list.filter(e => JSON.stringify(specOf(e)) !== liveSpecs[e.name]);
    }

    // Cały układ, nie tylko zmienione monitory. Monitor bez własnej reguły
    // ma z hyprland.lua pozycję „auto”, a Hyprland stawia takie na prawo od
    // tych z jawną pozycją — reguła tylko dla zmienionego sąsiada przestawiła
    // ekran laptopa z (0,0) na (3840,0) (zmierzone na atrapie). Ponowne
    // wysłanie tego samego trybu sprawdzone na eDP-1 tylko co do stanu
    // (zostaje ten sam); czy ekran przy tym mrugnie — do potwierdzenia.
    function changedSpecs() {
        const all = normalized(items);
        return differing(all).length > 0 ? all.map(specOf) : [];
    }

    // Bez normalizacji: układ Hyprlanda, który nie zaczyna się w (0,0),
    // nie może wyglądać na zmieniony, zanim ktoś czegoś dotknie.
    readonly property bool dirty: {
        live;
        return differing(items).length > 0;
    }

    function apply() {
        if (!valid) return;
        const specs = changedSpecs();
        if (specs.length > 0) MonitorService.apply(specs);
    }
}
