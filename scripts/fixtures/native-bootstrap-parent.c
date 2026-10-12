// Compile the complete production Owner, including its real namespace walk.
// Only ACL retrieval failure is injected; no permission decision is replaced.
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <stdbool.h>
#ifdef __APPLE__
#include <sys/acl.h>
static bool fail_acl;
static acl_t diagnostic_acl_get_fd_np(int fd, acl_type_t type);
#define acl_get_fd_np diagnostic_acl_get_fd_np
#elif defined(__linux__)
#include <sys/xattr.h>
static bool fail_acl;
static ssize_t diagnostic_fgetxattr(int fd, const char *name, void *value, size_t size);
#define fgetxattr diagnostic_fgetxattr
#endif
#include "../../src/platform_native/filesystem/filesystem_stub.c"
#ifdef __APPLE__
#undef acl_get_fd_np
static acl_t diagnostic_acl_get_fd_np(int fd, acl_type_t type) {
  if (fail_acl) { errno = EIO; return NULL; }
  return acl_get_fd_np(fd, type);
}
#elif defined(__linux__)
#undef fgetxattr
static ssize_t diagnostic_fgetxattr(int fd, const char *name, void *value, size_t size) {
  if (fail_acl) { errno = EIO; return -1; }
  return fgetxattr(fd, name, value, size);
}
#endif
#ifdef ACTQL_DIAGNOSTIC_LEGACY
#define actql_native_filesystem_bootstrap_parent_identity actql_native_filesystem_private_root_identity
#endif
#include <assert.h>
_Noreturn void moonbit_panic(void) { abort(); }

static moonbit_bytes_t bytes(const char *text) {
  size_t size = strlen(text);
  moonbit_bytes_t value = moonbit_make_bytes_raw((int32_t)size);
  memcpy(value, text, size);
  return value;
}

int main(int argc, char **argv) {
  assert(argc == 3);
  moonbit_bytes_t path = bytes(argv[2]);
  actql_native_filesystem_root *root = actql_native_filesystem_open_root(path, (int32_t)strlen(argv[2]));
  moonbit_decref(path);
  if (strcmp(argv[1], "probe") == 0) {
    int parent = actql_native_filesystem_bootstrap_parent_identity(root);
    int private_root = actql_native_filesystem_private_root_identity(root);
    printf("%d %d\n", parent, private_root);
  } else {
    assert(actql_native_filesystem_bootstrap_parent_identity(root));
    uint64_t device = root->result_device, inode = root->result_inode;
    struct stat status;
    assert(fstat(root->fd, &status) == 0);
    assert(device == (uint64_t)status.st_dev && inode == (uint64_t)status.st_ino);
    if (strcmp(argv[1], "foreign-uid-metadata") == 0) {
      // Unprivileged diagnostics cannot chown another user's directory. Check
      // the observed-stat predicate with an independently foreign UID instead.
      status.st_uid = geteuid() == 0 ? 1 : 0;
      assert(!actql_bootstrap_parent_status(&status));
    } else if (strcmp(argv[1], "child") == 0) {
      moonbit_bytes_t name = bytes("state");
      assert(actql_native_filesystem_create_directory(root, name, 5) == 0);
      uint64_t child_device = root->result_device, child_inode = root->result_inode;
      // Existing exclusive creation must not claim an already present child.
      assert(actql_native_filesystem_create_directory(root, name, 5) == 1);
      actql_native_filesystem_root *child = actql_native_filesystem_open_child_root(root, name, 5);
      assert(actql_native_filesystem_private_root_identity(child));
      assert(child->result_device == child_device && child->result_inode == child_inode);
      assert(actql_native_filesystem_bootstrap_parent_identity(root));
      assert(root->result_device == device && root->result_inode == inode);
      moonbit_decref(child); moonbit_decref(name);
    } else {
      if (strcmp(argv[1], "acl-failure") == 0) {
        fail_acl = true;
      } else if (strcmp(argv[1], "mode-change") == 0) {
        assert(chmod(argv[2], 0770) == 0);
      } else if (strcmp(argv[1], "replacement") == 0 || strcmp(argv[1], "alias-replacement") == 0) {
        char retired[4097];
        assert(snprintf(retired, sizeof(retired), "%s-retired", argv[2]) < (int)sizeof(retired));
        assert(rename(argv[2], retired) == 0);
        if (strcmp(argv[1], "replacement") == 0) assert(mkdir(argv[2], 0700) == 0);
        else assert(symlink(retired, argv[2]) == 0);
      } else { assert(false); }
      assert(!actql_native_filesystem_bootstrap_parent_identity(root));
      assert(root->result_device == 0 && root->result_inode == 0);
    }
    puts("checked");
  }
  moonbit_decref(root);
  return 0;
}
