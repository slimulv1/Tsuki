/* See LICENSE file for copyright and license details. */
/* Default settings; can be overriden by command line. */

static int topbar = 1;                      /* -b  option; if 0, dmenu appears at bottom     */
static const unsigned int alpha = 0xe0;     /* Amount of opacity. 0xff is opaque             */
static int centered = 0;                    /* -c option; centers dmenu on screen */
static int min_width = 400;                    /* minimum width when centered */
static const float menu_height_ratio = 2.0f;  /* This is the ratio used in the original calculation */
/* -fn option overrides fonts[0]; default X11 font or font set */
static const char *fonts[] = {
	"CaskaydiaCove Nerd Font:size=12"
};
static const char *prompt      = nullptr;      /* -p  option; prompt to the left of input field */
static const char *colors[SchemeLast][2] = {
	/*     fg         bg       */
	[SchemeNorm] = { "#d7cbd4", "#1d161b" },
	[SchemeSel] = { "#1d161b", "#d7425b" },
	[SchemeOut] = { "#1d161b", "#b22c43" },
};

static const unsigned int alphas[SchemeLast][2] = {
	[SchemeNorm] = { OPAQUE, alpha },
	[SchemeSel] = { OPAQUE, alpha },
	[SchemeOut] = { OPAQUE, alpha },
};
/* -l option; if nonzero, dmenu uses vertical list with given number of lines */
static unsigned int lines      = 10;

/*
 * Characters not considered part of a word while deleting words
 * for example: " /?\"&[]"
 */
static const char worddelimiters[] = " ";
