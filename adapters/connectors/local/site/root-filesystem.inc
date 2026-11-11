/* Local Connector I/O under an original directory descriptor. These handles
 * carry acquired descriptor custody, not Account, Run or read permission. */
#include <dirent.h>
#include <stdio.h>
#include <sys/file.h>

#include "root-filesystem-platform.inc"

#define LOCAL_MAX_ENTRIES 100000
#define LOCAL_NAME_BYTES 1024
#define LOCAL_ROOT_BYTES 4096
#define LOCAL_READ_BYTES 65536
/* The public reader ceiling counts relative path components. Its directory
 * iterator and final file add two physical child levels under that path. */
#define LOCAL_DEPTH 130

typedef struct local_fs_owner { napi_type_tag tag; } local_fs_owner;
typedef struct local_fs_original {
  local_fs_owner *owner;
  struct local_fs_original *parent;
  napi_ref retained, parent_reference;
  int descriptor, failure, close_error;
  bool consumed, closed, stopping, directory, writable, published, unlinked;
  bool write_active, write_lock, owner_lease;
  char lease_identity[37];
  struct local_fs_original *write_root;
  uint32_t children, depth;
  uint64_t entries, max_entries;
  uint64_t written, max_write_bytes;
  DIR *stream;
  struct stat identity;
  char name[LOCAL_ROOT_BYTES + 1];
  char destination[LOCAL_NAME_BYTES + 1];
} local_fs_original;

