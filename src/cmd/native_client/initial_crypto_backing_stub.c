#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include "moonbit.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* Installer-private descriptor custody. The selected initial-control envelope
 * owns this finite record; these facts issue neither an arena nor a Read loan.
 * Its caller must retain it through all mapping/context/Library cleanup ACKs. */
typedef struct {
  pthread_t thread;
  int fd;
  int ready;
  int close_result; /* 0 pending, 1 actual ACK, -1 consumed/Unknown */
  int name_present;
  int identity_observed;
  int descriptor_exposed;
  int acquisition_errno;
  dev_t device;
  ino_t inode;
  off_t bytes;
  char name[PATH_MAX];
} actql_initial_crypto_backing;

/* GC is deliberately not descriptor retirement. A lost enclosing original is
 * unfinished custody, never permission to close a still-borrowed descriptor. */
static void initial_backing_finalize(void *original) { (void)original; }

static int same_thread(const actql_initial_crypto_backing *original) {
  return original && pthread_equal(original->thread, pthread_self());
}

static int same_descriptor(const actql_initial_crypto_backing *original) {
  struct stat actual;
  return original->identity_observed && original->fd >= 0 &&
    fstat(original->fd, &actual) == 0 &&
    S_ISREG(actual.st_mode) && actual.st_dev == original->device &&
    actual.st_ino == original->inode && actual.st_uid == geteuid();
}

void *actql_initial_crypto_backing_open(int64_t bytes) {
  actql_initial_crypto_backing *original = moonbit_make_external_object(
    initial_backing_finalize, sizeof(*original));
  memset(original, 0, sizeof(*original));
  original->thread = pthread_self();
  original->fd = -1;
  original->close_result = 1;
  if (bytes <= 0 || (int64_t)(off_t)bytes != bytes) return original;
#ifdef __APPLE__
  size_t count = confstr(_CS_DARWIN_USER_TEMP_DIR, original->name,
    sizeof(original->name));
  if (!count || count >= sizeof(original->name)) return original;
#else
  memcpy(original->name, "/tmp/", sizeof("/tmp/"));
#endif
  size_t prefix = strlen(original->name);
  const char suffix[] = "actql-initial-crypto-XXXXXX";
  if (prefix + sizeof(suffix) > sizeof(original->name)) return original;
  memcpy(original->name + prefix, suffix, sizeof(suffix));
  original->fd = mkstemp(original->name);
  if (original->fd < 0) return original;
  original->close_result = 0;
  original->name_present = 1;
  struct stat actual;
  if (fstat(original->fd, &actual) != 0) {
    original->acquisition_errno = errno;
    return original;
  }
  original->device = actual.st_dev;
  original->inode = actual.st_ino;
  original->identity_observed = 1;
  if (!same_descriptor(original) || fchmod(original->fd, 0600) != 0) return original;
  /* Unlink before a usable descriptor escapes. Partial failures retain the
   * exact original name and descriptor for checked cleanup, never a reopen. */
  if (unlink(original->name) != 0) return original;
  original->name_present = 0;
  if (fcntl(original->fd, F_SETFD, FD_CLOEXEC) != 0 ||
      ftruncate(original->fd, (off_t)bytes) != 0) return original;
  original->bytes = (off_t)bytes;
  original->ready = 1;
  return original;
}

int32_t actql_initial_crypto_backing_current(actql_initial_crypto_backing *original) {
  if (!same_thread(original) || !original->ready || original->close_result != 0 ||
      original->name_present || !same_descriptor(original)) return 0;
  struct stat actual;
  return fstat(original->fd, &actual) == 0 && actual.st_nlink == 0 &&
    (actual.st_mode & 0777) == 0600 && actual.st_size == original->bytes;
}

/* This private synchronous borrow is only an argument to the existing actual
 * acquire_fd/domain constructor; the integer itself is never an authority. */
int32_t actql_initial_crypto_backing_descriptor(actql_initial_crypto_backing *original) {
  if (!actql_initial_crypto_backing_current(original)) return -1;
  original->descriptor_exposed = 1;
  return original->fd;
}

int32_t actql_initial_crypto_backing_acquisition_issue(actql_initial_crypto_backing *original) {
  return same_thread(original) ? original->acquisition_errno : EINVAL;
}

int32_t actql_initial_crypto_backing_close(actql_initial_crypto_backing *original) {
  if (!same_thread(original)) return 0;
  if (original->close_result == 1) return 1;
  if (original->close_result < 0) return 0;
  if (!original->identity_observed) {
    /* mkstemp confirmed this original open, but no descriptor borrow escaped.
     * A later observation is cleanup-only: preserve the original acquisition
     * failure and never set ready, reopen, truncate or issue another borrow. */
    if (original->ready || original->descriptor_exposed || !original->name_present)
      return 0;
    struct stat actual;
    if (fstat(original->fd, &actual) != 0 || !S_ISREG(actual.st_mode) ||
        actual.st_uid != geteuid()) return 0;
    original->device = actual.st_dev;
    original->inode = actual.st_ino;
    original->identity_observed = 1;
  }
  if (!same_descriptor(original)) return 0;
  if (original->name_present) {
    struct stat actual;
    if (lstat(original->name, &actual) != 0 || actual.st_dev != original->device ||
        actual.st_ino != original->inode || !S_ISREG(actual.st_mode) ||
        unlink(original->name) != 0) return 0;
    original->name_present = 0;
  }
  original->ready = 0;
  /* Never retry a consumed FD number after an unacknowledged close. */
  original->close_result = -1;
  if (close(original->fd) != 0) return 0;
  original->fd = -1;
  original->close_result = 1;
  return 1;
}
