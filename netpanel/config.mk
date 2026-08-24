# pkg-config: x11 xft xrender xext fontconfig
PKG_CONFIG = pkg-config

INCS = $(shell $(PKG_CONFIG) --cflags x11 xft xrender xext fontconfig)
LIBS = $(shell $(PKG_CONFIG) --libs   x11 xft xrender xext fontconfig) -lm

CFLAGS = -Os -Wall -Wextra -std=c99 -D_DEFAULT_SOURCE
CC ?= cc
