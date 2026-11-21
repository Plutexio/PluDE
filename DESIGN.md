# Styl PluDE

Jak odtworzyć wygląd i ruch PluDE w nowym elemencie (Quickshell, GTK,
hyprlock czy cokolwiek innego). Źródłem prawdy dla liczb jest
`Common/Theme.qml`, a dla kolorów paleta z tapety (`Common/Wallpaper.qml`).
Hyprland, hyprlock i wlogout dostają ją same (`Common/PaletteExport.qml`).
Wyspa (`~/PluDynamicIsland`) na razie zostaje przy stałych kolorach.

## Charakter

- **Ciemno, ale w kolorach tapety.** Paleta idzie z tapety (skwd-wall +
  matugen, `Common/Wallpaper.qml`): akcent, drugi akcent i tła z jej
  odcieniem. Zmiana tapety przemalowuje wszystko płynnie (`paletteMs`).
  Bez palety zostaje dawny niebieski.
- **Żywe, ale z sensem.** Ikony reagują na zmianę stanu, skąd by nie
  przyszła (podskok przy włączeniu, kręcenie głową przy wyłączeniu, fale
  przy głośności), klik puszcza falę, panele wyrastają z kontrolki.
  Ciągłe animacje tylko tam, gdzie coś trwa (ładowanie, łączenie, niski
  poziom baterii), nigdy „dla ozdoby” w tle.
- **Sprężystość.** Rzeczy wskakują z przestrzałem i opadają. Ruch wyraźny,
  ale krótki (do ~0,5 s).
- **Poświata zamiast szkła.** Gradient akcent → drugi akcent na rzeczach
  wybranych i aktywnych, miękkie cienie i poświaty (`SoftGlow`). Bez
  rozmycia Hyprlanda pod pełnoekranowymi warstwami (30 fps na 4K).
- **Pełne kolory na elementach.** Odcienie to kolor zmieszany z tłem pod
  spodem (`Theme.mix`), nie alfa: półprzezroczyste prześwitują i wyglądają
  tanio. Alfa zostaje w przyciemnieniu, obrysach i poświatach.
- **Każdy element sam się tłumaczy.** Skróty klawiszowe widoczne przy
  przyciskach, krótka podpowiedź „enter … · esc …” na dole ekranów pełnych.

## Kolory

### Z tapety (`palette.json`, tokeny `Theme`)

Matugen `scheme-vibrant`, tryb ciemny. Tony z palet Material (0–100,
jasność w HCT), nie role: role dawały pastelowy akcent.

| Token           | Skąd                                   | Użycie                                  |
|-----------------|----------------------------------------|-----------------------------------------|
| `surface`       | `surface_container_lowest`             | tło paneli, pigułek, docka              |
| `surfaceRaised` | `surface_container_low`                | przyciski, pola, komórki                |
| `surfacePressed`| `surface_container_high`               | wciśnięcie na `surfaceRaised`           |
| `text`          | `on_surface`                           | tekst główny                            |
| `textDim`       | neutral_variant 60                     | podpisy                                 |
| `textFaint`     | neutral_variant 50                     | podpowiedzi, placeholdery               |
| `accent`        | primary 70                             | zaznaczenie, fokus, wypełnienia         |
| `accentBright`  | primary 80                             | tekst i ikona w akcencie, środek poświaty |
| `accentDeep`    | primary 30                             | ciemne wypełnienie                      |
| `accentInk`     | primary 10                             | tekst na pełnym akcencie                |
| `accent2`       | primary 70 z `matugen color`, źródło obrócone o 36° | drugi koniec gradientów      |
| `border`        | `text` 8%                              | obrys 1 px                              |

Drugi akcent to nie tertiary matugena (w `scheme-vibrant` bywa prawie
szary) ani obrót w HSL (nie trzyma jasności: pomarańcz → jaskrawa
limonka). Ciepłe odcienie obracamy ku różowi, resztę ku fioletowi, bo od
pomarańczu naprzód wychodziła oliwka.

`Theme.inkOn(kolor)`: tekst na pełnym kolorze (ciemny odcień na jasnym,
biały na ciemnym). Akcent z palety jest jasny, biały tekst na nim ginie.

