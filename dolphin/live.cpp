// In-process palette refresh for Dolphin.
//
// KColorScheme caches the scheme path for the life of the process, and the
// file view copies that palette only when a graphics widget receives
// PaletteChange. Wallpaper changes rewrite the scheme file under a new path
// and this library points the running process at it.
//
// The file body uses ~47% opacity. The Places column and toolbar stay
// translucent too, but denser (~90%) so that left pane reads above the files.
// A fully clear color is what turned some panels black: an opaque widget
// flattens alpha 0 against black. Text, selection, buttons, and tooltips stay
// fully opaque.

#include <QAbstractScrollArea>
#include <QAbstractItemDelegate>
#include <QApplication>
#include <QByteArray>
#include <QColor>
#include <QDockWidget>
#include <QElapsedTimer>
#include <QFile>
#include <QFileSystemWatcher>
#include <QFont>
#include <QGraphicsView>
#include <QGraphicsWidget>
#include <QHash>
#include <QImageReader>
#include <QListView>
#include <QMainWindow>
#include <QMouseEvent>
#include <QPainter>
#include <QPointer>
#include <QProxyStyle>
#include <QStyleOptionViewItem>
#include <QStyle>
#include <QStyleFactory>
#include <QtMath>
#include <QStatusBar>
#include <QToolBar>
#include <QMetaObject>
#include <QPixmapCache>
#include <QStringList>
#include <KIconLoader>
#include <kde_terminal_interface.h>
#include <QTimer>
#include <QVBoxLayout>
#include <QWidget>

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <thread>

namespace {

constexpr int kBackgroundAlpha = 102; // ~0.40 file body.
constexpr int kChromeAlpha = 191; // 0.75 Places column and toolbar.
constexpr int kStripeAlpha = 40; // faint alternating rows in the file view.
constexpr int kPlacesSpacing = 0;
constexpr int kPlacesIconSize = 22;
constexpr int kPlacesExtraIconGap = 6;
constexpr int kSidebarDefaultWidth = 220;

QString homeConfig(const char *leaf);

QHash<qreal, QPixmap> &headingOrnamentCache()
{
    static QHash<qreal, QPixmap> cache;
    return cache;
}

QPixmap headingOrnament(qreal ratio)
{
    auto &cache = headingOrnamentCache();
    auto found = cache.constFind(ratio);
    if (found == cache.constEnd()) {
        QImageReader reader(homeConfig("/.config/wallust/assets/generated/dolphin-ornaments.svg"));
        reader.setScaledSize(QSize(qRound(64 * ratio), qRound(16 * ratio)));
        QPixmap image = QPixmap::fromImage(reader.read());
        image.setDevicePixelRatio(ratio);
        cache.insert(ratio, image);
        return image;
    }
    return found.value();
}

QRect headingOrnamentRect(const QRect &heading, int textWidth)
{
    // Keep a full gap after the label and before the panel's edge. Narrow
    // panels retain their complete title instead of squeezing in artwork.
    const QRect ornament(heading.right() - 64 - 12 + 1, heading.center().y() - 8, 64, 16);
    return ornament.left() >= heading.left() + textWidth + 18 ? ornament : QRect();
}

QFont imperiumFont()
{
    // Proportional UI sans (Limusic default). The embedded terminal keeps Monaspace.
    QFont font(QStringLiteral("Oxanium"), 11, QFont::Normal);
    font.setStyleName(QStringLiteral("Regular"));
    return font;
}

void applyInitialPanelLayout(QMainWindow *window)
{
    if (!window->isVisible() || window->property("imperiumPanelLayoutSet").toBool()) {
        return;
    }
    auto *places = window->findChild<QDockWidget *>(QStringLiteral("placesDock"));
    if (!places) {
        return;
    }
    // Restore named docks after Dolphin has restored its machine-local State
    // blob. Keep visibility choices, but start Places at the top of the left
    // sidebar, Folders below it, Information right, and Terminal below files.
    const auto dock = [window](QDockWidget *panel, Qt::DockWidgetArea area) {
        if (!panel) {
            return;
        }
        const bool hidden = panel->isHidden();
        panel->setFloating(false);
        window->addDockWidget(area, panel);
        panel->setVisible(!hidden);
    };
    dock(places, Qt::LeftDockWidgetArea);
    auto *folders = window->findChild<QDockWidget *>(QStringLiteral("foldersDock"));
    if (folders) {
        const bool hidden = folders->isHidden();
        dock(folders, Qt::LeftDockWidgetArea);
        window->splitDockWidget(places, folders, Qt::Vertical);
        folders->setVisible(!hidden);
    }
    dock(window->findChild<QDockWidget *>(QStringLiteral("infoDock")), Qt::RightDockWidgetArea);
    dock(window->findChild<QDockWidget *>(QStringLiteral("terminalDock")), Qt::BottomDockWidgetArea);
    window->setProperty("imperiumPanelLayoutSet", true);
}

// KIO paints its own labels with a hard-coded four-pixel icon gap. Keep its
// delegate, animations, capacity bars and event handling, and insert eight
// pixels into the native painted row. Installing this only for column zero
// is important: KIO's mouse handler casts itemDelegate() to its private class.
class PlacesGapDelegate : public QAbstractItemDelegate
{
public:
    PlacesGapDelegate(QListView *view, QAbstractItemDelegate *native)
        : QAbstractItemDelegate(view), m_view(view), m_native(native)
    {
        connect(native, &QAbstractItemDelegate::sizeHintChanged, this, &QAbstractItemDelegate::sizeHintChanged);
        connect(native, &QAbstractItemDelegate::commitData, this, &QAbstractItemDelegate::commitData);
        connect(native, &QAbstractItemDelegate::closeEditor, this, &QAbstractItemDelegate::closeEditor);
        const auto iconChanged = [this] {
            // KIO's smooth resize takes 500ms and uses an intermediate private
            // icon size. Paint natively until the requested size has settled.
            m_iconChange.start();
            QTimer::singleShot(600, this, [this] { m_view->viewport()->update(); });
        };
        connect(view, &QAbstractItemView::iconSizeChanged, this, iconChanged);
        iconChanged();
    }

