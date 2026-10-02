# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Czym to jest

Dock i launcher dla **Quickshell** (Wayland, layer-shell), dopełnienie dynamicznej
wyspy z `~/PluDynamicIsland`. Czysty QML, bez kroku budowania i bez testów.

- **Dock** (`PluAppDock/`): na dole ekranu, chowa się sam. Kolejność: przycisk
  launchera | przypięte | separator | uruchomione, nieprzypięte. Kropki okien,
  skakanie ikony przy uruchamianiu, plakietki powiadomień, postęp transferu,
  znaczek odtwarzania i rozmowy na Discordzie.
- **Launcher** (`PluLauncher/`): przyciemniony ekran z wyszukiwaniem i siatką
  aplikacji, ranking po częstości użycia. Otwierany `SUPER+R`, przyciskiem w docku i przez IPC.
- **Pasek** (`PluBar/`): dwie pigułki u góry po bokach wyspy. Lewa: obszary
  robocze i zasobnik. Prawa: jasność, głośność, mikrofon, sieć, Bluetooth, tryb
  energii, bateria, zasilanie. Klik w sieć lub BT otwiera nakładkę wyspy.
- **Ustawienia** (`PluSettings/`): zwykłe okno aplikacji ze stronami „Ogólne”
  (`settings.json`), „Monitory” i „Schowek i zrzuty”. Otwierane przez IPC,
  prawym klikiem na zasilaniu w pasku i wpisem „Ustawienia PluDE” w launcherze.
- **Schowek** (`PluClipboard/`): historia schowka (tekst i obrazy) na
  `wl-clipboard`, panel jak launcher. `SUPER+SHIFT+V`, wpis „Schowek”, IPC.
- **Zrzuty ekranu** (`PluScreenshot/`): `grim` + `slurp` + `swappy`, gotowy
  zrzut zgłasza wyspa (bez niej podgląd w rogu ekranu). `Print` (obszar albo okno), `SHIFT+Print` (ekran),
  `SUPER+Print` (aktywne okno), wpis „Zrzut ekranu”, IPC.

Środowisko: Quickshell 0.3.1, Qt 6.11, **tylko Hyprland** (0.56, konfiguracja w Lua).
Na innym kompozytorze `shell.qml` nie ładuje niczego i wypisuje jedną linię `console.info`.

## Polecenia

```sh
qs -p .                                          # uruchomienie z katalogu projektu
timeout 6 qs -p . --no-color > run.log 2>&1      # przebieg kontrolny, 124 = sukces
qs log -p ~/PluDE | tail                         # log działającej instancji
qs ipc -p ~/PluDE call launcher toggle           # launcher z zewnątrz
qs ipc -p ~/PluDE call bar brightnessStep 5      # jasność (klawisze w hyprland.lua)
qs ipc -p ~/PluDE call settings openPage monitors  # okno ustawień (open / toggle / close)
qs ipc -p ~/PluDE call clipboard toggle          # historia schowka (show / hide / clear)
qs ipc -p ~/PluDE call screenshot region         # zrzut: region / window / screen / edit
qs ipc -p ~/PluDE call screenshot delayed screen 3   # zrzut za 3 s, z odliczaniem
hyprctl globalshortcuts                          # czy skróty quickshell:* się zarejestrowały
hyprctl layers -j                                # przestrzenie nazw plude-dock / -launcher / -bar / -clipboard / -shot
```

Czysty przebieg nie ma ani jednej linii `WARN`/`ERROR`. Wyjątek: przy pierwszym
starcie (brak plików w `~/.config/plude/`) po jednym „Read … failed: File does not
exist” i „got operation finished from dropped operation” na plik. Pliki się wtedy
zapisują i następny start jest czysty.

Autostart i skróty są w `~/.config/hypr/hyprland.lua` (sekcje AUTOSTART, bindy
pod R i PLUDE na końcu: reguły warstw `no_anim`; rozmycia pod launcherem celowo nie ma).
Zależności spoza Quickshella: `wl-clipboard`, `grim`, `slurp`, `swappy`
(brak → komunikat w podglądzie zrzutu i na stronie ustawień, nic się nie wysypuje).

### Weryfikacja

Zasady jak w wyspie: `qmllint` nic tu nie da, jedyna realna walidacja to przebieg
i log. Sondy (`_probe*.qml`) uruchamiaj z **kopii** projektu w katalogu roboczym
sesji. Działająca instancja przeładowuje pliki z tego katalogu na żywo.
Przeładowanie rusza tylko po zapisie **w miejscu** i przy zmienionej treści:
`sed -i` podmienia plik (nowy i-węzeł) i instancja gubi jego obserwację, a zapis
tej samej treści nic nie robi (zmierzone: 0 przeładowań po obu). Wtedy pomaga
rzeczywista zmiana w innym obserwowanym pliku.

**Zrzuty.** `grabToImage` na `contentItem` okna nie działa („item has no QML
engine”). Trzeba chwycić element w środku, np. tło docka znalezione po
`radius === dock.dockRadius` wśród `dock.contentItem.children`. Taki zrzut ucina
wszystko, co wystaje nad tło (powiększenie, skok ikony). Zrzut całego okna: w kopii dodaj
do `Dock.qml` pusty `Item { anchors.fill: parent }` (alias `probeFrame`), a w sondzie
przepnij do niego dzieci: `c.parent = dock.probeFrame` dla każdego z
`contentItem.children`. Alias `default property` na `PanelWindow` NIE przejmuje
dzieci (zmierzone: 0 w ramce, 5 w `contentItem`).

