import QtQuick
import Quickshell
import qs.Common

// Strona „Wyspa”: konfiguracja PluDynamicIsland (config.jsonc wyspy).
// Wyspa czyta plik na żywo, więc zmiana działa od razu, a zapis jest
// punktowy — ręczne komentarze w pliku zostają (IslandConfigService).
//
// Pokazujemy to, co da się sensownie wybrać z listy. Reszta (np. progi
// koloru z okładki, czasy wewnętrzne) zostaje w pliku z opisem.
Column {
    id: page

    spacing: 22

    readonly property var cfg: IslandConfigService
    readonly property bool editable: cfg.writable

    function v(path, fallback) { return cfg.get(path, fallback); }
    function set(path, value) { cfg.set(path, value); }

    // Lista wyboru z liczb. Wartość spoza listy (wpisana ręcznie w pliku)
    // dochodzi na koniec — inaczej lista pokazałaby „—”.
    function numbers(list, current, label) {
        const all = list.indexOf(current) < 0 && current !== undefined ? list.concat([current]) : list;
        return all.slice().sort((a, b) => a - b).map(n => ({ value: n, label: label(n) }));
    }
    function ms(n) { return n >= 1000 ? (n / 1000).toLocaleString(Qt.locale("pl_PL"), "f", n % 1000 === 0 ? 0 : 1) + " s" : n + " ms"; }
    function pct(n) { return Math.round(n * 100) + "%"; }

    // Podgląd formatu zegara na żywo.
    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // ---- przełącznik + czas w jednym wierszu (auto-rozwinięcia) ----
    component TimedSwitch: Row {
        id: timed
        property string enabledKey: ""
        property string durationKey: ""
        property var durations: [2000, 3000, 4500, 6000]

        spacing: 12

        SettingsChoice {
            anchors.verticalCenter: parent.verticalCenter
            width: 96
            enabled: page.editable && page.v(timed.enabledKey, true)
            model: page.numbers(timed.durations, page.v(timed.durationKey), page.ms)
            value: page.v(timed.durationKey)
            onPicked: x => page.set(timed.durationKey, x)
        }

        SettingsSwitch {
            anchors.verticalCenter: parent.verticalCenter
            enabled: page.editable
            checked: page.v(timed.enabledKey, true)
            onToggled: page.set(timed.enabledKey, !checked)
        }
    }

    // ---- wiersz z jednym przełącznikiem ----
    component SwitchRow: IslandRow {
        id: switchRow
        property string key: ""
        // Wyłączony, gdy zależy od innego przełącznika, który jest wyłączony.
        property bool active: true
        paths: [key]

        SettingsSwitch {
            enabled: page.editable && switchRow.active
            checked: page.v(switchRow.key, true)
            onToggled: page.set(switchRow.key, !checked)
        }
    }

    // ---- wiersz z resetem do domyślnych ----
    // `paths` to klucze, które wiersz ustawia; strzałka resetu pokazuje się,
    // gdy którykolwiek z nich różni się w pliku od domyślnego.
    component IslandRow: SettingsRow {
        property var paths: []
        resettable: true
        modified: page.editable && paths.some(p => page.cfg.isModified(p))
        onReset: page.cfg.reset(paths)
    }

    // ---- karta widoczna w karuzeli ----
    // Wszystkie karty dzielą jeden klucz (lista cards.hidden), więc wiersz
    // karty porównuje i resetuje tylko SWOJĄ obecność na liście — reset
    // jednej karty nie może przywracać pozostałych.
    component CardRow: SettingsRow {
        id: cardRow
        property string key: ""

        readonly property bool hiddenNow: page.v("cards.hidden", []).indexOf(key) >= 0
        readonly property bool hiddenByDefault: (page.cfg.defaultValue("cards.hidden") ?? []).indexOf(key) >= 0

        resettable: true
        modified: page.editable && hiddenNow !== hiddenByDefault
        onReset: {
            const others = page.v("cards.hidden", []).filter(k => k !== cardRow.key);
            page.set("cards.hidden", hiddenByDefault ? others.concat([cardRow.key]) : others);
        }

        SettingsSwitch {
            enabled: page.editable
            checked: page.v("cards.hidden", []).indexOf(cardRow.key) < 0
            onToggled: {
                const hidden = page.v("cards.hidden", []).filter(k => k !== cardRow.key);
                page.set("cards.hidden", checked ? hidden.concat([cardRow.key]) : hidden);
            }
        }
    }

    // ---- stan pliku i wyspy ----

    Rectangle {
        width: page.width
        height: statusRow.implicitHeight + 24
        radius: 14
        visible: !page.cfg.ready || page.cfg.error !== ""
        // Pełny kolor, bez alfy (DESIGN.md): danger zmieszany z tłem karty.
        color: Qt.tint(Theme.surfaceRaised, Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.22))
        border.width: 1
        border.color: Theme.danger

        Row {
            id: statusRow
            x: 14
            y: 12
            width: parent.width - 28
            spacing: 10

            Icon {
                kind: "warning"
                size: 18
                color: Theme.danger
            }

            Text {
                width: parent.width - 28
                wrapMode: Text.Wrap
                color: Theme.text
                font.pixelSize: 12
                text: !page.cfg.ready
                    ? "Nie znaleziono " + page.cfg.defaultsPath + ". Sprawdź „Katalog wyspy” na stronie Ogólne."
                    : "Plik konfiguracji ma błąd (" + page.cfg.error + "). Popraw go w edytorze — do tego czasu zmiany stąd są wyłączone, a wyspa działa na ostatniej dobrej wersji."
            }
        }
    }

    SettingsSection {
        width: page.width
        title: "Plik"

        SettingsRow {
            title: IslandLink.alive ? "Wyspa działa" : "Wyspa nie działa"
            description: (IslandLink.alive ? "Zmiany wchodzą od razu." : "Zmiany wejdą przy jej starcie.")
                + " Wszystkie opcje z opisem są w pliku — także te, których tu nie ma."

            SettingsButton {
                text: "Otwórz plik"
                onClicked: page.cfg.openInEditor()
            }
        }
    }

    SettingsSection {
        width: page.width
        title: "Ogólne"

        IslandRow {
            paths: ["general.screen"]
            title: "Monitor"
            description: "Ekran, na którym stoi wyspa. Automatycznie: monitor w punkcie (0,0)."

            SettingsChoice {
                width: 260
                enabled: page.editable
                model: {
                    const cur = page.v("general.screen", "");
                    const out = [{ value: "", label: "Automatycznie" }];
                    const names = [];
                    MonitorService.monitors.forEach(m => {
                        if (m.disabled) return;
                        names.push(m.name);
                        out.push({ value: m.name, label: m.description !== "" ? m.name + " · " + m.description : m.name });
                    });
                    if (cur !== "" && names.indexOf(cur) < 0) out.push({ value: cur, label: cur + " (odłączony)" });
                    return out;
                }
                value: page.v("general.screen", "")
                onPicked: x => page.set("general.screen", x)
            }
        }

        IslandRow {
            paths: ["general.loopAnimations"]
            title: "Animacje w pętli"
            description: "Puls obwódki przy ładowaniu i kropek rozmowy. Każda klatka to przerysowanie ekranu — na słabszym GPU potrafi lagować."

            SettingsChoice {
                width: 180
                enabled: page.editable
                model: [
                    { value: "auto", label: "Bez laptopa" },
                    { value: "on", label: "Zawsze" },
                    { value: "off", label: "Nigdy" }
                ]
                value: page.v("general.loopAnimations", "auto")
                onPicked: x => page.set("general.loopAnimations", x)
            }
        }

        IslandRow {
            paths: ["general.topMargin"]
            title: "Odstęp od góry"

            SettingsChoice {
                width: 96
                enabled: page.editable
                model: page.numbers([0, 4, 8, 12, 16], page.v("general.topMargin"), n => n + " px")
                value: page.v("general.topMargin")
                onPicked: x => page.set("general.topMargin", x)
            }
        }

        IslandRow {
            paths: ["general.locale"]
            title: "Język daty"
            description: "Nazwy dni i miesięcy na karcie zegara."

            SettingsChoice {
                width: 140
                enabled: page.editable
                model: {
                    const list = [
                        { value: "pl_PL", label: "Polski" },
                        { value: "en_US", label: "English (US)" },
                        { value: "en_GB", label: "English (UK)" },
                        { value: "de_DE", label: "Deutsch" }
                    ];
                    const cur = page.v("general.locale", "pl_PL");
                    return list.some(l => l.value === cur) ? list : list.concat([{ value: cur, label: cur }]);
                }
                value: page.v("general.locale", "pl_PL")
                onPicked: x => page.set("general.locale", x)
            }
        }

        SwitchRow {
            key: "updates.check"
            title: "Sprawdzaj aktualizacje"
            description: "Przy starcie wyspa sprawdza GitHuba i pyta o nowe commity. Aktualizuje tylko czyste repozytorium, fast-forwardem."
        }
    }

    SettingsSection {
        width: page.width
        title: "Karty"

        CardRow { key: "music"; title: "Muzyka" }
        CardRow { key: "airpods"; title: "AirPodsy"; description: "Pojawia się tylko przy połączonych słuchawkach." }
        CardRow { key: "discord"; title: "Discord" }
        CardRow { key: "clock"; title: "Zegar" }
        CardRow { key: "connectivity"; title: "Łączność"; description: "Wi-Fi i Bluetooth. Nakładki z paska działają także bez karty." }
        CardRow { key: "notifications"; title: "Powiadomienia"; description: "Ukryta karta nie wyłącza powiadomień — dalej trafiają do historii." }
    }

    SettingsSection {
        width: page.width
        title: "Rozwijanie"

        IslandRow {
            paths: ["expand.collapseDelay"]
            title: "Zwijanie po zjechaniu kursorem"

            SettingsChoice {
                width: 96
                enabled: page.editable
                model: page.numbers([100, 220, 400, 700], page.v("expand.collapseDelay"), page.ms)
                value: page.v("expand.collapseDelay")
                onPicked: x => page.set("expand.collapseDelay", x)
            }
        }

        IslandRow {
            paths: ["expand.onTrackChange", "expand.trackChangeMs"]
            title: "Zmiana utworu"
            description: "Wyspa rozwija się na chwilę z kartą muzyki."
            TimedSwitch { enabledKey: "expand.onTrackChange"; durationKey: "expand.trackChangeMs" }
        }

        IslandRow {
            paths: ["expand.onNotification", "expand.notificationMs"]
            title: "Nowe powiadomienie"
            TimedSwitch { enabledKey: "expand.onNotification"; durationKey: "expand.notificationMs" }
        }

        IslandRow {
            paths: ["expand.onTransfer", "expand.transferMs"]
            title: "Kopiowanie pliku"
            description: "Start transferu w Dolphinie albo pobierania."
            TimedSwitch { enabledKey: "expand.onTransfer"; durationKey: "expand.transferMs" }
        }

        IslandRow {
            paths: ["expand.onAirPods", "expand.airPodsMs"]
            title: "Połączenie AirPodsów"
            TimedSwitch { enabledKey: "expand.onAirPods"; durationKey: "expand.airPodsMs" }
        }

        IslandRow {
            paths: ["expand.onTimer", "expand.timerMs"]
            title: "Dzwoniący minutnik"
            description: "Karta zegara z minutnikiem KClock, który właśnie się skończył."
            TimedSwitch { enabledKey: "expand.onTimer"; durationKey: "expand.timerMs"; durations: [4000, 8000, 15000, 30000] }
        }
    }

    SettingsSection {
        width: page.width
        title: "Zegar"

        IslandRow {
            paths: ["clock.pillFormat"]
            title: "W pigułce"
            description: "Teraz: " + Qt.formatTime(clock.date, page.v("clock.pillFormat", "HH:mm"))
                + ". Szerokość pigułki jest stała — z sekundami robi się ciasno."

            SettingsField {
                width: 160
                enabled: page.editable
                value: page.v("clock.pillFormat", "")
                placeholder: "HH:mm"
                onCommitted: t => { if (t.trim() !== "") page.set("clock.pillFormat", t.trim()); }
            }
        }

        IslandRow {
            paths: ["clock.cardFormat"]
            title: "Na karcie"
            description: "Teraz: " + Qt.formatTime(clock.date, page.v("clock.cardFormat", "HH:mm:ss"))

            SettingsField {
                width: 160
                enabled: page.editable
                value: page.v("clock.cardFormat", "")
                placeholder: "HH:mm:ss"
                onCommitted: t => { if (t.trim() !== "") page.set("clock.cardFormat", t.trim()); }
            }
        }

        IslandRow {
            paths: ["clock.dateFormat"]
            title: "Data"
            description: "Teraz: " + clock.date.toLocaleDateString(Qt.locale(page.v("general.locale", "pl_PL")), page.v("clock.dateFormat", "dddd, d MMMM"))
                + ". HH godzina, h 1–12, AP rano/po południu, dddd dzień, MMMM miesiąc."

            SettingsField {
                width: 160
                enabled: page.editable
                value: page.v("clock.dateFormat", "")
                placeholder: "dddd, d MMMM"
                onCommitted: t => { if (t.trim() !== "") page.set("clock.dateFormat", t.trim()); }
            }
        }

        SwitchRow {
            key: "clock.timers"
            title: "Minutniki KClock"
            description: "Lista minutników na karcie zegara (start, pauza, reset). Nowe dodaje się w KClock."
        }
    }

    SettingsSection {
        width: page.width
        title: "Widmo dźwięku"

        IslandRow {
            paths: ["spectrum.bars"]
            title: "Liczba słupków"

            SettingsChoice {
                width: 96
                enabled: page.editable
                model: page.numbers([3, 4, 5, 6, 8, 10, 12], page.v("spectrum.bars"), n => String(n))
                value: page.v("spectrum.bars")
                onPicked: x => page.set("spectrum.bars", x)
            }
        }

        IslandRow {
            paths: ["spectrum.framerate"]
            title: "Klatki na sekundę"
            description: "Automatycznie: 60 na desktopie, 30 na laptopie. Póki gra muzyka, każda klatka to przerysowanie ekranu."

            SettingsChoice {
                width: 140
                enabled: page.editable
                model: page.numbers([0, 30, 60, 120, 144], page.v("spectrum.framerate"), n => n === 0 ? "Automatycznie" : String(n))
                value: page.v("spectrum.framerate")
                onPicked: x => page.set("spectrum.framerate", x)
            }
        }

        IslandRow {
            paths: ["spectrum.noiseReduction"]
            title: "Wygładzanie"
            description: "Mniej = żywiej i nerwowo, więcej = leniwie."

            SettingsChoice {
                width: 140
                enabled: page.editable
                model: page.numbers([20, 35, 50, 70], page.v("spectrum.noiseReduction"),
                                    n => n === 35 ? "35 (domyślne)" : String(n))
                value: page.v("spectrum.noiseReduction")
                onPicked: x => page.set("spectrum.noiseReduction", x)
            }
        }

        IslandRow {
            paths: ["spectrum.colorFromArt"]
            title: "Kolor z okładki"
            description: "Słupki w kolorach okładki utworu, jak w iOS."

            SettingsSwitch {
                enabled: page.editable
                checked: page.v("spectrum.colorFromArt", true)
                onToggled: page.set("spectrum.colorFromArt", !checked)
            }
        }

        IslandRow {
            paths: ["spectrum.fallbackColor"]
            title: page.v("spectrum.colorFromArt", true) ? "Kolor bez okładki" : "Kolor słupków"

            SettingsColor {
                enabled: page.editable
                value: page.v("spectrum.fallbackColor", "")
                onPicked: x => page.set("spectrum.fallbackColor", x)
            }
        }
    }

    SettingsSection {
        width: page.width
        title: "Bateria (tylko laptop)"

        IslandRow {
            paths: ["battery.ring"]
            title: "Obwódka baterii"
            description: "Linia wokół zwiniętej pigułki, długa jak poziom baterii."

            SettingsSwitch {
                enabled: page.editable
                checked: page.v("battery.ring", true)
                onToggled: page.set("battery.ring", !checked)
            }
        }

        IslandRow {
            paths: ["battery.ringWidth"]
            title: "Grubość"

            SettingsChoice {
                width: 96
                enabled: page.editable && page.v("battery.ring", true)
                model: page.numbers([1, 1.5, 2, 3], page.v("battery.ringWidth"), n => String(n).replace(".", ",") + " px")
                value: page.v("battery.ringWidth")
                onPicked: x => page.set("battery.ringWidth", x)
            }
        }

        IslandRow {
            paths: ["battery.lowLevel"]
            title: "Niski poziom"
            description: "Poniżej, bez ładowania, obwódka zmienia kolor."

            SettingsChoice {
                width: 96
                enabled: page.editable && page.v("battery.ring", true)
                model: page.numbers([0.1, 0.15, 0.2, 0.3], page.v("battery.lowLevel"), page.pct)
                value: page.v("battery.lowLevel")
                onPicked: x => page.set("battery.lowLevel", x)
            }
        }

        IslandRow {
            paths: ["battery.color"]
            title: "Kolor na baterii"
            SettingsColor {
                enabled: page.editable && page.v("battery.ring", true)
                value: page.v("battery.color", "")
                onPicked: x => page.set("battery.color", x)
            }
        }

        IslandRow {
            paths: ["battery.chargingColor"]
            title: "Kolor na zasilaczu"
            SettingsColor {
                enabled: page.editable && page.v("battery.ring", true)
                value: page.v("battery.chargingColor", "")
                onPicked: x => page.set("battery.chargingColor", x)
            }
        }

        IslandRow {
            paths: ["battery.lowColor"]
            title: "Kolor przy niskim poziomie"
            SettingsColor {
                enabled: page.editable && page.v("battery.ring", true)
                value: page.v("battery.lowColor", "")
                onPicked: x => page.set("battery.lowColor", x)
            }
        }

        IslandRow {
            paths: ["battery.chargerNotice"]
            title: "Podłączenie ładowarki"
            description: "Pigułka poszerza się na chwilę i pokazuje stan zasilania."

            SettingsSwitch {
                enabled: page.editable
                checked: page.v("battery.chargerNotice", true)
                onToggled: page.set("battery.chargerNotice", !checked)
            }
        }
    }

    SettingsSection {
        width: page.width
        title: "Głośność i pigułki"

        IslandRow {
            paths: ["volume.notice"]
            title: "Pasek głośności"
            description: "Zmiana głośności klawiszami albo z paska pokazuje się na chwilę w zwiniętej pigułce."

            SettingsSwitch {
                enabled: page.editable
                checked: page.v("volume.notice", true)
                onToggled: page.set("volume.notice", !checked)
            }
        }

        IslandRow {
            paths: ["volume.step"]
            title: "Krok kółka"
            description: "Kółko nad pigułką wyjścia dźwięku na karcie muzyki."

            SettingsChoice {
                width: 96
                enabled: page.editable
                model: page.numbers([0.01, 0.02, 0.03, 0.05, 0.1], page.v("volume.step"), page.pct)
                value: page.v("volume.step")
                onPicked: x => page.set("volume.step", x)
            }
        }

        IslandRow {
            paths: ["pills.voice"]
            title: "Pigułka rozmowy"
            description: "Kanał i czas rozmowy na Discordzie obok wyspy."

            SettingsSwitch {
                enabled: page.editable
                checked: page.v("pills.voice", true)
                onToggled: page.set("pills.voice", !checked)
            }
        }

        IslandRow {
            paths: ["pills.screencast"]
            title: "Pigułka udostępniania"
            description: "Aplikacja, która udostępnia ekran, i czas."

            SettingsSwitch {
                enabled: page.editable
                checked: page.v("pills.screencast", true)
                onToggled: page.set("pills.screencast", !checked)
            }
        }

        SwitchRow {
            key: "pills.timer"
            title: "Pigułka minutnika"
            description: "Odliczanie minutnika KClock obok wyspy."
        }

        SwitchRow {
            key: "equalizer.autoHeadroom"
            title: "Zapas w korektorze"
            description: "Korektor (klik w widmo na karcie muzyki) ścisza wejście o największe podbicie, żeby bas nie przesterowywał."
        }
    }

    SettingsSection {
        width: page.width
        title: "Zerknięcia"

        SwitchRow {
            key: "glances.brightness"
            title: "Jasność ekranu"
            description: "Klawisze i suwak w pasku PluDE pokazują na chwilę poziom w zwiniętej pigułce."
        }

        SwitchRow { key: "glances.capsLock"; title: "Caps Lock" }

        SwitchRow {
            key: "glances.capsIndicator"
            title: "Stała ikonka Caps Locka"
            description: "W pigułce, póki Caps Lock jest włączony."
        }

        SwitchRow { key: "glances.numLock"; title: "Num Lock" }

        IslandRow {
            paths: ["glances.hudMs"]
            title: "Czas jasności i klawiszy"

            SettingsChoice {
                width: 96
                enabled: page.editable
                model: page.numbers([800, 1400, 2000, 3000], page.v("glances.hudMs"), page.ms)
                value: page.v("glances.hudMs")
                onPicked: x => page.set("glances.hudMs", x)
            }
        }

        IslandRow {
            paths: ["glances.commandDone", "glances.commandMs"]
            title: "Koniec długiej komendy"
            description: "Wymaga w ~/.zshrc: source " + Settings.islandPathRaw + "/integrations/island.zsh"
            TimedSwitch { enabledKey: "glances.commandDone"; durationKey: "glances.commandMs"; durations: [2000, 4000, 8000, 15000] }
        }

        IslandRow {
            paths: ["glances.ipcMs"]
            title: "Komunikaty z PluDE i skryptów"
            description: "Np. tekst ze zrzutu skopiowany do schowka."

            SettingsChoice {
                width: 96
                enabled: page.editable
                model: page.numbers([2000, 3000, 4500, 6000], page.v("glances.ipcMs"), page.ms)
                value: page.v("glances.ipcMs")
                onPicked: x => page.set("glances.ipcMs", x)
            }
        }
    }

    SettingsSection {
        width: page.width
        title: "Prywatność"

        SwitchRow {
            key: "privacy.dot"
            title: "Kropka w pigułce"
            description: "Pomarańczowa, gdy aplikacja nagrywa mikrofon, zielona przy kamerze."
        }

        IslandRow {
            paths: ["privacy.glance", "privacy.glanceMs"]
            title: "Nazwa aplikacji na starcie"
            description: "Zerknięcie, kto właśnie włączył mikrofon albo kamerę. Pomijane aplikacje są w pliku (privacy.ignoredApps)."
            TimedSwitch { enabledKey: "privacy.glance"; durationKey: "privacy.glanceMs"; durations: [1500, 2500, 4000, 6000] }
        }
    }

    SettingsSection {
        width: page.width
        title: "Efekty"

        SwitchRow { key: "effects.glassEdge"; title: "Szklana krawędź"; description: "Ramka wyspy jaśniejsza u góry." }
        SwitchRow { key: "effects.artGlow"; title: "Poświata okładki"; description: "Rozmyta okładka pod kartą muzyki." }
        SwitchRow { key: "effects.ripple"; title: "Fala"; description: "Przy powiadomieniu, AirPodsach, minutniku, ładowarce i wejściu na kanał." }
        SwitchRow { key: "effects.liquidPills"; title: "Płynne pigułki"; description: "Pigułki rozmowy, udostępniania i minutnika wypływają z wyspy jak kropla." }
        SwitchRow { key: "effects.carouselDepth"; title: "Głębia karuzeli"; description: "Przewijane karty oddalają się i przygasają." }
        SwitchRow { key: "effects.cascade"; title: "Kaskada"; description: "Treść karty wpływa po kolei." }
        SwitchRow { key: "effects.trackChange"; title: "Zmiana utworu"; description: "Okładka się obraca, tytuł wjeżdża od dołu." }
        SwitchRow { key: "effects.rollingClock"; title: "Przewijany zegar"; description: "Zmieniona cyfra przewija się jak w liczniku." }
    }

    SettingsSection {
        width: page.width
        title: "Powiadomienia i łączność"

        IslandRow {
            paths: ["notifications.historyLimit"]
            title: "Historia"
            description: "Tyle powiadomień trzyma karta."

            SettingsChoice {
                width: 96
                enabled: page.editable
                model: page.numbers([10, 30, 50, 100], page.v("notifications.historyLimit"), n => String(n))
                value: page.v("notifications.historyLimit")
                onPicked: x => page.set("notifications.historyLimit", x)
            }
        }

        IslandRow {
            paths: ["notifications.popupMs"]
            title: "Dymek powiadomienia"
            description: "Po tym czasie schodzi z karty; wpis zostaje w historii."

            SettingsChoice {
                width: 96
                enabled: page.editable
                model: page.numbers([3000, 5000, 8000, 12000], page.v("notifications.popupMs"), page.ms)
                value: page.v("notifications.popupMs")
                onPicked: x => page.set("notifications.popupMs", x)
            }
        }

        IslandRow {
            paths: ["bluetooth.scanMs"]
            title: "Skanowanie Bluetooth"
            description: "Kończy się samo, bo zajmuje radio."

            SettingsChoice {
                width: 96
                enabled: page.editable
                model: page.numbers([15000, 30000, 60000], page.v("bluetooth.scanMs"), page.ms)
                value: page.v("bluetooth.scanMs")
                onPicked: x => page.set("bluetooth.scanMs", x)
            }
        }

        IslandRow {
            paths: ["wifi.connectTimeoutMs"]
            title: "Limit łączenia z Wi-Fi"

            SettingsChoice {
                width: 96
                enabled: page.editable
                model: page.numbers([15000, 25000, 40000], page.v("wifi.connectTimeoutMs"), page.ms)
                value: page.v("wifi.connectTimeoutMs")
                onPicked: x => page.set("wifi.connectTimeoutMs", x)
            }
        }
    }

    SettingsSection {
        width: page.width
        title: "Domyślne"

        SettingsRow {
            id: resetAllRow

            readonly property int count: page.cfg.modifiedPaths.length
            // Reset wszystkiego jest za duży na jedno kliknięcie: pierwsze
            // tylko pyta, drugie (w ciągu confirmMs) wykonuje.
            property bool confirming: false
            property int confirmMs: 3000

            title: "Przywróć domyślne"
            description: count === 0 ? "Wszystkie ustawienia wyspy mają wartości domyślne."
                : "Zmienione: " + count + " " + (count === 1 ? "ustawienie" : count % 10 >= 2 && count % 10 <= 4 && (count % 100 < 10 || count % 100 >= 20) ? "ustawienia" : "ustawień")
                  + ". Komentarze w pliku zostają."

            onCountChanged: if (count === 0) confirming = false

            Timer {
                id: confirmTimer
                interval: resetAllRow.confirmMs
                onTriggered: resetAllRow.confirming = false
            }

            SettingsButton {
                text: resetAllRow.confirming ? "Na pewno?" : "Przywróć"
                tint: Theme.danger
                primary: resetAllRow.confirming
                enabled: page.editable && resetAllRow.count > 0
                onClicked: {
                    if (!resetAllRow.confirming) {
                        resetAllRow.confirming = true;
                        confirmTimer.restart();
                        return;
                    }
                    resetAllRow.confirming = false;
                    confirmTimer.stop();
                    page.cfg.resetAll();
                }
            }
        }
    }

    Text {
        x: 4
        width: page.width - 8
        text: "Zapis od razu do " + page.cfg.userPath.replace(Quickshell.env("HOME"), "~")
            + ". Zmieniana jest tylko wartość danego klucza, komentarze w pliku zostają."
        color: Theme.textFaint
        font.pixelSize: 11
        wrapMode: Text.Wrap
    }
}
