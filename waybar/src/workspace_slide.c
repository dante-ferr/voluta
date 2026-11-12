/* Paint a single moving selection behind Waybar's existing workspace buttons.
 * No allocation, padding or label is moved. CSS retains a static fallback when
 * this helper is unavailable. GTK frame times also handle interrupted moves.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <math.h>
#include <gtk/gtk.h>
#include <string.h>

typedef struct {
    double x, width, to_x, to_width;
    gint64 last_frame;
    gboolean ready;
    double opacity;
} Selection;

static gboolean advance(Selection *s, gint64 now) {
    /* Exponential, frame-time-scaled lerp keeps the selection moving at a
     * proportional rate and makes interrupted moves continue smoothly. */
    double dt = CLAMP((now - s->last_frame) / 1000000.0, 0.0, 0.1);
    /* A 120 ms time constant takes about 360 ms to settle while preserving
     * the quick-start, slow-finish glide. */
    double amount = 1.0 - exp(-dt / 0.12);
    s->last_frame = now;
    s->x += (s->to_x - s->x) * amount;
    s->width += (s->to_width - s->width) * amount;
    s->opacity += (1.0 - s->opacity) * amount;
    if (fabs(s->to_x - s->x) < 0.15 && fabs(s->to_width - s->width) < 0.15) {
        s->x = s->to_x;
        s->width = s->to_width;
        s->opacity = 1.0;
        return FALSE;
    }
    return TRUE;
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
            s->x = s->to_x = x;
            s->width = s->to_width = width;
            s->last_frame = now;
            s->ready = TRUE;
            s->opacity = 1.0;
            gtk_widget_queue_draw(box);
        } else {
            gboolean target_changed = s->to_x != x || s->to_width != width;
            if (target_changed) {
                s->to_x = x;
                s->to_width = width;
            }
            if (advance(s, now) || target_changed)
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
        gtk_style_context_lookup_color(style, "workspace-accent", &accent);
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
        /* Paint the soft exterior halo before the border and its lighting. */
        GdkRGBA accent = {0.7, 0.5, 0.2, 1.0};
        gtk_style_context_lookup_color(style, "workspace-accent", &accent);
        cairo_save(cr);
        for (int radius = 5; radius >= 1; --radius) {
            cairo_set_source_rgba(cr, accent.red, accent.green, accent.blue,
                                  accent.alpha * s->opacity * 0.05);
            cairo_set_line_width(cr, radius * 2.0);
            cairo_rectangle(cr, s->x + 1, margin.top + 2, s->width - 2, height - 4);
            cairo_stroke(cr);
        }
        cairo_restore(cr);
        /* Restore a solid black border over the exterior halo, then let light
         * from the filled interior spill onto its inner edge. The outer edge
         * stays black; there is no separate bright outline. */
        cairo_set_source_rgba(cr, 0, 0, 0, s->opacity);
        cairo_set_line_width(cr, 2);
        cairo_rectangle(cr, s->x + 1, margin.top + 2, s->width - 2, height - 4);
        cairo_stroke(cr);

        double left = s->x, top = margin.top + 1;
        double right = left + s->width, bottom = top + height - 2;
        const double edges[4][8] = {
            {left, top, left + 2, top, left, top, 2, height - 2},
            {right, top, right - 2, top, right - 2, top, 2, height - 2},
            {left, top, left, top + 2, left + 2, top, s->width - 4, 2},
            {left, bottom, left, bottom - 2, left + 2, bottom - 2, s->width - 4, 2},
        };
        for (int side = 0; side < 4; ++side) {
            const double *e = edges[side];
            cairo_pattern_t *light = cairo_pattern_create_linear(e[0], e[1], e[2], e[3]);
            cairo_pattern_add_color_stop_rgba(light, 0, accent.red, accent.green, accent.blue, 0);
            cairo_pattern_add_color_stop_rgba(light, 1, accent.red, accent.green, accent.blue,
                                             accent.alpha * s->opacity * 0.45);
            cairo_set_source(cr, light);
            cairo_rectangle(cr, e[4], e[5], e[6], e[7]);
            cairo_fill(cr);
            cairo_pattern_destroy(light);
        }
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

void voluta_glow_clusters_publish(void);
void voluta_clock_swap_scan(void);
void voluta_label_cap_install(void);
void voluta_label_cap_scan(void);

static gboolean discover_workspaces(gpointer unused) {
    (void)unused;
    GList *windows = gtk_window_list_toplevels();
    for (GList *it = windows; it; it = it->next)
        attach_selection(it->data, NULL);
    g_list_free(windows);
    /* Same tick publishes module cluster geometry for the top glow mask. */
    voluta_glow_clusters_publish();
    voluta_clock_swap_scan();
    voluta_label_cap_scan();
    return G_SOURCE_CONTINUE;
}

/* Waybar uses Gtk::Application. Register after GTK initialization, on its main
 * thread; scanning also attaches new bars after monitor changes or a reload. */
int g_application_run(GApplication *application, int argc, char **argv) {
    int (*real_run)(GApplication *, int, char **) =
        dlsym(RTLD_NEXT, "g_application_run");
    if (!GTK_IS_APPLICATION(application))
        return real_run(application, argc, argv);
    /* Before any module measures itself, or the first layout already
     * locks in the taller line from an icon or an emoji. */
    voluta_label_cap_install();
    guint scan = g_timeout_add(200, discover_workspaces, NULL);
    int status = real_run(application, argc, argv);
    g_source_remove(scan);
    return status;
}
