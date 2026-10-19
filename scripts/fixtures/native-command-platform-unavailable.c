#include <assert.h>
#include <stdio.h>
#include "../../src/platform_native/host_bootstrap/command_platform.h"

int main(void) {
  assert(actql_native_command_platform_current() == NULL);
  assert(actql_native_command_platform_initial_current() == NULL);
  assert(!actql_native_command_platform_available());
  assert(actql_native_command_platform_scratch_directory((void *)1) == NULL);
  assert(actql_native_command_platform_begin_load((void *)1,
    ACTQL_NATIVE_COMMAND_SQLITE_COMPONENT, (void *)2) == NULL);
  assert(!actql_native_command_platform_observe_load((void *)1, (void *)2));
  assert(!actql_native_command_platform_load_current((void *)1));
  assert(!actql_native_command_platform_module_released((void *)1, (void *)2));
  puts("unselected bootstrap entry passed");
  return 0;
}
