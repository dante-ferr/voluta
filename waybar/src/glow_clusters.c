/* Publish Waybar module-cluster geometry for the top glow mask.
 * Runs on the existing 200 ms discovery tick from workspace_slide.c.
 * Writes only when the measured clusters change, so battery idle stays quiet.
 *
 * Waybar names module widgets (window, clock, …) but the left/center/right
 * packing boxes only carry CSS classes modules-left / modules-center /
 * modules-right. Fall back to the three direct child boxes under the bar.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <gtk/gtk.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

typedef struct {
    int x;
    int width;
    gboolean ok;
} Cluster;

static char last_payload[2048];

static gboolean has_class(GtkWidget *widget, const char *class_name) {
    return gtk_style_context_has_class(gtk_widget_get_style_context(widget), class_name);
}

static gboolean find_class(GtkWidget *widget, const char *class_name, GtkWidget **out) {
    if (has_class(widget, class_name)) {
        *out = widget;
        return TRUE;
    }
    if (!GTK_IS_CONTAINER(widget))
        return FALSE;
    GList *children = gtk_container_get_children(GTK_CONTAINER(widget));
    for (GList *it = children; it; it = it->next) {
        if (find_class(it->data, class_name, out)) {
            g_list_free(children);
            return TRUE;
        }
    }
    g_list_free(children);
    return FALSE;
}

static void fill_cluster(GtkWidget *bar, GtkWidget *box, Cluster *out) {
    out->ok = FALSE;
    out->x = 0;
    out->width = 0;
    if (!box || !gtk_widget_get_mapped(box))
        return;
    int width = gtk_widget_get_allocated_width(box);
    if (width <= 1)
        return;
    int x = 0, y = 0;
    if (!gtk_widget_translate_coordinates(box, bar, 0, 0, &x, &y))
        return;
    out->x = x;
    out->width = width;
    out->ok = TRUE;
}

static void measure_cluster(GtkWidget *bar, const char *class_name, Cluster *out) {
    GtkWidget *box = NULL;
    out->ok = FALSE;
    if (!find_class(bar, class_name, &box))
        return;
    fill_cluster(bar, box, out);
}

/* Fallback when CSS classes are missing: the bar's root box packs three children. */
static void measure_clusters_fallback(GtkWidget *bar, Cluster *left, Cluster *center,
                                      Cluster *right) {
    if (!GTK_IS_CONTAINER(bar))
        return;
    GList *roots = gtk_container_get_children(GTK_CONTAINER(bar));
    GtkWidget *root = NULL;
    for (GList *it = roots; it; it = it->next) {
        if (GTK_IS_BOX(it->data)) {
            root = it->data;
            break;
        }
    }
    g_list_free(roots);
    if (!root)
        return;

    GList *children = gtk_container_get_children(GTK_CONTAINER(root));
    GtkWidget *boxes[3] = {0};
    int count = 0;
    for (GList *it = children; it && count < 3; it = it->next) {
        if (GTK_IS_BOX(it->data) && gtk_widget_get_mapped(it->data))
            boxes[count++] = it->data;
    }
    g_list_free(children);
    if (count >= 1)
        fill_cluster(bar, boxes[0], left);
    if (count >= 2)
        fill_cluster(bar, boxes[1], center);
    if (count >= 3)
        fill_cluster(bar, boxes[2], right);
}

static void clusters_path(char *buf, size_t n) {
    const char *config = getenv("XDG_CONFIG_HOME");
    if (config && *config) {
        snprintf(buf, n, "%s/waybar/wallust/glow-clusters.json", config);
        return;
    }
    const char *home = getenv("HOME");
    snprintf(buf, n, "%s/.config/waybar/wallust/glow-clusters.json",
             home && *home ? home : ".");
}

static void append_cluster(char *buf, size_t n, size_t *used, const Cluster *cluster,
                           gboolean *first) {
    if (!cluster->ok)
        return;
    int written = snprintf(buf + *used, n - *used,
                           "%s{\"x\":%d,\"width\":%d}",
                           *first ? "" : ",", cluster->x, cluster->width);
    if (written < 0 || (size_t)written >= n - *used)
        return;
    *used += (size_t)written;
    *first = FALSE;
}