### Stałe

| Token      | Wartość   | Użycie                                   |
|------------|-----------|------------------------------------------|
| `danger`   | `#e5484d` | wyłączenie, błąd, zasilanie w pasku      |
| `warning`  | `#f0b232` | restart, Caps Lock, jasność w pasku      |
| `success`  | `#38d47a` | status „jest / działa”, ładowanie        |
| `discord`  | `#5865f2` | tylko rzeczy od Discorda                 |

Bez palety (`base*` w `Theme`): tła `#0a0a0c` / `#17171a`, tekst
`#f2f2f2`, akcent `#5b8cff`, drugi `#a46bff`. To samo dostają hyprlock
i wlogout, dopóki PluDE nie policzy palety.

Przyciemnienie pod pełnoekranowym elementem: **czarny 0.45**, a za
panelem „zorza” (`AuroraDim`): plama akcentu u góry z lewej, drugiego
akcentu u dołu z prawej.

Obramowanie aktywnego okna Hyprlanda: gradient `accent` → `accent2`,
22° (`plude-colors.lua`). To samo jest obwódką pola hasła w hyprlocku.

### Pełne odcienie

`Theme.mix(tło, kolor, t)` = `tło + (kolor − tło) × t`. Typowe:
najechanie 0,1–0,13, otwarty panel / zaznaczone 0,2–0,22, wciśnięcie
0,3. W GTK (wlogout) te same odcienie liczy `PaletteExport`
(`accentSoft` 20%, `accentSoftStrong` 34%, `warningSoft`, `dangerSoft`).

## Kształt i typografia

- Zaokrąglenia: panel launchera **30**, dock **26**, pigułki paska i zwinięta
  wyspa **pełne** (wysokość 34), komórka launchera
  **18**, menu **16**, wiersz menu **10**, podpowiedź **13**. Okna Hyprlanda
  **10**. Okrągłe przyciski to pełne koła.
- Obrys 1 px, `border`; na panelach i pigułkach lekko zabarwiony akcentem
  (`mix(border, accent, 0.25)`), na dużych panelach w gradiencie
  `accent → border → accent2` (`PanelFrame`). Miękki cień pod pigułkami
  i panelami (`SoftGlow`).
- Krój: domyślny bezszeryfowy (Noto Sans) w QML. Rozmiary: 16 pole
  wyszukiwania, 13 menu, 12 podpisy i podpowiedzi, 11 nagłówki menu,
  10 plakietki (pogrubione).
- Ekrany „systemowe” (blokada) mogą iść w monospace: `Adwaita Mono`.
  JetBrains Mono / Fira Code nie są zainstalowane.
- Teksty w interfejsie po polsku, krótko. Na ekranach systemowych małymi
  literami („hasło”, „złe hasło (2)”).
- Ikony: `breeze-dark`. Własne ikony liniowe: viewBox 24, obrys 1.8,
  zaokrąglone końce, kolor `text`.

## Ruch

| Co                          | Czas    | Krzywa                              |
|-----------------------------|---------|-------------------------------------|
| sprężyna wyspy (domyślna)   | 520 ms  | OutBack, overshoot 0.9              |
| otwarcie panelu (launcher)  | 440 ms  | OutBack 1.1, skala 0.9→1, 28 px w górę |
| zamknięcie panelu           | 170 ms  | InCubic, bez odbicia                |
| pojawienie ikony (dock)     | 460 ms  | OutBack 1.6, co 45 ms od środka     |
| zapadnięcie ikony (dock)    | 240 ms  | InBack 2.2, co 28 ms od krawędzi    |
| wysunięcie tła docka        | 420 ms  | OutBack 0.8                         |
| najechanie / drobne zmiany  | 140 ms  | liniowo lub OutQuad (`quickMs`)     |
| zanikanie                   | 180 ms  | (`fadeMs`)                          |
| filtrowanie siatki          | 260 ms  | OutBack (wejście), OutCubic (przesunięcia) |
| przejście palety            | 900 ms  | `ColorAnimation` na tokenach Theme  |
| panel z kontrolki (pasek)   | 520 ms  | OutBack 1.25, najpierw na boki, potem w dół (`GrowBody`) |
| fala po kliknięciu          | 560 ms  | OutCubic, zanik od połowy (`Ripple`) |
| wciśnięcie kontrolki        | 90 / 460 ms | OutQuad w dół, OutBack 3.2 przy puszczeniu |
| podskok (`kick`)            | 110 + 520 ms | do 1,32, potem OutBack 3      |
| kręcenie głową (`shake`)    | ~350 ms | −3,5 / 3 / −2 / 1 / 0 px            |
| znacznik obszaru roboczego  | 220 / 420 ms | przód OutCubic, tył po 60 ms OutBack 1.6 |