Kursora nie da się ruszyć (brak ydotool, Wayland). Hover, przeciąganie, menu
i wysuwanie docka musi potwierdzić użytkownik.

## Architektura

`shell.qml` → `Loader` (tylko Hyprland) → `Main.qml`: `Dock`, `Launcher`, `Bar`,
`Clipboard`, `ShotToast`, `LazyLoader` z oknem ustawień, `IpcHandler` i `GlobalShortcut`. Moduły importuje się przez `import qs.Common` itd.
Singletony w podkatalogach działają **bez `qmldir`** (sprawdzone sondą), a pliki
w tym samym katalogu widzą się nawzajem bez importu.

```
Common/      Theme, Settings, Apps, Pins, IslandLink, PopupMenu, Icon
PluAppDock/  Dock (okno), DockItem (delegat), DockService (model)
PluLauncher/ Launcher (okno), LauncherService (stan, wyszukiwanie, częstość)
PluBar/      Bar (okno), BarButton, SliderPanel, Audio, Brightness, Connectivity
PluClipboard/  ClipboardService (historia, stan okna), Clipboard (okno), clip-store.sh
PluScreenshot/ ScreenshotService (kolejność kroków), ShotToast (podgląd w rogu)
PluSettings/ SettingsApp (stan okna), SettingsWindow, GeneralPage, MonitorsPage, CapturePage,
             MonitorService, MonitorDraft (szkic układu), MonitorCanvas,
             MonitorConfirm, ChoiceMenu, kontrolki Settings{Section,Row,Switch,Field,Choice,Button}
```

**Launcher nie importuje docka** (dock importuje launcher dla przycisku
„Aplikacje”). Dlatego przypinanie (`Pins`) i menu (`PopupMenu`) są w `Common`.

### Wyspa to osobny proces

Quickshell przeładowuje cały proces przy każdej zmianie pliku. Wyspa w tym samym
procesie przy każdej edycji docka wysyłałaby Discordowi nowe `AUTHORIZE`
i restartowała mostki. Rozmowa między procesami:

- **wyspa → dock**: `$XDG_RUNTIME_DIR/plude/island.json`, pisany przez
  `DockLink.qml` wyspy przy zmianie i co 5 s. Czytany przez `Common/IslandLink`.
  Plik, a nie IPC, bo zrestartowany dock ma od razu dostać stan. Po 15 s bez
  zapisu stan uznajemy za martwy i plakietki gasną.
- **dock → wyspa**: `qs -p <islandPath> ipc call island showNotifications <id>`.
- **zrzuty → wyspa**: zwykłe powiadomienie (`notify-send`), wyspa jest demonem
  powiadomień. Akcje wracają przez IPC PluDE (patrz „Zrzuty ekranu”).
- **pasek → wyspa**: `… call island toggleOverlay wifi|bluetooth` (nakładka
  Wi-Fi / BT; ta sama drugi raz ją zamyka). Martwa wyspa → `nmtui` /
  `bluetoothctl` w terminalu.
- **Klucz aplikacji** po obu stronach to id wpisu `.desktop`.

Media (znaczek odtwarzania) czytamy sami z MPRIS, nie przez wyspę. Wyspa wybiera
jeden odtwarzacz, a dock pokazuje znaczek przy każdym grającym.

### Pliki

- `~/.config/plude/settings.json`: monitor, terminal, ścieżka wyspy,
  `hideWithIsland`, `barReserve`, `screenshot*`, `clipboard*`. Pisze go okno ustawień (`Settings.set`), ale
  można go dalej edytować ręcznie. Zmiany wchodzą na żywo.
- `~/.config/plude/dock.json`: przypięte, pisze go program.
- `~/.config/plude/launcher.json`: licznik i czas ostatniego uruchomienia.
- `~/.config/plude/monitors.json`: reguły monitorów, pisze program. Z niego
  powstaje `~/.config/hypr/plude-monitors.lua` (patrz „Monitory”).
- `~/.local/state/plude/clipboard/`: historia schowka. `index.json` (spis
  z podglądem tekstu) i po jednym pliku z treścią na wpis (`<skrót>.txt`, `.png`).
  Katalog ma tryb 700: to jawna treść schowka.
- `$XDG_RUNTIME_DIR/plude/seen.json`: kiedy ostatnio byłeś w aplikacji (plakietki).
  Leży w tmpfs, bo historia powiadomień wyspy też znika z restartem.

`FileView` sam tworzy brakujące katalogi przy zapisie (zmierzone).

### Leniwe usługi Quickshella

**`DesktopEntries` i `ToplevelManager` zapełniają się dopiero po pierwszym dotknięciu.**
Zmierzone: 0 wpisów i 0 okien przy pierwszym odczycie, komplet (47 wpisów) ~2 s
później. Dwie konsekwencje:

- Każda funkcja w `Apps`, która szuka wpisu, **czyta `appCount`**. Powiązanie,
  które ją woła, przelicza się dzięki temu po dojechaniu listy. Bez tego delegaty
  utworzone przed skanem zostawały z ikoną zastępczą na zawsze (zmierzone:
  wszystkie przypięte z „!”). Samo `DesktopEntries.byId()` nie jest zależnością.
- Przypięte pokazujemy **wszystkie**, dopóki lista nie dojedzie (`Pins.visible`),
  zamiast mrugnąć pustym dockiem. Po skanie wpis odinstalowanej aplikacji znika
  z widoku, ale zostaje w `dock.json`.

Funkcje `DockService` wołane w powiązaniach delegatów (`windowsFor`,
`unseenCount`) działają, bo w środku czytają **właściwości** (`groups`, `activeKey`,
`seen.times`), a te są zależnościami.

### Okno → aplikacja

`Apps.entryForAppId`: dokładne id → małe litery → `StartupWMClass` → ostatni człon id
→ `heuristicLookup`. Wynik jest w pamięci podręcznej, czyszczonej przy zmianie
`appCount`. **Tylko po `appId`, nigdy po tytule.** Okno bez wpisu dostaje klucz
`wm:<appId>` i nie da się go przypiąć.

`appId` okna potrafi zmienić się po zmapowaniu. Zmiana właściwości elementu listy
nie przelicza powiązania z listą, więc `Instantiator` z `Connections` na każdym
oknie podbija `appIdRevision`.

### Dock: mysz

**Jedna `MouseArea` (`hitArea`) na cały dock**, a element pod kursorem wynika
z pozycji (`row.childAt`). To celowe. Qt daje hover tylko najwyższemu elementowi,
więc `MouseArea` na każdej ikonie zabierałaby hover i dock chowałby się pod
kursorem (ta sama pułapka co w wyspie, tam rozwiązana sumą trzech źródeł). Tu
pojedynczy obszar ma `containsMouse` zawsze wiarygodne. Delegaty nie obsługują
myszy, tylko rysują `hovered` i `pressed`, które ustawia dock.

Kolumna liczy się niezależnie od wysokości kursora, także w przerwie pod dockiem,
i zawsze z układu bazowego (patrz „Dock: animacje”).

### Dock: chowanie i maska

- `exclusionMode: Ignore`. Okno ma **stałą** wysokość (`headroom + dockHeight +
  bottomMargin`). Nad dockiem jest zapas na podpowiedź i skok ikony.
- Maska: schowany dock to pasek `revealHeight` (2 px logiczne = 4 fizyczne przy
  skali 2) przy krawędzi, szeroki na dock. Wysunięty dock to on sam razem
  z przerwą pod spodem, żeby zjazd kursorem ku krawędzi go nie chował.
- Szerokość jak w wyspie: wizualna (`body.width`, animowana) i zasięg
  (`reachWidth` = większa z nich). Maska i `hitArea` idą za zasięgiem.
- Dock zostaje wysunięty przy otwartym menu, w trakcie przeciągania i na pustym
  obszarze roboczym. Chowa go pełny ekran (`HyprlandWorkspace.hasFullscreen`)
  i ukrycie wyspy skrótem (`hideWithIsland`).

### Dock: model rzędu

`Repeater` stoi na `ListModel` synchronizowanym ruchami (`syncModel`: remove,
move, insert), **nie na tablicy JS**. Przy tablicy każda zmiana tworzy delegaty od
nowa: ikony mrugają, a `Behavior on x` i wskakiwanie nowej ikony (`appear`) nie mają czego animować.

Przeciąganie: rząd pokazuje podgląd (`drag.previewItems`), a ikonę niesie „duch”
w oknie docka. Miejsce wstawienia liczy się z geometrii **zamrożonej na starcie**
przeciągania (`originX` + `cellWidth`), nie z pozycji delegatów. Te animują się
w odpowiedzi na podgląd i liczenie z nich dawałoby sprzężenie zwrotne. Nieprzypiętą
aplikację przypinamy tylko po wciągnięciu w strefę przypiętych. Upuszczenie
`unpinDistance` nad dockiem odpina.

Kółko sumuje `angleDelta` do 120 (touchpad przysyła ~10 na zdarzenie, pułapka
z wyspy).

### Dock: animacje

- **Powiększanie jak w macOS** (`magnification`, `magRange`). Dwa układy rzędu:
  **bazowy** (`baseLayout`, bez powiększenia) i **powiększony** (`magLayout`, to,
  co widać). Kursor (`pointerU`), trafianie myszą (`keyAt`) i przeciąganie liczą
  się wyłącznie z bazowego. Ten nie zależy od powiększenia, więc rosnące ikony
  nie przesuwają kursora względem rzędu i nie ma sprzężenia zwrotnego.
  Powiększony rząd jest przesunięty (`shift`) tak, żeby punkt pod kursorem stał
  w miejscu. Dock rośnie w obie strony od kursora, a element pod kursorem jest ten
  sam w obu układach. Zmierzone: kursor nad 3. ikoną daje skale 1,04 / 1,38 /
  1,60 / 1,38 / 1,04, a przy lewej krawędzi dock rośnie tylko w prawo.