static bool local_fs_text(napi_env env, napi_value value, char *output,
    size_t maximum, bool root, bool self) {
  napi_valuetype type; size_t units = 0, bytes = 0, copied = 0;
  uint16_t text[LOCAL_ROOT_BYTES + 1];
  if (napi_typeof(env, value, &type) != napi_ok || type != napi_string ||
      napi_get_value_string_utf16(env, value, NULL, 0, &units) != napi_ok ||
      units > maximum || (!units && !self) ||
      napi_get_value_string_utf16(env, value, text, LOCAL_ROOT_BYTES + 1, &copied) != napi_ok ||
      copied != units) return false;
  for (size_t index = 0; index < units; index++) {
    uint16_t unit = text[index];
    if (!unit) return false;
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index == units || text[index] < 0xdc00 || text[index] > 0xdfff) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) return false;
  }
  if (napi_get_value_string_utf8(env, value, NULL, 0, &bytes) != napi_ok || bytes > maximum ||
      napi_get_value_string_utf8(env, value, output, maximum + 1, &copied) != napi_ok ||
      copied != bytes || memchr(output, 0, bytes)) return false;
  if (root) return bytes && output[0] == '/';
  return !strchr(output, '/') && strcmp(output, ".") && strcmp(output, "..");
}
static local_fs_original *local_fs_argument(napi_env env, napi_value value,
    local_fs_owner *owner) {
  bool matches = false; void *wrapped = NULL;
  if (napi_check_object_type_tag(env, value, &owner->tag, &matches) != napi_ok || !matches ||
      napi_unwrap(env, value, &wrapped) != napi_ok || !wrapped) return NULL;
  local_fs_original *original = wrapped;
  return original->owner == owner ? original : NULL;
}
static bool local_fs_same(const struct stat *a, const struct stat *b) {
  return a->st_dev == b->st_dev && a->st_ino == b->st_ino &&
    (a->st_mode & S_IFMT) == (b->st_mode & S_IFMT) && b->st_nlink != 0;
}
static bool local_fs_current(local_fs_original *original) {
  if (!original || original->consumed || original->stopping || original->failure || original->descriptor < 0) return false;
  struct stat descriptor, named;
  if (fstat(original->descriptor, &descriptor) != 0 ||
      !local_fs_same(&original->identity, &descriptor)) goto stale;
  if (original->parent) {
    if (!local_fs_current(original->parent) ||
        fstatat(original->parent->descriptor, original->name[0] ? original->name : ".",
          &named, AT_SYMLINK_NOFOLLOW) != 0) goto stale;
  } else if (lstat(original->name, &named) != 0) goto stale;
  if (!local_fs_same(&original->identity, &named)) goto stale;
  return true;
stale:
  original->failure = ESTALE; return false;
}
static void local_fs_finalize(napi_env env, void *data, void *hint) {
  (void)env; (void)hint;
  local_fs_original *original = data;
  /* A strong reference retains every live or uncertain physical original.
   * Finalization/process teardown is never used to acknowledge its close. */
  if (original->descriptor >= 0 || original->stream || original->parent_reference) return;
  free(original);
}
static napi_value local_fs_allocate(napi_env env, local_fs_owner *owner,
    local_fs_original *parent, napi_value parent_value, const char *name,
    bool directory, uint64_t entries) {
  local_fs_original *original = calloc(1, sizeof(*original)); napi_value object;
  if (!original) return unavailable(env, "LocalFileAllocationFailed");
  original->owner = owner; original->descriptor = -1;
  original->directory = directory; original->max_entries = entries;
  original->parent = parent; original->depth = parent ? parent->depth + 1 : 0;
  memcpy(original->name, name, strlen(name) + 1);
  if (napi_create_object(env, &object) != napi_ok ||
      napi_type_tag_object(env, object, &owner->tag) != napi_ok) {free(original); return NULL;}
  if (napi_wrap(env, object, original, local_fs_finalize, NULL, NULL) != napi_ok) {
    free(original); return NULL;
  }
  if (parent && napi_create_reference(env, parent_value, 1, &original->parent_reference) != napi_ok) return NULL;
  if (napi_create_reference(env, object, 1, &original->retained) != napi_ok) {
    if (original->parent_reference) {
      napi_delete_reference(env, original->parent_reference); original->parent_reference = NULL;
    }
    return NULL;
  }
  /* Publish the cleanup-capable wrapper before the first fallible syscall.
   * Failed open/stat/stream initialization returns this same original. */
  if (parent) {
    parent->children++;
    if (!local_fs_current(parent)) {original->failure = ESTALE; return object;}
  }
  return object;
}
static napi_value local_fs_create(napi_env env, local_fs_owner *owner,
    local_fs_original *parent, napi_value parent_value, const char *name,
    bool directory, uint64_t entries) {
  napi_value object = local_fs_allocate(env, owner, parent, parent_value, name, directory, entries);
  if (!object) return NULL;
  local_fs_original *original = local_fs_argument(env, object, owner);
  if (!original || original->failure) return object;
  if (parent) {
    struct stat named;
    if (fstatat(parent->descriptor, name[0] ? name : ".", &named, AT_SYMLINK_NOFOLLOW) != 0) {
      original->failure = errno; return object;
    }
    if (directory ? !S_ISDIR(named.st_mode) : !S_ISREG(named.st_mode)) {
      original->failure = EINVAL; return object;
    }
  }
  /* Nonblocking open also prevents a raced regular-file-to-FIFO replacement
   * from blocking before fstat can reject the acquired non-regular child. */
  int flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK | (directory ? O_DIRECTORY : 0);
  original->descriptor = parent
    ? openat(parent->descriptor, name[0] ? name : ".", flags) : open(name, flags);
  if (original->descriptor < 0) {original->failure = errno; return object;}
  if (fstat(original->descriptor, &original->identity) != 0) {
    original->failure = errno; return object;
  }
  if (directory ? !S_ISDIR(original->identity.st_mode) : !S_ISREG(original->identity.st_mode)) {
    original->failure = EINVAL; return object;
  }
  if (directory && parent) {
    original->stream = fdopendir(original->descriptor);
    if (!original->stream) original->failure = errno;
  }
  return object;
}
static napi_value local_fs_open_root(napi_env env, napi_callback_info info) {
  napi_value args[1]; size_t count = 1; void *data = NULL;
  char path[LOCAL_ROOT_BYTES + 1];
  if (napi_get_cb_info(env, info, &count, args, NULL, &data) != napi_ok || count != 1 || !data ||
      !local_fs_text(env, args[0], path, LOCAL_ROOT_BYTES, true, false))
    return unavailable(env, "InvalidLocalFileRoot");
  return local_fs_create(env, data, NULL, NULL, path, true, 0);
}
static napi_value local_fs_open_child(napi_env env, napi_callback_info info, bool directory) {
  napi_value args[3]; size_t count = directory ? 3 : 2; void *data = NULL;
  char name[LOCAL_NAME_BYTES + 1]; uint64_t entries = 0;
  if (napi_get_cb_info(env, info, &count, args, NULL, &data) != napi_ok ||
      count != (directory ? 3u : 2u) || !data ||
      !local_fs_text(env, args[1], name, LOCAL_NAME_BYTES, false, directory) ||
      (directory && !bound(env, args[2], LOCAL_MAX_ENTRIES, &entries)))
    return unavailable(env, "InvalidLocalFileChild");
  local_fs_original *parent = local_fs_argument(env, args[0], data);
  if (!parent || !parent->directory || parent->depth >= LOCAL_DEPTH ||
      parent->children == UINT32_MAX) return unavailable(env, "ForeignLocalFileRoot");
  if (parent->stopping) return unavailable(env, "LocalFileOriginalChanged");
  return local_fs_create(env, data, parent, args[0], name, directory, entries);
}
static napi_value local_fs_open_directory(napi_env env, napi_callback_info info) {
  return local_fs_open_child(env, info, true);
}
static napi_value local_fs_open_file(napi_env env, napi_callback_info info) {
  return local_fs_open_child(env, info, false);
}
static local_fs_original *local_fs_one(napi_env env, napi_callback_info info) {
  napi_value args[1]; size_t count = 1; void *data = NULL;
  if (napi_get_cb_info(env, info, &count, args, NULL, &data) != napi_ok || count != 1 || !data) return NULL;
  return local_fs_argument(env, args[0], data);
}
static napi_value local_fs_check(napi_env env, napi_callback_info info) {
  if (!local_fs_current(local_fs_one(env, info))) return unavailable(env, "LocalFileOriginalChanged");
  return undefined(env);
}
static bool local_fs_bigint(napi_env env, napi_value result, const char *name, int64_t number) {
  napi_value value;
  return napi_create_bigint_int64(env, number, &value) == napi_ok &&
    napi_set_named_property(env, result, name, value) == napi_ok;
}
static napi_value local_fs_stat(napi_env env, napi_callback_info info) {
  local_fs_original *original = local_fs_one(env, info); struct stat value; napi_value result;
  if (!local_fs_current(original) || fstat(original->descriptor, &value) != 0)
    return unavailable(env, "LocalFileOriginalChanged");
  int64_t modified_seconds, modified_nanos, changed_seconds, changed_nanos;
  local_fs_times(&value, &modified_seconds, &modified_nanos, &changed_seconds, &changed_nanos);
  /* Keep the native seconds/nanos pair exact; no binary64 timestamp/size path. */
  if (napi_create_object(env, &result) != napi_ok ||
      !local_fs_bigint(env, result, "dev", value.st_dev) ||
      !local_fs_bigint(env, result, "ino", value.st_ino) ||
      !local_fs_bigint(env, result, "size", value.st_size) ||
      !local_fs_bigint(env, result, "links", value.st_nlink) ||
      !local_fs_bigint(env, result, "modifiedSeconds", modified_seconds) ||
      !local_fs_bigint(env, result, "modifiedNanos", modified_nanos) ||
      !local_fs_bigint(env, result, "changedSeconds", changed_seconds) ||
      !local_fs_bigint(env, result, "changedNanos", changed_nanos) ||
      napi_object_freeze(env, result) != napi_ok) return NULL;
  return result;
}
/* A single stable anchor extends the SAME Store exclusion. Opaque original
 * custody and child-before-parent close use the existing Files handles. */
