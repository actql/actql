/* Matching-source syscall faults. Real descriptor I/O is retained; the
 * injected outcomes are diagnostics, not observed kernel failure evidence. */
#include <node_api.h>
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
static int selected_mode, rename_calls, sync_calls;
static int selected_rename(int oldfd, const char *oldname, int newfd, const char *newname, unsigned flags) {
  rename_calls++;
  if (selected_mode == 1 || selected_mode == 2) {
    errno = selected_mode == 1 ? ENOSYS : EINVAL; return -1;
  }
  int outcome = renameat2(oldfd, oldname, newfd, newname, flags);
  if (outcome == 0 && selected_mode == 5) {errno = EIO; return -1;}
  return outcome;
}
static int selected_sync(int fd) {
  sync_calls++;
  if ((selected_mode == 3 && sync_calls == 1) || (selected_mode == 4 && sync_calls == 2)) {
    errno = EIO; return -1;
  }
  return fsync(fd);
}
#undef NAPI_MODULE
#define NAPI_MODULE(name, callback)
#define renameat2 selected_rename
#define fsync selected_sync
#include "../local-files-linux.c"
#undef renameat2
#undef fsync
static napi_value select_mode(napi_env env, napi_callback_info info) {
  napi_value args[1]; size_t count = 1;
  if (napi_get_cb_info(env, info, &count, args, NULL, NULL) != napi_ok || count != 1 ||
      napi_get_value_int32(env, args[0], &selected_mode) != napi_ok) return NULL;
  rename_calls = sync_calls = 0;
  return undefined(env);
}
static napi_value rename_count(napi_env env, napi_callback_info info) {
  (void)info; napi_value value;
  return napi_create_int32(env, rename_calls, &value) == napi_ok ? value : NULL;
}
NAPI_MODULE_INIT() {
  napi_value methods, mode, count;
  if (napi_create_object(env, &methods) != napi_ok || !initialize(env, methods) ||
      napi_create_function(env, "select", NAPI_AUTO_LENGTH, select_mode, NULL, &mode) != napi_ok ||
      napi_create_function(env, "renames", NAPI_AUTO_LENGTH, rename_count, NULL, &count) != napi_ok ||
      napi_set_named_property(env, exports, "operations", methods) != napi_ok ||
      napi_set_named_property(env, exports, "select", mode) != napi_ok ||
      napi_set_named_property(env, exports, "renames", count) != napi_ok) return NULL;
  return exports;
}
