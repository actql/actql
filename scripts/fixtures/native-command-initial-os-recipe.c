/* Real selected entry, pinned allocator and OS originals. This verifies only
 * initial startup; no Runtime, Host, Read, Journal or component is acquired. */
#include "../../src/cmd/native_client/stdout_stub.c"
#include <assert.h>
extern void *mi_malloc(size_t);
extern void mi_free(void *);

__attribute__((constructor)) static void actql_test_recipe_later_initializer(void) {
  assert(actql_command_entry.initial_envelope_admitted);
  assert(actql_command_entry.initial_os == &actql_initial_os_facility);
  assert(actql_command_initial_recipe_current(&actql_command_entry));
  static const char marker[] = "later initializer\n";
  (void)write(STDOUT_FILENO, marker, sizeof(marker) - 1);
}

int main(void) {
  assert(actql_native_client_measure_prearguments(256, 4096, 65536, 8192) == 0);
  actql_native_client_capture_command_entry();
  assert(actql_native_command_platform_current() == &actql_command_entry);
  actql_native_initial_managed_original *managed = actql_command_entry.initial_managed;
  assert(managed && actql_native_initial_managed_current(managed));
  void *allocation = mi_malloc(144);
  assert(allocation && actql_initial_managed_contains(managed->area,
    managed->reserved_bytes, allocation, mi_usable_size(allocation)));
  memset(allocation, 0x5a, 144);
  mi_free(allocation);
  assert(actql_native_initial_os_facility_capture() == NULL);
  assert(actql_native_initial_os_facility_current(actql_command_entry.initial_os));
  /* Loss of normal currentness cannot reissue the lifetime or acknowledge the
   * original process-lived arena/TLS/loader state. No child release is claimed. */
  assert(setenv("DYLD_INSERT_LIBRARIES", "replacement", 1) == 0);
  assert(actql_native_command_platform_current() == NULL);
  assert(unsetenv("DYLD_INSERT_LIBRARIES") == 0);
  assert(actql_native_command_platform_current() == NULL);
  assert(actql_command_entry.initial_os->normal_refused);
  assert(actql_command_entry.initial_os == &actql_initial_os_facility);
  static const char marker[] = "initial OS recipe passed\n";
  (void)write(STDOUT_FILENO, marker, sizeof(marker) - 1);
  return 0;
}
