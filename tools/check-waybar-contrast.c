/* cc -Wall -Wextra -o /tmp/check-waybar-contrast tools/check-waybar-contrast.c
 *    $(pkg-config --cflags --libs gtk+-3.0 json-glib-1.0) -ldl -lm */
#include "../waybar/src/decoration_contrast.c"

int main(void) {
    GdkPixbuf *image = gdk_pixbuf_new(GDK_COLORSPACE_RGB, FALSE, 8, 40, 40);
    const double ink[] = {.002, .35, .7};
    Region strip = {0, 0, 40, 10};
    double score[4];
    gdk_pixbuf_fill(image, 0x080808ff);
    scores(image, strip, ink, score);
    g_assert_cmpint(choose_variant(score, -1), ==, 1);
    gdk_pixbuf_fill(image, 0x404040ff);
    scores(image, strip, ink, score);
    g_assert_cmpint(choose_variant(score, -1), ==, 0);
    gdk_pixbuf_fill(image, 0x202020ff);
    scores(image, strip, ink, score);
    g_assert_cmpint(choose_variant(score, -1), ==, 1);

    /* A dark wallpaper with a bright bar strip must keep every SVG dark. */
    gdk_pixbuf_fill(image, 0x080808ff);
    for (int y = 0; y < 10; y++)
        memset(gdk_pixbuf_get_pixels(image) + y * gdk_pixbuf_get_rowstride(image), 248, 40 * 3);
    scores(image, strip, ink, score);
    g_assert_cmpint(choose_variant(score, -1), ==, 0);
    scores(image, (Region){0, 10, 40, 10}, ink, score);
    g_assert_cmpint(choose_variant(score, -1), ==, 1);

    /* Both sides contribute equally to one shared decision. No SVG masks. */
    for (int y = 0; y < 10; y++)
        memset(gdk_pixbuf_get_pixels(image) + y * gdk_pixbuf_get_rowstride(image), 8, 20 * 3);
    scores(image, strip, ink, score);
    g_assert_cmpfloat_with_epsilon(score[3], .5, .00001);
    g_assert_cmpint(choose_variant(score, -1), ==, 0);
    scores(image, (Region){19.5, 0, 1, 10}, ink, score);
    g_assert_cmpfloat_with_epsilon(score[3], .5, .00001);
    scores(NULL, strip, ink, score);
    g_assert_cmpint(choose_variant(score, -1), ==, 0);

    /* Monitor origins cancel, fractional scale maps logical to native pixels. */
    Region native = image_region((Region){1932, -94, 1256, 34},
                                 (Region){1920, -100, 1280, 720}, 1920, 1080);
    g_assert_cmpfloat(native.x, ==, 18);
    g_assert_cmpfloat(native.y, ==, 9);
    g_assert_cmpfloat(native.width, ==, 1884);
    g_assert_cmpfloat(native.height, ==, 51);
    JsonParser *parser = json_parser_new();
    const char *json = "{\"DP-2\":{\"levels\":{\"0\":[{\"namespace\":\"awww-daemon\","
        "\"x\":2560,\"y\":0,\"w\":1920,\"h\":1080}],\"2\":["
        "{\"namespace\":\"waybar\",\"pid\":42,\"x\":2572,\"y\":8,\"w\":1896,\"h\":34},"
        "{\"namespace\":\"waybar\",\"pid\":99,\"x\":0,\"y\":0,\"w\":100,\"h\":10}]}}}";
    g_assert_true(json_parser_load_from_data(parser, json, -1, NULL));
    Region bar, wallpaper;
    g_assert_true(layer_regions(json_parser_get_root(parser), "DP-2", "awww-daemon", 42, &bar, &wallpaper));
    native = image_region(bar, wallpaper, 1920, 1080);
    g_assert_cmpfloat(native.x, ==, 12);
    g_assert_cmpfloat(native.y, ==, 8);
    g_assert_false(layer_regions(json_parser_get_root(parser), "DP-2", "awww-daemon", 43, &bar, &wallpaper));
    g_assert_false(layer_regions(json_parser_get_root(parser), "eDP-1", "awww-daemon", 42, &bar, &wallpaper));

    const double weak[] = {1, 2, 8, 1}, adequate[] = {1, 4, 8, 1};
    g_assert_cmpint(choose_variant(weak, -1), ==, 2);
    g_assert_cmpint(choose_variant(adequate, 2), ==, 1);
    g_object_unref(parser);
    g_object_unref(image);
    g_print("PASS: whole-strip colors, strict darkness, crop bounds, fractional edges/scale, monitor origins and compositor geometry\n");
    return 0;
}
