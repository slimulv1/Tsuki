/* See LICENSE file for copyright and license details. */
#include <stdio.h>

#include "../slstatus.h"
#include "../util.h"

#if defined(__linux__)
	#include <stdint.h>

	const char *
	ram_free(const char *unused)
	{
		uintmax_t free;
		FILE *fp;

		if (!(fp = fopen("/proc/meminfo", "r")))
			return NULL;

		if (lscanf(fp, "MemFree:", "%ju kB", &free) != 1) {
			fclose(fp);
			return NULL;
		}

		fclose(fp);
		return fmt_human(free * 1024, 1024);
	}

	struct meminfo {
		uintmax_t total, free, buffers, cached, shmem, sreclaimable;
	};

	static int
	read_meminfo(struct meminfo *m)
	{
		FILE *fp;
		char line[256];
		int found = 0;

		if (!(fp = fopen("/proc/meminfo", "r")))
			return -1;

		while (fgets(line, sizeof(line), fp)) {
			if (sscanf(line, "MemTotal: %ju kB", &m->total) == 1)
				found |= 1;
			else if (sscanf(line, "MemFree: %ju kB", &m->free) == 1)
				found |= 2;
			else if (sscanf(line, "Buffers: %ju kB", &m->buffers) == 1)
				found |= 4;
			else if (sscanf(line, "Cached: %ju kB", &m->cached) == 1)
				found |= 8;
			else if (sscanf(line, "Shmem: %ju kB", &m->shmem) == 1)
				found |= 16;
			else if (sscanf(line, "SReclaimable: %ju kB", &m->sreclaimable) == 1)
				found |= 32;
		}
		fclose(fp);

		return (found == 63) ? 0 : -1;
	}

	const char *
	ram_perc(const char *unused)
	{
		struct meminfo m;
		int percent;
		if (read_meminfo(&m) < 0)
			return NULL;

		if (m.total == 0)
			return NULL;

		percent = 100 * (m.total - m.free - m.buffers - m.cached - m.sreclaimable + m.shmem) / m.total;
		return bprintf("%d", percent);
	}

	const char *
	ram_total(const char *unused)
	{
		uintmax_t total;

		if (pscanf("/proc/meminfo", "MemTotal: %ju kB\n", &total)
		    != 1)
			return NULL;

		return fmt_human(total * 1024, 1024);
	}

	const char *
	ram_used(const char *unused)
	{
		struct meminfo m;
		uintmax_t used;

		if (read_meminfo(&m) < 0)
			return NULL;

		used = m.total - m.free - m.buffers - m.cached - m.sreclaimable + m.shmem;
		return fmt_human(used * 1024, 1024);
	}
#elif defined(__OpenBSD__)
	#include <stdlib.h>
	#include <sys/sysctl.h>
	#include <sys/types.h>
	#include <unistd.h>

	#define LOG1024 10
	#define pagetok(size, pageshift) (size_t)(size << (pageshift - LOG1024))

	inline int
	load_uvmexp(struct uvmexp *uvmexp)
	{
		int uvmexp_mib[] = {CTL_VM, VM_UVMEXP};
		size_t size;

		size = sizeof(*uvmexp);

		if (sysctl(uvmexp_mib, 2, uvmexp, &size, NULL, 0) >= 0)
			return 1;

		return 0;
	}

	const char *
	ram_free(const char *unused)
	{
		struct uvmexp uvmexp;
		int free_pages;

		if (!load_uvmexp(&uvmexp))
			return NULL;

		free_pages = uvmexp.npages - uvmexp.active;
		return fmt_human(pagetok(free_pages, uvmexp.pageshift) *
				 1024, 1024);
	}

	const char *
	ram_perc(const char *unused)
	{
		struct uvmexp uvmexp;
		int percent;

		if (!load_uvmexp(&uvmexp))
			return NULL;

		percent = uvmexp.active * 100 / uvmexp.npages;
		return bprintf("%d", percent);
	}

	const char *
	ram_total(const char *unused)
	{
		struct uvmexp uvmexp;

		if (!load_uvmexp(&uvmexp))
			return NULL;

		return fmt_human(pagetok(uvmexp.npages,
					 uvmexp.pageshift) * 1024, 1024);
	}

	const char *
	ram_used(const char *unused)
	{
		struct uvmexp uvmexp;

		if (!load_uvmexp(&uvmexp))
			return NULL;

		return fmt_human(pagetok(uvmexp.active,
					 uvmexp.pageshift) * 1024, 1024);
	}
#elif defined(__FreeBSD__)
	#include <sys/sysctl.h>
	#include <sys/vmmeter.h>
	#include <unistd.h>
	#include <vm/vm_param.h>

	const char *
	ram_free(const char *unused) {
		struct vmtotal vm_stats;
		int mib[] = {CTL_VM, VM_TOTAL};
		size_t len;

		len = sizeof(struct vmtotal);
		if (sysctl(mib, 2, &vm_stats, &len, NULL, 0) < 0
		    || !len)
			return NULL;

		return fmt_human(vm_stats.t_free * getpagesize(), 1024);
	}

	const char *
	ram_total(const char *unused) {
		unsigned int npages;
		size_t len;

		len = sizeof(npages);
		if (sysctlbyname("vm.stats.vm.v_page_count",
		                 &npages, &len, NULL, 0) < 0 || !len)
			return NULL;

		return fmt_human(npages * getpagesize(), 1024);
	}

	const char *
	ram_perc(const char *unused) {
		unsigned int npages;
		unsigned int active;
		size_t len;

		len = sizeof(npages);
		if (sysctlbyname("vm.stats.vm.v_page_count",
		                 &npages, &len, NULL, 0) < 0 || !len)
			return NULL;

		if (sysctlbyname("vm.stats.vm.v_active_count",
		                 &active, &len, NULL, 0) < 0 || !len)
			return NULL;

		return bprintf("%d", active * 100 / npages);
	}

	const char *
	ram_used(const char *unused) {
		unsigned int active;
		size_t len;

		len = sizeof(active);
		if (sysctlbyname("vm.stats.vm.v_active_count",
		                 &active, &len, NULL, 0) < 0 || !len)
			return NULL;

		return fmt_human(active * getpagesize(), 1024);
	}
#endif