static bool local_fs_lease_identity(const char *value) {
  for (size_t i = 0; i < 36; i++) {
    if (i == 8 || i == 13 || i == 18 || i == 23) {if (value[i] != '-') return false;}
    else if (!((value[i] >= '0' && value[i] <= '9') || (value[i] >= 'a' && value[i] <= 'f'))) return false;
  }
  return value[36] == 0;
}
static napi_value local_fs_open_lease(napi_env env, napi_callback_info info) {
  napi_value args[2]; size_t count = 2; void *data = NULL; char identity[LOCAL_ROOT_BYTES + 1];
  if (napi_get_cb_info(env, info, &count, args, NULL, &data) != napi_ok || count != 2 || !data ||
      !local_fs_text(env, args[1], identity, 36, false, false) || !local_fs_lease_identity(identity))
    return unavailable(env, "InvalidPublicationOwnerLease");
  local_fs_original *parent = local_fs_argument(env, args[0], data);
  if (!local_fs_current(parent) || !parent->directory || parent->depth != 0 ||
      parent->identity.st_uid != geteuid() || (parent->identity.st_mode & 077) != 0)
    return unavailable(env, "ForeignPublicationOwnerRoot");
  napi_value object = local_fs_allocate(env, data, parent, args[0], "owner-lease", false, 0);
  if (!object) return NULL;
  local_fs_original *original = local_fs_argument(env, object, data);
  if (!original || original->failure) return object;
  int flags = O_RDWR | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK;
  original->descriptor = openat(parent->descriptor, original->name, flags | O_CREAT | O_EXCL, 0600);
  bool created = original->descriptor >= 0;
  if (!created && errno == EEXIST) original->descriptor = openat(parent->descriptor, original->name, flags);
  if (original->descriptor < 0) {original->failure = errno; return object;}
  if (fstat(original->descriptor, &original->identity) != 0) {original->failure = errno; return object;}
  if (!S_ISREG(original->identity.st_mode) || original->identity.st_uid != geteuid() ||
      (original->identity.st_mode & 077) != 0 || !local_fs_current(original)) {
    original->failure = ESTALE; return object;
  }
  if (flock(original->descriptor, LOCK_EX | LOCK_NB) != 0) {original->failure = errno; return object;}
  if (created) {
    size_t offset = 0;
    while (offset < 36) {
      ssize_t wrote = pwrite(original->descriptor, identity + offset, 36 - offset, (off_t)offset);
      if (wrote < 0 && errno == EINTR) continue;
      if (wrote <= 0) {original->failure = wrote < 0 ? errno : EIO; return object;}
      offset += (size_t)wrote;
    }
    if (fsync(original->descriptor) != 0 || fsync(parent->descriptor) != 0) {
      original->failure = errno; return object;
    }
  }
  struct stat status;
  if (fstat(original->descriptor, &status) != 0 || status.st_size != 36) {
    original->failure = EINVAL; return object;
  }
  size_t offset = 0;
  while (offset < 36) {
    ssize_t read = pread(original->descriptor, original->lease_identity + offset, 36 - offset, (off_t)offset);
    if (read < 0 && errno == EINTR) continue;
    if (read <= 0) {original->failure = read < 0 ? errno : EIO; return object;}
    offset += (size_t)read;
  }
  original->lease_identity[36] = 0;
  if (!local_fs_lease_identity(original->lease_identity) || !local_fs_current(original)) {
    original->failure = ESTALE; return object;
  }
  original->owner_lease = true;
  return object;
}
static napi_value local_fs_lease_receipt(napi_env env, napi_callback_info info) {
  local_fs_original *original = local_fs_one(env, info); napi_value result, identity;
  if (original && (original->failure == EWOULDBLOCK || original->failure == EAGAIN))
    return unavailable(env, "PublicationStoreBusy");
  struct stat status, root_status; char identity_bytes[36];
  if (!original || !original->owner_lease || !local_fs_current(original) ||
      fstat(original->descriptor, &status) != 0 || status.st_uid != geteuid() ||
      (status.st_mode & 077) != 0 || status.st_size != 36 || !original->parent ||
      fstat(original->parent->descriptor, &root_status) != 0 || root_status.st_uid != geteuid() ||
      (root_status.st_mode & 077) != 0)
    return unavailable(env, "PublicationStoreLeaseUnavailable");
  size_t offset = 0;
  while (offset < sizeof(identity_bytes)) {
    ssize_t read = pread(original->descriptor, identity_bytes + offset, sizeof(identity_bytes) - offset, (off_t)offset);
    if (read < 0 && errno == EINTR) continue;
    if (read <= 0) return unavailable(env, "PublicationStoreLeaseUnavailable");
    offset += (size_t)read;
  }
  if (memcmp(identity_bytes, original->lease_identity, sizeof(identity_bytes)) || !local_fs_current(original))
    return unavailable(env, "PublicationStoreLeaseUnavailable");
  if (napi_create_object(env, &result) != napi_ok ||
      napi_create_string_utf8(env, original->lease_identity, 36, &identity) != napi_ok ||
      napi_set_named_property(env, result, "identity", identity) != napi_ok ||
      !local_fs_bigint(env, result, "device", status.st_dev) ||
      !local_fs_bigint(env, result, "inode", status.st_ino) || napi_object_freeze(env, result) != napi_ok) return NULL;
  return result;
}
/* Private Store metadata entry. The destination is fixed, and no public Files
 * publish/overwrite semantics are widened. JS owns the already-synced closed
 * record and both directory durability acknowledgements. */
