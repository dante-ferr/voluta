/* One wallpaper-based decision for every decoration on a bar. Both the bar
 * and wallpaper rectangles come from Hyprland, in the same coordinate space.
 * Queries are asynchronous; static geometry is never resampled. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <gtk/gtk.h>
#include <json-glib/json-glib.h>
#include <math.h>
#include <string.h>
#include <unistd.h>

typedef struct { double x, y, width, height; } Region;
static const char *variants[] = {"dark", "light", "bright"};
static GKeyFile *cache;
static GHashTable *images;
static double dark_luminance = .02, dark_coverage = .7;
static GSubprocess *pending;
static gint64 last_query;
static JsonNode *layers;

static double luminance(double r, double g, double b) {
    double values[] = {r, g, b};
    for (int i = 0; i < 3; i++)
        values[i] = values[i] <= .04045 ? values[i] / 12.92
            : pow((values[i] + .055) / 1.055, 2.4);
    return .2126 * values[0] + .7152 * values[1] + .0722 * values[2];
}

static double contrast(double a, double b) {
    return (MAX(a, b) + .05) / (MIN(a, b) + .05);
}

static int choose_variant(const double score[4], int previous) {
    /* Retain the user's strict darkness threshold; use the entire bar strip. */
    if (score[3] < dark_coverage - (previous > 0 ? .15 : 0)) return 0;
    double adequate = previous == 2 ? 3.3 : (previous == 1 ? 2.7 : 3.0);
    int selected = score[1] >= adequate ? 1 : (score[2] > score[1] ? 2 : 1);
    if (score[0] > score[selected] * 1.15) selected = 0;
    if (previous >= 0 && (previous == 0 || selected == 0) &&
        score[previous] > 0 && score[selected] < score[previous] * 1.12)
        selected = previous;
    return selected;
}

static gboolean read_region(JsonObject *object, Region *region) {
    const char *names[] = {"x", "y", "w", "h"};
    double values[4];
    for (int i = 0; i < 4; i++) {
        if (!json_object_has_member(object, names[i])) return FALSE;
        values[i] = json_object_get_double_member(object, names[i]);
        if (!isfinite(values[i])) return FALSE;
    }
    *region = (Region){values[0], values[1], values[2], values[3]};
    return region->width > 0 && region->height > 0;
}

static gboolean layer_regions(JsonNode *root, const char *output, const char *namespace,
                              int pid, Region *bar, Region *wallpaper) {
    if (!root || !output || !namespace || !JSON_NODE_HOLDS_OBJECT(root)) return FALSE;
    JsonObject *outputs = json_node_get_object(root);
    if (!json_object_has_member(outputs, output)) return FALSE;
    JsonObject *monitor = json_object_get_object_member(outputs, output);
    if (!monitor || !json_object_has_member(monitor, "levels")) return FALSE;
    JsonObject *levels = json_object_get_object_member(monitor, "levels");
    int bars = 0, backgrounds = 0;
    for (int level = 0; level < 4; level++) {
        char key[] = {(char)('0' + level), 0};
        if (!json_object_has_member(levels, key)) continue;
        JsonArray *array = json_object_get_array_member(levels, key);
        if (!array) continue;
        for (guint i = 0; i < json_array_get_length(array); i++) {
            JsonObject *layer = json_array_get_object_element(array, i);
            if (!layer || !json_object_has_member(layer, "namespace")) continue;
            const char *name = json_object_get_string_member(layer, "namespace");
            if (g_strcmp0(name, "waybar") == 0 && json_object_has_member(layer, "pid") &&
                json_object_get_int_member(layer, "pid") == pid && read_region(layer, bar)) bars++;
            if (g_strcmp0(name, namespace) == 0 && read_region(layer, wallpaper)) backgrounds++;
        }
    }
    /* Ambiguous or missing compositor geometry must not select the wrong area. */
    return bars == 1 && backgrounds == 1;
}

static Region image_region(Region bar, Region wallpaper, int width, int height) {
    double sx = width / wallpaper.width, sy = height / wallpaper.height;
    return (Region){(bar.x - wallpaper.x) * sx, (bar.y - wallpaper.y) * sy,
                    bar.width * sx, bar.height * sy};
}

/* Every native pixel in the bar strip contributes, including areas between
 * icons and underneath plates. Fractional edge pixels use their covered area.
 * Harmonic contrast avoids averaging away poorly contrasted colors. */
static void scores(GdkPixbuf *image, Region area, const double ink[3], double result[4]) {
    memset(result, 0, 4 * sizeof(double));
    if (!image || area.width <= 0 || area.height <= 0) return;
    double left = MAX(0, area.x), top = MAX(0, area.y);
    double right = MIN(gdk_pixbuf_get_width(image), area.x + area.width);
    double bottom = MIN(gdk_pixbuf_get_height(image), area.y + area.height);
    double weight = 0, dark_weight = 0, inverse[3] = {0};
    int channels = gdk_pixbuf_get_n_channels(image), stride = gdk_pixbuf_get_rowstride(image);
    const guchar *pixels = gdk_pixbuf_get_pixels(image);
    for (int y = floor(top); y < ceil(bottom); y++) {
        for (int x = floor(left); x < ceil(right); x++) {
            const guchar *p = pixels + y * stride + x * channels;
            double base = luminance(p[0] / 255., p[1] / 255., p[2] / 255.);
            double coverage = (MIN(x + 1., right) - MAX(x, left)) *
                              (MIN(y + 1., bottom) - MAX(y, top));
            weight += coverage;
            if (base <= dark_luminance) dark_weight += coverage;
            for (int v = 0; v < 3; v++) inverse[v] += coverage / contrast(ink[v], base);
        }
    }
    for (int v = 0; v < 3; v++) result[v] = weight ? weight / inverse[v] : 0;
    result[3] = weight ? dark_weight / weight : 0;
}

