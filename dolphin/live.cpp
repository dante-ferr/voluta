// In-process palette refresh for Dolphin.
//
// KColorScheme caches the scheme path for the life of the process, and the
// file view copies that palette only when a graphics widget receives
// PaletteChange. Wallpaper changes rewrite the scheme file under a new path
// and this library points the running process at it.
//
// Backgrounds use 88% opacity, which is less transparent than Kitty (75%).
// A fully clear color is what turned some panels black: an opaque widget
// flattens alpha 0 against black. Text, selection, buttons, and tooltips
// stay fully opaque.

#include <QAbstractScrollArea>
#include <QApplication>
#include <QByteArray>
#include <QColor>
#include <QDockWidget>
#include <QFile>
#include <QFileSystemWatcher>
#include <QGraphicsView>
#include <QGraphicsWidget>
#include <QListView>
#include <QStatusBar>
#include <QToolBar>
#include <QMetaObject>
#include <QPixmapCache>
#include <QStringList>
#include <KIconLoader>
#include <QTimer>
#include <QWidget>

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <thread>

namespace {

constexpr int kBackgroundAlpha = 224; // 0.88. Kitty uses 0.75.

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

class LiveTheme : public QObject
{
public:
    explicit LiveTheme(QObject *parent)
        : QObject(parent)
        , m_conf(homeConfig("/.config/qt6ct/dolphin-live.conf"))
    {
        connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] {
            QTimer::singleShot(80, this, [this] { apply(); });
        });
        arm();
        apply();
        QTimer::singleShot(400, this, [this] { apply(); });
        QTimer::singleShot(1200, this, [this] { apply(); });
    }

    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() == QEvent::PaletteChange || event->type() == QEvent::Show) {
            if (auto *widget = qobject_cast<QWidget *>(watched)) {
                // Dolphin resets the viewport color on focus. Keep that fill
                // translucent so it cannot flatten to black.
                widget->setAttribute(Qt::WA_TranslucentBackground, true);
                widget->setAutoFillBackground(false);
            }
        }
        return QObject::eventFilter(watched, event);
    }

private:
    void arm()
    {
        if (QFile::exists(m_conf) && !m_watcher.files().contains(m_conf)) {
            m_watcher.addPath(m_conf);
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
        while (!conf.atEnd()) {
            const QString line = QString::fromUtf8(conf.readLine()).trimmed();
            if (line.startsWith(QLatin1String("scheme="))) {
                schemePath = line.mid(7);
            } else if (line.startsWith(QLatin1String("qss="))) {
                qssPath = line.mid(4);
            } else if (line.startsWith(QLatin1String("icons="))) {
                icons = line.mid(6);
            }
        }
        const SchemeColors colors = readScheme(schemePath);
        if (!colors.ok) {
            m_applying = false;
            return;
        }

        // A new path misses KColorScheme's thread-local cache. DolphinView
        // then reads the wallpaper's colors, including the background alpha.
        qApp->setProperty("KDE_COLOR_SCHEME_PATH", schemePath);

        const QPalette palette = paletteFrom(colors);
        if (!sameColor(qApp->palette(), palette)) {
            qApp->setPalette(palette);
        }

        const auto widgets = QApplication::allWidgets();
        for (QWidget *widget : widgets) {
            if (auto *toolbar = qobject_cast<QToolBar *>(widget)) {
                toolbar->setContentsMargins(16, 10, 16, 6);
            }
            if (auto *status = qobject_cast<QStatusBar *>(widget)) {
                status->setContentsMargins(18, 8, 18, 12);
            }
            if (auto *dock = qobject_cast<QDockWidget *>(widget)) {
                dock->setContentsMargins(8, 8, 10, 8);
            }

            auto *view = qobject_cast<QGraphicsView *>(widget);
            const bool places = widget->inherits("KFilePlacesView");
            if (!view && !places) {
                continue;
            }
            if (places) {
                if (auto *list = qobject_cast<QListView *>(widget)) {
                    if (list->spacing() != 4) {
                        list->setSpacing(4);
                    }
                }
            }
            if (!sameColor(widget->palette(), palette)) {
                widget->setPalette(palette);
            }
            widget->setAttribute(Qt::WA_TranslucentBackground, true);
            widget->setAutoFillBackground(false);
            if (auto *area = qobject_cast<QAbstractScrollArea *>(widget)) {
                if (QWidget *viewport = area->viewport()) {
                    viewport->setAttribute(Qt::WA_TranslucentBackground, true);
                    viewport->setAutoFillBackground(false);
                    if (!viewport->property("imperiumGlass").toBool()) {
                        viewport->installEventFilter(this);
                        viewport->setProperty("imperiumGlass", true);
                    }
                    if (!sameColor(viewport->palette(), palette)) {
                        viewport->setPalette(palette);
                    }
                }
                if (places) {
                    ViewportMargins::set(area, 14, 6, 6, 8);
                } else if (view) {
                    ViewportMargins::set(area, 10, 8, 10, 8);
                }
            }
            if (!view || !view->scene()) {
                continue;
            }
            view->setBackgroundBrush(Qt::NoBrush);
            const auto items = view->scene()->items();
            for (QGraphicsItem *item : items) {
                auto *graphics = qgraphicsitem_cast<QGraphicsWidget *>(item);
                if (graphics && !sameColor(graphics->palette(), palette)) {
                    graphics->setPalette(palette);
                }
            }
        }

        if (!qssPath.isEmpty() && qssPath != m_qssPath) {
            QFile qss(qssPath);
            if (qss.open(QIODevice::ReadOnly)) {
                const QByteArray body = qss.readAll();
                if (body != m_qss) {
                    m_qss = body;
                    qApp->setStyleSheet(QString::fromUtf8(body));
                }
                m_qssPath = qssPath;
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

    void refreshIcons()
    {
        QPixmapCache::clear();
        // Drop KIconLoader's pixmap cache in this process before the file
        // view asks for icons again. A bus signal would arrive too late.
        if (KIconLoader *icons = KIconLoader::global()) {
            icons->newIconLoader();
        }

        const auto widgets = QApplication::allWidgets();
        for (QWidget *widget : widgets) {
            widget->update();
            if (widget->inherits("DolphinView")) {
                QMetaObject::invokeMethod(widget, "reload", Qt::QueuedConnection);
            }
        }
    }

    QFileSystemWatcher m_watcher;
    QString m_conf;
    QString m_qssPath;
    QString m_icons;
    QByteArray m_qss;
    bool m_iconsReady = false;
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
            std::this_thread::sleep_for(std::chrono::milliseconds(25));
        }
    }).detach();
}
