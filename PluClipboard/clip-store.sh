#!/bin/sh
# Jeden wpis historii schowka. Woła to `wl-paste --watch` (ClipboardService)
# przy każdej zmianie schowka, a treść przychodzi na stdin.
#
#   clip-store.sh <text|image> <katalog> <limit bajtów> <bajty podglądu>
#
# Wynik to jedna linia na stdout (dziedziczony po wl-paste, czyta go QML):
#   rodzaj TAB id TAB plik TAB rozmiar TAB opis TAB typ MIME TAB podgląd
# Podgląd to początek tekstu z \n, \t, \r i \\ zapisanymi jako dwa znaki,
# żeby cały wpis mieścił się w jednej linii.
#
# Skrypt, a nie QML: treść schowka bywa binarna i duża, a QML nie ma jak
# policzyć z niej skrótu ani zapisać jej do pliku.
kind=$1
dir=$2
max=$3
peek=$4

# Stdin czytamy do końca także wtedy, gdy wpis pomijamy: po drugiej stronie
# potoku pisze aplikacja, z której skopiowano, i urwany potok to dla niej SIGPIPE.
skip() {
    cat > /dev/null
    exit 0
}

# nil: pusty schowek przy starcie. sensitive: menedżer haseł oznaczył treść
# (x-kde-passwordManagerHint) i do historii ona nie trafia.
[ "$CLIPBOARD_STATE" = data ] || skip

# Jedno skopiowanie = jeden wpis. Obraz z przeglądarki przychodzi razem
# z text/html, komórki arkusza razem z obrazkiem: text/plain wygrywa
# z obrazem, obraz wygrywa z samym HTML-em.
types=$(wl-paste --list-types 2> /dev/null)
has() { printf '%s\n' "$types" | grep -q "^$1"; }
case $kind in
    text) has text/plain || { has image/ && skip; } ;;
    image) has text/plain && skip ;;
    *) skip ;;
esac

mkdir -p "$dir" && chmod 700 "$dir" || skip
tmp=$(mktemp "$dir/.in.XXXXXX") || skip
trap 'rm -f "$tmp"' EXIT

# O jeden bajt ponad limit: tak widać, że treść była za duża.
head -c "$((max + 1))" > "$tmp"
cat > /dev/null
size=$(stat -c %s "$tmp")
[ "$size" -gt 0 ] && [ "$size" -le "$max" ] || exit 0

if [ "$kind" = image ]; then
    mime=$(file -b --mime-type "$tmp")
    case $mime in
        image/*) ;;
        *) exit 0 ;;
    esac
    ext=$(printf '%s' "${mime#image/}" | tr -c 'a-z0-9' '-')
    # "PNG image data, 800 x 600, …", ale w JPEG-u najpierw stoi gęstość
    # ("density 72x72"), a wymiary są ostatnie.
    info=$(file -b "$tmp" | grep -oE '[0-9]+ ?x ?[0-9]+' | tail -n 1 | tr -d ' ')
    preview=
else
    # Same spacje i puste linie to nie wpis.
    grep -q '[^[:space:]]' "$tmp" || exit 0
    mime=text/plain
    ext=txt
    info=$(grep -c '' "$tmp")
    # iconv -c wyrzuca znak ucięty w połowie przez head.
    preview=$(head -c "$peek" "$tmp" | iconv -c -f UTF-8 -t UTF-8 2> /dev/null | tr -d '\000' \
        | awk 'BEGIN { ORS = "\\n" } { gsub(/\\/, "\\\\\\\\"); gsub(/\t/, "\\t"); gsub(/\r/, "\\r"); print }')
fi

# Id to skrót treści: to samo skopiowane drugi raz wraca na górę listy,
# zamiast się dublować.
id=$(sha256sum < "$tmp" | cut -c 1-24)
mv -f "$tmp" "$dir/$id.$ext" || exit 0
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$kind" "$id" "$id.$ext" "$size" "$info" "$mime" "$preview"
