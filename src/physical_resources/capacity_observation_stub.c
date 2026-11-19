/* Optional downward-safe diagnostic bridge: standalone Core never needs the
 * filesystem library. No managed layout, allocation, authority or callback. */
#include <stdint.h>
#include <errno.h>
/* A weak definition, rather than an undefined weak import, also links a
 * standalone Darwin Core executable. The installed filesystem supplies the
 * strong implementation. noinline keeps that substitution observable. */
__attribute__((weak, noinline))
void actql_native_file_capacity_observe(const void *ledger, int32_t kind,
    int32_t serial, int64_t requested, int64_t capacity, int64_t limit,
    int64_t reserved) {
  (void)ledger; (void)kind; (void)serial; (void)requested; (void)capacity;
  (void)limit; (void)reserved;
}
void actql_resource_capacity_observation(const void *ledger, int32_t kind,
    int32_t serial, int64_t requested, int64_t capacity, int64_t limit,
    int64_t reserved) {
  int original_errno = errno;
  actql_native_file_capacity_observe(ledger, kind, serial, requested, capacity,
        limit, reserved);
  errno = original_errno;
}
