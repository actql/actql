/* Included by the existing filesystem Owner after its ordinary census. The
 * selected command never asks libc to construct/grow a DIR or fill/sort an
 * entire union directory. No generic census or object-name rule changes. */
#define ACTQL_COMMAND_CENSUS_BYTES 65536

#ifdef ACTQL_SCOPED_READ_ALLOCATOR
extern actql_read_context *actql_bootstrap_current_read_context(void);
#endif

#if defined(__APPLE__) && defined(ACTQL_SCOPED_READ_ALLOCATOR)
/* Required getattrlistbulk attributes, packed in their documented order.
 * Copy fields rather than dereferencing potentially unaligned kernel data. */
static const char *actql_command_census_name(
    const unsigned char *record, size_t bytes) {
  const size_t prefix = sizeof(uint32_t) + sizeof(attribute_set_t);
  attribute_set_t returned;
  attrreference_t reference;
  if (bytes < prefix + sizeof(reference)) return NULL;
  memcpy(&returned, record + sizeof(uint32_t), sizeof(returned));
  memcpy(&reference, record + prefix, sizeof(reference));
  if (!(returned.commonattr & ATTR_CMN_NAME) || reference.attr_dataoffset < 0 ||
      reference.attr_length == 0) return NULL;
  size_t offset = (size_t)reference.attr_dataoffset;
  if (offset < sizeof(reference) || offset > bytes - prefix ||
      reference.attr_length > bytes - prefix - offset) return NULL;
  const char *name = (const char *)record + prefix + offset;
  size_t length = reference.attr_length;
  if (name[length - 1] != 0 || memchr(name, 0, length - 1)) return NULL;
  return name;
}

/* Only the public bounded kernel attribute interface is used. Unsupported
 * filesystems refuse, including union stacks whose duplicate-hiding semantics
 * would require an unbounded read/sort. No alternate libc route is selected. */
static int32_t actql_command_directory_census_bounded(
    actql_native_filesystem_root *root, moonbit_bytes_t frame,
    int32_t length, int32_t count) {
  if (!actql_census_frame_valid(frame, length, count)) return 4;
  if (!root || root->fd < 0) return -1;
  if (root->census_cleanup_unconfirmed || root->namespace_cleanup_unconfirmed)
    return 3;
  if (root->census_stream || root->census_descriptor_acquired) return -1;
  struct stat original;
  struct statfs filesystem;
  if (fstat(root->fd, &original) != 0 || !S_ISDIR(original.st_mode) ||
      fstatfs(root->fd, &filesystem) != 0) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling,
      "inspect selected directory census failed");
    return -1;
  }
  if (filesystem.f_flags & MNT_UNION) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling,
      "selected directory census filesystem unavailable");
    return -1;
  }
  unsigned char *seen = count == 0 ? NULL : calloc((size_t)count, 1);
  unsigned char *buffer = malloc(ACTQL_COMMAND_CENSUS_BYTES);
  if ((count != 0 && !seen) || !buffer) {
    free(seen); free(buffer); return 2;
  }
  int descriptor = openat(root->fd, ".",
    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (descriptor < 0) {
    free(seen); free(buffer);
    actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling,
      "open selected directory census", errno);
    return -1;
  }
  root->census_descriptor = descriptor;
  root->census_descriptor_acquired = true;
  root->census_descriptor_close_consumed = false;
  struct attrlist attributes = {0};
  attributes.bitmapcount = ATTR_BIT_MAP_COUNT;
  attributes.commonattr = ATTR_BULK_REQUIRED;
  int32_t result = 0, observed = 0;
  bool malformed = false;
  while (result == 0) {
    int entries = getattrlistbulk(descriptor, &attributes, buffer,
      ACTQL_COMMAND_CENSUS_BYTES, 0);
    if (entries < 0) {
      actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling,
        "read selected directory census", errno);
      result = -1; break;
    }
    if (entries == 0) break;
    size_t offset = 0;
    for (int entry = 0; entry < entries; ++entry) {
      if (++observed > count + 2) {result = 1; break;}
      if (offset > ACTQL_COMMAND_CENSUS_BYTES - sizeof(uint32_t)) {
        malformed = true; result = -1; break;
      }
      uint32_t bytes;
      memcpy(&bytes, buffer + offset, sizeof(bytes));
      if (bytes == 0 || bytes > ACTQL_COMMAND_CENSUS_BYTES - offset) {
        malformed = true; result = -1; break;
      }
      const char *name = actql_command_census_name(buffer + offset, bytes);
      offset += bytes;
      if (!name) {malformed = true; result = -1; break;}
      if (!strcmp(name, ".") || !strcmp(name, "..")) continue;
      int32_t frame_offset = 0, matched = -1;
      unsigned char kind = 0;
      for (int32_t index = 0; index < count; ++index) {
        const char *expected = (const char *)frame + frame_offset + 1;
        if (!strcmp(expected, name)) {
          matched = index; kind = frame[frame_offset]; break;
        }
        frame_offset += (int32_t)strlen(expected) + 2;
      }
      if (matched < 0 || seen[matched]) {result = 1; break;}
      struct stat member;
      if (fstatat(root->fd, name, &member, AT_SYMLINK_NOFOLLOW) != 0) {
        int error = errno;
        result = error == ENOENT ? 1 : -1;
        actql_replace_bounded_errno_error(&root->error,
          root->diagnostic_ceiling, "inspect selected census member", error);
        break;
      }
      if ((kind == 'f' && !S_ISREG(member.st_mode)) ||
          (kind == 'd' && !S_ISDIR(member.st_mode))) {result = 1; break;}
      seen[matched] = 1;
    }
  }
  if (malformed)
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling,
      "invalid selected directory census record");
  if (result == 0) {
    for (int32_t index = 0; index < count; ++index)
      if (!seen[index]) {result = 1; break;}
    struct stat current;
    if (fstat(root->fd, &current) != 0 || current.st_dev != original.st_dev ||
        current.st_ino != original.st_ino || current.st_mode != original.st_mode ||
        current.st_nlink == 0 || current.st_mtime != original.st_mtime ||
        current.st_ctime != original.st_ctime ||
        current.st_mtimespec.tv_nsec != original.st_mtimespec.tv_nsec ||
        current.st_ctimespec.tv_nsec != original.st_ctimespec.tv_nsec) result = 1;
  }
  free(seen); free(buffer);
  root->census_descriptor_close_consumed = true;
  int closed = close(descriptor), error = errno;
  if (root->test_census_close_failures > 0) {
    root->test_census_close_failures--; closed = -1; error = EIO;
  }
  if (closed != 0) {
    actql_census_unconfirmed(root, "close selected directory census", error);
    return 3;
  }
  root->census_descriptor = -1;
  root->census_descriptor_acquired = false;
  return result;
}
#endif

int32_t actql_native_filesystem_command_directory_census(
    actql_native_filesystem_root *root, moonbit_bytes_t frame,
    int32_t length, int32_t count) {
#if defined(__APPLE__) && defined(ACTQL_SCOPED_READ_ALLOCATOR)
  if (actql_native_command_platform_current() && root &&
      root->read_context_user && root->read_context &&
      actql_bootstrap_current_read_context() == root->read_context)
    return actql_command_directory_census_bounded(root, frame, length, count);
#else
  (void)frame; (void)length; (void)count;
#endif
  if (root) actql_replace_bounded_error(&root->error, root->diagnostic_ceiling,
    "selected directory census original unavailable");
  return -1;
}