static void query_finished(GObject *object, GAsyncResult *result, gpointer unused) {
    (void)unused;
    char *output = NULL;
    if (g_subprocess_communicate_utf8_finish(G_SUBPROCESS(object), result, &output, NULL, NULL) &&
        g_subprocess_get_successful(G_SUBPROCESS(object))) {
        JsonParser *parser = json_parser_new();
        if (output && json_parser_load_from_data(parser, output, -1, NULL)) {
            if (layers) json_node_free(layers);
            layers = json_node_copy(json_parser_get_root(parser));
        }
        g_object_unref(parser);
    }
    g_free(output);
    g_clear_object(&pending);
}

static void sample_bar(GtkWidget *window) {
    if (!gtk_widget_get_mapped(window)) return;
    GdkMonitor *(*layer_monitor)(GtkWindow *) = dlsym(RTLD_DEFAULT, "gtk_layer_get_monitor");
    GdkMonitor *monitor = layer_monitor ? layer_monitor(GTK_WINDOW(window)) : NULL;
    if (!monitor) monitor = gdk_display_get_monitor_at_window(
        gtk_widget_get_display(window), gtk_widget_get_window(window));
    if (!monitor) return;
    GdkRectangle geometry;
    gdk_monitor_get_geometry(monitor, &geometry);
    char *key = g_strdup_printf("monitor:%d:%d:%d:%d", geometry.x, geometry.y,
                                geometry.width, geometry.height);
    char *output = g_key_file_get_string(cache, key, "output", NULL);
    char *namespace = g_key_file_get_string(cache, key, "namespace", NULL);
    char *path = g_key_file_get_string(cache, key, "image", NULL);
    Region bar, wallpaper;
    if (!layer_regions(layers, output, namespace, getpid(), &bar, &wallpaper)) {
        g_free(key); g_free(output); g_free(namespace); g_free(path);
        return;
    }
    char *signature = g_strdup_printf("%s:%s:%.3f:%.3f:%.3f:%.3f:%.3f:%.3f:%.3f:%.3f",
        key, path ? path : "", bar.x, bar.y, bar.width, bar.height,
        wallpaper.x, wallpaper.y, wallpaper.width, wallpaper.height);
    const char *last = g_object_get_data(G_OBJECT(window), "decoration-sample");
    if (g_strcmp0(last, signature) == 0) { g_free(signature); goto done; }
    g_object_set_data_full(G_OBJECT(window), "decoration-sample", signature, g_free);
    GdkPixbuf *image = path ? g_hash_table_lookup(images, path) : NULL;
    if (!image && path) {
        image = gdk_pixbuf_new_from_file(path, NULL);
        if (image) g_hash_table_insert(images, g_strdup(path), image);
    }
    if (!image) goto done;
    Region area = image_region(bar, wallpaper, gdk_pixbuf_get_width(image), gdk_pixbuf_get_height(image));
    GtkStyleContext *style = gtk_widget_get_style_context(window);
    GdkRGBA color[3] = {{0}};
    gtk_style_context_lookup_color(style, "box-background", &color[0]);
    gtk_style_context_lookup_color(style, "decoration-light", &color[1]);
    gtk_style_context_lookup_color(style, "decoration-bright", &color[2]);
    double ink[3], score[4];
    for (int v = 0; v < 3; v++) ink[v] = luminance(color[v].red, color[v].green, color[v].blue);
    scores(image, area, ink, score);
    int previous = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(window), "decoration-variant")) - 1;
    int selected = choose_variant(score, previous);
    for (int v = 0; v < 3; v++) {
        char *name = g_strdup_printf("decoration-%s", variants[v]);
        if (v == selected) gtk_style_context_add_class(style, name);
        else gtk_style_context_remove_class(style, name);
        g_free(name);
    }
    g_object_set_data(G_OBJECT(window), "decoration-variant", GINT_TO_POINTER(selected + 1));
    if (g_getenv("WAYBAR_CONTRAST_DEBUG"))
        g_printerr("[decoration] %s all %s; wallpaper pixels %.2f,%.2f %.2fx%.2f; dark coverage %.1f%%\n",
                   output, variants[selected], area.x, area.y, area.width, area.height, score[3] * 100);
 done:
    g_free(key); g_free(output); g_free(namespace); g_free(path);
}

void update_decoration_contrast(GList *windows) {
    if (!cache) {
        cache = g_key_file_new();
        char *path = g_build_filename(g_get_user_config_dir(), "waybar", "wallust", "contrast.ini", NULL);
        g_key_file_load_from_file(cache, path, G_KEY_FILE_NONE, NULL);
        g_free(path);
        double threshold = g_key_file_get_double(cache, "contrast", "dark_luminance", NULL);
        if (threshold > 0 && threshold <= 1) dark_luminance = threshold;
        threshold = g_key_file_get_double(cache, "contrast", "dark_coverage", NULL);
        if (threshold > 0 && threshold <= 1) dark_coverage = threshold;
        images = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_object_unref);
    }
    gint64 now = g_get_monotonic_time();
    if (pending && now - last_query > 3 * G_USEC_PER_SEC) g_subprocess_force_exit(pending);
    if (!pending && now - last_query > 2 * G_USEC_PER_SEC) {
        last_query = now;
        pending = g_subprocess_new(G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_SILENCE,
                                  NULL, "hyprctl", "-j", "layers", NULL);
        if (pending) g_subprocess_communicate_utf8_async(pending, NULL, NULL, query_finished, NULL);
    }
    for (GList *it = windows; it; it = it->next)
        if (!strcmp(gtk_widget_get_name(it->data), "waybar")) sample_bar(it->data);
}
