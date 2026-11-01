/* Physical staging only: the existing Effect Owner supplies the approved
 * request, original Content, claim and Account grant before these calls.
 * The original directory FD, not a resolved string, bounds every mutation. */
static napi_value local_fs_open_writer(napi_env env, napi_callback_info info) {
  napi_value args[4]; size_t count = 4; void *data = NULL;
  char temporary[LOCAL_NAME_BYTES + 1], destination[LOCAL_NAME_BYTES + 1];
  uint64_t maximum;
  if (napi_get_cb_info(env, info, &count, args, NULL, &data) != napi_ok || count != 4 || !data ||
      !local_fs_text(env, args[1], temporary, LOCAL_NAME_BYTES, false, false) ||
      !local_fs_text(env, args[2], destination, LOCAL_NAME_BYTES, false, false) ||
      !strcmp(temporary, destination) ||
      !bound(env, args[3], UINT64_C(2147483647), &maximum))
    return unavailable(env, "InvalidLocalFileWrite");
  local_fs_original *parent = local_fs_argument(env, args[0], data);
  if (!parent || !parent->directory || parent->depth >= LOCAL_DEPTH ||
      parent->children == UINT32_MAX || parent->stopping)
    return unavailable(env, "ForeignLocalFileRoot");
  /* Publish cleanup custody before the first lock/open/stat can fail. */
  napi_value object = local_fs_allocate(env, data, parent, args[0], temporary, false, 0);
  if (!object) return NULL;
  local_fs_original *original = local_fs_argument(env, object, data);
  if (!original || original->failure) return object;
  original->writable = true; original->max_write_bytes = maximum;
  memcpy(original->destination, destination, strlen(destination) + 1);
  local_fs_original *root = parent;
  while (root->parent) root = root->parent;
  if (root->write_active) {original->failure = EBUSY; return object;}
  if (flock(root->descriptor, LOCK_EX | LOCK_NB) != 0) {original->failure = errno; return object;}
  root->write_active = true; original->write_root = root; original->write_lock = true;
  original->descriptor = openat(parent->descriptor, temporary,
    O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0600);
  if (original->descriptor < 0) {original->failure = errno; return object;}
  if (fstat(original->descriptor, &original->identity) != 0 ||
      !S_ISREG(original->identity.st_mode) || original->identity.st_nlink != 1) {
    original->failure = errno ? errno : EINVAL; return object;
  }
  return object;
}

static napi_value local_fs_write(napi_env env, napi_callback_info info) {
  napi_value args[2]; size_t count = 2, length = 0; void *data = NULL, *bytes = NULL;
  bool buffer = false;
  if (napi_get_cb_info(env, info, &count, args, NULL, &data) != napi_ok || count != 2 || !data ||
      napi_is_buffer(env, args[1], &buffer) != napi_ok || !buffer ||
      napi_get_buffer_info(env, args[1], &bytes, &length) != napi_ok ||
      !length || length > LOCAL_READ_BYTES)
    return unavailable(env, "InvalidLocalFileWrite");
  local_fs_original *original = local_fs_argument(env, args[0], data);
  if (!local_fs_current(original) || !original->writable || original->published ||
      length > original->max_write_bytes - original->written)
    return unavailable(env, "LocalFileWriteUnavailable");
  size_t offset = 0;
  while (offset < length) {
    ssize_t amount = pwrite(original->descriptor, (unsigned char *)bytes + offset,
      length - offset, (off_t)(original->written + offset));
    if (amount < 0 && errno == EINTR) continue;
    if (amount <= 0) {
      original->failure = amount < 0 ? errno : EIO;
      return unavailable(env, "LocalFileWriteFailed");
    }
    offset += (size_t)amount;
  }
  original->written += length;
  return undefined(env);
}

static napi_value local_fs_publish(napi_env env, napi_callback_info info) {
  napi_value args[2]; size_t count = 2; void *data = NULL; bool overwrite;
  napi_valuetype type;
  if (napi_get_cb_info(env, info, &count, args, NULL, &data) != napi_ok || count != 2 || !data ||
      napi_typeof(env, args[1], &type) != napi_ok || type != napi_boolean ||
      napi_get_value_bool(env, args[1], &overwrite) != napi_ok)
    return unavailable(env, "InvalidLocalFileWrite");
  local_fs_original *original = local_fs_argument(env, args[0], data);
  if (!local_fs_current(original) || !original->writable || original->published)
    return unavailable(env, "LocalFileWriteUnavailable");
  if (fsync(original->descriptor) != 0) return unavailable(env, "LocalFileSyncFailed");
  /* Exclusive rename is the create condition itself, not a preceding exists
   * check. Replacement swaps the directory entry, never follows its symlink. */
  int result = local_fs_rename(original->parent->descriptor, original->name,
    original->destination, overwrite);
  if (result != 0) return unavailable(env,
    errno == EEXIST ? "LocalFileDestinationExists" : "LocalFilePublishFailed");
  original->published = true;
  memcpy(original->name, original->destination, strlen(original->destination) + 1);
  /* A failure after rename is an uncertain durable outcome. The Effect's
   * original claim/journal must reconcile it; this method never retries. */
  if (fsync(original->parent->descriptor) != 0)
    return unavailable(env, "LocalFilePublishDurabilityUnknown");
  return undefined(env);
}