    void paint(QPainter *painter, const QStyleOptionViewItem &option, const QModelIndex &index) const override
    {
        if (!m_native) {
            return;
        }
        const int iconSize = qMin(m_view->iconSize().width(), m_view->iconSize().height());
        const int width = option.rect.width() - kPlacesExtraIconGap;
        const int height = option.rect.height();
        // The user can still choose automatic icon sizing in Dolphin's menu.
        // Unknown or very narrow layouts retain the complete native rendering.
        if (m_iconChange.elapsed() < 600 || iconSize <= 0 || width <= iconSize + 24 || height <= 0) {
            m_native->paint(painter, option, index);
            return;
        }

        const qreal dpr = painter->device()->devicePixelRatioF();
        QPixmap row(QSize(qCeil(width * dpr), qCeil(height * dpr)));
        row.setDevicePixelRatio(dpr);
        row.fill(Qt::transparent);
        QStyleOptionViewItem nativeOption(option);
        nativeOption.rect = QRect(0, 0, width, height);
        QPainter nativePainter(&row);
        nativePainter.setFont(painter->font());
        nativePainter.setRenderHints(painter->renderHints());
        // Exactly one call: native paint consumes drag state and starts the
        // asynchronous capacity query. Repainting clipped passes is unsafe.
        m_native->paint(&nativePainter, nativeOption, index);
        nativePainter.end();

        int headerHeight = 0;
        const int groupRole = index.model()->roleNames().key(QByteArrayLiteral("group"), -1);
        if (groupRole >= 0) {
            QModelIndex previous;
            for (int r = index.row() - 1; r >= 0; --r) {
                if (!m_view->isRowHidden(r)) {
                    previous = index.siblingAtRow(r);
                    break;
                }
            }
            if (index.data(groupRole).toString() != previous.data(groupRole).toString()) {
                // Ask the native delegate for the header's extra height rather
                // than duplicating KIO's font and spacing calculation.
                QStyleOptionViewItem hintOption(nativeOption);
                hintOption.features |= QStyleOptionViewItem::HasDecoration;
                hintOption.decorationSize = QSize(iconSize, iconSize);
                const int bodyHeight = qApp->style()->sizeFromContents(QStyle::CT_ItemViewItem, &hintOption, {}, option.widget).height();
                if (m_headerFontHeight != m_view->fontMetrics().height() || m_headerSpacing != m_view->spacing()) {
                    m_headerHeight = 0;
                    m_headerFontHeight = m_view->fontMetrics().height();
                    m_headerSpacing = m_view->spacing();
                }
                // An appearing/disappearing row scales its body, not its
                // header. Keep the settled header height through that fade.
                m_headerHeight = qMax(m_headerHeight, m_native->sizeHint(nativeOption, index).height() - bodyHeight);
                headerHeight = qBound(0, m_headerHeight, height);
            }
        }

        const auto copy = [&](const QRectF &target, const QRectF &source) {
            if (!target.isEmpty()) {
                painter->drawPixmap(target.translated(option.rect.topLeft()), row,
                                    QRectF(source.x() * dpr, source.y() * dpr, source.width() * dpr, source.height() * dpr));
            }
        };
        // Keep group titles at the original position; only the item body gains
        // a gap. Native text elision already accounts for the reduced width.
        copy(QRectF(0, 0, width, headerHeight), QRectF(0, 0, width, headerHeight));
        if (index.row() == 0 && headerHeight >= 16 && groupRole >= 0) {
            const QRect header(option.rect.x(), option.rect.y(), width, headerHeight);
            const int titleWidth = m_view->fontMetrics().horizontalAdvance(index.data(groupRole).toString());
            QRect ornament = headingOrnamentRect(header, titleWidth + 6);
            ornament = QStyle::visualRect(option.direction, header, ornament);
            if (!ornament.isEmpty()) {
                painter->save();
                painter->setOpacity(0.70);
                painter->drawPixmap(ornament.topLeft(), headingOrnament(dpr));
                painter->restore();
            }
        }
        const int bodyHeight = height - headerHeight;
        const int split = option.direction == Qt::LeftToRight ? iconSize + 6 : width - iconSize - 6;
        // RTL shifts the label side away from the right-hand icon; the action
        // stays at the real viewport edge in both directions. KIO hit testing
        // uses visualRect(), so its eject and group hitboxes remain unchanged.
        copy(QRectF(0, headerHeight, split, bodyHeight), QRectF(0, headerHeight, split, bodyHeight));
        copy(QRectF(split, headerHeight, kPlacesExtraIconGap, bodyHeight), QRectF(split, headerHeight, 1, bodyHeight));
        copy(QRectF(split + kPlacesExtraIconGap, headerHeight, width - split, bodyHeight), QRectF(split, headerHeight, width - split, bodyHeight));
    }

