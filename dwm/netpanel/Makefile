# netpanel — Wi-Fi panel popup (X11/Xft)
# đồng bộ phong cách Makefile của slstatus/dwm

include config.mk

all: netpanel

config.h:
	cp config.def.h $@

netpanel.o: netpanel.c config.h
	$(CC) -c $(CFLAGS) $(INCS) -o $@ netpanel.c

netpanel: netpanel.o
	$(CC) -o $@ netpanel.o $(LIBS)

clean:
	rm -f netpanel netpanel.o config.h

.PHONY: all clean
