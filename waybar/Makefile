CC ?= gcc
CFLAGS ?= -O2 -fPIC -Wall -Wextra
LDFLAGS ?= -shared -ldl

TARGET = lib/libwaybar_hyprland_shim.so
SRC = src/hyprland_dispatch_shim.c

all: $(TARGET)

$(TARGET): $(SRC)
	@mkdir -p lib
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)

.PHONY: all clean