    QSize sizeHint(const QStyleOptionViewItem &option, const QModelIndex &index) const override
    { return m_native ? m_native->sizeHint(option, index) : QSize(); }
    QList<int> paintingRoles() const override
    { return m_native ? m_native->paintingRoles() : QList<int>(); }
    bool helpEvent(QHelpEvent *event, QAbstractItemView *view, const QStyleOptionViewItem &option, const QModelIndex &index) override
    { return m_native && m_native->helpEvent(event, view, option, index); }
    bool editorEvent(QEvent *event, QAbstractItemModel *model, const QStyleOptionViewItem &option, const QModelIndex &index) override
    { return m_native && m_native->editorEvent(event, model, option, index); }
    QWidget *createEditor(QWidget *parent, const QStyleOptionViewItem &option, const QModelIndex &index) const override
    { return m_native ? m_native->createEditor(parent, option, index) : nullptr; }
    void destroyEditor(QWidget *editor, const QModelIndex &index) const override
    { if (m_native) m_native->destroyEditor(editor, index); }
    void setEditorData(QWidget *editor, const QModelIndex &index) const override
    { if (m_native) m_native->setEditorData(editor, index); }
    void setModelData(QWidget *editor, QAbstractItemModel *model, const QModelIndex &index) const override
    { if (m_native) m_native->setModelData(editor, model, index); }
    void updateEditorGeometry(QWidget *editor, const QStyleOptionViewItem &option, const QModelIndex &index) const override
    { if (m_native) m_native->updateEditorGeometry(editor, option, index); }

private:
    QListView *m_view;
    QPointer<QAbstractItemDelegate> m_native;
    QElapsedTimer m_iconChange;
    mutable int m_headerHeight = 0;
    mutable int m_headerFontHeight = 0;
    mutable int m_headerSpacing = 0;
};

QString homeConfig(const char *leaf)
{
    return QString::fromLocal8Bit(qgetenv("HOME")) + QString::fromLatin1(leaf);
}

QColor parseColor(const QString &text)
{
    const QStringList parts = text.split(QLatin1Char(','));
    if (parts.size() < 3) {
        return {};
    }
    const int alpha = parts.size() >= 4 ? parts.at(3).trimmed().toInt() : 255;
    return QColor(parts.at(0).trimmed().toInt(), parts.at(1).trimmed().toInt(), parts.at(2).trimmed().toInt(), alpha);
}

QColor glass(QColor color)
{
    color.setAlpha(kBackgroundAlpha);
    return color;
}

QColor openBackground(QColor color)
{
    // Item and row fills must not lay a second slab. Alpha 0 is skipped by
    // the painter; an opaque near-black fill is the black bar.
    color.setAlpha(0);
    return color;
}

QColor solid(QColor color)
{
    color.setAlpha(255);
    return color;
}

struct SchemeColors {
    QColor viewBg;
    QColor viewAlt;
    QColor viewFg;
    QColor windowBg;
    QColor windowFg;
    QColor selectBg;
    QColor selectFg;
    QColor buttonBg;
    QColor buttonFg;
    QColor tipBg;
    QColor tipFg;
    QColor accent;
    bool ok = false;
};

SchemeColors readScheme(const QString &path)
{
    SchemeColors colors;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return colors;
    }
    QString group;
    while (!file.atEnd()) {
        const QString line = QString::fromUtf8(file.readLine()).trimmed();
        if (line.startsWith(QLatin1Char('[')) && line.endsWith(QLatin1Char(']'))) {
            group = line.mid(1, line.size() - 2);
            continue;
        }
        const int split = line.indexOf(QLatin1Char('='));
        if (split <= 0) {
            continue;
        }
        const QString key = line.left(split);
        const QColor value = parseColor(line.mid(split + 1));
        if (!value.isValid()) {
            continue;
        }
        // Folder icons are recolored from QPalette::Accent. DecorationFocus
        // is the wallpaper accent; leaving Accent unset keeps the launch color.
        if (key == QLatin1String("DecorationFocus") && !colors.accent.isValid()) {
            colors.accent = value;
        }
        if (group == QLatin1String("Colors:View")) {
            if (key == QLatin1String("BackgroundNormal")) {
                colors.viewBg = value;
            } else if (key == QLatin1String("BackgroundAlternate")) {
                colors.viewAlt = value;
            } else if (key == QLatin1String("ForegroundNormal")) {
                colors.viewFg = value;
            }
        } else if (group == QLatin1String("Colors:Window")) {
            if (key == QLatin1String("BackgroundNormal")) {
                colors.windowBg = value;
            } else if (key == QLatin1String("ForegroundNormal")) {
                colors.windowFg = value;
            }
        } else if (group == QLatin1String("Colors:Selection")) {
            if (key == QLatin1String("BackgroundNormal")) {
                colors.selectBg = value;
            } else if (key == QLatin1String("ForegroundNormal")) {
                colors.selectFg = value;
            }
        } else if (group == QLatin1String("Colors:Button")) {
            if (key == QLatin1String("BackgroundNormal")) {
                colors.buttonBg = value;
            } else if (key == QLatin1String("ForegroundNormal")) {
                colors.buttonFg = value;
            }
        } else if (group == QLatin1String("Colors:Tooltip")) {
            if (key == QLatin1String("BackgroundNormal")) {
                colors.tipBg = value;
            } else if (key == QLatin1String("ForegroundNormal")) {
                colors.tipFg = value;
            }
        }
    }
    colors.ok = colors.viewBg.isValid() && colors.viewFg.isValid() && colors.windowBg.isValid();
    return colors;
}

QPalette paletteFrom(const SchemeColors &colors)
{
    QPalette palette;
    const QColor viewBg = openBackground(colors.viewBg);
    const QColor viewAlt = openBackground(colors.viewAlt.isValid() ? colors.viewAlt : colors.viewBg);
    const QColor windowBg = glass(colors.windowBg);
    const QColor text = solid(colors.viewFg);
    const QColor windowText = solid(colors.windowFg.isValid() ? colors.windowFg : colors.viewFg);
    const QColor selectBg = solid(colors.selectBg.isValid() ? colors.selectBg : colors.viewFg);
    const QColor selectFg = solid(colors.selectFg.isValid() ? colors.selectFg : colors.viewFg);
    const QColor accent = solid(colors.accent.isValid() ? colors.accent : selectBg);
    const QColor buttonBg = solid(colors.buttonBg.isValid() ? colors.buttonBg : colors.windowBg);
    const QColor buttonFg = solid(colors.buttonFg.isValid() ? colors.buttonFg : colors.viewFg);
    const QColor tipBg = solid(colors.tipBg.isValid() ? colors.tipBg : colors.windowBg);
    const QColor tipFg = solid(colors.tipFg.isValid() ? colors.tipFg : colors.viewFg);

    const auto paint = [&](QPalette::ColorGroup group) {
        palette.setColor(group, QPalette::Window, windowBg);
        palette.setColor(group, QPalette::WindowText, windowText);
        palette.setColor(group, QPalette::Base, viewBg);
        palette.setColor(group, QPalette::AlternateBase, viewAlt);
        palette.setColor(group, QPalette::Text, text);
        palette.setColor(group, QPalette::BrightText, text);
        palette.setColor(group, QPalette::Button, buttonBg);
        palette.setColor(group, QPalette::ButtonText, buttonFg);
        palette.setColor(group, QPalette::Highlight, selectBg);
        palette.setColor(group, QPalette::HighlightedText, selectFg);
        palette.setColor(group, QPalette::Accent, accent);
        palette.setColor(group, QPalette::ToolTipBase, tipBg);
        palette.setColor(group, QPalette::ToolTipText, tipFg);
        palette.setColor(group, QPalette::Link, text);
        palette.setColor(group, QPalette::PlaceholderText, text);
    };
    paint(QPalette::Active);
    paint(QPalette::Inactive);
    paint(QPalette::Disabled);
    return palette;
}