static napi_value local_fs_publish_store_owner(napi_env env, napi_callback_info info) {
  napi_value args[4]; size_t count = 4; void *data = NULL;
  char name[LOCAL_NAME_BYTES + 1]; uint64_t device, inode; bool lossless;
  if (napi_get_cb_info(env, info, &count, args, NULL, &data) != napi_ok || count != 4 || !data ||
      !local_fs_text(env, args[1], name, LOCAL_NAME_BYTES, false, false) ||
      strncmp(name, ".owner-opening-", 15) || strlen(name) != 51 ||
      !local_fs_lease_identity(name + 15) ||
      napi_get_value_bigint_uint64(env, args[2], &device, &lossless) != napi_ok || !lossless ||
      napi_get_value_bigint_uint64(env, args[3], &inode, &lossless) != napi_ok || !lossless)
    return unavailable(env, "InvalidPublicationStoreOwner");
  local_fs_original *root = local_fs_argument(env, args[0], data);
  struct stat staged;
  if (!local_fs_current(root) || !root->directory || root->depth != 0 ||
      fstatat(root->descriptor, name, &staged, AT_SYMLINK_NOFOLLOW) != 0 ||
      !S_ISDIR(staged.st_mode) || staged.st_uid != geteuid() || (staged.st_mode & 077) ||
      (uint64_t)staged.st_dev != device || (uint64_t)staged.st_ino != inode)
    return unavailable(env, "PublicationStoreOwnershipLost");
  if (local_fs_rename(root->descriptor, name, "owner", false) != 0)
    return unavailable(env, errno == EEXIST || errno == ENOTEMPTY ?
      "PublicationStoreBusy" : "PublicationStoreOwnerPublishFailed");
  return undefined(env);
}
/* Replace only this Store's complete lease metadata under the original owner
 * directory descriptor. Compare the old physical original immediately before
 * rename; a copied token or callback substitution is never the original. */
