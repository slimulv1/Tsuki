/* See LICENSE file for copyright and license details. */
#include <stdint.h>
#include <stdio.h>
#include <time.h>

#include "../slstatus.h"
#include "../util.h"

#if defined(CLOCK_BOOTTIME)
	#define UPTIME_FLAG CLOCK_BOOTTIME
#elif defined(CLOCK_UPTIME)
	#define UPTIME_FLAG CLOCK_UPTIME
#else
	#define UPTIME_FLAG CLOCK_MONOTONIC
#endif

const char *
uptime(const char *unused)
{
	char warn_buf[256];
	uintmax_t h, m;
	struct timespec uptime;

	if (clock_gettime(UPTIME_FLAG, &uptime) < 0) {
		snprintf(warn_buf, sizeof(warn_buf), "clock_gettime %d", UPTIME_FLAG);
		/* %s chứ không phải warn(warn_buf): truyền chuỗi dựng lúc runtime
		 * làm format string là mẫu CWE-134 — hiện warn_buf chưa chứa '%'
		 * nên chưa nổ, nhưng chỉ cần thêm %s vào snprintf ở trên là
		 * vfprintf sẽ đọc varargs không tồn tại (CERT C FIO34-C). */
		warn("%s", warn_buf);
		return nullptr;
	}

	h = uptime.tv_sec / 3600;
	m = uptime.tv_sec % 3600 / 60;

	return bprintf("%juh %jum", h, m);
}
