CC ?= gcc
CFLAGS ?= -O2 -fPIC -Wall -Wextra
LDFLAGS ?= -shared -ldl

TARGET = lib/libwaybar_hyprland_shim.so
SRC = src/hyprland_dispatch_shim.c src/workspace_slide.c
GTK_CFLAGS = $(shell pkg-config --cflags gtk+-3.0 json-glib-1.0)
GTK_LIBS = $(shell pkg-config --libs gtk+-3.0 json-glib-1.0) -lm

all: $(TARGET)

$(TARGET): $(SRC) Makefile
	@mkdir -p lib
	$(CC) $(CFLAGS) $(GTK_CFLAGS) $(LDFLAGS) -o $@ $(SRC) $(GTK_LIBS)

clean:
	rm -f $(TARGET)

.PHONY: all clean