static napi_value local_fs_replace_store_owner(napi_env env, napi_callback_info info) {
  napi_value args[11]; size_t count = 11; void *data = NULL;
  char name[LOCAL_NAME_BYTES + 1]; int64_t expected[9]; bool lossless;
  if (napi_get_cb_info(env, info, &count, args, NULL, &data) != napi_ok || count != 11 || !data ||
      !local_fs_text(env, args[1], name, LOCAL_NAME_BYTES, false, false) ||
      strncmp(name, ".lease-", 7) || strlen(name) != 48 || strcmp(name + 43, ".json"))
    return unavailable(env, "InvalidPublicationStoreOwner");
  for (size_t index = 0; index < 9; index++) {
    if (napi_get_value_bigint_int64(env, args[index + 2], &expected[index], &lossless) != napi_ok || !lossless)
      return unavailable(env, "InvalidPublicationStoreOwner");
  }
  local_fs_original *directory = local_fs_argument(env, args[0], data);
  struct stat before, staged; int64_t ms, mn, cs, cn;
  if (!local_fs_current(directory) || !directory->directory || directory->depth != 1 ||
      strcmp(directory->name, "owner") ||
      (int64_t)directory->identity.st_dev != expected[7] ||
      (int64_t)directory->identity.st_ino != expected[8] ||
      fstatat(directory->descriptor, "owner.json", &before, AT_SYMLINK_NOFOLLOW) != 0 ||
      fstatat(directory->descriptor, name, &staged, AT_SYMLINK_NOFOLLOW) != 0 ||
      !S_ISREG(before.st_mode) || !S_ISREG(staged.st_mode) ||
      (int64_t)before.st_dev != expected[0] || (int64_t)before.st_ino != expected[1] ||
      before.st_size != expected[2] || (int64_t)staged.st_dev != expected[5] ||
      (int64_t)staged.st_ino != expected[6])
    return unavailable(env, "PublicationStoreOwnershipLost");
  local_fs_times(&before, &ms, &mn, &cs, &cn);
  if (ms * INT64_C(1000000000) + mn != expected[3] ||
      cs * INT64_C(1000000000) + cn != expected[4])
    return unavailable(env, "PublicationStoreOwnershipLost");
  if (local_fs_rename(directory->descriptor, name, "owner.json", true) != 0)
    return unavailable(env, "PublicationStoreOwnerPublishFailed");
  return undefined(env);
}
static napi_value local_fs_entry_kind(napi_env env, napi_callback_info info) {
  napi_value args[2], result; size_t count = 2; void *data = NULL;
  char name[LOCAL_NAME_BYTES + 1]; struct stat status;
  if (napi_get_cb_info(env, info, &count, args, NULL, &data) != napi_ok || count != 2 || !data ||
      !local_fs_text(env, args[1], name, LOCAL_NAME_BYTES, false, false))
    return unavailable(env, "InvalidLocalFileChild");
  local_fs_original *parent = local_fs_argument(env, args[0], data);
  if (!local_fs_current(parent) || !parent->directory)
    return unavailable(env, "LocalFileOriginalChanged");
  if (fstatat(parent->descriptor, name, &status, AT_SYMLINK_NOFOLLOW) != 0)
    return unavailable(env, "LocalFileEntryUnavailable");
  /* This observation selects an open operation, not identity or authority.
   * The subsequent descriptor acquisition independently checks its kind. */
  const char *kind = S_ISREG(status.st_mode) ? "file" : S_ISDIR(status.st_mode) ? "directory"
    : S_ISLNK(status.st_mode) ? "symlink" : "other";
  return napi_create_string_utf8(env, kind, NAPI_AUTO_LENGTH, &result) == napi_ok ? result : NULL;
}
static napi_value local_fs_next(napi_env env, napi_callback_info info) {
  local_fs_original *original = local_fs_one(env, info); napi_value result;
  if (!local_fs_current(original) || !original->stream)
    return unavailable(env, "LocalFileOriginalChanged");
  for (;;) {
    errno = 0; struct dirent *entry = readdir(original->stream);
    if (!entry) {
      if (errno) {original->failure = errno; return unavailable(env, "LocalDirectoryReadFailed");}
      return napi_get_null(env, &result) == napi_ok ? result : NULL;
    }
    size_t length = strnlen(entry->d_name, LOCAL_NAME_BYTES + 1);
    if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
    if (!length || length > LOCAL_NAME_BYTES || ++original->entries > original->max_entries) {
      original->failure = EOVERFLOW; return unavailable(env, "LocalDirectoryEntryLimit");
    }
    return napi_create_buffer_copy(env, length, entry->d_name, NULL, &result) == napi_ok ? result : NULL;
  }
}
static napi_value local_fs_read(napi_env env, napi_callback_info info) {
  napi_value args[3], result; size_t count = 3; void *data = NULL;
  uint64_t amount; double offset; napi_valuetype type;
  if (napi_get_cb_info(env, info, &count, args, NULL, &data) != napi_ok || count != 3 || !data ||
      !bound(env, args[2], LOCAL_READ_BYTES, &amount) ||
      napi_typeof(env, args[1], &type) != napi_ok || type != napi_number ||
      napi_get_value_double(env, args[1], &offset) != napi_ok ||
      !(offset >= 0 && offset <= 9007199254740991.0) || (double)(int64_t)offset != offset)
    return unavailable(env, "InvalidLocalFileReadBounds");
  local_fs_original *original = local_fs_argument(env, args[0], data);
  if (!local_fs_current(original) || original->directory)
    return unavailable(env, "LocalFileOriginalChanged");
  unsigned char bytes[LOCAL_READ_BYTES];
  ssize_t read_bytes = pread(original->descriptor, bytes, amount, (off_t)offset);
  if (read_bytes < 0) return unavailable(env, "LocalFileReadFailed");
  return napi_create_buffer_copy(env, (size_t)read_bytes, bytes, NULL, &result) == napi_ok ? result : NULL;
}
static napi_value local_fs_close(napi_env env, napi_callback_info info) {
  local_fs_original *original = local_fs_one(env, info); napi_value result, outcome, error;
  if (!original) return unavailable(env, "ForeignLocalFileRoot");
  original->stopping = true;
  if (!original->consumed && !original->children) {
    if (original->writable && !original->published && original->descriptor >= 0) {
      struct stat descriptor, named, parent;
      /* Abort removes only this acquired temporary inode. A substituted name
       * or uncertain unlink is retained, never mistaken for cleanup ACK. */
      if (original->parent->descriptor < 0 ||
          fstat(original->parent->descriptor, &parent) != 0 ||
          !local_fs_same(&original->parent->identity, &parent)) {
        original->failure = errno ? errno : ESTALE;
        goto observed;
      }
      if (!original->unlinked) {
        if (fstat(original->descriptor, &descriptor) != 0 ||
            fstatat(original->parent->descriptor, original->name, &named, AT_SYMLINK_NOFOLLOW) != 0 ||
            !local_fs_same(&descriptor, &named) ||
            unlinkat(original->parent->descriptor, original->name, 0) != 0) {
          original->failure = errno ? errno : ESTALE; goto observed;
        }
        original->unlinked = true;
      }
      if (fsync(original->parent->descriptor) != 0) {
        original->failure = errno; goto observed;
      }
    }
    original->consumed = true;
    int descriptor = original->descriptor; original->descriptor = -1;
    DIR *stream = original->stream; original->stream = NULL;
    if (descriptor < 0 || (stream ? closedir(stream) : close(descriptor)) == 0) original->closed = true;
    else original->close_error = errno;
    if (original->closed && original->write_lock) {
      if (flock(original->write_root->descriptor, LOCK_UN) != 0) {
        original->closed = false; original->close_error = errno;
      } else {
        original->write_root->write_active = false;
        original->write_lock = false; original->write_root = NULL;
      }
    }
    if (original->closed) {
      if (original->parent_reference) {
        original->parent->children--;
        napi_delete_reference(env, original->parent_reference); original->parent_reference = NULL;
        original->parent = NULL;
      }
      if (original->retained) {
        napi_delete_reference(env, original->retained); original->retained = NULL;
      }
    }
  }
observed:;
  const char *state = original->closed ? "closed" : original->consumed ? "unknown" : "pending";
  if (napi_create_object(env, &result) != napi_ok ||
      napi_create_string_utf8(env, state, NAPI_AUTO_LENGTH, &outcome) != napi_ok ||
      napi_create_int32(env, original->close_error, &error) != napi_ok ||
      napi_set_named_property(env, result, "outcome", outcome) != napi_ok ||
      napi_set_named_property(env, result, "errno", error) != napi_ok ||
      napi_object_freeze(env, result) != napi_ok) return NULL;
  return result;
}
#include "root-file-writer.inc"
/* Inert implementation DATA from this same image, not a Resource or allowance.
 * Each retained path descriptor owns one real allocation, including its name
 * arrays. Fixed N-API/call-stack overhead is not a second per-wrapper quote. */