Zasady:

- **Wejście sprężyste, wyjście krótkie.** Otwarcie z odbiciem, zamknięcie
  szybkie i bez odbicia: kiedy już wiadomo, co zrobić, ma zniknąć.
- **Fala.** Wiele elementów nie wchodzi naraz: opóźnienie rośnie z
  odległością (od środka rzędu, po przekątnej siatki, po obwodzie koła).
- **Tło rusza razem z treścią**, przyciemnienie idzie za postępem panelu
  (przycięte do 1, żeby przestrzał nie przyciemniał mocniej).
- **Wszystko z jednej wartości.** Pozycja, skala i krycie panelu liczone
  z jednego `reveal` / `open`, żeby odbicie obejmowało je naraz.
- Przybliżenia krzywych poza Qt:
  - OutBack ~1.6 → `cubic-bezier(0.18, 0.89, 0.32, 1.28)` (Hyprland, hyprlock),
  - miękkie wyhamowanie → `cubic-bezier(0.25, 1, 0.5, 1)`.
- Animacje Hyprlanda na warstwach PluDE są wyłączone (`no_anim`), bo
  elementy animują się same. Wyjątek: wlogout, który nie ma animacji
  zamknięcia, dostaje `animation = fade`.
- **Bez rozmycia Hyprlanda pod pełnoekranowymi warstwami.** Na 4K obcina
  do 30 fps (zmierzone przy launcherze).

## Wzorce elementów

- **Panel pełnoekranowy** (launcher, schowek, koło wylogowania): przyciemniony
  ekran 0.45 z zorzą (`AuroraDim`), panel `PanelFrame` (poświata akcentu,
  obrys gradientem) na środku, klik obok zamyka, Esc zamyka, drugie
  wciśnięcie skrótu zamyka.
- **Zaznaczenie** w siatce i liście: `Selection`, gradient
  `mix(surface, accent)` → `mix(surface, accent2)`, obrys `accentBright`
  45%, poświata. Najechanie: `mix(surface, accent, 0.1)`.
- **Kontrolka paska**: najechanie i otwarty panel to odcień `tint` (akcent;
  jasność `warning`, zasilanie `danger`), ikona w `tintBright`. Klik puszcza
  falę po pigułce. Zmiana stanu z dowolnego źródła: `kick()` przy
  włączeniu, `shake()` przy wyłączeniu. Panel kontrolki wyrasta spod niej
  (`GrowBody`).
- **Ikony, które coś robią**: głośnik puszcza łuki (na zewnątrz głośniej,
  do środka ciszej), słońce obraca się z jasnością, kreski Wi-Fi zapalają
  się po kolei przy łączeniu, przez baterię przy ładowaniu przelatuje
  błysk, przy niskim poziomie wypełnienie pulsuje.
- **Przycisk / komórka**: `surfaceRaised`, obrys `border`, podpis `textDim`
  pod ikoną. Najechanie: odcień akcentu + obrys w pełnym akcencie + tekst
  `text` + ikona rośnie. Akcje nieodwracalne: restart w `warning`,
  wyłączenie w `danger`.
- **Podgląd w rogu** (zrzut ekranu): karta `surface` 20, wjeżdża sprężyną
  z prawej, znika sama po 6 s, najechanie ją zatrzymuje. Okrągłe przyciski
  akcji, usuwanie w `danger`.
- **Skróty** jako małe plakietki (zaokrąglone 6, `surfaceRaised`, litera
  pogrubiona w `text`) przy elemencie, którego dotyczą.
