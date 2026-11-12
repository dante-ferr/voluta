/* Keep the window-title and workspace labels on the bar font's line box.
 * A large workspace icon or an emoji in a title would otherwise raise the
 * Pango line and grow the whole bar. Height stays on the widget font.
 * Baseline is cleared so GtkLabel's yalign can center the ink in that line;
 * reporting the font baseline forces yalign to 0 and pins the numerals high. */
#include <gtk/gtk.h>
#include <string.h>

static void (*orig_height)(GtkWidget *, gint *, gint *);
static void (*orig_height_for_width)(GtkWidget *, gint, gint *, gint *);
static void (*orig_height_and_baseline)(GtkWidget *, gint, gint *, gint *, gint *, gint *);

static gboolean capped_label(GtkWidget *widget) {
    if (!GTK_IS_LABEL(widget))
        return FALSE;
    for (GtkWidget *parent = widget; parent; parent = gtk_widget_get_parent(parent)) {
        const char *name = gtk_widget_get_name(parent);
        if (name && (!strcmp(name, "window") || !strcmp(name, "workspaces")))
            return TRUE;
    }
    return FALSE;
}

/* Line box of the widget's own font, ignoring fallback glyphs in the text. */
static void nominal_line(GtkWidget *widget, gint *height, gint *baseline) {
    PangoLayout *layout = gtk_widget_create_pango_layout(widget, "Hg");
    pango_layout_get_pixel_size(layout, NULL, height);
    *baseline = pango_layout_get_baseline(layout) / PANGO_SCALE;
    g_object_unref(layout);
    if (*height < 1)
        *height = 1;
    if (*baseline < 0 || *baseline > *height)
        *baseline = *height / 2;
}

static void clamp_pair(GtkWidget *widget, gint *minimum, gint *natural) {
    if (!minimum || !natural || !capped_label(widget))
        return;
    gint height, baseline;
    nominal_line(widget, &height, &baseline);
    if (*minimum > height)
        *minimum = height;
    if (*natural > height)
        *natural = height;
}

static void capped_height(GtkWidget *widget, gint *minimum, gint *natural) {
    orig_height(widget, minimum, natural);
    clamp_pair(widget, minimum, natural);
}

static void capped_height_for_width(GtkWidget *widget, gint width, gint *minimum, gint *natural) {
    orig_height_for_width(widget, width, minimum, natural);
    clamp_pair(widget, minimum, natural);
}

static void capped_height_and_baseline(GtkWidget *widget, gint width, gint *minimum_height,
                                       gint *natural_height, gint *minimum_baseline,
                                       gint *natural_baseline) {
    orig_height_and_baseline(widget, width, minimum_height, natural_height, minimum_baseline,
                             natural_baseline);
    if (!capped_label(widget))
        return;
    gint height, baseline;
    nominal_line(widget, &height, &baseline);
    if (minimum_height && *minimum_height > height)
        *minimum_height = height;
    if (natural_height && *natural_height > height)
        *natural_height = height;
    (void)baseline;
    /* -1 lets the label center a single line. A real baseline disables yalign. */
    if (minimum_baseline)
        *minimum_baseline = -1;
    if (natural_baseline)
        *natural_baseline = -1;
}

void voluta_label_cap_install(void) {
    GtkWidgetClass *klass = GTK_WIDGET_CLASS(g_type_class_ref(GTK_TYPE_LABEL));
    if (klass->get_preferred_height == capped_height)
        return;
    orig_height = klass->get_preferred_height;
    orig_height_for_width = klass->get_preferred_height_for_width;
    orig_height_and_baseline = klass->get_preferred_height_and_baseline_for_width;
    klass->get_preferred_height = capped_height;
    klass->get_preferred_height_for_width = capped_height_for_width;
    klass->get_preferred_height_and_baseline_for_width = capped_height_and_baseline;
}

/* Icon ink sits 1px above the button center while the numerals are already
 * centered, because both share a floor. Shift the workspace line down, and
 * the numeral rise in the format cancels that shift for the numerals only. */
static gboolean lower_workspace_icons(GtkWidget *widget, cairo_t *cr, gpointer unused) {
    (void)widget;
    (void)unused;
    cairo_translate(cr, 0, 1);
    return FALSE;
}

static gboolean workspace_label(GtkWidget *widget) {
    for (GtkWidget *parent = widget; parent; parent = gtk_widget_get_parent(parent)) {
        const char *name = gtk_widget_get_name(parent);
        if (name && !strcmp(name, "workspaces"))
            return TRUE;
    }
    return FALSE;
}

static void visit_label(GtkWidget *widget, gpointer unused) {
    (void)unused;
    if (GTK_IS_LABEL(widget) && capped_label(widget) &&
        !g_object_get_data(G_OBJECT(widget), "voluta-label-cap")) {
        g_object_set_data(G_OBJECT(widget), "voluta-label-cap", GINT_TO_POINTER(1));
        gtk_widget_set_valign(widget, GTK_ALIGN_CENTER);
        gtk_label_set_yalign(GTK_LABEL(widget), 0.5f);
        if (workspace_label(widget))
            g_signal_connect(widget, "draw", G_CALLBACK(lower_workspace_icons), NULL);
        gtk_widget_queue_resize(gtk_widget_get_toplevel(widget));
    }
    if (GTK_IS_CONTAINER(widget))
        gtk_container_foreach(GTK_CONTAINER(widget), visit_label, NULL);
}

void voluta_label_cap_scan(void) {
    voluta_label_cap_install();
    GList *windows = gtk_window_list_toplevels();
    for (GList *it = windows; it; it = it->next)
        visit_label(it->data, NULL);
    g_list_free(windows);
}
