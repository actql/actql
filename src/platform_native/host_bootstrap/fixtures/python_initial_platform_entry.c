/* Physical receiver of the production private entry, not a replacement
 * platform-original struct. Only mapping failure and the emitted initializer
 * are controlled; capacity and original issuance come from that same entry. */
#include <Python.h>
#include <assert.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>
#include "../initial_managed_mimalloc217.h"
static int fixture_mode;
static void *fixture_map(void *address, size_t bytes, int protection,
    int flags, int fd, off_t offset) {
  return fixture_mode == 1 ? MAP_FAILED :
    mmap(address, bytes, protection, flags, fd, offset);
}
#define mmap fixture_map
#include "../python_initial_platform.c"
#undef mmap
#include "../../installed_arena_entry/runtime_initialization_shim.c"

static unsigned initialization_calls;
static void *escaped;
static actql_control_runtime_origin *runtime;
static actql_native_python_initial_platform_original *entry;
extern void *mi_malloc(size_t);
extern void mi_free(void *);

int actql_control_runtime_roots_state(void) { return initialization_calls != 0; }
int actql_original_control_initialize(int argc, char **argv) {
  assert(argc == 1 && argv && argv[0] && !argv[1]);
  assert(actql_native_python_initial_platform_current(&python_original));
  assert(initialization_calls++ == 0);
  escaped = mi_malloc(128);
  assert(escaped && actql_initial_managed_contains(python_original.managed->area,
    python_original.managed->reserved_bytes, escaped, mi_usable_size(escaped)));
  memset(escaped, 0x5a, 128);
  return 0;
}

int original_python_platform_runtime_initialization_calls(void) {
  return (int)initialization_calls;
}

int original_python_platform_release_runtime_allocation(void) {
  if (!python_original_thread(&python_original) || !escaped) return 0;
  assert(((unsigned char *)escaped)[0] == 0x5a);
  assert(((unsigned char *)escaped)[127] == 0x5a);
  mi_free(escaped);
  escaped = NULL;
  return 1;
}

static void *foreign_entry(void *unused) {
  (void)unused;
  assert(!actql_native_python_initial_platform_current(entry));
  assert(actql_native_python_initial_platform_restore(entry) == ACTQL_INITIAL_MANAGED_INVALID);
  assert(actql_control_runtime_current(runtime) == ACTQL_CONTROL_UNAVAILABLE);
  return NULL;
}

int original_python_platform_entry_case(int selected) {
  assert(selected >= 0 && selected <= 3 && PyGILState_Check());
  fixture_mode = selected;
  assert(!_mi_process_is_initialized);
  assert(actql_control_runtime_initialize_into(&runtime) == ACTQL_CONTROL_UNAVAILABLE);
  assert(!runtime && !initialization_calls);
  assert(actql_native_python_initial_platform_begin_into(NULL) == ACTQL_INITIAL_MANAGED_INVALID);
  if (selected == 3) assert(setenv("DYLD_ACTQL_UNSUPPORTED_FIXTURE", "1", 1) == 0);
  PyMemAllocatorEx before[3];
  for (int i = 0; i < 3; ++i) PyMem_GetAllocator(i, &before[i]);
  int result = actql_native_python_initial_platform_begin_into(&entry);
  assert(entry == &python_original && entry->interpreter == PyInterpreterState_Get());
  assert(entry->python_thread == PyThreadState_Get());
  assert(actql_native_python_initial_platform_begin_into(&entry) == ACTQL_INITIAL_MANAGED_INVALID);
  actql_native_python_initial_platform_original *duplicate = NULL;
  assert(actql_native_python_initial_platform_begin_into(&duplicate) == ACTQL_INITIAL_MANAGED_INVALID);
  assert(!duplicate);
  for (int i = 0; i < 3; ++i) {
    PyMemAllocatorEx current;
    PyMem_GetAllocator(i, &current);
    assert(same_allocator(&before[i], &current));
  }
  struct actql_native_python_initial_platform_original copy = *entry;
  assert(!actql_native_python_initial_platform_current(&copy));
  assert(actql_native_python_initial_platform_restore(&copy) == ACTQL_INITIAL_MANAGED_INVALID);
  if (selected == 1 || selected == 3) {
    assert(result == (selected == 1 ? ACTQL_INITIAL_MANAGED_MAPPING : ACTQL_INITIAL_MANAGED_PARENT));
    if (selected == 3) assert(unsetenv("DYLD_ACTQL_UNSUPPORTED_FIXTURE") == 0);
    assert(!actql_native_python_initial_platform_current(entry));
    assert(actql_control_runtime_initialize_into(&runtime) == ACTQL_CONTROL_UNAVAILABLE);
    assert(!runtime && !initialization_calls && !_mi_process_is_initialized);
    assert(actql_native_python_initial_platform_restore(entry) == 1);
    assert(actql_native_python_initial_platform_restore(entry) == 1);
    return 1;
  }
  assert(result == 0 && actql_native_python_initial_platform_current(entry));
  assert(entry->managed->mapping_bytes == (size_t)192 * 1024 * 1024);
  assert(actql_control_runtime_initialize_into(&runtime) == ACTQL_CONTROL_OK);
  assert(initialization_calls == 1 && actql_control_runtime_current(runtime) == ACTQL_CONTROL_OK);
  pthread_t other;
  assert(pthread_create(&other, NULL, foreign_entry, NULL) == 0);
  assert(pthread_join(other, NULL) == 0);
  if (selected == 2) {
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) { foreign_entry(NULL); _exit(0); }
    int status = 0;
    assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
  }
  assert(actql_native_python_initial_platform_restore(entry) == 1);
  assert(!actql_native_python_initial_platform_current(entry));
  assert(actql_control_runtime_current(runtime) == ACTQL_CONTROL_UNAVAILABLE);
  assert(((unsigned char *)escaped)[127] == 0x5a);
  mi_free(escaped);
  assert(entry->managed->mapping_acquired && entry->managed->heap && entry->managed->metadata_area);
  assert(actql_native_python_initial_platform_restore(entry) == 1);
  return 1;
}
