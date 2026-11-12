/* LD_PRELOAD helper for gsimplecal.
 *
 * GtkCalendar paints each day number at day_rect.y (top of the cell). This
 * shim moves the current point down by VOLUTA_GSIMPLECAL_DAY_PAD so the digit
 * sits in the middle of the padded day-number cell.
 *
 * Keep VOLUTA_GSIMPLECAL_DAY_PAD in sync with calendar.day-number padding in
 * gsimplecal/gtk.css. Week numbers stay off in Voluta's gsimplecal config. */
#define _GNU_SOURCE
#include <ctype.h>
#include <dlfcn.h>
#include <pango/pangocairo.h>
#include <stdlib.h>
#include <string.h>

static int is_day_number(const char *text) {
    if (!text || !isdigit((unsigned char)text[0]))
        return 0;
    if (text[1] == '\0')
        return 1;
    return isdigit((unsigned char)text[1]) && text[2] == '\0';
}

static int day_pad_px(void) {
    const char *value = getenv("VOLUTA_GSIMPLECAL_DAY_PAD");
    if (value && *value) {
        int pad = atoi(value);
        if (pad >= 0 && pad <= 64)
            return pad;
    }
    return 12;
}

void pango_cairo_show_layout(cairo_t *cr, PangoLayout *layout) {
    static void (*real)(cairo_t *, PangoLayout *);
    if (!real)
        real = dlsym(RTLD_NEXT, "pango_cairo_show_layout");

    const char *text = pango_layout_get_text(layout);
    if (is_day_number(text) && cairo_has_current_point(cr)) {
        double shift = (double)day_pad_px();
        if (shift > 0.5) {
            cairo_save(cr);
            cairo_rel_move_to(cr, 0, shift);
            real(cr, layout);
            cairo_restore(cr);
            return;
        }
    }
    real(cr, layout);
}