struct ViewportMargins : QAbstractScrollArea {
    static void set(QAbstractScrollArea *area, int left, int top, int right, int bottom)
    {
        auto method = static_cast<void (QAbstractScrollArea::*)(int, int, int, int)>(&ViewportMargins::setViewportMargins);
        (area->*method)(left, top, right, bottom);
    }
};

bool sameColor(const QPalette &have, const QPalette &want)
{
    return have.color(QPalette::Text) == want.color(QPalette::Text)
        && have.color(QPalette::Base) == want.color(QPalette::Base)
        && have.color(QPalette::Window) == want.color(QPalette::Window)
        && have.color(QPalette::Highlight) == want.color(QPalette::Highlight)
        && have.color(QPalette::Accent) == want.color(QPalette::Accent);
}

// Dolphin supplies the branch cell and expanded state through QStyle, but
// does not pass the row's hover state. Use the painter's row transform to
// reveal the native toggle on row hover without changing its hit target.
class FolderBranchStyle : public QProxyStyle
{
public:
    explicit FolderBranchStyle(QGraphicsView *view)
        : QProxyStyle(nullptr), m_view(view)
    {
        setParent(view->scene());
        view->viewport()->setMouseTracking(true);
        view->viewport()->installEventFilter(this);
    }

    void refreshTheme(const QString &schemePath)
    {
        if (m_schemePath == schemePath) {
            return;
        }
        // Kvantum retains the rendered SVG inside each style instance. The
        // scene owns a separate instance from QApplication, so palette/QSS
        // updates alone leave file selections painted with the old artwork.
        if (QStyle *fresh = QStyleFactory::create(QStringLiteral("kvantum"))) {
            setBaseStyle(fresh);
        }
        m_schemePath = schemePath;
    }

    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (m_view && watched == m_view->viewport()) {
            if (event->type() == QEvent::MouseMove) {
                const auto *mouse = static_cast<QMouseEvent *>(event);
                // Rubber-band selection already hit-tests and repaints the
                // scene. Do not run a second full-width scene query for every
                // drag event just to reveal a folder toggle.
                updateHover(mouse->buttons() == Qt::NoButton
                                ? mouse->position().toPoint() : QPoint(-1, -1));
            } else if (event->type() == QEvent::MouseButtonRelease) {
                const auto *mouse = static_cast<QMouseEvent *>(event);
                if (mouse->buttons() == Qt::NoButton) {
                    updateHover(mouse->position().toPoint());
                }
            } else if (event->type() == QEvent::Enter) {
                updateHover(static_cast<QEnterEvent *>(event)->position().toPoint());
            } else if (event->type() == QEvent::Leave) {
                updateHover(QPoint(-1, -1));
            } else if (event->type() == QEvent::Wheel) {
                QTimer::singleShot(0, this, [this] { updateHover(m_pointer); });
            }
        }
        return QProxyStyle::eventFilter(watched, event);
    }

    void drawPrimitive(PrimitiveElement element, const QStyleOption *option,
                       QPainter *painter, const QWidget *widget = nullptr) const override
    {
        if (element != PE_IndicatorBranch) {
            QProxyStyle::drawPrimitive(element, option, painter, widget);
            return;
        }
        if (!(option->state & State_Children) || !m_view) {
            return;
        }
        const bool expanded = option->state & State_Open;
        const QWidget *viewport = m_view->viewport();
        bool invertible = false;
        const QTransform inverse = painter->worldTransform().inverted(&invertible);
        const qreal rowY = inverse.map(QPointF(m_pointer)).y();
        const bool hovered = m_hoveredRow && invertible && viewport->rect().contains(m_pointer)
            && rowY >= option->rect.top() && rowY < option->rect.bottom() + 1;
        if (!hovered) {
            return;
        }

        const QPointF center = QRectF(option->rect).center();
        const qreal direction = m_view->layoutDirection() == Qt::RightToLeft ? -1.0 : 1.0;
        QPolygonF chevron;
        if (expanded) {
            chevron << QPointF(-3.5, -1.75) << QPointF(0, 1.75) << QPointF(3.5, -1.75);
        } else {
            chevron << QPointF(-1.75 * direction, -3.5) << QPointF(1.75 * direction, 0)
                    << QPointF(-1.75 * direction, 3.5);
        }
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing);
        painter->translate(center);
        painter->setPen(QPen(m_view->palette().color(QPalette::Text), 1.5,
                             Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        painter->drawPolyline(chevron);
        painter->restore();
    }

private:
    QString m_schemePath;

    void updateHover(const QPoint &pointer)
    {
        m_pointer = pointer;
        if (!m_view) {
            return;
        }
        QGraphicsWidget *next = nullptr;
        QWidget *viewport = m_view->viewport();
        if (viewport->rect().contains(pointer)) {
            const QPointF scenePointer = m_view->mapToScene(pointer);
            // Most motion stays within the same row. Reuse that hit instead
            // of asking QGraphicsScene to collect and sort its items again.
            if (m_hoveredRow && m_hoveredRow->isVisible()) {
                const qreal localY = m_hoveredRow->mapFromScene(scenePointer).y();
                const QRectF bounds = m_hoveredRow->boundingRect();
                if (localY >= bounds.top() && localY < bounds.bottom()) {
                    return;
                }
            }
            // Hit-test the whole horizontal row, including its empty gutters.
            const auto items = m_view->items(QRect(0, pointer.y(), viewport->width(), 1),
                                             Qt::IntersectsItemBoundingRect);
            for (QGraphicsItem *item : items) {
                auto *row = qgraphicsitem_cast<QGraphicsWidget *>(item);
                if (row && row->inherits("DolphinFileItemListWidget")) {
                    // The one-pixel query intersects both rows at a boundary.
                    // Match the painter's half-open vertical interval instead
                    // of switching early to the next row while moving down.
                    const qreal localY = row->mapFromScene(scenePointer).y();
                    const QRectF bounds = row->boundingRect();
                    if (localY >= bounds.top() && localY < bounds.bottom()) {
                        next = row;
                        break;
                    }
                }
            }
        }
        if (m_hoveredRow != next) {
            if (m_hoveredRow) {
                m_hoveredRow->update();
            }
            m_hoveredRow = next;
            if (next) {
                next->update();
            }
        }
    }

    QPointer<QGraphicsView> m_view;
    QPointer<QGraphicsWidget> m_hoveredRow;
    QPoint m_pointer{-1, -1};
};

