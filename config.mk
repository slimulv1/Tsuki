# dwm version
VERSION = 6.8

# Customize below to fit your system

# paths
PREFIX = /usr/local
MANPREFIX = ${PREFIX}/share/man

X11INC = /usr/include
X11LIB = /usr/lib

# Xinerama, comment if you don't want it
XINERAMALIBS  = -lXinerama
XINERAMAFLAGS = -DXINERAMA

# freetype
FREETYPELIBS = -lfontconfig -lXft
FREETYPEINC = /usr/include/freetype2
# OpenBSD (uncomment)
#FREETYPEINC = ${X11INC}/freetype2
#MANPREFIX = ${PREFIX}/man

# includes and libs
INCS = -I${X11INC} -I${FREETYPEINC}
# -lXcursor: drw_cur_load() nạp cursor theo theme từ Xresources "Xcursor".
# Thiếu thì dwm rơi về XCreateFontCursor — mũi tên xám mặc định, không sao theme.
LIBS = -L${X11LIB} -lX11 ${XINERAMALIBS} ${FREETYPELIBS} -lXrender -lImlib2 -lXcursor

# flags
# -Wundef: bắt lỗi gõ sai tên macro trong #if (dễ xảy ra với các patch
#   để lại #if <PATCH>_PATCH trong dwm.c / vanitygaps.c).
# ARCHFLAGS: -march=native cho hiệu năng tối đa trên máy đang chạy, nhưng
#   binary cài vào ${PREFIX}/bin sẽ SIGILL nếu mang sang máy CPU khác.
#   Ghi đè được:  make ARCHFLAGS="-march=x86-64-v3"
#   (CFLAGS ghi đè bằng dấu `=` nên ARCHFLAGS phải là `?=`)
ARCHFLAGS ?= -march=native
CPPFLAGS = -D_DEFAULT_SOURCE -D_BSD_SOURCE -D_XOPEN_SOURCE=700L -DVERSION=\"${VERSION}\" ${XINERAMAFLAGS}
#CFLAGS   = -g -std=c23 -Wall -Wextra -O0 ${INCS} ${CPPFLAGS}
CFLAGS   = -std=c23 -Wall -Wextra -Werror -Wundef -O3 ${ARCHFLAGS} -flto -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wformat=2 -Werror=format-security -fPIE ${INCS} ${CPPFLAGS}
LDFLAGS  = -pie -z relro -z now -flto ${LIBS}

# Solaris
#CFLAGS = -fast ${INCS} -DVERSION=\"${VERSION}\"
#LDFLAGS = ${LIBS}

# compiler and linker
CC = cc
