/* Actual CAPI/MI entrance into the selected Runtime initialization fence.
 * The emitted Moon initializer is a controlled receiver here; this does not
 * execute a product Moon module or supply the ordinary startup envelope. */
#include "python_initial_managed.c"
#include "../../installed_arena_entry/runtime_initialization_shim.c"

static unsigned initialized;
static void *escaped;

int actql_control_runtime_roots_state(void) { return initialized != 0; }

int actql_original_control_initialize(int argc, char **argv) {
  assert(argc == 1 && argv && argv[0] && !argv[1]);
  assert(actql_native_python_initial_managed_current());
  assert(initialized++ == 0);
  escaped = mi_malloc(128);
  assert(escaped && actql_initial_managed_contains(managed->area,
    managed->reserved_bytes, escaped, mi_usable_size(escaped)));
  memset(escaped, 0x5a, 128);
  return 0;
}

static void *foreign_runtime(void *pointer) {
  assert(actql_control_runtime_current(pointer) == ACTQL_CONTROL_UNAVAILABLE);
  actql_control_runtime_origin *other = NULL;
  assert(actql_control_runtime_initialize_into(&other) == ACTQL_CONTROL_UNAVAILABLE);
  assert(!other);
  return NULL;
}

int original_python_runtime_case(int selected) {
  assert(selected >= 0 && selected <= 2 && PyGILState_Check());
  assert(!_mi_process_is_initialized && !initialized);
  actql_control_runtime_origin *runtime = NULL;
  assert(actql_control_runtime_initialize_into(&runtime) == ACTQL_CONTROL_UNAVAILABLE);
  assert(!runtime && !initialized && !_mi_process_is_initialized);
  if (selected == 0) return 1;
  entry.interpreter = PyInterpreterState_Get();
  entry.process = getpid();
  entry.thread = pthread_self();
  entry.generation = 1;
  mode = selected == 1 ? 2 : 4;
  managed = actql_native_python_initial_managed_begin(&entry);
  assert(managed);
  if (selected == 1) {
    assert(actql_control_runtime_initialize_into(&runtime) == ACTQL_CONTROL_UNAVAILABLE);
    assert(!runtime && !initialized && !escaped);
    assert(actql_native_initial_managed_restore(managed) == 1);
    return 1;
  }
  assert(actql_control_runtime_initialize_into(&runtime) == ACTQL_CONTROL_OK);
  assert(runtime && initialized == 1);
  assert(actql_control_runtime_current(runtime) == ACTQL_CONTROL_OK);
  actql_control_runtime_origin *duplicate = NULL;
  assert(actql_control_runtime_initialize_into(&duplicate) == ACTQL_CONTROL_UNAVAILABLE);
  assert(!duplicate && initialized == 1);
  pthread_t other;
  assert(pthread_create(&other, NULL, foreign_runtime, runtime) == 0);
  assert(pthread_join(other, NULL) == 0);
  assert(actql_native_initial_managed_restore(managed) == 1);
  assert(actql_control_runtime_current(runtime) == ACTQL_CONTROL_UNAVAILABLE);
  assert(((unsigned char *)escaped)[127] == 0x5a);
  mi_free(escaped);
  assert(managed->mapping_acquired && managed->metadata_area && managed->heap);
  return 1;
}