// Paint only in the window's existing outer margins. The overlay never takes
// focus or mouse input and never places decoration over the file viewport.
class CornerFrame : public QWidget
{
public:
    explicit CornerFrame(QMainWindow *window) : QWidget(window)
    {
        setObjectName(QStringLiteral("imperiumCornerFrame"));
        setAttribute(Qt::WA_TransparentForMouseEvents);
        setAttribute(Qt::WA_NoSystemBackground);
        setFocusPolicy(Qt::NoFocus);
        window->installEventFilter(this);
        setGeometry(window->rect());
        show();
    }

    void refresh()
    {
        QImageReader reader(homeConfig("/.config/wallust/assets/generated/medium-corner-br.svg"));
        const qreal ratio = devicePixelRatioF();
        constexpr int kMediumCornerPx = 56;
        reader.setScaledSize(QSize(qRound(kMediumCornerPx * ratio), qRound(kMediumCornerPx * ratio)));
        m_corner = QPixmap::fromImage(reader.read());
        m_corner.setDevicePixelRatio(ratio);
        raise();
        update();
    }

protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (watched == parentWidget() && (event->type() == QEvent::Resize || event->type() == QEvent::Show)) {
            setGeometry(parentWidget()->rect());
            raise();
        }
        return QWidget::eventFilter(watched, event);
    }

    void paintEvent(QPaintEvent *) override
    {
        if (m_corner.isNull()) return;
        QPainter painter(this);
        painter.setOpacity(0.70);
        const qreal ratio = devicePixelRatioF();
        const int w = qRound(m_corner.width() / ratio);
        const int h = qRound(m_corner.height() / ratio);
        constexpr int kMarginPx = 6;
        painter.drawPixmap(width() - kMarginPx - w, height() - kMarginPx - h, m_corner);
    }

private:
    QPixmap m_corner;
};

class LiveTheme : public QObject
{
public:
    explicit LiveTheme(QObject *parent)
        : QObject(parent)
        , m_conf(homeConfig("/.config/qt6ct/dolphin-live.conf"))
    {
        connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] {
            scheduleApply(120);
        });
        qApp->installEventFilter(this);
        arm();
        scheduleApply(0);
        QTimer::singleShot(900, this, [this] { scheduleApply(0); });
    }

    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() == QEvent::Polish || event->type() == QEvent::Show) {
            if (auto *window = qobject_cast<QMainWindow *>(watched);
                window && window->inherits("DolphinMainWindow")) {
                // The alpha buffer has to exist before the Wayland surface
                // is shown, or the file body is flattened to an opaque fill.
                window->setAttribute(Qt::WA_TranslucentBackground, true);
                window->setAttribute(Qt::WA_NoSystemBackground, true);
                window->setAutoFillBackground(false);
            }
        }
        if (event->type() == QEvent::Show && (watched->inherits("KFilePlacesView") || watched->inherits("TerminalPanel")
                                            || qobject_cast<QMainWindow *>(watched))) {
            scheduleApply(80);
        }
        if (watched->property("imperiumGlass").toBool()
            && (event->type() == QEvent::PaletteChange || event->type() == QEvent::Show)) {
            if (auto *widget = qobject_cast<QWidget *>(watched)) {
                // Dolphin resets the viewport color on focus and paints the
                // opaque scheme color over the window. Put the clear fill back
                // after that handler.
                const auto clearFill = [widget = QPointer<QWidget>(widget)] {
                    if (!widget) {
                        return;
                    }
                    widget->setAttribute(Qt::WA_TranslucentBackground, true);
                    widget->setAutoFillBackground(false);
                };
                clearFill();
                QTimer::singleShot(0, widget, clearFill);
            }
        }
        if (watched->property("imperiumPlacesChrome").toBool()
            && (event->type() == QEvent::PaletteChange || event->type() == QEvent::Show
                || event->type() == QEvent::StyleChange)) {
            if (auto *widget = qobject_cast<QWidget *>(watched)) {
                const QColor fill = widget->property("imperiumPlacesFill").value<QColor>();
                const auto restore = [widget = QPointer<QWidget>(widget), fill] {
                    if (!widget || !fill.isValid()) {
                        return;
                    }
                    QPalette chromePalette = widget->palette();
                    chromePalette.setColor(QPalette::Window, fill);
                    chromePalette.setColor(QPalette::Base, fill);
                    chromePalette.setColor(QPalette::Button, fill);
                    widget->setAttribute(Qt::WA_TranslucentBackground, true);
                    widget->setAutoFillBackground(true);
                    widget->setPalette(chromePalette);
                };
                restore();
                QTimer::singleShot(0, widget, restore);
            }
        }
        return QObject::eventFilter(watched, event);
    }

