pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// ---------------------------------------------------------------
// Stan launchera, wyszukiwanie i ranking po częstości użycia
// (~/.config/plude/launcher.json).
// ---------------------------------------------------------------
Singleton {
    id: root

    // Po ilu dniach uruchomienie waży połowę (ranking pustego zapytania
    // i premia w wynikach wyszukiwania).
    property real halfLifeDays: 14
    // Ile najwyżej punktów premii za częstość przy wpisanym zapytaniu —
    // mniej niż różnica między "zaczyna się od" a "zawiera", żeby często
    // używana aplikacja nie wypychała trafienia po nazwie.
    property int maxUsageBonus: 150

    property bool open: false

    function toggle() { open = !open; }
    function show() { open = true; }
    function hide() { open = false; }

    // ---- częstość użycia ----

    FileView {
        path: Settings.configDir + "/launcher.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) writeAdapter();
        }

        JsonAdapter {
            id: usage
            // { "<id .desktop>": { count: n, last: epoch ms } }
            property var apps: ({})
        }
    }

    // Każde uruchomienie się liczy — także z docka: dock to też "używam
    // tej aplikacji", a launcher ma pokazywać to, czego naprawdę używasz.
    Connections {
        target: Apps
        function onLaunched(id) {
            const a = Object.assign({}, usage.apps);
            const cur = a[id] || { count: 0, last: 0 };
            a[id] = { count: cur.count + 1, last: Date.now() };
            usage.apps = a;
        }
    }

    // count ważony wiekiem ostatniego użycia (połowiczny zanik).
    function frecency(id) {
        const u = usage.apps[id];
        if (!u) return 0;
        const days = (Date.now() - u.last) / 86400000;
        return u.count * Math.pow(0.5, days / halfLifeDays);
    }

    // ---- wyszukiwanie ----

    // Punkty trafienia napisu w zapytanie; 0 = nie pasuje.
    function matchScore(text, q) {
        const t = (text || "").toLowerCase();
        if (t === "") return 0;
        if (t === q) return 1000;
        if (t.startsWith(q)) return 800;
        // Początek słowa: "code" w "Visual Studio Code", "st" w "Ustawienia systemu"
        const words = t.split(/[\s\-_.]+/);
        for (let i = 0; i < words.length; i++) if (words[i].startsWith(q)) return 600;
        if (t.indexOf(q) >= 0) return 400;
        return 0;
    }

    // Litery zapytania po kolei, niekoniecznie obok siebie ("vsc" → "Visual
    // Studio Code"). Im ciaśniej leżą, tym więcej punktów.
    function fuzzyScore(text, q) {
        const t = (text || "").toLowerCase();
        let pos = -1, first = -1;
        for (let i = 0; i < q.length; i++) {
            pos = t.indexOf(q[i], pos + 1);
            if (pos < 0) return 0;
            if (first < 0) first = pos;
        }
        const spread = pos - first + 1 - q.length;   // ile liter "pomiędzy"
        return Math.max(50, 200 - spread * 10 - first * 2);
    }

    function score(e, q) {
        let s = matchScore(e.name, q);
        if (s === 0) {
            const extra = [e.genericName, e.id, e.comment].concat(e.keywords || []);
            for (let i = 0; i < extra.length; i++) s = Math.max(s, matchScore(extra[i], q) > 0 ? 250 : 0);
        }
        if (s === 0) s = fuzzyScore(e.name, q);
        return s;
    }

    function search(query) {
        const q = (query || "").trim().toLowerCase();
        const apps = Apps.visibleApps;
        // Zależność od użycia — ranking pustego zapytania ma się przeliczyć
        // po każdym uruchomieniu.
        usage.apps;

        if (q === "") {
            return apps.slice().sort((a, b) => {
                const d = frecency(b.id) - frecency(a.id);
                return d !== 0 ? d : a.name.localeCompare(b.name);
            });
        }

        const scored = [];
        for (let i = 0; i < apps.length; i++) {
            const s = score(apps[i], q);
            if (s > 0) scored.push({ e: apps[i], s: s + Math.min(maxUsageBonus, frecency(apps[i].id) * 15) });
        }
        scored.sort((a, b) => b.s - a.s || a.e.name.localeCompare(b.e.name));
        return scored.map(x => x.e);
    }
}
