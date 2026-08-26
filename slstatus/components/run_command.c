/* See LICENSE file for copyright and license details. */
#include <stdio.h>
#include <string.h>

#include "../slstatus.h"
#include "../util.h"

const char *
run_command(const char *cmd)
{
	char *p;
	FILE *fp;

	if (!(fp = popen(cmd, "r"))) {
		warn("popen '%s':", cmd);
		return nullptr;
	}

	p = fgets(buf, sizeof(buf) - 1, fp);
	if (pclose(fp) < 0) {
		warn("pclose '%s':", cmd);
		return nullptr;
	}
	if (!p)
		return nullptr;

	if ((p = strrchr(buf, '\n')))
		p[0] = '\0';

	return buf[0] ? buf : nullptr;
}
