import QtQuick
import qs.Common

// ---------------------------------------------------------------
// Rozwinięta lista wyboru (SettingsChoice). Jedna na całe okno ustawień,
// rysowana w oknie, a nie jako osobny popup.
//
// Dlaczego nie PopupMenu z Common (jak w pasku): w zwykłym oknie aplikacji
// grabFocus popupu nie działał — klik obok nie zamykał listy, a otwarcie
// drugiej przy wiszącej pierwszej dawało popup w rogu ekranu (Hyprland nie
// umiał go zakotwiczyć). Tutaj jest zawsze jedna lista, a klik obok ją
// zamyka i od razu idzie dalej, więc klik w inną listę otwiera ją od razu.
// ---------------------------------------------------------------
FocusScope {
    id: menu

    property int rowHeight: 30
    property int padding: 4
    property int maxVisible: 9
    // Odstęp od pola i od krawędzi okna.
    property int gap: 4
    property int edgeMargin: 12

    // Kto otworzył listę (SettingsChoice) i jej wpisy: [{ value, label }].
    property Item owner: null
    property var entries: []
    property var value: null
    property int highlighted: -1
    readonly property bool open: owner !== null

    // Pozycja listy w tym elemencie, liczona raz, przy otwarciu.
    property real menuX: 0
    property real menuY: 0
    property real menuWidth: 0
    property bool above: false

    visible: panel.opacity > 0.01

    function show(item, list, current) {
        owner = item;
        entries = list;
        value = current;
        highlighted = list.findIndex(e => e.value === current);
        place();
        forceActiveFocus();
        items.positionViewAtIndex(Math.max(0, highlighted), ListView.Contain);
    }

    function close() {
        if (!owner) return;
        owner = null;
        // Fokus wraca do okna (Esc zamyka okno, Enter nie wybiera z zamkniętej).
        if (parent) parent.forceActiveFocus();
    }

    function pick(index) {
        const o = owner;
        const e = entries[index];
        // Najpierw zamknięcie, potem akcja: akcja przelicza model listy
        // (pułapka z PopupMenu — delegat niszczony w trakcie handlera).
        close();
        if (o && e) o.picked(e.value);
    }

    // Pod polem, a gdy pod spodem brakuje miejsca, a nad nim jest więcej —
    // nad polem. Dłuższa lista się przewija.
    function place() {
        const p = owner.mapToItem(menu, 0, 0);
        const wanted = Math.min(entries.length, maxVisible) * rowHeight + 2 * padding;
        const below = height - (p.y + owner.height + gap) - edgeMargin;
        const aboveSpace = p.y - gap - edgeMargin;
        above = below < wanted && aboveSpace > below;
        const h = Math.min(wanted, above ? aboveSpace : below);
        panel.height = Math.max(rowHeight + 2 * padding, h);
        menuWidth = owner.width;
        menuX = Math.min(p.x, width - edgeMargin - menuWidth);
        const y = above ? p.y - gap - panel.height : p.y + owner.height + gap;
        // Zawsze w oknie, nawet gdy pole jest częściowo przewinięte poza nie.
        menuY = Math.max(edgeMargin, Math.min(y, height - edgeMargin - panel.height));
    }

    onWidthChanged: close()
    onHeightChanged: close()

    Keys.onEscapePressed: close()
    Keys.onUpPressed: {
        highlighted = Math.max(0, highlighted - 1);
        items.positionViewAtIndex(highlighted, ListView.Contain);
    }
    Keys.onDownPressed: {
        highlighted = Math.min(entries.length - 1, highlighted + 1);
        items.positionViewAtIndex(highlighted, ListView.Contain);
    }
    Keys.onReturnPressed: if (highlighted >= 0) pick(highlighted)
    Keys.onEnterPressed: if (highlighted >= 0) pick(highlighted)

    // Klik obok: zamyka i przepuszcza klik dalej, żeby trafił w to, co
    // pod spodem (inna lista otwiera się od razu). Wyjątek: klik w pole,
    // które listę otworzyło — ten tylko zamyka, inaczej lista otwierałaby
    // się z powrotem tym samym klikiem.
    MouseArea {
        anchors.fill: parent
        enabled: menu.open
        onPressed: mouse => {
            const o = menu.owner;
            const p = o.mapFromItem(menu, mouse.x, mouse.y);
            const onOwner = p.x >= 0 && p.y >= 0 && p.x < o.width && p.y < o.height;
            menu.close();
            mouse.accepted = onOwner;
        }
        onWheel: wheel => {
            menu.close();
            wheel.accepted = false;
        }
    }

    Rectangle {
        id: panel

        x: menu.menuX
        y: menu.menuY
        width: menu.menuWidth
        radius: 14
        color: Theme.surface
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
        transformOrigin: menu.above ? Item.Bottom : Item.Top

        opacity: menu.open ? 1 : 0
        scale: menu.open ? 1 : 0.96

        Behavior on opacity { NumberAnimation { duration: Theme.quickMs; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.OutCubic } }

        // Klik w samą listę nie może dojść do MouseArea „obok”. Zanikająca
        // lista (po zamknięciu) nie łapie już niczego.
        enabled: menu.open

        MouseArea {
            anchors.fill: parent
            onWheel: wheel => wheel.accepted = items.contentHeight <= items.height
        }

        ListView {
            id: items

            anchors.fill: parent
            anchors.margins: menu.padding
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            model: menu.entries.length

            delegate: Rectangle {
                id: row

                required property int index
                readonly property var entry: menu.entries[index] ?? null
                readonly property bool current: entry !== null && entry.value === menu.value

                width: ListView.view.width
                height: menu.rowHeight
                radius: 10
                color: menu.highlighted === index ? Theme.hoverStrong : "transparent"

                Rectangle {
                    visible: row.current
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.accent
                }

                Text {
                    x: 26
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 10
                    text: row.entry ? row.entry.label : ""
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: row.current ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: menu.highlighted = row.index
                    onClicked: menu.pick(row.index)
                }
            }
        }
    }
}