- **Bez `Row`.** Pozycje liczymy sami. `Row` uruchamiał przejście `move` przy
  KAŻDEJ zmianie szerokości sąsiada, czyli przy każdym ruchu myszy. Delegat
  szuka swojego miejsca po kluczu (`magLayout.keys.indexOf`), nie po `index`,
  bo `rowModel` dogania `displayItems` dopiero w `onDisplayItemsChanged`.
- `Behavior` na x/szerokości (dodanie lub zdjęcie ikony) działa tylko przy
  `magStrength === 0`. Pod kursorem powiększenie ma iść za myszą bez opóźnienia.
- Maska i `hitArea` rosną w górę o `growTop`, żeby górna część powiększonej ikony
  była dalej „w docku”. Powiększenie działa tylko nad tłem docka, nie nad całą maską.
- `sourceSize` ikon liczone pod `1 + magnification`, inaczej powiększona ikona to
  rozciągnięta mała bitmapa. Plakietki rosną razem z ikoną (są w `iconHolder`).
- **Wskakiwanie przy wysuwaniu** (`appear`): opóźnienie rośnie z odległością od
  środka rzędu (`appearStagger`), `OutBack` z overshoot 1,6.
- **Chowanie**: odwrotnie. Ikony zapadają się od krawędzi do środka
  (`hideStagger`, `InBack`, zamach w górę przed zapadnięciem), a tło (`body.open`)
  rusza `bodyHideLead` ms później: zwęża się do środka, blednie i zjeżdża
  z krótkim zamachem. Pozycja, zwężenie i przygaśnięcie tła są wyprowadzone
  z jednej wartości `open`, więc odbicie przy wysuwaniu obejmuje je naraz.
- **`appear` to zwykła wartość, nie powiązanie `shown ? 1 : 0`.** Animacja
  powiązania nie zrywa, więc po zmianie `shown` wracało ono od razu do 0
  i ikony czekające na swoją kolej znikały bez animacji (zmierzone: środkowe
  0,00 po 50 ms, skrajne 1,07). Wartość początkowa idzie w `Component.onCompleted`.
- Zapas nad dockiem (`headroom` 76) mieści powiększoną ikonę z plakietką (~28 px
  przy 54 i 0,6) i podpowiedź nad nią. Podpowiedź idzie za skalą ikony pod
  kursorem (`tooltip.follow`). Większe `magnification` → podnieś `headroom`.

### Pasek

- Pigułki mają wysokość i `topMargin` zwiniętej wyspy (34 i 8), więc stoją
  z nią w linii. Każda sięga najwyżej do `sideLimit`: środek ekranu zostaje
  na najszerszą wyspę (`islandMaxWidth` = `overlayWidth` nakładek, 620)
  plus `islandGap`. Zmienisz nakładkę w wyspie → zmień też tutaj.
- Okno ma stałą wysokość z miejscem na podpowiedź pod pigułkami. Maska to
  tylko dwie pigułki. `exclusiveZone` = 42 (okna zaczynają się pod paskiem),
  wyłączane `barReserve: false` w `settings.json`. Schowany z wyspą pasek
  oddaje miejsce, pełny ekran nie zmienia strefy (okna na innych obszarach
  przeskakiwałyby przy każdym przełączeniu).
- Tutaj MouseArea na każdej kontrolce jest w porządku: pasek się nie chowa,
  więc kradzież hovera niczego nie zwija. Podpowiedź jest jedna, w oknie
  paska; kontrolki zgłaszają najechanie przez `bar.noteHover`.
- Panele (głośność, jasność) i menu trybu energii to `PopupWindow`
  z `grabFocus`. Klik w kontrolkę dochodzi już PO zamknięciu panelu przez
  kompozytor, więc `closedAt` blokuje ponowne otwarcie tym samym klikiem.
- **Jasność**: odczyt z `/sys/class/backlight/*` co `pollMs` (sysfs nie
  zgłasza zmian), zapis przez logind `Session.SetBrightness` (bez roota,
  sprawdzone). Klawisze jasności w `hyprland.lua` idą przez IPC paska,
  bo `brightnessctl` nie jest zainstalowany.
- **Dźwięk i mikrofon** (`Audio`) to kopia `AudioService` wyspy: wiązanie
  `PwObjectTracker`, krok 3%, mikrofon = wszystkie źródła naraz. Zmiana
  głośności z paska to dla wyspy zmiana z zewnątrz, więc pokazuje ona swój pasek w pigułce.
- **Obszary robocze**: `Hyprland.dispatch("hl.dsp.focus({ workspace = N })")`,
  czyli składnia Lua jak w `hyprland.lua` (sprawdzone `hyprctl dispatch`: „ok”,
  zła składnia daje błąd Lua; Quickshell wysyła to samo `dispatch …`). Repeater stoi
  na liczbie kropek, nie na tablicy, żeby nowy obszar nie tworzył delegatów od nowa.
- Bluetooth włączany jak w wyspie: `rfkill unblock`, bo zablokowany adapter
  ignoruje `enabled = true`.

### Ikony

- **`//@ pragma IconTheme breeze-dark` w `shell.qml` jest konieczne.** Bez niego
  Quickshell widzi tylko `hicolor`. Zmierzone: `application-x-executable`,
  `network-wired`, `applications-games` → brak.
