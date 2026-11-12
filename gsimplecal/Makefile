CC ?= gcc
CFLAGS ?= -O2 -fPIC -Wall -Wextra
LDFLAGS ?= -shared -ldl

TARGET = lib/libgsimplecal_center.so
PANGO_CFLAGS = $(shell pkg-config --cflags pangocairo)
PANGO_LIBS = $(shell pkg-config --libs pangocairo)

all: $(TARGET)

$(TARGET): center_days.c Makefile
	@mkdir -p lib
	$(CC) $(CFLAGS) $(PANGO_CFLAGS) $(LDFLAGS) -o $@ center_days.c $(PANGO_LIBS)

clean:
	rm -f $(TARGET)

.PHONY: all clean