static napi_value local_fs_write_construction_profile(napi_env env, napi_callback_info info) {
  size_t count = 0; void *data = NULL; napi_value result;
  if (napi_get_cb_info(env, info, &count, NULL, NULL, &data) != napi_ok || count != 0 || !data ||
      napi_create_object(env, &result) != napi_ok) return NULL;
  const char *names[] = {"nativeOriginalBytes", "maxRootBytes", "maxNameBytes", "maxDepth", "writeQuantumBytes"};
  const int64_t values[] = {sizeof(local_fs_original), LOCAL_ROOT_BYTES, LOCAL_NAME_BYTES,
    LOCAL_DEPTH, LOCAL_READ_BYTES};
  for (size_t index = 0; index < sizeof(values) / sizeof(values[0]); index++) {
    napi_value value;
    if (napi_create_int64(env, values[index], &value) != napi_ok ||
        napi_set_named_property(env, result, names[index], value) != napi_ok) return NULL;
  }
  if (napi_object_freeze(env, result) != napi_ok) return NULL;
  return result;
}
static bool initialize_local_files(napi_env env, napi_value exports) {
  local_fs_owner *owner = calloc(1, sizeof(*owner));
  if (!owner) {unavailable(env, "LocalFileAllocationFailed"); return false;}
  owner->tag.lower = (uint64_t)(uintptr_t)owner; owner->tag.upper = UINT64_C(0x414354514c46494c);
  const char *names[] = {"openFileRoot", "openFileDirectory", "openRootFile", "fileRootCurrent",
    "fileRootStat", "fileRootNext", "fileRootRead", "fileRootClose", "fileRootEntryKind",
    "openRootFileWriter", "fileRootWrite", "fileRootPublish", "openStoreOwnerLease", "storeOwnerLeaseReceipt",
    "localFileWriteConstructionProfile", "publishStoreOwnerDirectory", "replaceStoreOwnerMetadata"};
  napi_callback callbacks[] = {local_fs_open_root, local_fs_open_directory, local_fs_open_file,
    local_fs_check, local_fs_stat, local_fs_next, local_fs_read, local_fs_close, local_fs_entry_kind,
    local_fs_open_writer, local_fs_write, local_fs_publish, local_fs_open_lease, local_fs_lease_receipt,
    local_fs_write_construction_profile, local_fs_publish_store_owner, local_fs_replace_store_owner};
  for (size_t index = 0; index < sizeof(callbacks) / sizeof(callbacks[0]); index++) {
    napi_value function;
    if (napi_create_function(env, names[index], NAPI_AUTO_LENGTH, callbacks[index], owner, &function) != napi_ok ||
        napi_set_named_property(env, exports, names[index], function) != napi_ok) return false;
  }
  return true;
}
