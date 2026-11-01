/* Private Node Host filesystem binding, not an operational admission. Its
 * actual image/loader, allocation and FD lifetime belong to the selected Host
 * recipe before initialization. No libc DIR, global pool or finalizer ACK. */
#include <node_api.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#if defined(__APPLE__)
#include <sys/attr.h>
#include <sys/mount.h>
#endif

#define DIRECTORY_BYTES 65536
#define DIRECTORY_PATH_BYTES 4096
#define DIRECTORY_NAME_BYTES 1024
#define DIRECTORY_MAX_ENTRIES 100000

typedef struct directory_owner directory_owner;
typedef struct directory_original {
  directory_owner *owner;
  napi_ref retained;
  int descriptor, failure, close_error;
  bool consumed, closed, exhausted;
  uint32_t remaining;
  size_t offset;
  uint64_t observed, work, max_entries, max_name, max_work;
  struct stat identity;
  char path[DIRECTORY_PATH_BYTES + 1];
  unsigned char *buffer;
} directory_original;
struct directory_owner { napi_type_tag tag; };

#include "napi-filesystem-helpers.inc"
static directory_original *original(napi_env env, napi_callback_info info,
    size_t expected, napi_value *args, directory_owner **owner) {
  size_t count = expected; void *data = NULL;
  if (napi_get_cb_info(env, info, &count, args, NULL, &data) != napi_ok ||
      count != expected || !data) return NULL;
  *owner = data;
  bool matches = false;
  if (napi_check_object_type_tag(env, args[0], &(*owner)->tag, &matches) != napi_ok || !matches)
    return NULL;
  void *wrapped = NULL;
  if (napi_unwrap(env, args[0], &wrapped) != napi_ok || !wrapped) return NULL;
  /* Only this actual module instance's native tag may recognize a handle.
   * A copied object or another loaded instance cannot supply that original. */
  directory_original *item = wrapped;
  return item->owner == *owner ? item : NULL;
}
static void finalize(napi_env env, void *data, void *hint) {
  (void)env; (void)hint;
  directory_original *item = data;
  /* Uncertain originals keep a strong reference and never reach this path.
   * Environment/process teardown is not a physical close acknowledgement. */
  if (!item->closed && item->descriptor >= 0) return;
  free(item->buffer);
  free(item);
}
#if defined(__APPLE__)
static bool same_stat(const struct stat *left, const struct stat *right) {
  return left->st_dev == right->st_dev && left->st_ino == right->st_ino &&
    left->st_mode == right->st_mode && right->st_nlink != 0 &&
    left->st_mtimespec.tv_sec == right->st_mtimespec.tv_sec &&
    left->st_mtimespec.tv_nsec == right->st_mtimespec.tv_nsec &&
    left->st_ctimespec.tv_sec == right->st_ctimespec.tv_sec &&
    left->st_ctimespec.tv_nsec == right->st_ctimespec.tv_nsec;
}
static bool current(directory_original *item) {
  struct stat fd, path;
  struct statfs filesystem;
  if (item->failure || item->consumed || item->descriptor < 0) return false;
  if (fstat(item->descriptor, &fd) != 0 || lstat(item->path, &path) != 0 ||
      !same_stat(&item->identity, &fd) || !same_stat(&item->identity, &path) ||
      fstatfs(item->descriptor, &filesystem) != 0 || (filesystem.f_flags & MNT_UNION) ||
      memcmp(filesystem.f_fstypename, "apfs", sizeof("apfs")) != 0) {
    item->failure = ESTALE; return false;
  }
  return true;
}
#endif
static napi_value open_directory(napi_env env, napi_callback_info info) {
#if !defined(__APPLE__)
  (void)info; return unavailable(env, "HostJournalDirectoryPlatformUnavailable");
#else
  napi_value args[4], object; size_t count = 4, path_bytes = 0, path_units = 0; void *data = NULL;
  uint64_t entries, name, work; napi_valuetype type;
  if (napi_get_cb_info(env, info, &count, args, NULL, &data) != napi_ok || count != 4 ||
      !data || napi_typeof(env, args[0], &type) != napi_ok || type != napi_string ||
      napi_get_value_string_utf16(env, args[0], NULL, 0, &path_units) != napi_ok ||
      path_units == 0 || path_units > DIRECTORY_PATH_BYTES ||
      napi_get_value_string_utf8(env, args[0], NULL, 0, &path_bytes) != napi_ok ||
      path_bytes == 0 || path_bytes > DIRECTORY_PATH_BYTES ||
      !bound(env, args[1], DIRECTORY_MAX_ENTRIES, &entries) ||
      !bound(env, args[2], DIRECTORY_NAME_BYTES, &name) ||
      !bound(env, args[3], UINT64_C(9007199254740991), &work))
    return unavailable(env, "HostJournalDirectoryBoundsUnavailable");
  directory_owner *owner = data;
  directory_original *item = calloc(1, sizeof(*item));
  if (!item) return unavailable(env, "HostJournalDirectoryAllocationUnavailable");
  item->descriptor = -1; item->owner = owner;
  item->buffer = malloc(DIRECTORY_BYTES);
  if (!item->buffer) { free(item); return unavailable(env, "HostJournalDirectoryAllocationUnavailable"); }
  item->max_entries = entries; item->max_name = name; item->max_work = work;
  size_t copied;
  if (napi_get_value_string_utf8(env, args[0], item->path, sizeof(item->path), &copied) != napi_ok ||
      copied != path_bytes || memchr(item->path, 0, copied)) {
    free(item->buffer); free(item); return unavailable(env, "HostJournalDirectoryPathUnavailable");
  }
  /* Establish the JS wrapper and retained native custody BEFORE acquiring FD.
   * Every later failure is recorded on this returned original, so current()
   * refuses and the consumer can still call its one-shot physical close. */
  if (napi_create_object(env, &object) != napi_ok ||
      napi_type_tag_object(env, object, &owner->tag) != napi_ok) {
    free(item->buffer); free(item); return NULL;
  }
  if (napi_wrap(env, object, item, finalize, NULL, NULL) != napi_ok) {
    free(item->buffer); free(item); return NULL;
  }
  if (napi_create_reference(env, object, 1, &item->retained) != napi_ok) return NULL;
  item->descriptor = open(item->path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (item->descriptor < 0) { item->failure = errno; return object; }
  struct statfs filesystem;
  if (fstat(item->descriptor, &item->identity) != 0 ||
      !S_ISDIR(item->identity.st_mode) || fstatfs(item->descriptor, &filesystem) != 0) {
    item->failure = errno ? errno : EINVAL; return object;
  }
  if ((filesystem.f_flags & MNT_UNION) ||
      memcmp(filesystem.f_fstypename, "apfs", sizeof("apfs")) != 0)
    item->failure = ENOTSUP;
  return object;
#endif
}
static napi_value assert_current(napi_env env, napi_callback_info info) {
  napi_value args[1]; directory_owner *owner;
  directory_original *item = original(env, info, 1, args, &owner);
  (void)owner;
#if defined(__APPLE__)
  if (item && current(item)) return undefined(env);
#else
  (void)item;
#endif
  return unavailable(env, "HostJournalDirectoryCurrentUnavailable");
}
static napi_value next_name(napi_env env, napi_callback_info info) {
  napi_value args[1], result; directory_owner *owner;
  directory_original *item = original(env, info, 1, args, &owner);
  (void)owner;
#if !defined(__APPLE__)
  (void)item; return unavailable(env, "HostJournalDirectoryPlatformUnavailable");
#else
  if (!item || !current(item)) return unavailable(env, "HostJournalDirectoryCurrentUnavailable");
  while (!item->exhausted) {
    if (!item->remaining) {
      struct attrlist attributes = {0}; attributes.bitmapcount = ATTR_BIT_MAP_COUNT;
      attributes.commonattr = ATTR_BULK_REQUIRED;
      memset(item->buffer, 0, DIRECTORY_BYTES);
      int records = getattrlistbulk(item->descriptor, &attributes, item->buffer, DIRECTORY_BYTES, 0);
      if (records < 0) { item->failure = errno; return unavailable(env, "HostJournalDirectoryReadUnavailable"); }
      if (records == 0) { item->exhausted = true; break; }
      if (records > DIRECTORY_BYTES / 4) goto malformed;
      item->remaining = (uint32_t)records; item->offset = 0;
    }
    const size_t prefix = sizeof(uint32_t) + sizeof(attribute_set_t);
    uint32_t bytes; attribute_set_t returned; attrreference_t reference;
    if (item->offset > DIRECTORY_BYTES - sizeof(bytes)) goto malformed;
    unsigned char *record = item->buffer + item->offset;
    memcpy(&bytes, record, sizeof(bytes));
    if (bytes < prefix + sizeof(reference) || bytes > DIRECTORY_BYTES - item->offset) goto malformed;
    memcpy(&returned, record + sizeof(bytes), sizeof(returned));
    memcpy(&reference, record + prefix, sizeof(reference));
    if (!(returned.commonattr & ATTR_CMN_NAME) || reference.attr_dataoffset < (int)sizeof(reference) ||
        reference.attr_length < 2) goto malformed;
    size_t offset = (size_t)reference.attr_dataoffset, length = reference.attr_length;
    if (offset > bytes - prefix || length > bytes - prefix - offset ||
        length - 1 > item->max_name) goto malformed;
    const char *name = (char *)record + prefix + offset;
    if (name[length - 1] != 0 || memchr(name, 0, length - 1) || memchr(name, '/', length - 1)) goto malformed;
    item->offset += bytes; item->remaining--;
    /* Count native work, including dots and one refused lookahead, before
     * creating any returned JS Buffer. Kernel storage is always fixed. */
    if (length > item->max_work - item->work || ++item->observed > item->max_entries + 3) goto excessive;
    item->work += length;
    if ((length == 2 && name[0] == '.') || (length == 3 && name[0] == '.' && name[1] == '.')) continue;
    if (napi_create_buffer_copy(env, length - 1, name, NULL, &result) != napi_ok) return NULL;
    return result;
  }
  if (napi_get_null(env, &result) != napi_ok) return NULL;
  return result;
malformed:
  item->failure = EINVAL; return unavailable(env, "HostJournalDirectoryRecordUnavailable");
excessive:
  item->failure = EOVERFLOW; return unavailable(env, "HostJournalDirectoryBoundsUnavailable");
#endif
}
static napi_value close_directory(napi_env env, napi_callback_info info) {
  napi_value args[1], result, outcome, error; directory_owner *owner;
  directory_original *item = original(env, info, 1, args, &owner);
  (void)owner;
  if (!item) return unavailable(env, "HostJournalDirectoryOriginalUnavailable");
  if (!item->consumed) {
    item->consumed = true;
    int fd = item->descriptor; item->descriptor = -1;
    if (fd < 0 || close(fd) == 0) item->closed = true;
    else item->close_error = errno;
    /* Never retry EINTR or any other consumed close. A subsequent descriptor
     * with the same integer is not this original. Unknown remains retained. */
    if (item->closed && item->retained) {
      free(item->buffer); item->buffer = NULL;
      napi_delete_reference(env, item->retained); item->retained = NULL;
    }
  }
  if (napi_create_object(env, &result) != napi_ok ||
      napi_create_string_utf8(env, item->closed ? "closed" : "unknown", NAPI_AUTO_LENGTH, &outcome) != napi_ok ||
      napi_create_int32(env, item->close_error, &error) != napi_ok ||
      napi_set_named_property(env, result, "outcome", outcome) != napi_ok ||
      napi_set_named_property(env, result, "errno", error) != napi_ok ||
      napi_object_freeze(env, result) != napi_ok) return NULL;
  return result;
}
#include "../../connectors/local/site/root-filesystem.inc"

static napi_value initialize(napi_env env, napi_value exports) {
  directory_owner *owner = calloc(1, sizeof(*owner));
  if (!owner) return unavailable(env, "HostJournalDirectoryAllocationUnavailable");
  owner->tag.lower = (uint64_t)(uintptr_t)owner;
  owner->tag.upper = UINT64_C(0x414354514c444952);
  const char *names[] = {"open", "next", "current", "close"};
  napi_callback callbacks[] = {open_directory, next_name, assert_current, close_directory};
  for (size_t index = 0; index < 4; index++) {
    napi_value function;
    if (napi_create_function(env, names[index], NAPI_AUTO_LENGTH, callbacks[index], owner, &function) != napi_ok ||
        napi_set_named_property(env, exports, names[index], function) != napi_ok) return NULL;
  }
  if (!initialize_local_files(env, exports) || napi_object_freeze(env, exports) != napi_ok) return NULL;
  /* This selected native module/owner remains process-lived. Successful child
   * close retires only that child, never its loaded image or shared backing. */
  return exports;
}
NAPI_MODULE(NODE_GYP_MODULE_NAME, initialize)
