# Styl PluDE

Jak odtworzyć wygląd i ruch PluDE w nowym elemencie (Quickshell, GTK,
hyprlock czy cokolwiek innego). Źródłem prawdy dla liczb jest
`Common/Theme.qml`, przepisany z wyspy (`~/PluDynamicIsland`). Zmieniasz
wartość tam → zmień ją w wyspie i w konfiguracjach wymienionych na końcu.

## Charakter

- **Ciemno, płasko, spokojnie.** Prawie czarne tła, jeden niebieski akcent,
  reszta szarości. Kolor tylko tam, gdzie coś znaczy (stan, akcja, skrót).
- **Sprężystość zamiast efekciarstwa.** Rzeczy wskakują z lekkim
  przestrzałem i opadają. Ruch ma być wyraźny, ale krótki (do ~0,5 s).
- **Nie „premium”.** Bez szklanych kart, wielkich cieni, cienkich
  eleganckich krojów i napuszonych podpisów. Na ekranie blokady po
  przeróbce najlepiej wypadł monospace, małe litery i sama treść bez karty.
- **Pełne kolory, bez alfy na elementach.** Półprzezroczyste podświetlenia
  prześwitują tłem i wyglądają tanio. Odcień akcentu to akcent zmieszany
  z tłem pod spodem, policzony do pełnego koloru (tabela niżej).
  Alfa zostaje tylko w przyciemnieniu ekranu i w obrysach.
- **Każdy element sam się tłumaczy.** Skróty klawiszowe widoczne przy
  przyciskach, krótka podpowiedź „enter … · esc …” na dole ekranów pełnych.

## Kolory

| Token           | Wartość                  | Użycie                                   |
|-----------------|--------------------------|------------------------------------------|
| `surface`       | `#0a0a0c`                | tło paneli (dock, launcher, tarcza)      |
| `surfaceRaised` | `#17171a`                | przyciski, pola, komórki na panelu       |
| `border`        | `rgba(255,255,255,0.08)` | obrys paneli, 1 px                       |
| `hover`         | `rgba(255,255,255,0.08)` | podświetlenie w QML                      |
| `hoverStrong`   | `rgba(255,255,255,0.16)` | wciśnięcie w QML                         |
| `text`          | `#f2f2f2`                | tekst główny                             |
| `textDim`       | `#9a9aa2`                | podpisy, daty                            |
| `textFaint`     | `#6a6a72`                | podpowiedzi, placeholdery                |
| `accent`        | `#5b8cff`                | zaznaczenie, fokus, pojedyncze znaki     |
| `danger`        | `#e5484d`                | wyłączenie, błąd, złe hasło              |
| `warning`       | `#f0b232`                | restart, Caps Lock, klawisz esc          |
| `success`       | `#38d47a`                | status „jest / działa” (kropka)          |
| `discord`       | `#5865f2`                | tylko rzeczy od Discorda                 |

Przyciemnienie ekranu pod pełnoekranowym elementem: **czarny 0.45**
(w hyprlocku `brightness = 0.55`).

Obramowanie aktywnego okna Hyprlanda (`hyprland.lua`, `col.active_border`):
gradient `rgb(100,0,180)` → `rgb(0,50,180)`, 22°. Używane też jako obwódka
pola hasła w hyprlocku.

### Pełne odcienie (akcent zmieszany z `surfaceRaised`)

Tam, gdzie nie ma alfy (GTK/CSS, hyprlock), zamiast `rgba(accent, x)`:

| Co                        | Kolor     |
|---------------------------|-----------|
| obrys na `surfaceRaised`  | `#2a2a2c` |
| obrys fokusu              | `#4f4f51` |
| obrys na `surface`        | `#1c1c1f` |
| accent 20% (najechanie)   | `#252e48` |
| accent 34% (wciśnięcie)   | `#2e3f68` |
| warning 20% / 34%         | `#42361f` / `#614c22` |
| danger 22% / 36%          | `#442225` / `#61292c` |

Wzór: `kanał = tło + (kolor − tło) × procent`.

## Kształt i typografia

- Zaokrąglenia: panel launchera **30**, dock **26**, pigułki paska i zwinięta
  wyspa **pełne** (wysokość 34), komórka launchera
  **18**, menu **16**, wiersz menu **10**, podpowiedź **13**. Okna Hyprlanda
  **10**. Okrągłe przyciski to pełne koła.
- Obrys 1 px, `border`. Cieni praktycznie brak.
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

- **Panel pełnoekranowy** (launcher, koło wylogowania): przyciemniony
  ekran 0.45, panel `surface` z obrysem `border` na środku, klik obok
  zamyka, Esc zamyka, drugie wciśnięcie skrótu zamyka.
- **Przycisk / komórka**: `surfaceRaised`, obrys `border`, podpis `textDim`
  pod ikoną. Najechanie: odcień akcentu + obrys w pełnym akcencie + tekst
  `text` + ikona rośnie. Akcje nieodwracalne: restart w `warning`,
  wyłączenie w `danger`.
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

- Rozmiary, czcionki i pozycje są w **pikselach fizycznych**: przy skali
  2 wszystko ×2 względem wartości logicznych.
- `#` w wartościach pisze się `##` (np. kolory w znacznikach Pango).
- Locale systemu to `C.UTF-8` (brak `pl_PL`): polską datę daje
  `plude-lock-date.sh`.
- Wbudowanego `$TIME` nie da się pokolorować częściowo; zegar to `cmd`
  z `date` i znacznikami `<span>`.

## Gdzie te wartości są przepisane

Zmieniasz paletę lub czasy → popraw też:

- `~/PluDynamicIsland` (wyspa, źródło oryginałów),
- `~/PluDE/Common/Theme.qml`,
- `~/.config/wlogout/style.css`, `wheel.svg`, `icons/*.svg`,
- `~/.config/hypr/hyprlock.conf`,
- `~/.config/hypr/hyprland.lua` (obramowanie okien, reguły warstw).
