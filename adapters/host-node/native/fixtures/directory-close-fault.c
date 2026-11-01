/* Matching-source injected consumed-close failure, not an observed OS failure.
 * The real descriptor is closed exactly once before EIO is reported. */
#include <node_api.h>
#include <unistd.h>
#include <errno.h>
static int close_attempts;
static int real_closes;
static int consumed_close(int fd) {
  close_attempts++;
  int result = close(fd);
  if (result != 0) return result;
  real_closes++;
  errno = EIO; return -1;
}
#undef NAPI_MODULE
#define NAPI_MODULE(name, callback)
#define close consumed_close
#if defined(__linux__)
#include "../local-files-linux.c"
#else
#include "../directory-darwin.c"
#endif
#undef close
static napi_value attempts(napi_env env, napi_callback_info info) {
  (void)info; napi_value result;
  if (napi_create_int32(env, close_attempts, &result) != napi_ok) return NULL;
  return result;
}
static napi_value physically_closed(napi_env env, napi_callback_info info) {
  (void)info; napi_value result;
  if (napi_create_int32(env, real_closes, &result) != napi_ok) return NULL;
  return result;
}
NAPI_MODULE_INIT() {
  (void)exports;
  napi_value wrapper, operations, count, actual;
  if (napi_create_object(env, &operations) != napi_ok ||
      !initialize(env, operations) || napi_create_object(env, &wrapper) != napi_ok ||
      napi_create_function(env, "attempts", NAPI_AUTO_LENGTH, attempts, NULL, &count) != napi_ok ||
      napi_create_function(env, "physicallyClosed", NAPI_AUTO_LENGTH, physically_closed, NULL, &actual) != napi_ok ||
      napi_set_named_property(env, wrapper, "operations", operations) != napi_ok ||
      napi_set_named_property(env, wrapper, "physicallyClosed", actual) != napi_ok ||
      napi_set_named_property(env, wrapper, "attempts", count) != napi_ok) return NULL;
  return wrapper;
}
