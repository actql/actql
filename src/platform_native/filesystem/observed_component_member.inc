/* Included after the original filesystem and scoped-Read implementations. */
#include "observed_component_member.h"
#include <pthread.h>

struct actql_native_observed_component_member {
  actql_native_filesystem_root *root;
  actql_native_observed_file_stat *stat;
  pthread_t thread;
  pid_t process;
  int kind;
  const void *runtime;
  char name[129], path[4097], source[41], manifest[65], digest[65];
};
static void actql_observed_component_member_finalize(void *raw) {
  actql_native_observed_component_member *member = raw;
  /* Drop only managed aliases. No descriptor, Read, module or platform ACK. */
  if (member->root) moonbit_decref(member->root);
  if (member->stat) moonbit_decref(member->stat);
}
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
static bool actql_component_hex(moonbit_bytes_t bytes, int length) {
  if (Moonbit_array_length(bytes) != length) return false;
  for (int i = 0; i < length; i++)
    if (!((bytes[i] >= '0' && bytes[i] <= '9') ||
          (bytes[i] >= 'a' && bytes[i] <= 'f'))) return false;
  return true;
}
#endif
int actql_native_observed_component_member_current(
    actql_native_observed_component_member *member) {
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  if (!member || member->process != getpid() ||
      !pthread_equal(member->thread, pthread_self()) ||
      !member->root || !member->root->read_context ||
      !member->root->read_context_user ||
      !actql_observed_file_root_matches(member->root, member->stat)) return 0;
  struct stat relative, named;
  return actql_stat_regular_at(member->root, member->name, &relative) &&
    actql_observed_file_matches(&member->stat->original, &relative) &&
    lstat(member->path, &named) == 0 &&
    actql_observed_file_matches(&member->stat->original, &named);
#else
  (void)member; return 0;
#endif
}
/* Only the Runtime's whole-member reader invokes this private FFI after
 * matching the actual Reader digest to its admitted manifest. Public stat,
 * digest or path values are never a bootstrap original or load permission. */
void *actql_native_filesystem_observed_component_member(
    actql_native_filesystem_root *root, actql_native_observed_file_stat *stat,
    moonbit_bytes_t name, int32_t length, int32_t kind,
    moonbit_bytes_t source, moonbit_bytes_t manifest, moonbit_bytes_t digest) {
  actql_native_observed_component_member *member = moonbit_make_external_object(
    actql_observed_component_member_finalize, sizeof(*member));
  memset(member, 0, sizeof(*member));
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  if (!root || !root->custody_path || !root->read_context ||
      !actql_native_filesystem_root_read_available(root) ||
      !actql_observed_file_root_matches(root, stat) || length <= 0 ||
      length > 128 || Moonbit_array_length(name) != length ||
      memchr(name, 0, (size_t)length) || (kind != 1 && kind != 2) ||
      !actql_component_hex(source, 40) || !actql_component_hex(manifest, 64) ||
      !actql_component_hex(digest, 64)) return member;
  char text[129]; memcpy(text, name, (size_t)length); text[length] = 0;
  if (!actql_valid_name(text, (size_t)length)) return member;
  size_t parent_length = strlen(root->custody_path);
  if (parent_length + 1 + (size_t)length > 4096) return member;
  member->root = root; moonbit_incref(root);
  member->stat = stat; moonbit_incref(stat);
  member->process = getpid(); member->thread = pthread_self(); member->kind = kind;
  memcpy(member->name, text, (size_t)length + 1);
  memcpy(member->path, root->custody_path, parent_length);
  member->path[parent_length] = '/';
  memcpy(member->path + parent_length + 1, text, (size_t)length + 1);
  memcpy(member->source, source, 40); memcpy(member->manifest, manifest, 64);
  memcpy(member->digest, digest, 64);
#else
  (void)root; (void)stat; (void)name; (void)length; (void)kind;
  (void)source; (void)manifest; (void)digest;
#endif
  return member;
}
/* A borrowed nominal association, not a serialized identity or a root of
 * funding. The command retains this Runtime until its component users close;
 * keeping another strong edge here would create a Runtime/member cycle. */
int32_t actql_native_filesystem_bind_component_runtime(
    actql_native_observed_component_member *member, const void *runtime) {
  if (!runtime || !member || member->runtime ||
      !actql_native_observed_component_member_current(member)) return 0;
  member->runtime = runtime;
  return 1;
}
const void *actql_native_observed_component_member_runtime(
    actql_native_observed_component_member *member) {
  return actql_native_observed_component_member_current(member) ? member->runtime : NULL;
}
enum actql_native_command_component_kind
actql_native_observed_component_member_kind(
    actql_native_observed_component_member *member) {
  return actql_native_observed_component_member_current(member) ? member->kind : 0;
}
#define ACTQL_COMPONENT_MEMBER_TEXT(function, field) \
const char *function(actql_native_observed_component_member *member) { \
  return actql_native_observed_component_member_current(member) ? member->field : NULL; \
}
ACTQL_COMPONENT_MEMBER_TEXT(actql_native_observed_component_member_path, path)
ACTQL_COMPONENT_MEMBER_TEXT(actql_native_observed_component_member_source, source)
ACTQL_COMPONENT_MEMBER_TEXT(actql_native_observed_component_member_manifest_sha256, manifest)
ACTQL_COMPONENT_MEMBER_TEXT(actql_native_observed_component_member_sha256, digest)
#undef ACTQL_COMPONENT_MEMBER_TEXT
int actql_native_observed_component_member_image(
    actql_native_observed_component_member *member, const char *image_path) {
  if (!actql_native_observed_component_member_current(member) || !image_path)
    return 0;
  struct stat image;
  return lstat(image_path, &image) == 0 &&
    actql_observed_file_matches(&member->stat->original, &image);
}