- `sourceSize` podajemy w px **logicznych**: Qt sam mnoży przez skalę ekranu
  (zmierzone: ikona 56 z dawnym ×2 dawała żądanie 224 px przy skali 2).
- `asynchronous: false`: dostawca `image://icon` nie jest wątkowo bezpieczny (wyspa).

### Launcher

- `keyboardFocus: Exclusive` tylko przy otwartym launcherze. `OnDemand` nie wystarcza
  (wyspa), a zamknięty z `Exclusive` zjadałby klawisze.
- `Escape` obsługuje `FocusScope`, bo `TextInput` go nie połyka.
  Strzałki w bok chodzą po siatce tylko przy kursorze na skraju tekstu.
- Pole jest źródłem prawdy dla swojej treści (pułapka `text:` z wyspy).
- Ranking: dokładna nazwa 1000, początek 800, początek słowa 600, zawiera 400,
  pola dodatkowe (genericName, id, comment, keywords) 250, dopasowanie rozproszone
  50–200. Premia za częstość to najwyżej 150, żeby nie wypychała trafień po nazwie.
  Częstość = liczba uruchomień z połowicznym zanikiem 14 dni. Liczą się też
  uruchomienia z docka (sygnał `Apps.launched`).

### Launcher: animacje

- Otwarcie: panel sprężyście (`reveal`, `OutBack`) ze skali 0,9 i 28 px niżej,
  ikony wlatują falą po przekątnej (`openStep` × (wiersz + kolumna), sygnał
  `cascade`). Zamknięcie: 170 ms `InCubic`, bez odbicia.
- Wyszukiwanie: bez fali, tylko przejścia GridView (`add`, `remove`, `move`,
  `displaced`). Niepasujące się kurczą, reszta przejeżdża na nowe miejsca.
- Zaznaczenie to `GridView.highlight`, które przepływa między komórkami.
  Jego przezroczystość idzie za `enter` bieżącej komórki.
- Najechanie: sprężyna na skali ikony. Uruchomienie: ikona rośnie o 70%
  i się rozpływa (`launchingId`), a launcher w tym czasie się zamyka.
- **Siatka stoi na `ListModel` synchronizowanym ruchami (`syncModel`), nie na
  tablicy wyników.** Z tablicą każda zmiana (otwarcie, litera) tworzyła
  wszystkie delegaty od nowa z synchronicznym ładowaniem ikon. Zmierzone: pętla
  zdarzeń stała ~450 ms przy pierwszym otwarciu i ~190 ms przy kolejnych, a
  animacja otwarcia w ogóle nie była widoczna. Teraz otwarcie tylko restartuje
  animacje żywych delegatów.
- **Przejścia GridView tylko przy `open`.** Przy starcie wpisy `.desktop`
  dochodzą pojedynczo (47 synchronizacji). Animacje niewidocznego okna nie idą,
  więc odtwarzały się przy pierwszym otwarciu z nieaktualnych pozycji
  (zmierzone: cała siatka przesunięta o 7 pól).
- Zostaje jednorazowe ~600 ms przy **pierwszym** pokazaniu okna w procesie
  (utworzenie grafu sceny i wgranie tekstur). Kolejne otwarcia są płynne.
- **Bez rozmycia Hyprlanda pod launcherem.** Reguła `blur` na tej warstwie
  obcinała go do 30 fps, także przy rozmyciu samego panelu (`ignore_alpha` 0,5).
  Zmierzone `FrameAnimation`: 33 ms na klatkę z rozmyciem, 16,7 ms bez.
- **Start animacji po rozgrzaniu okna** (`revealPending`). Każde pokazanie okna
  odtwarza powierzchnię: pierwsze klatki trwają ~60, potem 26–30 ms. Animacja
  rusza przy pierwszej klatce < 20 ms (najwyżej po 8). W czasie oczekiwania panel
  ma krycie **0,01, nie 0**. Przy 0 Qt go nie rysuje, więc glify i tekstury szły
  na GPU w drugiej klatce animacji (~36 ms). Po obu zmianach cała animacja
  otwarcia idzie równo po 16–17 ms.
- Pomiar płynności: `FrameAnimation { onTriggered: frames.push(frameTime) }`
  w kopii `Launcher.qml`, sonda otwiera launcher i wypisuje sekwencję. Inna
  przestrzeń nazw warstwy (np. przez zmienną środowiskową) omija reguły Hyprlanda.
- Zrzut zaraz po ponownym pokazaniu okna nie działa („item is not attached to
  a window” przez ~200 ms). Fali otwarcia nie da się złapać `grabToImage`.

### Schowek (`PluClipboard/`)

- **Dwóch obserwatorów**: `wl-paste --type text --watch` i `--type image --watch`.
  Zmierzone: `--watch` bez typu budzi polecenie tylko dla tekstu (sam obraz
  w schowku nic nie zgłasza). Wyczyszczenie schowka i zamknięcie aplikacji, która
  go trzymała, nie dają żadnego zdarzenia, więc „podtrzymywania” schowka nie ma.
- Obserwator woła `clip-store.sh` z treścią na stdin i `CLIPBOARD_STATE` w
  środowisku: `data`, `nil` (pusty schowek przy starcie) albo `sensitive`
  (`x-kde-passwordManagerHint`, czyli hasło z menedżera haseł). Zapisujemy tylko `data`.
