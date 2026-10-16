// Compile with Qt6Widgets/KIconThemes and run with -platform offscreen.
// Include the real hook to exercise the same font/layout code as Dolphin.
#include "../dolphin/live.cpp"
#include <QSettings>
#include <cstdio>
#include <cstdlib>

static void check(bool ok, const char *message)
{
    if (!ok) {
        std::fprintf(stderr, "FAIL: %s\n", message);
        std::exit(1);
    }
}

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    const QFont expected = imperiumFont();
    check(expected.weight() == QFont::Normal && expected.pointSize() == 10,
          "hook font must be Normal at 10 points");
    // Pass an isolated generated home as the first remaining argument.
    check(argc > 1, "expected generated home argument");
    const QString home = QString::fromLocal8Bit(argv[1]);
    for (const auto &entry : {
             qMakePair(QStringLiteral("/.config/qt6ct/qt6ct.conf"), QStringLiteral("Fonts/general")),
             qMakePair(QStringLiteral("/.config/qt6ct/qt6ct.conf"), QStringLiteral("Fonts/fixed")),
             qMakePair(QStringLiteral("/.config/kdeglobals"), QStringLiteral("General/font")),
             qMakePair(QStringLiteral("/.config/kdeglobals"), QStringLiteral("General/toolBarFont")),
             qMakePair(QStringLiteral("/.local/share/konsole/Imperium.profile"), QStringLiteral("Appearance/Font")),
         }) {
        QSettings settings(home + entry.first, QSettings::IniFormat);
        // QSettings reserves [General] for root keys; KConfig uses it as a
        // named group. Account for that when reading the KDE font settings.
        const QString key = entry.second.startsWith(QLatin1String("General/"))
            ? entry.second.mid(8) : entry.second;
        const QVariant value = settings.value(key);
        // KConfig stores fonts as unquoted comma-separated strings. QSettings
        // interprets those as lists; rejoin to test what KConfig passes to Qt.
        const QString serialized = value.metaType().id() == QMetaType::QStringList
            ? value.toStringList().join(QLatin1Char(',')) : value.toString();
        QFont decoded;
        check(decoded.fromString(serialized), "generated font string is invalid");
        check(decoded.family() == expected.family() && decoded.styleName() == expected.styleName()
                  && decoded.weight() == expected.weight() && decoded.pointSize() == expected.pointSize(),
              "generated font differs from the hook's font");
    }

    QMainWindow window;
    window.setCentralWidget(new QWidget);
    const auto add = [&window](const char *name, Qt::DockWidgetArea area) {
        auto *dock = new QDockWidget(QString::fromLatin1(name), &window);
        dock->setObjectName(QString::fromLatin1(name));
        dock->setWidget(new QWidget);
        window.addDockWidget(area, dock);
        return dock;
    };
    auto *folders = add("foldersDock", Qt::LeftDockWidgetArea);
    auto *places = add("placesDock", Qt::LeftDockWidgetArea);
    window.splitDockWidget(folders, places, Qt::Vertical);
    auto *info = add("infoDock", Qt::LeftDockWidgetArea);
    auto *terminal = add("terminalDock", Qt::RightDockWidgetArea);
    window.resize(1000, 800);
    window.show();
    app.processEvents();
    check(places->y() > folders->y(), "fixture does not reproduce Places below Folders");
    info->hide();
    applyInitialPanelLayout(&window);
    app.processEvents();
    check(places->y() < folders->y(), "Places was not moved above Folders");
    check(window.dockWidgetArea(info) == Qt::RightDockWidgetArea, "Information is not on the right");
    check(window.dockWidgetArea(terminal) == Qt::BottomDockWidgetArea, "Terminal is not at the bottom");
    check(info->isHidden(), "layout reset changed hidden panel visibility");
    window.addDockWidget(Qt::RightDockWidgetArea, places);
    applyInitialPanelLayout(&window);
    check(window.dockWidgetArea(places) == Qt::RightDockWidgetArea, "layout reset repeated within the same window");
    std::puts("PASS: Qt parses matching Regular fonts and repairs Places below Folders without changing visibility");
}
