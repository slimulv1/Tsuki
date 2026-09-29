# netpanel — Wi-Fi panel popup (X11/Xft)
# đồng bộ phong cách Makefile của slstatus/dwm

include config.mk

all: netpanel

config.h:
	cp config.def.h $@

netpanel.o: netpanel.c config.h
	$(CC) -c $(CFLAGS) $(INCS) -o $@ netpanel.c

netpanel: netpanel.o
	$(CC) -o $@ netpanel.o $(LDFLAGS) $(LIBS)

# KHÔNG xoá config.h: nó được git track và là cấu hình thật của máy.
# Rule `config.h:` cp từ config.def.h sẽ âm thầm thay hết tùy chỉnh nếu mất.
# Muốn dựng bản sạch: dùng `make distclean`.
clean:
	rm -f netpanel netpanel.o

distclean: clean
	rm -f config.h

.PHONY: all clean distclean
