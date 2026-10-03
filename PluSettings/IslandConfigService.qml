pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// ---------------------------------------------------------------
// Konfiguracja wyspy (~/.config/PluDynamicIsland/config.jsonc) dla strony
// „Wyspa” w ustawieniach. Plik należy do wyspy: ona go tworzy, czyta na
// żywo i waliduje. My tylko czytamy i podmieniamy pojedyncze wartości.
//
// Zapis jest PUNKTOWY: zmieniamy w tekście sam zakres wartości jednego
// klucza (albo dopisujemy brakujący klucz), a nie serializujemy całości.
// Plik jest JSONC z komentarzami pisanymi ręcznie — JSON.stringify całego
// obiektu skasowałby je przy pierwszym kliknięciu przełącznika.
//
// Domyślne wartości bierzemy z config.default.jsonc w katalogu wyspy
// (Settings.islandPath), tak samo jak ona — bez kopii listy opcji tutaj.
// ---------------------------------------------------------------
Singleton {
    id: root

    readonly property string userPath: Quickshell.env("HOME") + "/.config/PluDynamicIsland/config.jsonc"
    readonly property string defaultsPath: Settings.islandPath + "/config.default.jsonc"

    // Domyślne wczytane — bez nich nie wiadomo, jakie opcje istnieją.
    readonly property bool ready: priv.defaults !== null
    // Błąd składni w pliku użytkownika ("" = brak). Zapis jest wtedy
    // zablokowany: punktowa podmiana w zepsutym pliku mogłaby go dobić.
    readonly property string error: priv.error
    readonly property bool writable: ready && error === ""
    // Domyślne scalone z plikiem użytkownika — to, co widzi wyspa.
    readonly property var values: priv.values

    // Wartość po ścieżce "sekcja.klucz". Czyta `values`, więc powiązanie,
    // które ją woła, przelicza się po każdej zmianie pliku.
    function get(path, fallback) {
        let v = root.values;
        for (const k of path.split(".")) {
            if (v === null || typeof v !== "object" || !(k in v)) return fallback;
            v = v[k];
        }
        return v;
    }

    function set(path, value) { return setMany([[path, value]]); }

    // Kilka zmian jednym zapisem: [[ścieżka, wartość], …]. Osobne zapisy
    // też by się złożyły (applyUser podmienia tekst od razu), ale każdy
    // to przeładowanie w wyspie.
    function setMany(pairs) {
        if (!root.writable) return false;
        // Brak pliku (wyspa jeszcze nie startowała): zaczynamy od szablonu,
        // jak zrobiłaby to ona — z komentarzami.
        const base = priv.userText !== null ? priv.userText : priv.defaultsText;
        let text = base;
        for (const [path, value] of pairs) {
            try {
                text = setInText(text, path.split("."), format(value));
            } catch (e) {
                if (!e.jsonc) throw e;
                console.warn("[wyspa] nie udało się zapisać " + path + ": " + e.msg);
                return false;
            }
        }
        if (text === base) return true;
        priv.applyUser(text);
        userFile.setText(text);
        return true;
    }

    // ---- wartości domyślne i reset ----

    function walk(obj, path) {
        let v = obj;
        for (const k of path.split(".")) {
            if (v === null || typeof v !== "object" || Array.isArray(v) || !(k in v)) return undefined;
            v = v[k];
        }
        return v;
    }

    function defaultValue(path) { return walk(priv.defaults, path); }

    // Zmienione = w PLIKU stoi coś innego niż domyślne. Liczy się wartość
    // z pliku, nie scalona: zła wartość (np. tekst zamiast liczby) przegrywa
    // przy scalaniu z domyślną, ale dalej siedzi w pliku i reset ma ją
    // usunąć. Brak klucza w pliku = domyślne.
    function isModified(path) {
        const u = walk(priv.user, path);
        return u !== undefined && JSON.stringify(u) !== JSON.stringify(defaultValue(path));
    }

    // Wszystkie zmienione liście (listy, np. cards.hidden, to jeden liść).
    readonly property var modifiedPaths: {
        const out = [];
        function scan(def, prefix) {
            for (const k in def) {
                const p = prefix === "" ? k : prefix + "." + k;
                const d = def[k];
                if (d !== null && typeof d === "object" && !Array.isArray(d)) scan(d, p);
                else if (root.isModified(p)) out.push(p);
            }
        }
        if (priv.defaults !== null) scan(priv.defaults, "");
        return out;
    }

    // Reset wpisuje wartość domyślną w miejsce zmienionej, zamiast kasować
    // klucz — plik zostaje kompletną, opisaną listą opcji, jak szablon.
    function reset(paths) {
        return setMany(paths.filter(p => defaultValue(p) !== undefined).map(p => [p, defaultValue(p)]));
    }

    function resetAll() { return reset(modifiedPaths); }

    // Jak w szablonie wyspy: listy ze spacją po przecinku.
    function format(value) {
        return Array.isArray(value) ? "[" + value.map(v => JSON.stringify(v)).join(", ") + "]" : JSON.stringify(value);
    }

    // Plik w edytorze z terminala z ustawień (jak wpisy Terminal=true).
    function openInEditor() {
        Quickshell.execDetached([Settings.terminal, "-e", "sh", "-c", "exec \"${EDITOR:-nano}\" \"$1\"", "sh", root.userPath]);
    }

    QtObject {
        id: priv

        property var defaults: null
        property string defaultsText: ""
        // null = pliku użytkownika nie ma.
        property var userText: null
        property var user: ({})
        property string error: ""
        property var values: ({})

        function applyDefaults(text) {
            try {
                defaultsText = text;
                defaults = root.plain(root.parse(text));
            } catch (e) {
                if (!e.jsonc) throw e;
                defaults = null;
                console.warn("[wyspa] " + root.defaultsPath + ": " + root.describe(text, e));
            }
            recompute();
        }

        function applyUser(text) {
            userText = text;
            if (text === null) {
                user = {};
                error = "";
            } else {
                try {
                    user = root.plain(root.parse(text));
                    error = "";
                } catch (e) {
                    if (!e.jsonc) throw e;
                    // Ostatnie dobre `user` zostaje, jak w wyspie.
                    error = root.describe(text, e);
                }
            }
            recompute();
        }

        function recompute() {
            values = defaults === null ? {} : root.merge(defaults, user);
        }
    }

    FileView {
        id: defaultsFile
        path: root.defaultsPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: priv.applyDefaults(text())
        onLoadFailed: {
            priv.defaults = null;
            priv.recompute();
        }
    }

    FileView {
        id: userFile
        path: root.userPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: priv.applyUser(text())
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) priv.applyUser(null);
        }
        // Obserwacja pliku, którego nie było, nic nie łapie (zmierzone
        // w wyspie) — po pierwszym zapisie wczytujemy go od nowa.
        onSaved: reload()
    }

    // ---- scalanie ----

    // Typ bierze się z wartości domyślnej; niezgodna wartość z pliku
    // przegrywa z domyślną, bo tak samo postąpi wyspa (ona też zgłosi
    // to w swoim logu, my tylko pokazujemy).
    function kind(v) {
        if (Array.isArray(v)) return "array";
        return v === null ? "null" : typeof v;
    }

    function merge(def, user) {
        if (user === undefined || kind(def) !== kind(user)) return def;
        if (kind(def) !== "object") return user;
        const out = {};
        for (const k in def) out[k] = merge(def[k], user[k]);
        return out;
    }

    // ---- JSONC z pozycjami ----

    // Ten sam parser co w IslandConfig wyspy (komentarze, przecinek na
    // końcu, linia błędu), ale zwraca drzewo z zakresami w tekście —
    // obiekt: { type: "object", start, end, members: [{ key, keyStart,
    // valueStart, valueEnd, node }] }, reszta: { type: "value", value }.
    function parse(text) {
        let pos = 0;

        function fail(msg) { throw { jsonc: true, msg: msg, pos: pos }; }

        function skip() {
            for (;;) {
                while (pos < text.length && /\s/.test(text[pos])) pos++;
                if (text.startsWith("//", pos)) {
                    while (pos < text.length && text[pos] !== "\n") pos++;
                } else if (text.startsWith("/*", pos)) {
                    const end = text.indexOf("*/", pos + 2);
                    if (end < 0) fail("niezamknięty komentarz /*");
                    pos = end + 2;
                } else {
                    return;
                }
            }
        }

        function token(re, what) {
            const m = re.exec(text.slice(pos));
            if (!m) fail("oczekiwano: " + what);
            pos += m[0].length;
            return m[0];
        }

        function string() {
            return JSON.parse(token(/^"(?:[^"\\\n]|\\.)*"/, "napis w \"cudzysłowie\""));
        }

        function value() {
            skip();
            const c = text[pos];
            if (c === "{") return object();
            if (c === "[") return list();
            if (c === "\"") return { type: "value", value: string() };
            if (c === "-" || (c >= "0" && c <= "9"))
                return { type: "value", value: Number(token(/^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?/, "liczba")) };
            if (text.startsWith("true", pos)) { pos += 4; return { type: "value", value: true }; }
            if (text.startsWith("false", pos)) { pos += 5; return { type: "value", value: false }; }
            if (text.startsWith("null", pos)) { pos += 4; return { type: "value", value: null }; }
            fail(pos >= text.length ? "plik urywa się w połowie" : "nieoczekiwany znak '" + c + "'");
        }

        function object() {
            const node = { type: "object", start: pos, end: -1, members: [] };
            pos++;
            for (;;) {
                skip();
                if (text[pos] === "}") { pos++; node.end = pos; return node; }
                if (text[pos] !== "\"") fail("oczekiwano nazwy w \"cudzysłowie\" albo }");
                const keyStart = pos;
                const key = string();
                skip();
                if (text[pos] !== ":") fail("oczekiwano : po \"" + key + "\"");
                pos++;
                skip();
                const valueStart = pos;
                const child = value();
                node.members.push({ key: key, keyStart: keyStart, valueStart: valueStart, valueEnd: pos, node: child });
                skip();
                if (text[pos] === ",") { pos++; continue; }
                if (text[pos] === "}") { pos++; node.end = pos; return node; }
                fail(pos >= text.length ? "plik urywa się, brakuje }" : "brak przecinka po \"" + key + "\"");
            }
        }

        function list() {
            const out = [];
            pos++;
            for (;;) {
                skip();
                if (text[pos] === "]") { pos++; return { type: "value", value: out }; }
                out.push(plain(value()));
                skip();
                if (text[pos] === ",") { pos++; continue; }
                if (text[pos] === "]") { pos++; return { type: "value", value: out }; }
                fail(pos >= text.length ? "plik urywa się, brakuje ]" : "brak przecinka w liście");
            }
        }

        skip();
        if (text[pos] !== "{") fail("plik ma zaczynać się od {");
        const result = object();
        skip();
        if (pos < text.length) fail("coś po ostatnim }");
        return result;
    }

    function plain(node) {
        if (node.type !== "object") return node.value;
        const out = {};
        for (const m of node.members) out[m.key] = plain(m.node);
        return out;
    }

    function describe(text, e) {
        const before = text.slice(0, e.pos).split("\n");
        return "linia " + before.length + ", kolumna " + (before[before.length - 1].length + 1) + ": " + e.msg;
    }

    // ---- punktowy zapis ----

    // Wcięcie wiersza, w którym leży `pos`, o ile przed `pos` są same białe znaki.
    function indentAt(text, pos) {
        const lineStart = text.lastIndexOf("\n", pos - 1) + 1;
        const lead = text.slice(lineStart, pos);
        return /^[ \t]*$/.test(lead) ? lead : null;
    }

    function setInText(text, keys, valueJson) {
        let node = parse(text);
        let objIndent = "";
        for (let i = 0; i < keys.length; i++) {
            const m = node.members.find(x => x.key === keys[i]);
            const last = i === keys.length - 1;

            if (!m) return insertMember(text, node, objIndent, keys[i], nest(keys.slice(i + 1), valueJson));

            // Klucz jest, ale zamiast obiektu ma np. liczbę — podmieniamy
            // całą wartość na obiekt z resztą ścieżki.
            if (last || m.node.type !== "object")
                return text.slice(0, m.valueStart) + (last ? valueJson : nest(keys.slice(i + 1), valueJson)) + text.slice(m.valueEnd);

            objIndent = indentAt(text, m.keyStart) ?? objIndent + "    ";
            node = m.node;
        }
        return text;
    }

    // { "a": { "b": wartość } } dla brakującej reszty ścieżki — w jednej
    // linii, bo to zwykle jeden klucz.
    function nest(keys, valueJson) {
        let out = valueJson;
        for (let i = keys.length - 1; i >= 0; i--) out = "{ " + JSON.stringify(keys[i]) + ": " + out + " }";
        return out;
    }

    // Nowy klucz idzie na KONIEC obiektu, w osobnym wierszu, za komentarzem
    // kończącym wiersz poprzedniego klucza — wstawiony zaraz po wartości
    // przejąłby jej komentarz ("a": 1, // opis a).
    function insertMember(text, node, objIndent, key, valueJson) {
        const member = JSON.stringify(key) + ": " + valueJson;

        if (node.members.length === 0) {
            const inner = objIndent + "    ";
            const p = node.start + 1;
            const closesOnLine = /^[ \t]*\}/.test(text.slice(p));
            return text.slice(0, p) + "\n" + inner + member + (closesOnLine ? "\n" + objIndent : "") + text.slice(p);
        }

        const prev = node.members[node.members.length - 1];
        const indent = indentAt(text, prev.keyStart) ?? objIndent + "    ";
        let p = prev.valueEnd;
        while (text[p] === " " || text[p] === "\t") p++;
        const hasComma = text[p] === ",";
        if (hasComma) p++;
        while (text[p] === " " || text[p] === "\t") p++;
        if (text.startsWith("//", p)) while (p < text.length && text[p] !== "\n") p++;

        if (hasComma) return text.slice(0, p) + "\n" + indent + member + text.slice(p);
        return text.slice(0, prev.valueEnd) + "," + text.slice(prev.valueEnd, p) + "\n" + indent + member + text.slice(p);
    }
}