- **Pola tekstowe**: `surfaceRaised`, placeholder w `textFaint`, stan
  w obwódce: akcent przy sprawdzaniu, `danger` przy błędzie, `warning`
  przy Caps Locku.
- **Kolor w tekście** oszczędnie, pojedyncze znaki: dwukropek zegara
  w akcencie, zielona kropka przed użytkownikiem, nazwy klawiszy
  w podpowiedzi (`enter` akcent, `esc` warning).

## Poza QML: pułapki

### wlogout (GTK3 CSS), `~/.config/wlogout`

- Przyciski idą do siatki **kolumnami**, nie wierszami (kod wlogout).
  Siatka nie jest homogeniczna: równe `min-width`, inaczej podpisy
  rozpychają kolumny.
- Własne pozycje tylko marginesami; skrypt `plude-wlogout` przycina siatkę
  do stałego rozmiaru na środku, dopiero wtedy marginesy w px mają sens.
- **Żadnych `cubic-bezier` z y > 1.** GTK3 liczy z nich ujemny rozmiar
  (Gtk-CRITICAL „specified_width >= 0”), a cairo przerywa proces.
  Odbicie robi się klatkami: przestrzał w ~55–65%, powrót, dobicie.
- `background-size: 0` też zabija proces; minimum 1 px.
- GTK3 wczytuje SVG w rozmiarze z pliku: przy skali 2 obraz musi mieć
  dwukrotność rozmiaru, w jakim jest rysowany, inaczej tekst jest
  pikselowaty.

### hyprlock, `~/.config/hypr/hyprlock.conf`

- hyprlock nie mnoży przez skalę monitora: rozmiary, czcionki i pozycje są
  w **pikselach fizycznych**. Dlatego widżety są w szablonie
  `hyprlock-widgets.conf` w px **logicznych** (`{{ N * $s }}`, `$mon`),
  a `plude-lock.sh` przy każdej blokadzie przepisuje go raz na monitor
  (nazwa, skala, zaokrąglenie) do `plude-lock-monitors.conf`, który
  dołącza `hyprlock.conf`. Blokować zawsze przez skrypt (hypridle,
  SUPER+L, wlogout). Zaokrągla skrypt, bo hyprlang przy skali 1,5 daje
  `112.5` i hyprlock taki rozmiar odrzuca.
- Podgląd bez blokowania ekranu: zagnieżdżony `Hyprland -c <lua>` na
  obszarze specjalnym, atrapy `hyprctl -i 1 output create headless`,
  potem `WAYLAND_DISPLAY=wayland-2 hyprlock -c …` i `grim -o`.
- `#` w wartościach pisze się `##` (np. kolory w znacznikach Pango).
- Locale systemu to `C.UTF-8` (brak `pl_PL`): polską datę daje
  `plude-lock-date.sh`.
- Wbudowanego `$TIME` nie da się pokolorować częściowo; zegar to `cmd`
  z `date` i znacznikami `<span>`.

## Gdzie idzie paleta

Pisze PluDE (`PaletteExport`) przy każdej nowej palecie i przy starcie:

- `~/.config/hypr/plude-colors.lua`: ramki okien (dofile w `hyprland.lua`
  po bloku `general`; na żywo `hyprctl eval`),
- `~/.config/hypr/plude-lock-colors.conf`: zmienne hyprlocka i `$nazwaHex`
  dla `{{#nazwa}}` w `hyprlock-widgets.conf` (wkleja `plude-lock.sh`),
- `~/.config/wlogout/plude-colors.css` (`@define-color`, `@import`
  w `style.css`) i `wheel-plude.svg` (z szablonu `wheel.svg`).

Ręcznie, przy zmianie stałych kolorów albo czasów:

- `~/PluDynamicIsland` (wyspa),
- `~/.config/wlogout/icons/*.svg` (obrys `#f2f2f2`),
- `~/.config/swappy/config` (`custom_color` to dawny akcent, czcionka),
- `~/.config/hypr/hyprland.lua` (reguły warstw, gradient domyślny bez PluDE).
