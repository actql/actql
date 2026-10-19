/* Actual selected APFS ACL observations plus malformed syscall-result probes.
 * The private diagnostic does not admit the command's initial-control profile. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <membership.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/acl.h>
#include <sys/attr.h>
#include <sys/kauth.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>
#include "owned_capacity.h"
#include "scoped_read.h"

static const char *mode;
static unsigned observations;
static int selected_statfs(int fd, struct statfs *value) {
  int result = fstatfs(fd, value);
  if (!result && !strcmp(mode, "union")) value->f_flags |= MNT_UNION;
  if (!result && !strcmp(mode, "filesystem"))
    memcpy(value->f_fstypename, "other", sizeof("other"));
  return result;
}
static int selected_attributes(int fd, struct attrlist *attributes,
    void *buffer, size_t bytes, unsigned long options) {
  ++observations;
  assert(bytes == 4096 && options == FSOPT_REPORT_FULLSIZE);
  if (!strcmp(mode, "unsupported")) {errno = ENOTSUP; return -1;}
  int result = fgetattrlist(fd, attributes, buffer, bytes, options);
  if (!result && !strcmp(mode, "truncated")) {
    uint32_t too_large = 4097;
    memcpy(buffer, &too_large, sizeof(too_large));
  }
  if (!result && (!strcmp(mode, "overflow") || !strcmp(mode, "magic"))) {
    attrreference_t reference;
    memcpy(&reference, (char *)buffer + sizeof(uint32_t), sizeof(reference));
    assert(reference.attr_length >= KAUTH_FILESEC_SIZE(0));
    size_t offset = sizeof(uint32_t) + reference.attr_dataoffset;
    if (!strcmp(mode, "overflow")) {
      uint32_t count = KAUTH_ACL_MAX_ENTRIES + 1;
      memcpy((char *)buffer + offset + offsetof(struct kauth_filesec,
        fsec_acl.acl_entrycount), &count, sizeof(count));
    } else memset((char *)buffer + offset, 0, sizeof(uint32_t));
  }
  return result;
}
#define fstatfs(...) selected_statfs(__VA_ARGS__)
#define fgetattrlist(...) selected_attributes(__VA_ARGS__)
#include "../filesystem_stub.c"
#undef fgetattrlist
#undef fstatfs
#include "../../host_bootstrap/command_platform_unavailable.h"
#undef malloc
#undef free
#undef strdup
#include "../../remote_journal/inspection_stub.c"

static void set_entry(int fd, acl_tag_t tag) {
  acl_t acl = acl_init(1);
  acl_entry_t entry;
  acl_permset_t permissions;
  uuid_t user;
  assert(acl && mbr_uid_to_uuid(geteuid(), user) == 0);
  assert(acl_create_entry(&acl, &entry) == 0);
  assert(acl_set_tag_type(entry, tag) == 0);
  assert(acl_set_qualifier(entry, user) == 0);
  assert(acl_get_permset(entry, &permissions) == 0);
  assert(acl_add_perm(permissions, ACL_DELETE_CHILD) == 0);
  assert(acl_set_fd_np(fd, acl, ACL_TYPE_EXTENDED) == 0);
  assert(acl_free(acl) == 0);
}

int main(int argc, char **argv) {
  assert(argc == 3);
  mode = argv[1];
  bool inspection = !strcmp(mode, "inspection");
  assert(mkdir(argv[2], 0700) == 0);
  int fd = open(argv[2], O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  assert(fd >= 0);
  bool permit = !strcmp(mode, "permit");
  bool empty = !strcmp(mode, "empty") || inspection;
  if (!empty) set_entry(fd, permit ? ACL_EXTENDED_ALLOW : ACL_EXTENDED_DENY);
  /* Setup uses the platform API before the private diagnostic's acquisition.
   * Its independent original ACL route supplies the comparison oracle. */
  assert(actql_private_root_acl(fd) == empty);
  assert(actql_bootstrap_parent_acl(fd) == !permit);
  static const unsigned char recipe[32] = {19};
  actql_owned_capacity *lease = NULL;
  actql_read_context *context = NULL;
  assert(actql_native_owned_acquire(64 * (size_t)sysconf(_SC_PAGESIZE),
    1, recipe, &lease) == 0);
  assert(actql_native_owned_transfer(lease, 1, recipe) == 0);
  assert(actql_native_owned_enter(lease) == 0);
  assert(actql_read_context_create(lease, &context) == 0);
  assert(actql_read_context_retain(context) == 0);
  assert(actql_read_context_enter(context) == 0);
  if (inspection) {
    char source[4097];
    assert(snprintf(source, sizeof(source), "%s/source.sqlite3", argv[2]) > 0);
    int source_fd = open(source, O_WRONLY | O_CREAT | O_EXCL, 0600);
    assert(source_fd >= 0 && write(source_fd, "original", 8) == 8 &&
      close(source_fd) == 0);
    moonbit_bytes_t path = moonbit_make_bytes_raw((int32_t)strlen(source));
    memcpy(path, source, strlen(source));
    actql_journal_inspection *copy = inspection_open_bounded_original(
      path, (int32_t)strlen(source), 1024, getenv("TMPDIR"), 1);
    assert(copy && copy->ready && !copy->absent && copy->path_descriptor == -1 &&
      !copy->path_close_errno);
    assert(actql_journal_inspection_prepare_private_index(copy));
    assert(actql_journal_inspection_validate(copy));
    assert(inspection_close(copy));
    moonbit_decref(copy);
    moonbit_decref(path);
  } else {
    bool regular = empty || permit || !strcmp(mode, "deny");
    assert(actql_command_acl_bounded(fd, false) == empty);
    assert(actql_command_acl_bounded(fd, true) == (regular && !permit));
    assert(observations == ((!strcmp(mode, "union") ||
      !strcmp(mode, "filesystem")) ? 0 : 2));
  }
  assert(close(fd) == 0);
  assert(actql_read_context_leave(context) == 0);
  assert(actql_native_owned_leave(lease) == 0);
  assert(actql_read_context_release_after_owner_ack(context) == 0);
  assert(actql_read_context_try_close(&context) == 0);
  assert(actql_native_owned_try_close(&lease) == 0);
  printf("{\"case\":\"%s\",\"passed\":true,\"originalsClosed\":true,"
    "\"observations\":%u,\"bufferBytes\":%d,\"statfsBytes\":%zu,"
    "\"maxFilesecBytes\":%zu,\"commandBootstrap\":false}\n",
    mode, observations, ACTQL_COMMAND_ACL_BYTES, sizeof(struct statfs),
    (size_t)KAUTH_FILESEC_SIZE(KAUTH_ACL_MAX_ENTRIES));
  return 0;
}
