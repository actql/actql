/* Runtime and application initializers may use ordinary libc before main. */
#include <assert.h>
#include "../../src/cmd/native_client/stdout_stub.c"

static bool application_initialized;
__attribute__((constructor)) static void actql_test_application_initializer(void) {
  assert(atomic_load(&actql_command_entry_state) == 0);
  assert(!actql_command_early_input_attempted);
  assert(fputs("", stdout) >= 0 && fflush(stdout) == 0);
  application_initialized = true;
}

int main(void) {
  assert(application_initialized);
  assert(atomic_load(&actql_command_entry_state) == 0);
  assert(actql_native_command_platform_current() == NULL);
  assert(actql_native_client_measure_prearguments(256, 4096, 65536, 8192) == 0);
  actql_native_client_capture_command_entry();
  assert(actql_native_command_platform_current() == &actql_command_entry);
  puts("normal main passed");
  return 0;
}