- Skrypt zawsze czyta stdin do końca: po drugiej stronie potoku pisze aplikacja,
  z której skopiowano.
- Jedno skopiowanie = jeden wpis. `text/plain` wygrywa z obrazem (komórki
  arkusza), obraz wygrywa z samym `text/html` (obraz z przeglądarki).
- Id wpisu to skrót treści (sha256, 24 znaki): to samo skopiowane ponownie
  wraca na górę. Wynik skryptu to jedna linia na stdout, dziedziczonym po
  `wl-paste`, więc czyta ją `SplitParser` procesu obserwatora.
- Podgląd tekstu idzie w tej linii z `\n`, `\t`, `\r`, `\\` jako dwa znaki, **nie
  w base64**: `Qt.atob(string)` wypisuje ostrzeżenie o przestarzałej metodzie.
- Obserwatorzy ruszają dopiero po wczytaniu spisu (`ready`). Zdarzenie sprzed
  wczytania zapisałoby spis z jednym wpisem. Przy każdym starcie obserwator
  zgłasza bieżącą treść schowka; `ingest` pomija ją, jeśli stoi już na górze.
- Wybór wpisu: `wl-copy < plik` (obraz z `--type`), a przy `clipboardPaste`
  potem `hl.dsp.send_shortcut({ mods, key = "V", window = "address:0x…" })` do
  okna aktywnego przy otwarciu. Terminale (`terminalClasses`, po fragmencie
  klasy) dostają `CTRL SHIFT`. Zmierzone: `send_shortcut` dochodzi także do okna
  bez fokusu, ale **wklejenie działa tylko w oknie z fokusem** (Wayland daje
  schowek tylko jemu). Fokus wraca sam, bo `keyboardFocus` spada do `None`
  od razu przy `open = false`, a skrót idzie `pasteDelayMs` po `wl-copy`.
- `Hyprland.activeToplevel` i `focusedMonitor` są leniwe jak inne usługi
  (zmierzone: `null` przy pierwszym odczycie), dlatego usługi trzymają je w powiązaniach.
- Okno otwiera się na monitorze z fokusem (`ClipboardService.screen`), nie na
  monitorze docka. Reszta (reveal, fala, `ListModel` synchronizowany ruchami,
  przejścia tylko przy `open`) jak w launcherze.
- Limit (`clipboardMax`) nie obejmuje przypiętych. Pliki wpisów, które wypadły,
  kasuje `rm` od razu, a osierocone (starsze niż minuta) `sweep` przy starcie.
- Sonda: w kopii przestaw `Settings.stateDir` i `configDir`, inaczej sonda pisze
  do prawdziwej historii. Okno testowe do wklejania: `kitty --class …` na
  obszarze specjalnym (`hl.dsp.exec_cmd(cmd, { workspace = "special:x silent" })`).

### Zrzuty ekranu (`PluScreenshot/`)

- Kolejność: `hyprctl -j monitors / clients / activewindow` (jeden proces) →
  `slurp` (tylko tryb `region`) → `grim` → `wl-copy` → powiadomienie w wyspie albo `swappy`.
- **Gotowy zrzut i błąd zgłasza wyspa** (`viaIsland`: żyje i nie jest schowana):
  `notify-send` z miniaturą jako ikoną (`-i plik`), `desktop-entry` =
  `plude-screenshot-notice` i akcjami `default` / `edit` / `folder` / `delete`.
  Nadawcą jest osobny, ukryty wpis z `Exec=true`: klik w kartę w wyspie woła
  akcję domyślną i dodatkowo uruchamia wpis nadawcy, a `plude-screenshot`
  zrobiłby wtedy nowy zrzut.
  notify-send wypisuje nazwę klikniętej akcji, a skrypt oddaje ją przez
  `ipc call screenshot act <akcja> <plik>`. Proces czeka na klik najwyżej
  `actionWaitSeconds`, bo wyspa nie wygasza powiadomień z historii.
  Bez wyspy to samo pokazuje `ShotToast`, który zawsze obsługuje odliczanie.
  Przyciski akcji w wyspie wymagały poprawki po jej stronie: `removeEntry`
  robił `dismiss()` przed `invoke()` i akcja ginęła („Cannot invoke destroyed
  notification” w logu wyspy). Teraz `removeEntry(entry, true)` zostawia
  powiadomienie otwarte.
- **Tryb `region` to obszar i okno naraz**: slurp dostaje na stdin prostokąty
  widocznych okien i monitorów. Przeciągnięcie zaznacza obszar, klik bierze
  pole pod kursorem. Kolejność pól = co jest na wierzchu (obszar specjalny,
  pływające, kafelki, monitor).
- Kolory slurpa liczone z `Theme` (`hex`): tło jak przyciemnienie launchera,
  zaznaczenie `00000000` (slurp rysuje je operatorem źródła, więc wycina dziurę
  w przyciemnieniu).
- Warstwa slurpa ma przestrzeń nazw `selection`. Reguła `no_anim` w
  `hyprland.lua`, żeby zanikająca ramka nie łapała się na zrzut.
