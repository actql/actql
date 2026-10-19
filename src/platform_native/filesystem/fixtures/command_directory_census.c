/* Matching-provider physical primitive cases. Direct calls to the private
 * bounded implementation do not admit a command bootstrap or normal profile. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/attr.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>
#include "owned_capacity.h"
#include "scoped_read.h"

static bool union_selection, other_filesystem, malformed, unsupported;
static unsigned bulk_calls;
static void (*during_bulk)(void);
static int observe_fstatfs(int fd, struct statfs *value) {
  int result = fstatfs(fd, value);
  if (result == 0 && union_selection) value->f_flags |= MNT_UNION;
  if (result == 0 && other_filesystem) {
    memset(value->f_fstypename, 0, sizeof(value->f_fstypename));
    memcpy(value->f_fstypename, "unselected", sizeof("unselected"));
  }
  return result;
}
static int observe_bulk(int fd, void *attributes, void *buffer,
    size_t bytes, uint64_t options) {
  bulk_calls++;
  assert(bytes == 65536);
  if (during_bulk) during_bulk();
  if (unsupported) {errno = ENOTSUP; return -1;}
  int result = getattrlistbulk(fd, attributes, buffer, bytes, options);
  if (result > 0 && malformed) memset(buffer, 0, sizeof(uint32_t));
  return result;
}
#define fstatfs(...) observe_fstatfs(__VA_ARGS__)
#define getattrlistbulk(...) observe_bulk(__VA_ARGS__)
#include "../filesystem_stub.c"
#undef getattrlistbulk
#undef fstatfs
#include "../../host_bootstrap/command_platform_unavailable.h"

static const unsigned char recipe[32] = {17};
static actql_native_filesystem_root *active_root;
static void refuse_parent_close(void) {
  int original = active_root->fd;
  assert(actql_native_filesystem_root_close(active_root) == -1);
  assert(active_root->fd == original && fcntl(original, F_GETFD) >= 0);
}
static void file_at(const char *directory, const char *name) {
  char path[4097];
  assert(snprintf(path, sizeof(path), "%s/%s", directory, name) > 0);
  int fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0600);
  assert(fd >= 0 && write(fd, "original", 8) == 8 && close(fd) == 0);
}
int main(int argc, char **argv) {
  assert(argc == 3);
  const char *mode = argv[1], *directory = argv[2];
  assert(mkdir(directory, 0700) == 0);
  file_at(directory, "LICENSE");
  char child[4097];
  assert(snprintf(child, sizeof(child), "%s/bin", directory) > 0);
  assert(mkdir(child, 0700) == 0);
  if (!strcmp(mode, "extra")) file_at(directory, "extra");
  union_selection = !strcmp(mode, "union");
  other_filesystem = !strcmp(mode, "filesystem");
  malformed = !strcmp(mode, "malformed");
  unsupported = !strcmp(mode, "unsupported");
  actql_owned_capacity *lease = NULL;
  actql_read_context *context = NULL;
  assert(actql_native_owned_acquire(64 * (size_t)sysconf(_SC_PAGESIZE),
    1, recipe, &lease) == 0);
  assert(actql_native_owned_transfer(lease, 1, recipe) == 0);
  assert(actql_native_owned_enter(lease) == 0);
  assert(actql_read_context_create(lease, &context) == 0);
  assert(actql_read_context_retain(context) == 0);
  assert(actql_read_context_enter(context) == 0);
  actql_native_filesystem_root *root = NULL;
  assert(actql_native_filesystem_scoped_open_root(context,
    (moonbit_bytes_t)directory, (int32_t)strlen(directory), 128, &root) == 0);
  assert(root && root->fd >= 0);
  if (!strcmp(mode, "active-parent-close")) {
    active_root = root;
    during_bulk = refuse_parent_close;
  }
  if (!strcmp(mode, "close-unknown")) root->test_census_close_failures = 1;
  const unsigned char expected[] = "fLICENSE\0dbin\0";
  moonbit_bytes_t frame = moonbit_make_bytes_raw(sizeof(expected) - 1);
  memcpy(frame, expected, sizeof(expected) - 1);
  int result;
  if (!strcmp(mode, "unavailable")) {
    result = actql_native_filesystem_command_directory_census(
      root, frame, sizeof(expected) - 1, 2);
    assert(result == -1 && bulk_calls == 0);
  } else {
    result = actql_command_directory_census_bounded(
      root, frame, sizeof(expected) - 1, 2);
    if (union_selection || other_filesystem)
      assert(result == -1 && bulk_calls == 0);
    else if (malformed || unsupported) assert(result == -1 && bulk_calls == 1);
    else if (!strcmp(mode, "extra")) assert(result == 1 && bulk_calls == 1);
    else if (!strcmp(mode, "close-unknown")) {
      assert(result == 3 && root->census_cleanup_unconfirmed &&
        root->census_descriptor_acquired && root->census_descriptor_close_consumed);
      int reused = open("/dev/null", O_RDONLY);
      assert(reused == root->census_descriptor);
      unsigned before = bulk_calls;
      assert(actql_command_directory_census_bounded(
        root, frame, sizeof(expected) - 1, 2) == 3 && bulk_calls == before);
      int32_t physical = 0;
      assert(actql_native_filesystem_scoped_root_close(root, &physical) == 0);
      assert(physical == -1 && root->read_context_user);
      assert(fcntl(reused, F_GETFD) >= 0 && close(reused) == 0);
      assert(actql_read_context_leave(context) == 0);
      assert(actql_native_owned_leave(lease) == 0);
      assert(actql_read_context_release_after_owner_ack(context) == 0);
      assert(actql_read_context_try_close(&context) == ACTQL_OWNED_BUSY);
      /* This original remains deliberately unacknowledged. Test-process exit
       * is not its Read/backing cleanup ACK and cannot turn it into a retry. */
      printf("{\"case\":\"%s\",\"passed\":true,\"originalsClosed\":false,"
        "\"unknownRetained\":true,\"bulkCalls\":%u,"
        "\"commandBootstrap\":false,\"installed\":false}\n", mode, bulk_calls);
      return 0;
    } else {
      assert((!strcmp(mode, "exact") || !strcmp(mode, "active-parent-close")) &&
        result == 0 && bulk_calls > 0);
      unsigned before = bulk_calls;
      assert(actql_command_directory_census_bounded(
        root, frame, sizeof(expected) - 1, 2) == 0);
      assert(bulk_calls > before);
    }
  }
  assert(!root->census_descriptor_acquired && !root->census_cleanup_unconfirmed);
  int32_t physical = -1;
  assert(actql_native_filesystem_scoped_root_close(root, &physical) == 0);
  assert(physical == 0 && !root->read_context_user);
  moonbit_decref(root); moonbit_decref(frame);
  assert(actql_read_context_leave(context) == 0);
  assert(actql_native_owned_leave(lease) == 0);
  assert(actql_read_context_release_after_owner_ack(context) == 0);
  assert(actql_read_context_try_close(&context) == 0);
  assert(actql_native_owned_try_close(&lease) == 0);
  printf("{\"case\":\"%s\",\"passed\":true,\"originalsClosed\":true,"
    "\"bulkCalls\":%u,\"commandBootstrap\":false,\"installed\":false}\n",
    mode, bulk_calls);
  return 0;
}
