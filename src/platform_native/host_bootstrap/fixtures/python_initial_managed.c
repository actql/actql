/* Actual CPython/MI physical entrance diagnostic. Its finite selection is a
 * fixture, not the complete ordinary Python startup envelope or an issuer. */
#include <Python.h>
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include "../python_initial_platform.h"
#include "../initial_managed_mimalloc217.h"

struct actql_native_python_initial_platform_original {
  PyInterpreterState *interpreter;
  pid_t process;
  pthread_t thread;
  unsigned generation;
};
static actql_native_python_initial_platform_original entry;
static actql_native_initial_managed_original *managed;
static int mode;
static unsigned mappings;
static bool spent;
extern bool _mi_process_is_initialized;
extern void *mi_malloc(size_t);
extern void mi_free(void *);

static void *observed_mapping(void *address, size_t bytes, int protection,
    int flags, int fd, off_t offset) {
  ++mappings;
  if (mode == 2) return MAP_FAILED;
  return mmap(address, bytes, protection, flags, fd, offset);
}
static mi_heap_t *observed_heap(int arena) {
  return mode == 3 ? NULL : mi_heap_new_in_arena(arena);
}
#define ACTQL_PYTHON_INITIAL_OPERATIONAL_ENTRY 1
#define mmap observed_mapping
#define mi_heap_new_in_arena observed_heap
#include "../initial_managed.inc"
#undef mi_heap_new_in_arena
#undef mmap

bool actql_native_python_initial_platform_managed_selection(
    actql_native_python_initial_platform_original *original, size_t out[4]) {
  /* Nominal/process/thread checks precede any CAPI use on a foreign thread. */
  if (original != &entry || spent || entry.generation != 1 ||
      entry.process != getpid() || !pthread_equal(entry.thread, pthread_self()) ||
      !PyGILState_Check() || PyInterpreterState_Get() != entry.interpreter)
    return false;
  if (!actql_initial_managed_prepare_candidate(4096, out)) return false;
  if (mode == 1) out[0] = 1;
  return true;
}

static void *foreign(void *unused) {
  (void)unused;
  assert(!actql_native_initial_managed_current(managed));
  assert(actql_native_initial_managed_restore(managed) == ACTQL_INITIAL_MANAGED_INVALID);
  assert(actql_native_python_initial_managed_begin(&entry) == NULL);
  return NULL;
}

int original_python_initial_case(int selected) {
  assert(PY_VERSION_HEX == 0x030c0cf0);
  assert(PyGILState_Check());
  assert(selected >= 0 && selected <= 6);
  if (selected == 6) {
    assert(_mi_process_is_initialized);
    entry.interpreter = PyInterpreterState_Get();
    entry.process = getpid();
    entry.thread = pthread_self();
    entry.generation = 1;
    assert(actql_native_python_initial_managed_begin(&entry) == NULL);
    assert(mappings == 0 && managed == NULL);
    return 1;
  }
  assert(!_mi_process_is_initialized);
  assert(managed == NULL && entry.generation == 0);
  mode = selected;
  PyMemAllocatorEx before[3], after;
  for (int index = 0; index < 3; ++index) PyMem_GetAllocator(index, &before[index]);
  if (mode == 0) {
    assert(actql_native_python_initial_managed_begin(NULL) == NULL);
    assert(!_mi_process_is_initialized && mappings == 0);
    return 1;
  }
  entry.interpreter = PyInterpreterState_Get();
  entry.process = getpid();
  entry.thread = pthread_self();
  entry.generation = 1;
  managed = actql_native_python_initial_managed_begin(&entry);
  if (mode == 1) {
    assert(managed == NULL && mappings == 0 && !_mi_process_is_initialized);
    return 1;
  }
  assert(managed && mappings == 1);
  assert(actql_native_python_initial_managed_begin(&entry) == NULL);
  for (int index = 0; index < 3; ++index) {
    PyMem_GetAllocator(index, &after);
    assert(after.ctx == before[index].ctx && after.malloc == before[index].malloc &&
      after.calloc == before[index].calloc && after.realloc == before[index].realloc &&
      after.free == before[index].free);
  }
  if (mode == 2 || mode == 3) {
    assert(!actql_native_initial_managed_current(managed));
    assert(actql_native_initial_managed_issue(managed) ==
      (mode == 2 ? ACTQL_INITIAL_MANAGED_MAPPING : ACTQL_INITIAL_MANAGED_HEAP));
    assert(_mi_process_is_initialized == (mode == 3));
    assert(managed->mapping_acquired == (mode == 3));
    assert(actql_native_initial_managed_restore(managed) == 1);
    assert(actql_native_initial_managed_restore(managed) == 1);
    return 1;
  }
  assert(actql_native_initial_managed_current(managed));
  assert(managed->python_entry == &entry && _mi_process_is_initialized);
  assert(managed->metadata_arena_id > 0 && managed->arena_id > 0);
  void *allocation = mi_malloc(128);
  assert(allocation && actql_initial_managed_contains(managed->area,
    managed->reserved_bytes, allocation, mi_usable_size(allocation)));
  memset(allocation, 0x5a, 128);
  struct actql_native_initial_managed_original copy = *managed;
  assert(!actql_native_initial_managed_current(&copy));
  assert(actql_native_initial_managed_restore(&copy) == ACTQL_INITIAL_MANAGED_INVALID);
  pthread_t other;
  assert(pthread_create(&other, NULL, foreign, NULL) == 0);
  assert(pthread_join(other, NULL) == 0);
  if (mode == 5) {
    spent = true;
    assert(!actql_native_initial_managed_current(managed));
    assert(actql_native_python_initial_managed_begin(&entry) == NULL);
  }
  assert(actql_native_initial_managed_restore(managed) == 1);
  assert(!actql_native_initial_managed_current(managed));
  assert(managed->mapping_acquired && managed->heap && managed->metadata_area);
  assert(((unsigned char *)allocation)[127] == 0x5a);
  mi_free(allocation);
  assert(actql_native_initial_managed_restore(managed) == 1);
  assert(actql_native_python_initial_managed_begin(&entry) == NULL);
  return 1;
}