- `grim -l 1`. Zmierzone na ekranie 4K: poziom 6 (domyślny) 2,2 s, poziom 1
  0,76 s i plik większy o 26%, poziom 0 0,18 s i 25 MB.
- Kody wyjścia skryptu zrzutu: 10 = anulowane w slurpie, 127 = brak narzędzia
  (nazwa na stdout), reszta = błąd grima.
- **swappy z `-o`**: wynik zapisuje się przy zamknięciu okna (zmierzone, także
  przy zamknięciu przez kompozytor) i wraca do schowka. Dla zrzutu to ten sam
  plik, dla obrazu z historii schowka nowy plik w katalogu zrzutów. Przez
  `execDetached`: edytor ma przeżyć przeładowanie powłoki.
  `~/.config/swappy/config`: katalog przycisku „Zapisz”, czcionka, kolor akcentu.
- Podgląd (`ShotToast`) chowa się przed następnym zrzutem (`starting`) i wtedy
  zrzut czeka `settleMs`. Najechanie liczone z karty, miniatury i przycisków
  osobno (kradzież hovera). Kliknięcia w podglądzie i w akcje powiadomienia
  musi potwierdzić użytkownik.
- Wpisy launchera mają `sleep 0.3` w `Exec`: launcher zamyka się 170 ms.
- Sonda: narzędzia można rozpakować z paczek do katalogu roboczego
  (`pacman -Sp grim` → `curl` → `bsdtar`) i dodać do `PATH` sondy.

### Menu (`PopupMenu`)

`PopupWindow` z `grabFocus: true` (klik obok zamyka), a nie element w oknie docka.
Menu z wieloma oknami jest wyższe niż zapas nad dockiem. W `onClicked` najpierw
zamknięcie, potem akcja: akcja potrafi zmienić `entries` i Repeater zniszczyłby
delegat w trakcie jego własnego handlera (pułapka z historii wyspy).

### Uruchamianie

`Apps.launch`: `DesktopEntry.execute()`, a dla `Terminal=true` terminal
z ustawień + `-e`, przez `execDetached` z katalogiem roboczym (sprawdzone:
kontekst z `workingDirectory` działa). Aplikacje nie są dziećmi powłoki
i przeżywają jej przeładowanie.

### Okno ustawień

- `FloatingWindow` (xdg toplevel) w `LazyLoader` powiązanym z `SettingsApp.shown`.
  Zamknięcie przez kompozytor (SUPER+C) daje `visible = false` (zmierzone), a wtedy
  okno się rozładowuje.
- Klasa okna to zawsze `org.quickshell` (`FloatingWindow` nie ma `appId`). Dlatego:
  - reguła `plude-settings` w `hyprland.lua` (pływa, 780×560, środek) łapie
    okno po **tytule** (`SettingsApp.windowTitle`);
  - `~/.local/share/applications/org.quickshell.desktop` nadpisuje ukryty wpis
    systemowy. Dock pokazuje okno jako „Ustawienia PluDE”, launcher ma wpis.
    `Exec` z `~` wewnątrz `sh -c "…"`, bo `$` w cudzysłowie to błąd składni
    `.desktop` (ostrzeżenie `quickshell.desktopentry`).
- Fokus na już otwarte okno: `hl.dsp.focus({ window = "title:…" })` **bez**
  `^…$`. Z kotwicami dispatch odpowiada „ok”, ale fokus nie przechodzi (zmierzone).
- Lista wyboru (`SettingsChoice`) rozwija **wspólny `ChoiceMenu` rysowany
  w oknie** (`SettingsApp.menu`), a nie `Common/PopupMenu`. Popup z `grabFocus`
  w zwykłym oknie (xdg toplevel) nie łapał kliknięć (zgłoszone przez
  użytkownika): klik obok nie zamykał listy, a druga lista otwarta przy
  wiszącej pierwszej lądowała w rogu ekranu. `ChoiceMenu` zamyka się przy
  kliknięciu obok i przepuszcza je dalej (klik w inną listę otwiera ją od razu,
  klik we własne pole tylko zamyka). Zamyka się też przy przewinięciu strony
  i zmianie rozmiaru okna. Strzałki, Enter, Esc (Esc zamyka listę, nie okno).
- Tryby monitora to tylko to, co zgłasza EDID. Matryca laptopa (Sharp 4K) ma
  jeden tryb, jądro też widzi tylko `3840x2160` (`/sys/class/drm/card1-eDP-1/modes`).
- Pole (`SettingsField`) zapisuje przy Enterze lub wyjściu z pola, Esc cofa
  zmianę. `value` wchodzi do pola tylko bez fokusu (pułapka `text:`).
- Zrzut: `ld.item.contentItem.children[0]` (FocusScope). W oknie jest osobny
  prostokąt tła, bo bez niego zrzut wychodzi przezroczysty. W sondzie przestaw
  `Settings.configDir` na katalog roboczy, żeby `set` nie pisał prawdziwego pliku.

### Monitory (`PluSettings/MonitorService`)

Strona „Monitory” edytuje **szkic** (`MonitorDraft`, bez interfejsu, więc sonda
sprawdza go bez klikania). Do Hyprlanda idzie on dopiero po „Zastosuj”, a potem
`MonitorConfirm` (nakładka na całe okno, nie na stronę) czeka na Enter lub Esc.

