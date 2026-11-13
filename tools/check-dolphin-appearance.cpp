// Compile with Qt6Widgets/KIconThemes and run with -platform offscreen.
// Include the real hook to exercise the same font/layout code as Dolphin.
#include "../dolphin/live.cpp"
#include <QSettings>
#include <QTextEdit>
#include <QTextDocument>
#include <QSaveFile>
#include <KFilePlacesView>
#include <KFilePlacesModel>
#include <cstdio>
#include <cstdlib>

// Match the inline editor's Qt class selector and zero document margin without
// depending on Dolphin's private headers. Its initial height is one text line.
class KItemListRoleEditor : public QTextEdit
{
    Q_OBJECT
public:
    using QTextEdit::QTextEdit;
};

class DolphinItemListView : public QGraphicsWidget
{
    Q_OBJECT
};

static void check(bool ok, const char *message)
{
    if (!ok) {
        std::fprintf(stderr, "FAIL: %s\n", message);
        std::exit(1);
    }
}

static void verifyLiveSelection(const QString &home)
{
    QCoreApplication::setApplicationName(QStringLiteral("dolphin"));
    QGraphicsScene scene;
    QGraphicsView view(&scene);
    KFilePlacesModel placesModel;
    KFilePlacesView places;
    places.setModel(&placesModel);
    places.resize(260, 500);
    places.show();
    auto *files = new DolphinItemListView;
    scene.addItem(files);
    view.show();
    LiveTheme hook(qApp);
    const auto read = [](const QString &path) {
        QFile file(path);
        check(file.open(QIODevice::ReadOnly), "cannot read live selection fixture");
        return file.readAll();
    };
    const auto write = [](const QString &path, const QByteArray &body) {
        QSaveFile file(path);
        check(file.open(QIODevice::WriteOnly) && file.write(body) == body.size() && file.commit(),
              "cannot replace live selection fixture");
    };
    const QString confPath = home + QStringLiteral("/.config/qt6ct/dolphin-live.conf");
    const QByteArray conf = read(confPath);
    const QString originalPath = qApp->property("KDE_COLOR_SCHEME_PATH").toString();
    const QByteArray scheme = read(originalPath);
    const QColor originalSelection = readScheme(originalPath).selectBg;
    const QString svgPath = home + QStringLiteral("/.config/wallust/assets/generated/kvantum-dolphin.svg");
    const QByteArray svg = read(svgPath);
    const auto render = [&] {
        QImage image(120, 32, QImage::Format_ARGB32_Premultiplied);
        image.fill(Qt::transparent);
        QPainter painter(&image);
        QStyleOptionViewItem option;
        option.rect = image.rect();
        option.palette = files->palette();
        option.state = QStyle::State_Enabled | QStyle::State_Selected | QStyle::State_Active;
        option.showDecorationSelected = true;
        scene.style()->drawPrimitive(QStyle::PE_PanelItemViewItem, &option, &painter, view.viewport());
        return image;
    };
    const auto renderPlace = [&] {
        QImage image(240, 96, QImage::Format_ARGB32_Premultiplied);
        image.fill(Qt::transparent);
        QPainter painter(&image);
        QStyleOptionViewItem option;
        option.initFrom(&places);
        option.rect = image.rect();
        option.state = QStyle::State_Enabled | QStyle::State_Selected | QStyle::State_Active;
        const QModelIndex index = placesModel.index(0, 0);
        check(index.isValid(), "Places fixture has no native model row");
        places.itemDelegateForIndex(index)->paint(&painter, option, index);
        return image;
    };
    QImage previous = render();
    QImage previousPlace = renderPlace();
    int generation = 0;
    for (const QColor &selection : {QColor(210, 70, 95), QColor(60, 180, 140)}) {
        QByteArray nextSvg = svg;
        nextSvg.replace(originalSelection.name().toUtf8(), selection.name().toUtf8());
        write(svgPath, nextSvg);
        // Kvantum versions may select the general theme by executable name
        // rather than applicationName in this offscreen test binary.
        write(home + QStringLiteral("/.config/wallust/assets/generated/kvantum-imperium.svg"), nextSvg);
        // Demonstrate why changing the on-disk theme alone is insufficient.
        check(render() == previous, "fixture did not reproduce Kvantum's cached selection artwork");
        check(renderPlace() == previousPlace, "fixture did not reproduce cached Places artwork");
        const QString nextPath = originalPath + QString::number(++generation);
        QByteArray nextScheme = scheme;
        const auto rgb = [](const QColor &color) {
            return QByteArray::number(color.red()) + ',' + QByteArray::number(color.green()) + ',' + QByteArray::number(color.blue());
        };
        nextScheme.replace(rgb(originalSelection), rgb(selection));
        write(nextPath, nextScheme);
        QByteArray nextConf = conf;
        nextConf.replace(originalPath.toUtf8(), nextPath.toUtf8());
        write(confPath, nextConf);
        QElapsedTimer wait;
        wait.start();
        while (qApp->property("KDE_COLOR_SCHEME_PATH").toString() != nextPath && wait.elapsed() < 3000) {
            QCoreApplication::processEvents();
        }
        check(qApp->property("KDE_COLOR_SCHEME_PATH").toString() == nextPath,
              "live watcher missed a consecutive atomic palette update");
        const QImage current = render();
        check(current != previous, "open file view retained the previous selection artwork");
        check(files->palette().color(QPalette::Highlight) == selection,
              "open file view retained the previous selection palette");
        const QImage currentPlace = renderPlace();
        check(currentPlace != previousPlace, "open Places sidebar retained the previous selection artwork");
        check(places.palette().color(QPalette::Highlight) == selection,
              "open Places sidebar retained the previous selection palette");
        previousPlace = currentPlace;
        previous = current;
    }
}

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    const QFont expectedUi = imperiumFont();
    QFont expectedMono(QStringLiteral("Monaspace Argon"), 10, QFont::Normal);
    expectedMono.setStyleName(QStringLiteral("Regular"));
    check(expectedUi.weight() == QFont::Normal && expectedUi.pointSize() == 11,
          "hook font must be Normal at 11 points");
    // Pass an isolated generated home as the first remaining argument.
    check(argc > 1, "expected generated home argument");
    const QString home = QString::fromLocal8Bit(argv[1]);
    QFile stylesheet(home + QStringLiteral("/.config/qt6ct/qss/imperium.qss"));
    check(stylesheet.open(QIODevice::ReadOnly), "cannot read generated stylesheet");
    app.setStyleSheet(QString::fromUtf8(stylesheet.readAll()));
    KItemListRoleEditor renameEditor;
    app.setFont(expectedUi);
    renameEditor.setFont(expectedUi);
    renameEditor.document()->setDocumentMargin(0);
    renameEditor.setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    renameEditor.setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    renameEditor.setPlainText(QStringLiteral("arquivo.txt"));
    // The initial file-label rectangle has room for a line and a thin border;
    // it must remain readable before textChanged expands the editor.
    renameEditor.resize(240, renameEditor.fontMetrics().height() + 2);
    renameEditor.selectAll();
    renameEditor.show();
    app.processEvents();
    check(renameEditor.viewport()->height() >= renameEditor.fontMetrics().height(),
          "F2 editor clips the initial filename before typing");
    renameEditor.hide();
    app.setStyleSheet({});
    for (const auto &entry : {
             qMakePair(QStringLiteral("/.config/qt6ct/qt6ct.conf"),
                       qMakePair(QStringLiteral("Fonts/general"), expectedUi)),
             qMakePair(QStringLiteral("/.config/qt6ct/qt6ct.conf"),
                       qMakePair(QStringLiteral("Fonts/fixed"), expectedMono)),
             qMakePair(QStringLiteral("/.config/kdeglobals"),
                       qMakePair(QStringLiteral("General/font"), expectedUi)),
             qMakePair(QStringLiteral("/.config/kdeglobals"),
                       qMakePair(QStringLiteral("General/toolBarFont"), expectedUi)),
             qMakePair(QStringLiteral("/.local/share/konsole/Imperium.profile"),
                       qMakePair(QStringLiteral("Appearance/Font"), expectedMono)),
         }) {
        QSettings settings(home + entry.first, QSettings::IniFormat);
        // QSettings reserves [General] for root keys; KConfig uses it as a
        // named group. Account for that when reading the KDE font settings.
        const QString key = entry.second.first.startsWith(QLatin1String("General/"))
            ? entry.second.first.mid(8) : entry.second.first;
        const QFont &expected = entry.second.second;
        const QVariant value = settings.value(key);
        // KConfig stores fonts as unquoted comma-separated strings. QSettings
        // interprets those as lists; rejoin to test what KConfig passes to Qt.
        const QString serialized = value.metaType().id() == QMetaType::QStringList
            ? value.toStringList().join(QLatin1Char(',')) : value.toString();
        QFont decoded;
        check(decoded.fromString(serialized), "generated font string is invalid");
        check(decoded.family() == expected.family() && decoded.styleName() == expected.styleName()
                  && decoded.weight() == expected.weight() && decoded.pointSize() == expected.pointSize(),
              "generated font differs from the expected UI or mono font");
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
    QImageReader artwork(home + QStringLiteral("/.config/wallust/assets/generated/big-corner-tl.svg"));
    check(!artwork.read().isNull(), "Qt cannot render the shared corner SVG");
    check(!headingOrnament(1.0).isNull(), "Qt cannot render the shared heading ornament SVG");
    const QRect heading(6, 4, 220, 24);
    const QRect ornament = headingOrnamentRect(heading, 72);
    check(!ornament.isEmpty() && heading.contains(ornament)
              && ornament.left() >= heading.left() + 72 + 18,
          "heading ornament overlaps its label or panel edge");
    check(headingOrnamentRect(QRect(0, 0, 140, 24), 72).isEmpty(),
          "narrow headings must omit artwork instead of covering text");
    auto *frame = new CornerFrame(&window);
    frame->refresh();
    check(frame->testAttribute(Qt::WA_TransparentForMouseEvents)
              && frame->focusPolicy() == Qt::NoFocus,
          "corner artwork can intercept file interactions");
    window.resize(1100, 850);
    app.processEvents();
    check(frame->geometry() == window.rect(), "corner frame did not follow window resizing");
    verifyLiveSelection(home);
    std::puts("PASS: Qt fonts, F2 editor, panel layout, and consecutive live selection repaints");
}

#include "check-dolphin-appearance.moc"
