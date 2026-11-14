#ifndef DIRECT_EXTRACTOR_H
#define DIRECT_EXTRACTOR_H
#include <stdint.h>
#include <stddef.h>
// Return nonzero from callback to cancel. Returns 0 success, 1 failure, 2 cancelled.
typedef int (*dr_progress)(void *, int64_t, int64_t, const char *);
int dr_extract(const char *source, const char *destination, dr_progress progress, void *context, char *error, size_t error_size);
#endif
