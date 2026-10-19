/* Observe the actual pinned allocator's initialization flag after the real
 * command constructor. This is a diagnostic, never an initial admission. */
#include <assert.h>
#include "../../src/cmd/native_client/stdout_stub.c"

extern bool _mi_preloading(void);
int actql_test_entry_before_allocator;

__attribute__((constructor)) static void actql_test_observe_initial_order(void) {
  assert(atomic_load(&actql_command_entry_state) == 1);
  assert(actql_command_early_input_attempted);
  assert(actql_command_early_input_status == ACTQL_COMMAND_INPUT_OK);
  assert(!actql_command_entry.initial_envelope_admitted);
  actql_test_entry_before_allocator = _mi_preloading() ? 1 : 0;
}
