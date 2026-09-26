# dwm - dynamic window manager
# See LICENSE file for copyright and license details.

include config.mk

SRC = drw.c dwm.c util.c
OBJ = ${SRC:.c=.o}

all: dwm

.c.o:
	${CC} -c ${CFLAGS} $<

${OBJ}: config.h config.mk drw.h util.h functions.h themes/*.h

config.h:
	cp config.def.h $@

dwm: ${OBJ}
	${CC} -o $@ ${OBJ} ${LDFLAGS}

# KHÔNG xoá config.h ở đây: config.h là cấu hình thật của máy (được git track),
# nằm cùng các tùy chỉnh chỉ có ở đó — themes/wal.h, tag, keybind, rules.
# Xoá nó rồi để rule `config.h:` cp lại từ config.def.h sẽ âm thầm thay thế
# toàn bộ cấu hình bằng bản default. Muốn dựng bản sạch từ đầu thì dùng
# `make distclean` (xoá cả config.h) — hoặc chép tay config.h ra trước.
clean:
	rm -f dwm ${OBJ} dwm-${VERSION}.tar.gz

distclean: clean
	rm -f config.h

dist: clean
	mkdir -p dwm-${VERSION}
	cp -R LICENSE Makefile config.def.h config.mk\
		dwm.1 drw.h util.h functions.h ${SRC} dwm.png\
		vanitygaps.c movestack.c shiftview.c themes KEYBINDS.md dwm-${VERSION}
	tar -cf dwm-${VERSION}.tar dwm-${VERSION}
	gzip dwm-${VERSION}.tar
	rm -rf dwm-${VERSION}

install: all
	mkdir -p ${DESTDIR}${PREFIX}/bin
	cp -f dwm ${DESTDIR}${PREFIX}/bin/dwm
	chmod 755 ${DESTDIR}${PREFIX}/bin/dwm
	mkdir -p ${DESTDIR}${MANPREFIX}/man1
	sed "s/VERSION/${VERSION}/g" < dwm.1 > ${DESTDIR}${MANPREFIX}/man1/dwm.1
	chmod 644 ${DESTDIR}${MANPREFIX}/man1/dwm.1

uninstall:
	rm -f ${DESTDIR}${PREFIX}/bin/dwm\
		${DESTDIR}${MANPREFIX}/man1/dwm.1

.PHONY: all clean dist install uninstall