private:
    void scheduleApply(int delayMs)
    {
        if (!m_applyDebounce) {
            m_applyDebounce = new QTimer(this);
            m_applyDebounce->setSingleShot(true);
            connect(m_applyDebounce, &QTimer::timeout, this, [this] { apply(); });
        }
        m_applyDebounce->setInterval(delayMs);
        m_applyDebounce->start();
    }

    void arm()
    {
        if (QFile::exists(m_conf) && !m_watcher.files().contains(m_conf)) {
            m_watcher.addPath(m_conf);
        }
        if (!m_qssPath.isEmpty() && QFile::exists(m_qssPath) && !m_watcher.files().contains(m_qssPath)) {
            m_watcher.addPath(m_qssPath);
        }
    }

    void apply()
    {
        if (m_applying) {
            return;
        }
        m_applying = true;
        arm();

        QFile conf(m_conf);
        if (!conf.open(QIODevice::ReadOnly | QIODevice::Text)) {
            m_applying = false;
            return;
        }
        QString schemePath;
        QString qssPath;
        QString icons;
        QString terminalProfile;
        while (!conf.atEnd()) {
            const QString line = QString::fromUtf8(conf.readLine()).trimmed();
            if (line.startsWith(QLatin1String("scheme="))) {
                schemePath = line.mid(7);
            } else if (line.startsWith(QLatin1String("qss="))) {
                qssPath = line.mid(4);
            } else if (line.startsWith(QLatin1String("icons="))) {
                icons = line.mid(6);
            } else if (line.startsWith(QLatin1String("terminal="))) {
                terminalProfile = line.mid(9);
            }
        }
        const SchemeColors colors = readScheme(schemePath);
        if (!colors.ok) {
            m_applying = false;
            return;
        }
        const bool schemeChanged = schemePath != m_schemePath;
        // The first pass already inherits KVANTUM_THEME from the launcher.
        // Rebuilding that style is only needed after a later palette path change.
        const bool refreshStyle = m_haveScheme && schemeChanged;
        m_haveScheme = true;
        m_schemePath = schemePath;

        if (schemeChanged) {
            // Heading artwork follows the palette path, not the icon accent alone.
            headingOrnamentCache().clear();
        }

        // A new path misses KColorScheme's thread-local cache. DolphinView
        // then reads the wallpaper's colors, including the background alpha.
        qApp->setProperty("KDE_COLOR_SCHEME_PATH", schemePath);

        if (refreshStyle) {
            // KFilePlacesView's native delegate paints selections through
            // QApplication::style(), without passing its widget. Its Kvantum
            // SVG cache is independent of the file scene's FolderBranchStyle
            // and cannot be refreshed by the sidebar palette or QSS alone.
            if (QStyle *fresh = QStyleFactory::create(QStringLiteral("kvantum"))) {
                qApp->setStyle(fresh);
            }
        }

        const QFont font = imperiumFont();
        if (qApp->font() != font) {
            qApp->setFont(font);
        }

        const QPalette palette = paletteFrom(colors);
        if (!sameColor(qApp->palette(), palette)) {
            qApp->setPalette(palette);
        }
        QPalette chromePalette = palette;
        QColor chrome = solid(colors.viewBg);
        chrome.setAlpha(kChromeAlpha);
        chromePalette.setColor(QPalette::Window, chrome);
        chromePalette.setColor(QPalette::Base, chrome);
        chromePalette.setColor(QPalette::Button, chrome);
        const auto paintChrome = [this, &chromePalette, chrome](QWidget *widget, bool placesColumn = false) {
            // Keep chrome translucent; only denser than the file body.
            widget->setAttribute(Qt::WA_TranslucentBackground, true);
            // Places must auto-fill: its View palette is clear, so without a
            // real fill the window glass shows through and matches the body.
            widget->setAutoFillBackground(placesColumn);
            if (!sameColor(widget->palette(), chromePalette)) {
                widget->setPalette(chromePalette);
            }
            const QString chromeCss = QStringLiteral("background-color: rgba(%1,%2,%3,%4);")
                                          .arg(chrome.red())
                                          .arg(chrome.green())
                                          .arg(chrome.blue())
                                          .arg(kChromeAlpha);
            if (widget->property("imperiumChrome").toString() != chromeCss) {
                widget->setStyleSheet(chromeCss);
                widget->setProperty("imperiumChrome", chromeCss);
            }
            if (placesColumn) {
                widget->setProperty("imperiumPlacesChrome", true);
                widget->setProperty("imperiumPlacesFill", chrome);
                if (!widget->property("imperiumPlacesFilter").toBool()) {
                    widget->installEventFilter(this);
                    widget->setProperty("imperiumPlacesFilter", true);
                }
            }
        };

        const auto widgets = QApplication::allWidgets();
        for (QWidget *widget : widgets) {
            if (auto *window = qobject_cast<QMainWindow *>(widget); window && window->inherits("DolphinMainWindow")) {
                applyInitialPanelLayout(window);
                // The file body is the window fill. It has to be a real
                // translucent surface or Qt flattens that alpha to black.
                window->setAttribute(Qt::WA_TranslucentBackground, true);
                window->setAttribute(Qt::WA_NoSystemBackground, true);
                window->setAutoFillBackground(false);
                auto *frame = window->findChild<QWidget *>(QStringLiteral("imperiumCornerFrame"), Qt::FindDirectChildrenOnly);
                // CornerFrame has no Q_OBJECT; only this class sets the object name.
                if (!frame) {
                    auto *corner = new CornerFrame(window);
                    corner->refresh();
                } else if (schemeChanged) {
                    static_cast<CornerFrame *>(frame)->refresh();
                }
            }
        }
        for (QWidget *widget : widgets) {
            if (widget->inherits("TerminalPanel") && !terminalProfile.isEmpty()) {
                for (QObject *child : widget->findChildren<QObject *>()) {
                    auto *terminal = qobject_cast<TerminalInterface *>(child);
                    if (terminal && terminal->terminalProcessId() > 0
                        && child->property("imperiumTerminalProfile").toString() != terminalProfile
                        && terminal->setCurrentProfile(terminalProfile)) {
                        child->setProperty("imperiumTerminalProfile", terminalProfile);
                    }
                }
            }
            if (auto *toolbar = qobject_cast<QToolBar *>(widget)) {
                toolbar->setContentsMargins(8, 4, 8, 3);
                paintChrome(toolbar);
            }
            if (auto *status = qobject_cast<QStatusBar *>(widget)) {
                status->setContentsMargins(10, 3, 10, 4);
                paintChrome(status);
            }
            if (auto *dock = qobject_cast<QDockWidget *>(widget)) {
                const bool placesDock = dock->objectName() == QLatin1String("placesDock");
                dock->setContentsMargins(4, 2, placesDock ? 0 : 4, 4);
                paintChrome(dock, placesDock);
                if (placesDock) {
                    // Sit a denser translucent plate behind Places. The view
                    // itself stays clear so wallpaper shows through the plate
                    // alpha instead of matching the file body glass.
                    QWidget *content = dock->widget();
                    if (content && content->objectName() != QLatin1String("imperiumPlacesPlate")) {
                        auto *plate = new QWidget(dock);
                        plate->setObjectName(QStringLiteral("imperiumPlacesPlate"));
                        auto *layout = new QVBoxLayout(plate);
                        layout->setContentsMargins(0, 0, 0, 0);
                        layout->setSpacing(0);
                        content->setParent(plate);
                        layout->addWidget(content);
                        dock->setWidget(plate);
                        content = plate;
                    }
                    if (content) {
                        paintChrome(content, true);
                    }
                }
            }

            auto *view = qobject_cast<QGraphicsView *>(widget);
            const bool places = widget->inherits("KFilePlacesView");
            if (!view && !places) {
                continue;
            }
            if (places) {
                if (auto *list = qobject_cast<QListView *>(widget)) {
                    if (list->spacing() != kPlacesSpacing) {
                        list->setSpacing(kPlacesSpacing);
                    }
                    if (!list->property("imperiumPlacesGap").toBool() && list->itemDelegate()) {
                        list->setIconSize(QSize(kPlacesIconSize, kPlacesIconSize));
                        list->setItemDelegateForColumn(0, new PlacesGapDelegate(list, list->itemDelegate()));
                        list->setProperty("imperiumPlacesGap", true);
                    }
                }
                setInitialSidebarWidth(widget);
            }
            if (places) {
                // Keep the Places list clear so the chrome plate behind it shows.
                widget->setAttribute(Qt::WA_TranslucentBackground, true);
                widget->setAutoFillBackground(false);
                widget->setStyleSheet(QStringLiteral("background-color: transparent;"));
                if (!sameColor(widget->palette(), palette)) {
                    widget->setPalette(palette);
                }
            } else if (!sameColor(widget->palette(), palette)) {
                widget->setPalette(palette);
            }
            widget->setAttribute(Qt::WA_TranslucentBackground, true);
            widget->setAutoFillBackground(false);
            if (auto *area = qobject_cast<QAbstractScrollArea *>(widget)) {
                if (QWidget *viewport = area->viewport()) {
                    if (places) {
                        viewport->setAttribute(Qt::WA_TranslucentBackground, true);
                        viewport->setAutoFillBackground(false);
                        viewport->setStyleSheet(QStringLiteral("background-color: transparent;"));
                        if (!sameColor(viewport->palette(), palette)) {
                            viewport->setPalette(palette);
                        }
                    } else {
                        viewport->setAttribute(Qt::WA_TranslucentBackground, true);
                        viewport->setAutoFillBackground(false);
                        if (!viewport->property("imperiumGlass").toBool()) {
                            viewport->setProperty("imperiumGlass", true);
                        }
                        if (!sameColor(viewport->palette(), palette)) {
                            viewport->setPalette(palette);
                        }
                    }
                }
                if (places) {
                    ViewportMargins::set(area, 6, 2, 0, 4);
                } else if (view) {
                    ViewportMargins::set(area, 4, 2, 4, 4);
                }
            }
            if (!view || !view->scene()) {
                continue;
            }
            if (!places) {
                // The window fill is the 60% body. Dolphin's own palette
                // update paints an opaque view color unless this stays clear.
                const QString bodyCss = QStringLiteral("background-color: rgba(%1,%2,%3,%4);")
                                            .arg(colors.windowBg.red())
                                            .arg(colors.windowBg.green())
                                            .arg(colors.windowBg.blue())
                                            .arg(kBackgroundAlpha);
                view->setProperty("imperiumGlass", true);
                view->setAttribute(Qt::WA_TranslucentBackground, true);
                view->setAutoFillBackground(false);
                if (view->property("imperiumBody").toString() != bodyCss) {
                    view->setStyleSheet(bodyCss);
                    view->setProperty("imperiumBody", bodyCss);
                }
                if (!view->property("imperiumGlassFilter").toBool()) {
                    view->installEventFilter(this);
                    view->setProperty("imperiumGlassFilter", true);
                }
                if (QWidget *inner = view->viewport()) {
                    inner->setProperty("imperiumGlass", true);
                    inner->setAttribute(Qt::WA_TranslucentBackground, true);
                    inner->setAutoFillBackground(false);
                    if (inner->property("imperiumBody").toString() != bodyCss) {
                        inner->setStyleSheet(bodyCss);
                        inner->setProperty("imperiumBody", bodyCss);
                    }
                    if (!inner->property("imperiumGlassFilter").toBool()) {
                        inner->installEventFilter(this);
                        inner->setProperty("imperiumGlassFilter", true);
                    }
                }
            }
            view->setBackgroundBrush(Qt::NoBrush);
            const auto items = view->scene()->items();
            for (QGraphicsItem *item : items) {
                auto *graphics = qgraphicsitem_cast<QGraphicsWidget *>(item);
                if (graphics && graphics->inherits("DolphinItemListView")
                    && !view->scene()->property("imperiumFolderBranches").toBool()) {
                    // Graphics widgets inherit the scene style, rather than
                    // their parent widget's style. This also covers new rows.
                    view->scene()->setStyle(new FolderBranchStyle(view));
                    view->scene()->setProperty("imperiumFolderBranches", true);
                }
                if (graphics && graphics->inherits("DolphinItemListView")) {
                    auto *branches = static_cast<FolderBranchStyle *>(view->scene()->style());
                    branches->refreshTheme(schemePath);
                }
                if (graphics && graphics->inherits("DolphinItemListView")) {
                    QPalette body = palette;
                    const QColor fill = glass(colors.windowBg);
                    QColor stripe = colors.windowBg;
                    // Soften the stock zebra: lift slightly toward the text and
                    // keep most of the wallpaper visible through the stripe.
                    const QColor text = solid(colors.viewFg);
                    stripe.setRed(qBound(0, 255, qRound(stripe.red() * 0.94 + text.red() * 0.06)));
                    stripe.setGreen(qBound(0, 255, qRound(stripe.green() * 0.94 + text.green() * 0.06)));
                    stripe.setBlue(qBound(0, 255, qRound(stripe.blue() * 0.94 + text.blue() * 0.06)));
                    stripe.setAlpha(kStripeAlpha);
                    body.setColor(QPalette::Base, fill);
                    body.setColor(QPalette::Window, fill);
                    body.setColor(QPalette::AlternateBase, stripe);
                    if (!sameColor(graphics->palette(), body)) {
                        graphics->setPalette(body);
                    }
                } else if (graphics && !sameColor(graphics->palette(), palette)) {
                    graphics->setPalette(palette);
                } else if (graphics && graphics->inherits("DolphinItemListView") && schemeChanged) {
                    // Inherited palettes may already match. Dolphin still
                    // needs this event to refresh its cached row style options
                    // and hover pixmaps from the new KColorScheme path.
                    QEvent changed(QEvent::PaletteChange);
                    QCoreApplication::sendEvent(graphics, &changed);
                }
            }
        }

        if (qssPath != m_qssPath) {
            if (!m_qssPath.isEmpty()) {
                m_watcher.removePath(m_qssPath);
            }
            m_qssPath = qssPath;
        }
        arm();
        if (!qssPath.isEmpty()) {
            QFile qss(qssPath);
            if (qss.open(QIODevice::ReadOnly)) {
                const QByteArray body = qss.readAll();
                if (body != m_qss) {
                    m_qss = body;
                    qApp->setStyleSheet(QString::fromUtf8(body));
                }
            }
        }

        // The first read records the icons Dolphin opened with. A later value
        // means the wallpaper accent changed and cached pixmaps are stale.
        if (icons != m_icons || !m_iconsReady) {
            const bool refresh = m_iconsReady && icons != m_icons;
            m_icons = icons;
            m_iconsReady = true;
            if (refresh) {
                refreshIcons();
            }
        }
        m_applying = false;
    }

    void setInitialSidebarWidth(QWidget *placesView)
    {
        if (!placesView->isVisible()) {
            return;
        }
        for (QWidget *parent = placesView->parentWidget(); parent; parent = parent->parentWidget()) {
            auto *dock = qobject_cast<QDockWidget *>(parent);
            if (!dock) {
                continue;
            }
            if (dock->property("imperiumSidebarWidthSet").toBool() || dock->isFloating()) {
                return;
            }
            auto *window = qobject_cast<QMainWindow *>(dock->parentWidget());
            if (!window) {
                return;
            }
            if (dock->width() != kSidebarDefaultWidth) {
                window->resizeDocks({dock}, {kSidebarDefaultWidth}, Qt::Horizontal);
            }
            // Start with the tracked width on both hosts; later resizing in
            // this window is respected until it is reopened.
            dock->setProperty("imperiumSidebarWidthSet", true);
            return;
        }
    }

    void refreshIcons()
    {
        QPixmapCache::clear();
        // Drop KIconLoader's pixmap cache in this process before the file
        // view asks for icons again. A bus signal would arrive too late.
        if (KIconLoader *icons = KIconLoader::global()) {
            icons->reconfigure(QString());
        }

        const auto widgets = QApplication::allWidgets();
        for (QWidget *widget : widgets) {
            widget->update();
            if (widget->inherits("DolphinView")) {
                QMetaObject::invokeMethod(widget, "reload", Qt::QueuedConnection);
                // An idle thumbnail worker's closed connection is discovered
                // on its next request. Retry after KIO discards that connection
                // so visible folder composites come from the new worker.
                QTimer::singleShot(600, widget, [widget] {
                    QMetaObject::invokeMethod(widget, "reload", Qt::QueuedConnection);
                });
            }
        }
    }

    QFileSystemWatcher m_watcher;
    QTimer *m_applyDebounce = nullptr;
    QString m_conf;
    QString m_schemePath;
    QString m_qssPath;
    QString m_icons;
    QByteArray m_qss;
    bool m_iconsReady = false;
    bool m_haveScheme = false;
    bool m_applying = false;
};

