/* Paint a single moving selection behind Waybar's existing workspace buttons.
 * No allocation, padding or label is moved. CSS retains a static fallback when
 * this helper is unavailable. GTK frame times also handle interrupted moves.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <gtk/gtk.h>
#include <string.h>

typedef struct {
    double x, width, from_x, from_width, to_x, to_width;
    gint64 started;
    gboolean ready;
    double opacity, from_opacity;
} Selection;

static void advance(Selection *s, gint64 now) {
    double t = CLAMP((now - s->started) / 280000.0, 0.0, 1.0);
    double ease = t * t * (3.0 - 2.0 * t);
    s->x = s->from_x + (s->to_x - s->from_x) * ease;
    s->width = s->from_width + (s->to_width - s->from_width) * ease;
    double edge = t < 0.5 ? 1.0 - 2.0 * t : 2.0 * t - 1.0;
    s->opacity = 0.5 + 0.5 * edge * edge * (3.0 - 2.0 * edge);
    if (t < 0.5)
        s->opacity = 0.5 + (s->from_opacity - 0.5) * edge * edge * (3.0 - 2.0 * edge);
}

static gboolean selection_tick(GtkWidget *box, GdkFrameClock *clock, gpointer data) {
    Selection *s = data;
    gint64 now = gdk_frame_clock_get_frame_time(clock);
    GList *children = gtk_container_get_children(GTK_CONTAINER(box));
    GtkWidget *active = NULL;
    for (GList *it = children; it; it = it->next) {
        GtkWidget *child = it->data;
        if (gtk_widget_get_visible(child) &&
            gtk_style_context_has_class(gtk_widget_get_style_context(child), "active")) {
            active = child;
            break;
        }
    }
    if (active) {
        gint x = 0, y = 0;
        gtk_widget_translate_coordinates(active, box, 0, 0, &x, &y);
        double width = gtk_widget_get_allocated_width(active);
        if (!s->ready) {
            s->x = s->from_x = s->to_x = x;
            s->width = s->from_width = s->to_width = width;
            s->started = now - 280000;
            s->ready = TRUE;
            s->opacity = s->from_opacity = 1.0;
            gtk_widget_queue_draw(box);
        } else {
            advance(s, now);
            if (s->to_x != x || s->to_width != width) {
                s->from_x = s->x;
                s->from_width = s->width;
                s->to_x = x;
                s->to_width = width;
                s->from_opacity = s->opacity;
                s->started = now;
            }
            /* Include the last frame, so the outline reaches its exact target. */
            if (now - s->started <= 320000)
                gtk_widget_queue_draw(box);
        }
    } else if (s->ready) {
        s->ready = FALSE;
        gtk_widget_queue_draw(box);
    }
    g_list_free(children);
    return G_SOURCE_CONTINUE;
}

static gboolean selection_draw(GtkWidget *box, cairo_t *cr, gpointer data) {
    Selection *s = data;
    GtkStyleContext *style = gtk_widget_get_style_context(box);
    double width = gtk_widget_get_allocated_width(box);
    double height = gtk_widget_get_allocated_height(box);
    /* Allocations include CSS margins; GTK's normal drawing excludes them. */
    GtkBorder margin;
    gtk_style_context_get_margin(style, gtk_style_context_get_state(style), &margin);
    width -= margin.left + margin.right;
    height -= margin.top + margin.bottom;
    gtk_render_background(style, cr, margin.left, margin.top, width, height);
    gtk_render_frame(style, cr, margin.left, margin.top, width, height);

    if (s->ready) {
        GdkRGBA accent = {0.7, 0.5, 0.2, 1.0};
        gtk_style_context_lookup_color(style, "color1", &accent);
        accent.alpha *= s->opacity;
        gdk_cairo_set_source_rgba(cr, &accent);
        cairo_rectangle(cr, s->x, margin.top + 1, s->width, height - 2);
        cairo_fill(cr);
    }

    GList *children = gtk_container_get_children(GTK_CONTAINER(box));
    for (GList *it = children; it; it = it->next)
        gtk_container_propagate_draw(GTK_CONTAINER(box), it->data, cr);
    g_list_free(children);

    if (s->ready && s->width > 2 && height > 4) {
        cairo_set_source_rgba(cr, 0, 0, 0, s->opacity);
        cairo_set_line_width(cr, 2);
        cairo_rectangle(cr, s->x + 1, margin.top + 2, s->width - 2, height - 4);
        cairo_stroke(cr);
    }
    /* We have painted the container and its children in the required order. */
    return TRUE;
}

static void attach_selection(GtkWidget *widget, gpointer unused) {
    (void)unused;
    if (GTK_IS_BOX(widget) && !strcmp(gtk_widget_get_name(widget), "workspaces") &&
        !g_object_get_data(G_OBJECT(widget), "imperium-selection")) {
        Selection *s = g_new0(Selection, 1);
        g_object_set_data_full(G_OBJECT(widget), "imperium-selection", s, g_free);
        gtk_style_context_add_class(gtk_widget_get_style_context(widget), "sliding-selection");
        g_signal_connect(widget, "draw", G_CALLBACK(selection_draw), s);
        gtk_widget_add_tick_callback(widget, selection_tick, s, NULL);
    }
    if (GTK_IS_CONTAINER(widget))
        gtk_container_foreach(GTK_CONTAINER(widget), attach_selection, NULL);
}

static gboolean discover_workspaces(gpointer unused) {
    (void)unused;
    GList *windows = gtk_window_list_toplevels();
    for (GList *it = windows; it; it = it->next)
        attach_selection(it->data, NULL);
    g_list_free(windows);
    return G_SOURCE_CONTINUE;
}

/* Waybar uses Gtk::Application. Register after GTK initialization, on its main
 * thread; scanning also attaches new bars after monitor changes or a reload. */
int g_application_run(GApplication *application, int argc, char **argv) {
    int (*real_run)(GApplication *, int, char **) =
        dlsym(RTLD_NEXT, "g_application_run");
    if (!GTK_IS_APPLICATION(application))
        return real_run(application, argc, argv);
    guint scan = g_timeout_add(200, discover_workspaces, NULL);
    int status = real_run(application, argc, argv);
    g_source_remove(scan);
    return status;
}
