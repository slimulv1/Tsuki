# slock version
VERSION = 1.6

# Customize below to fit your system

# paths
PREFIX = /usr/local
MANPREFIX = ${PREFIX}/share/man

X11INC = /usr/X11R6/include
X11LIB = /usr/X11R6/lib

# includes and libs
# FREETYPEINC: Xft/Xft.h keo <ft2build.h> (cua freetype2) vao qua. Tren Arch
# file no nam o /usr/include/freetype2/ft2build.h chu khong phai /usr/include
# — do pkg-config freetype2 --cflags chay ra -I/usr/include/freetype2.
# Khong co -I nay thi build fail ngay: "fatal error: ft2build.h: No such file
# or directory". Cung duong dan voi dwm/config.mk (FREETYPEINC).
FREETYPEINC = /usr/include/freetype2
INCS = -I. -I/usr/include -I${X11INC} -I${FREETYPEINC}
# -lXft: ve CHU cho man khoa (gio/ngay/ten user). slock goc khong lien thu vien
# font nao nen man hinh chi to 1 mau nen phang. Xft keo theo fontconfig.
#
# KHONG lien Imlib2 (thu vien doc anh) vao day: slock cai o /usr/local/bin voi
# quyen setuid root. Moi thu vien parse du lieu la them mot be phan giai vao
# mot binary chay voi quyen root — loi trong be phan giai do la loi leo thang.
# Phan ve cua slock viet bang Xlib + Xft thuan, khong can Imlib2.
LIBS = -L/usr/lib -lc -lcrypt -L${X11LIB} -lX11 -lXext -lXrandr -lXft

# flags
CPPFLAGS = -DVERSION=\"${VERSION}\" -D_DEFAULT_SOURCE -DHAVE_SHADOW_H
CFLAGS = -std=c23 -Wall -Wextra -Werror -Os -fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE ${INCS} ${CPPFLAGS}
LDFLAGS = -pie -z relro -z now -s ${LIBS}
COMPATSRC = explicit_bzero.c

# On OpenBSD and Darwin remove -lcrypt from LIBS
#LIBS = -L/usr/lib -lc -L${X11LIB} -lX11 -lXext -lXrandr
# On *BSD remove -DHAVE_SHADOW_H from CPPFLAGS
# On NetBSD add -D_NETBSD_SOURCE to CPPFLAGS
#CPPFLAGS = -DVERSION=\"${VERSION}\" -D_BSD_SOURCE -D_NETBSD_SOURCE
# On OpenBSD set COMPATSRC to empty
#COMPATSRC =
