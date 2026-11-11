#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include "moonbit.h"
#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

// The standalone diagnostic does not link a generated MoonBit entrypoint.
// Any unexpected runtime panic terminates the fixture; it cannot become PASS.
_Noreturn void moonbit_panic(void) { abort(); }

static unsigned heap_entries;
static unsigned descriptor_entries;
static void *layout_malloc(size_t bytes) {
  heap_entries++;
  return malloc(bytes);
}
static void *layout_calloc(size_t count, size_t bytes) {
  heap_entries++;
  return calloc(count, bytes);
}
static char *layout_strdup(const char *text) {
  heap_entries++;
  return strdup(text);
}
static int layout_open(const char *path, int flags, ...) {
  (void)path; (void)flags;
  descriptor_entries++;
  abort();
}
static ssize_t layout_read(int fd, void *bytes, size_t length) {
  (void)fd; (void)bytes; (void)length;
  descriptor_entries++;
  abort();
}
static int layout_close(int fd) {
  (void)fd;
  descriptor_entries++;
  abort();
}

// The query and actual declarations are compiled from the real Owner. These
// guards catch accidental acquisition, allocation or retirement in the query;
// no mock Root/Reader, filesystem failure or boolean ACK is supplied.
#define malloc layout_malloc
#define calloc layout_calloc
#define strdup layout_strdup
#define open layout_open
#define read layout_read
#define close layout_close
#include "../../src/platform_native/filesystem/filesystem_stub.c"
#undef malloc
#undef calloc
#undef strdup
#undef open
#undef read
#undef close

int main(void) {
  int64_t root = actql_native_filesystem_read_layout_field(0);
  int64_t reader = actql_native_filesystem_read_layout_field(1);
  int64_t overhead = actql_native_filesystem_read_layout_field(2);
  int64_t observation = actql_native_filesystem_read_layout_field(3);
  int64_t acquisition = actql_native_filesystem_read_layout_field(4);
  assert(root == (int64_t)sizeof(actql_native_filesystem_root));
  assert(reader == (int64_t)sizeof(actql_native_filesystem_reader));
  assert(overhead == (int64_t)(sizeof(struct moonbit_object) +
    sizeof(void (*)(void *))));
  assert(observation == (int64_t)sizeof(actql_native_observed_file_stat));
  assert(acquisition == (int64_t)sizeof(actql_filesystem_scoped_acquisition));
  assert(root > 0 && reader > 0 && overhead > 0 && observation > 0 && acquisition > 0);
  assert(actql_native_filesystem_read_layout_field(-1) == -1);
  assert(actql_native_filesystem_read_layout_field(5) == -1);
  assert(heap_entries == 0 && descriptor_entries == 0);
  printf("{\"cases\":9,\"rootPayload\":%lld,\"readerPayload\":%lld,"
    "\"externalOverhead\":%lld,\"observationPayload\":%lld,\"acquisitionPayload\":%lld,"
    "\"heapEntries\":0,\"descriptorEntries\":0,"
    "\"publicAcceptance\":false}\n",
    (long long)root, (long long)reader, (long long)overhead,
    (long long)observation, (long long)acquisition);
  return 0;
}