LiveTheme *g_hook = nullptr;

void installHook()
{
    if (!qApp || g_hook) {
        return;
    }
    g_hook = new LiveTheme(qApp);
    g_hook->setObjectName(QStringLiteral("imperium-live"));
}

bool processIsDolphin()
{
    std::ifstream input("/proc/self/comm");
    std::string name;
    std::getline(input, name);
    return name == "dolphin";
}

void dropPreload()
{
    const char *raw = std::getenv("LD_PRELOAD");
    if (!raw || !std::strstr(raw, "libdolphin-live.so")) {
        return;
    }
    std::string kept;
    const char *cursor = raw;
    while (*cursor) {
        const char *end = std::strchr(cursor, ':');
        const std::string part = end ? std::string(cursor, end) : std::string(cursor);
        if (part.find("libdolphin-live.so") == std::string::npos && !part.empty()) {
            if (!kept.empty()) {
                kept.push_back(':');
            }
            kept += part;
        }
        if (!end) {
            break;
        }
        cursor = end + 1;
    }
    if (kept.empty()) {
        unsetenv("LD_PRELOAD");
    } else {
        setenv("LD_PRELOAD", kept.c_str(), 1);
    }
}

} // namespace

extern "C" __attribute__((constructor)) void imperiumDolphinLiveInit()
{
    // The embedded Konsole shell inherits the environment. Drop the preload
    // before that child starts so zsh does not load Qt.
    dropPreload();
    if (!processIsDolphin()) {
        return;
    }
    std::thread([] {
        for (int attempt = 0; attempt < 400; ++attempt) {
            if (QCoreApplication::instance()) {
                QMetaObject::invokeMethod(QCoreApplication::instance(), installHook, Qt::QueuedConnection);
                return;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(attempt < 40 ? 5 : 25));
        }
    }).detach();
}