- **`apply` wysyła cały układ, nie tylko zmienione monitory.** Monitor bez
  własnej reguły ma z `hyprland.lua` pozycję `auto`, a Hyprland stawia takie na
  prawo od monitorów z jawną pozycją. Zmierzone: reguła tylko dla atrapy
  przestawiła eDP-1 z (0,0) na (3840,0).
- Układ jest normalizowany do (0,0) dopiero przy `apply` (automat ekranu
  docka szuka (0,0)). `dirty` porównuje surowy szkic, żeby układ Hyprlanda
  niezaczynający się w (0,0) nie wyglądał na zmieniony.
- Zmiana rozmiaru logicznego (tryb, skala, obrót) przesuwa sąsiadów na
  prawo i poniżej o różnicę. Przyciąganie krawędzi (`moveTo`) liczy
  `snapPx` ekranu przeliczone na px logiczne.
- `MonitorCanvas`: `Repeater` na **liczbie** monitorów (tablica szkicu
  zmienia się przy każdym ruchu myszy i odtwarzałaby delegaty w trakcie
  przeciągania). Widok (`fit`) zamrożony na czas przeciągania.
- Odświeżanie w szkicu dociągnięte do listy trybów (Hyprland podaje 59.997,
  lista 60.00), skala do 1/120. Inaczej listy wyboru nie znajdą bieżącej wartości.
- Reguły z `eval` zostają w Hyprlandzie do `hyprctl reload`, także dla atrap
  po ich usunięciu. Atrapa podłączona ponownie wraca z ostatnią regułą.

- Odczyt: `hyprctl monitors all -j` (z wyłączonymi i `availableModes`),
  odświeżany po zdarzeniach `monitoradded*`, `monitorremoved*`, `configreloaded`.
- Zmiana na żywo: `hyprctl eval 'hl.monitor({ … })'`, bez przeładowania.
  hyprctl kończy się kodem 0 także przy błędzie Lua, więc o wyniku mówi treść:
  „ok” albo „error: …”. `eval 'error(x)'` to sposób na odczyt wartości z Lua.
- Po zmianie `confirmSeconds` na potwierdzenie, potem cofnięcie. Do tego
  strażnik poza procesem (`sh` przez `execDetached` + znacznik
  w `$XDG_RUNTIME_DIR/plude/`), bo przeładowanie powłoki w trakcie
  oczekiwania zostawiłoby niepotwierdzoną zmianę na zawsze. Zmierzone: po
  wyjściu sondy strażnik przywrócił ostatni zatwierdzony stan.
- Zapis: przy potwierdzeniu cały podłączony układ (pozycje zależą od siebie)
  trafia do `monitors.json`, a z niego do `plude-monitors.lua`. `hyprland.lua`
  dołącza ten plik przez `dofile` na końcu sekcji MONITORS. Nie `require`, bo stan
  Lua trwa między wywołaniami `eval` (zmierzone) i `require` zwróciłby moduł z pamięci.
- Reguły po opisie (`output = "desc:…"`, działa), nazwa portu tylko przy
  pustym opisie. Reguła ustawiona przed podłączeniem monitora działa po nim.
- Pułapki (zmierzone): reguła bez `disabled = false` NIE włącza wyłączonego
  monitora (zawsze komplet pól). Złą skalę Hyprland po cichu poprawia, a
  `validScales` (k/120, rozmiar logiczny w całych pikselach) zgadza się z nim
  w 8/8 przypadków. Klon wyłącza `mirror = ""`, a `mirrorOf` w JSON-ie to id.
- Sondy na atrapach: `hyprctl output create headless NAZWA` / `output remove
  NAZWA` (atrapa ma pusty opis). W kopii projektu przestaw `hyprDir`
  i ścieżkę `monitors.json`, żeby nie nadpisać prawdziwych plików.
- Singleton powstaje przy pierwszym dotknięciu, `ready` mówi, że doszedł
  pierwszy odczyt.

### Hyprland w Lua

- Skróty globalne: `hl.dsp.global("quickshell:launcherToggle")`, tak samo
  `clipboardToggle`, `screenshotRegion`, `screenshotScreen`, `screenshotWindow`. Sprawdzone przez
  `hyprctl dispatch 'hl.dsp.global("…")'`: warstwa `plude-launcher` się pojawia.
- Reguła warstwy: `hl.layer_rule({ name, match = { namespace = "^…$" }, … })`.
- `Hyprland.usingLua` = true. Stuby API: `/usr/share/hypr/stubs/hl.meta.lua`.

## Styl

Jak w wyspie: kod i komentarze po polsku, nazwy właściwości po angielsku.
Komentarze tłumaczą „dlaczego”. Ustawienia jako nazwane właściwości na górze pliku.
Wartości wyprowadzamy, zamiast je powielać. Cztery spacje, sekcje oddzielone
blokiem myślników. Kolory i czasy animacji w `Common/Theme` są przepisane z wyspy:
zmiana tutaj wymaga zmiany tam.

Wygląd i ruch całego PluDE (paleta, krzywe, wzorce, pułapki GTK i hyprlocka
przy przenoszeniu stylu poza QML): `DESIGN.md`.
