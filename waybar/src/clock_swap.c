/* Stack the time and date clocks in one cell.
 * GtkBox cannot overlap its children, so this helper reparents the pair into
 * a GtkOverlay sized by the time. Hover slides the date down from above that
 * same cell while the time fades. Painting is clipped to the cell, so the
 * date never opens a second plate. */
#include <gtk/gtk.h>
#include <math.h>
#include <string.h>

typedef struct {
    GtkWidget *box;
    GtkWidget *overlay;
    GtkWidget *time;
    GtkWidget *date;
    double shown;
    double target;
    gint64 last_frame;
} ClockSwap;

static gboolean has_clock_class(GtkWidget *widget, const char *class_name) {
    if (!strcmp(gtk_widget_get_name(widget), "clock") &&
        gtk_style_context_has_class(gtk_widget_get_style_context(widget), class_name))
        return TRUE;
    if (!GTK_IS_CONTAINER(widget))
        return FALSE;
    gboolean found = FALSE;
    GList *children = gtk_container_get_children(GTK_CONTAINER(widget));
    for (GList *it = children; it && !found; it = it->next)
        found = has_clock_class(it->data, class_name);
    g_list_free(children);
    return found;
}

static GtkWidget *direct_child_with_class(GtkWidget *box, const char *class_name) {
    GtkWidget *found = NULL;
    GList *children = gtk_container_get_children(GTK_CONTAINER(box));
    for (GList *it = children; it && !found; it = it->next) {
        if (has_clock_class(it->data, class_name))
            found = it->data;
    }
    g_list_free(children);
    return found;
}

static void paint_child(cairo_t *cr, GtkWidget *overlay, GtkWidget *child, double alpha, double dy) {
    if (alpha < 0.01)
        return;
    cairo_save(cr);
    cairo_translate(cr, 0, dy);
    cairo_push_group(cr);
    gtk_container_propagate_draw(GTK_CONTAINER(overlay), child, cr);
    cairo_pop_group_to_source(cr);
    cairo_paint_with_alpha(cr, alpha);
    cairo_restore(cr);
}

/* Own the overlay's paint. Sliding the date by reallocating it every frame
   relayouts the bar and leaves a second box; a clip plus a y-translate keeps
   both labels in the time cell. */
static gboolean draw_overlay(GtkWidget *overlay, cairo_t *cr, gpointer data) {
    ClockSwap *swap = data;
    int width = gtk_widget_get_allocated_width(overlay);
    int height = gtk_widget_get_allocated_height(overlay);
    if (width < 1 || height < 1)
        return FALSE;
    cairo_save(cr);
    cairo_rectangle(cr, 0, 0, width, height);
    cairo_clip(cr);
    paint_child(cr, overlay, swap->time, 1.0 - swap->shown, 0);
    int travel = gtk_widget_get_allocated_height(swap->date);
    if (travel < 1)
        travel = height;
    paint_child(cr, overlay, swap->date, swap->shown, (swap->shown - 1.0) * travel);
    cairo_restore(cr);
    return TRUE;
}

static gboolean clock_tick(GtkWidget *overlay, GdkFrameClock *clock, gpointer data) {
    (void)overlay;
    ClockSwap *swap = data;
    gint64 now = gdk_frame_clock_get_frame_time(clock);
    if (swap->last_frame == 0)
        swap->last_frame = now;
    double dt = CLAMP((now - swap->last_frame) / 1000000.0, 0.0, 0.05);
    swap->last_frame = now;
    /* A 130 ms time constant settles in about 400 ms. */
    double amount = 1.0 - exp(-dt / 0.13);
    gboolean moving = fabs(swap->target - swap->shown) > 0.004;
    if (moving)
        swap->shown += (swap->target - swap->shown) * amount;
    if (fabs(swap->target - swap->shown) <= 0.004)
        swap->shown = swap->target;
    if (moving)
        gtk_widget_queue_draw(swap->overlay);
    return G_SOURCE_CONTINUE;
}

static gboolean on_crossing(GtkWidget *widget, GdkEventCrossing *event, gpointer data) {
    (void)widget;
    if (event->detail == GDK_NOTIFY_INFERIOR)
        return FALSE;
    ClockSwap *swap = data;
    swap->target = event->type == GDK_ENTER_NOTIFY ? 1.0 : 0.0;
    return FALSE;
}

static void watch_hover(GtkWidget *widget, ClockSwap *swap) {
    if (!widget)
        return;
    gtk_widget_add_events(widget, GDK_ENTER_NOTIFY_MASK | GDK_LEAVE_NOTIFY_MASK);
    g_signal_connect(widget, "enter-notify-event", G_CALLBACK(on_crossing), swap);
    g_signal_connect(widget, "leave-notify-event", G_CALLBACK(on_crossing), swap);
}

static void attach_timedate(GtkWidget *widget) {
    if (!GTK_IS_BOX(widget) || strcmp(gtk_widget_get_name(widget), "timedate") != 0)
        return;
    if (g_object_get_data(G_OBJECT(widget), "voluta-clock-swap"))
        return;
    GtkWidget *time = direct_child_with_class(widget, "time");
    GtkWidget *date = direct_child_with_class(widget, "date");
    if (!time || !date || time == date)
        return;

    ClockSwap *swap = g_new0(ClockSwap, 1);
    swap->box = widget;
    swap->time = time;
    swap->date = date;
    g_object_set_data_full(G_OBJECT(widget), "voluta-clock-swap", swap, g_free);

    g_object_ref(time);
    g_object_ref(date);
    gtk_container_remove(GTK_CONTAINER(widget), time);
    gtk_container_remove(GTK_CONTAINER(widget), date);

    swap->overlay = gtk_overlay_new();
    gtk_widget_set_halign(swap->overlay, GTK_ALIGN_START);
    gtk_widget_set_valign(swap->overlay, GTK_ALIGN_CENTER);
    gtk_container_add(GTK_CONTAINER(swap->overlay), time);
    gtk_overlay_add_overlay(GTK_OVERLAY(swap->overlay), date);
    gtk_overlay_set_overlay_pass_through(GTK_OVERLAY(swap->overlay), date, TRUE);
    gtk_box_pack_start(GTK_BOX(widget), swap->overlay, FALSE, FALSE, 0);
    gtk_widget_show_all(swap->overlay);
    g_object_unref(time);
    g_object_unref(date);

    gtk_style_context_add_class(gtk_widget_get_style_context(widget), "clock-stack");
    g_signal_connect(swap->overlay, "draw", G_CALLBACK(draw_overlay), swap);
    watch_hover(gtk_widget_get_parent(widget), swap);
    watch_hover(swap->overlay, swap);
    watch_hover(swap->time, swap);
    gtk_widget_add_tick_callback(swap->overlay, clock_tick, swap, NULL);
}

static void scan_widget(GtkWidget *widget, gpointer unused) {
    (void)unused;
    attach_timedate(widget);
    if (GTK_IS_CONTAINER(widget))
        gtk_container_foreach(GTK_CONTAINER(widget), scan_widget, NULL);
}

void voluta_clock_swap_scan(void) {
    GList *windows = gtk_window_list_toplevels();
    for (GList *it = windows; it; it = it->next)
        scan_widget(it->data, NULL);
    g_list_free(windows);
}