static gboolean publish_bar(GtkWidget *bar, char *buf, size_t n, size_t *used,
                            gboolean *first_bar) {
    if (!GTK_IS_WINDOW(bar) || !gtk_widget_get_mapped(bar))
        return FALSE;
    const char *name = gtk_widget_get_name(bar);
    if (!name || strcmp(name, "waybar") != 0)
        return FALSE;

    Cluster left = {0}, center = {0}, right = {0};
    measure_cluster(bar, "modules-left", &left);
    measure_cluster(bar, "modules-center", &center);
    measure_cluster(bar, "modules-right", &right);
    if (!left.ok && !center.ok && !right.ok)
        measure_clusters_fallback(bar, &left, &center, &right);
    if (!left.ok && !center.ok && !right.ok)
        return FALSE;

    GdkWindow *gdk_window = gtk_widget_get_window(bar);
    if (!gdk_window)
        return FALSE;
    /* Layer-shell surfaces often report origin 0,0; use the monitor geometry
     * so Quickshell can match ShellScreen.x/y/width. */
    int origin_x = 0, origin_y = 0, width = 0;
    GdkDisplay *display = gtk_widget_get_display(bar);
    GdkMonitor *monitor = display ? gdk_display_get_monitor_at_window(display, gdk_window)
                                  : NULL;
    if (monitor) {
        GdkRectangle geometry;
        gdk_monitor_get_geometry(monitor, &geometry);
        origin_x = geometry.x;
        origin_y = geometry.y;
        width = geometry.width;
    }
    if (width <= 1)
        width = gdk_window_get_width(gdk_window);
    if (width <= 1)
        width = gtk_widget_get_allocated_width(bar);
    if (width <= 1)
        return FALSE;

    int written = snprintf(buf + *used, n - *used,
                           "%s{\"x\":%d,\"y\":%d,\"width\":%d,\"clusters\":[",
                           *first_bar ? "" : ",", origin_x, origin_y, width);
    if (written < 0 || (size_t)written >= n - *used)
        return FALSE;
    *used += (size_t)written;

    gboolean first_cluster = TRUE;
    append_cluster(buf, n, used, &left, &first_cluster);
    append_cluster(buf, n, used, &center, &first_cluster);
    append_cluster(buf, n, used, &right, &first_cluster);

    written = snprintf(buf + *used, n - *used, "]}");
    if (written < 0 || (size_t)written >= n - *used)
        return FALSE;
    *used += (size_t)written;
    *first_bar = FALSE;
    return TRUE;
}

void voluta_glow_clusters_publish(void) {
    char payload[sizeof(last_payload)];
    size_t used = 0;
    int written = snprintf(payload, sizeof(payload), "{\"bars\":[");
    if (written < 0)
        return;
    used = (size_t)written;

    gboolean first_bar = TRUE;
    GList *windows = gtk_window_list_toplevels();
    for (GList *it = windows; it; it = it->next)
        publish_bar(it->data, payload, sizeof(payload), &used, &first_bar);
    g_list_free(windows);

    written = snprintf(payload + used, sizeof(payload) - used, "]}\n");
    if (written < 0 || (size_t)written >= sizeof(payload) - used)
        return;
    used += (size_t)written;

    if (!strcmp(payload, last_payload))
        return;

    char path[512];
    char tmp[544];
    clusters_path(path, sizeof(path));
    snprintf(tmp, sizeof(tmp), "%s.tmp", path);

    FILE *file = fopen(tmp, "w");
    if (!file)
        return;
    if (fwrite(payload, 1, used, file) != used) {
        fclose(file);
        unlink(tmp);
        return;
    }
    if (fclose(file) != 0) {
        unlink(tmp);
        return;
    }
    if (rename(tmp, path) != 0) {
        unlink(tmp);
        return;
    }
    memcpy(last_payload, payload, used + 1);
}
