pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ---------------------------------------------------------------
// Przypięte aplikacje — ~/.config/plude/dock.json.
//
// W Common, a nie w docku: przypina też launcher, a launcher nie może
// importować docka (dock importuje launcher — przycisk "Aplikacje").
// Plik pisze program przy każdym przypięciu i przeciągnięciu, dlatego nie
// siedzi w ręcznie edytowanym settings.json.
// ---------------------------------------------------------------
Singleton {
    id: root

    // Przypięte przy pierwszym starcie (brak dock.json).
    readonly property var defaults: ["zen", "kitty", "discord", "spotify-launcher"]

    readonly property var list: store.pinned

    // Przypięte, które naprawdę istnieją. Zanim DesktopEntries dojedzie, nie
    // wiadomo, które są — pokazujemy wszystkie, zamiast mrugnąć pustym
    // dockiem. Po skanie wpis, którego już nie ma (odinstalowany), znika
    // z widoku, ale zostaje w dock.json: wróci razem z aplikacją.
    readonly property var visible: store.pinned.filter(k => !Apps.ready || Apps.entry(k))

    FileView {
        path: Settings.configDir + "/dock.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) writeAdapter();
        }

        JsonAdapter {
            id: store
            property var pinned: root.defaults
        }
    }

    function has(id) { return store.pinned.indexOf(id) >= 0; }

    // Tylko prawdziwe wpisy .desktop. Okno bez wpisu ("wm:…") nie miałoby
    // czego uruchomić po zamknięciu; "__…" to elementy stałe docka.
    function canPin(id) { return !!id && !id.startsWith("wm:") && !id.startsWith("__"); }

    // Wstawia (albo przenosi) PRZED beforeId; pusty beforeId = na koniec.
    // Po id, nie indeksie: dock liczy pozycję względem widocznych, a
    // dock.json trzyma też te ukryte.
    function place(id, beforeId) {
        if (!canPin(id)) return;
        const l = store.pinned.filter(k => k !== id);
        const at = beforeId && beforeId !== "" ? l.indexOf(beforeId) : -1;
        l.splice(at < 0 ? l.length : at, 0, id);
        store.pinned = l;
    }

    function pin(id) { if (!has(id)) place(id, ""); }
    function unpin(id) { if (has(id)) store.pinned = store.pinned.filter(k => k !== id); }
    function toggle(id) { if (has(id)) unpin(id); else pin(id); }
}
