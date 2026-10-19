/* Selected Darwin command ACL observation uses a fixed caller-owned kernel
 * attribute buffer. It never constructs libc filesec/ACL objects or retries
 * with a growing buffer. The ordinary filesystem ACL route is unchanged. */
#if defined(__APPLE__) && defined(ACTQL_SCOPED_READ_ALLOCATOR)
#include <sys/kauth.h>

#define ACTQL_COMMAND_ACL_BYTES 4096
_Static_assert(sizeof(uint32_t) + sizeof(attrreference_t) +
  KAUTH_FILESEC_SIZE(KAUTH_ACL_MAX_ENTRIES) <= ACTQL_COMMAND_ACL_BYTES,
  "selected ACL representation must fit its original fixed buffer");

static bool actql_command_acl_bounded(int fd, bool deny_only) {
  struct statfs filesystem;
  if (fstatfs(fd, &filesystem) != 0 || (filesystem.f_flags & MNT_UNION) ||
      memcmp(filesystem.f_fstypename, "apfs", sizeof("apfs")) != 0)
    return false;
  struct attrlist attributes = {0};
  attributes.bitmapcount = ATTR_BIT_MAP_COUNT;
  attributes.commonattr = ATTR_CMN_EXTENDED_SECURITY;
  unsigned char buffer[ACTQL_COMMAND_ACL_BYTES] = {0};
  if (fgetattrlist(fd, &attributes, buffer, sizeof(buffer),
      FSOPT_REPORT_FULLSIZE) != 0) return false;
  uint32_t bytes;
  attrreference_t reference;
  const size_t prefix = sizeof(bytes) + sizeof(reference);
  memcpy(&bytes, buffer, sizeof(bytes));
  if (bytes < prefix || bytes > sizeof(buffer)) return false;
  memcpy(&reference, buffer + sizeof(bytes), sizeof(reference));
  /* On this selected filesystem an absent ACL has an empty attribute. Any
   * syscall failure, truncated reference or invalid representation refuses. */
  if (reference.attr_length == 0) return bytes == prefix;
  if (reference.attr_dataoffset < (int32_t)sizeof(reference)) return false;
  size_t offset = sizeof(bytes) + (size_t)reference.attr_dataoffset;
  if (offset > bytes || reference.attr_length > bytes - offset ||
      reference.attr_length < KAUTH_FILESEC_SIZE(0)) return false;
  struct kauth_filesec header;
  memset(&header, 0, sizeof(header));
  memcpy(&header, buffer + offset, KAUTH_FILESEC_SIZE(0));
  if (header.fsec_magic != KAUTH_FILESEC_MAGIC) return false;
  uint32_t count = header.fsec_entrycount;
  if (count == KAUTH_FILESEC_NOACL) count = 0;
  if (count > KAUTH_ACL_MAX_ENTRIES ||
      reference.attr_length != KAUTH_FILESEC_SIZE(count)) return false;
  if (!deny_only) return count == 0;
  for (uint32_t index = 0; index < count; ++index) {
    struct kauth_ace entry;
    memcpy(&entry, buffer + offset + KAUTH_FILESEC_SIZE(index), sizeof(entry));
    if ((entry.ace_flags & KAUTH_ACE_KINDMASK) != KAUTH_ACE_DENY) return false;
  }
  return true;
}
#endif
