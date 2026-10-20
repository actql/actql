/* Selected private Python Native initial-control component only. The trusted
 * producer supplies genuine source/recipe identities before compilation. No
 * automatic constructor runs this entry, and the ordinary missing-supplier
 * path must not select it as whole startup or business funding. */
#if !defined(ACTQL_PYTHON_INITIAL_OPERATIONAL_ENTRY) || \
    !defined(ACTQL_PYTHON_INITIAL_SOURCE_SHA) || \
    !defined(ACTQL_PYTHON_INITIAL_RECIPE_SHA)
#error "Select the original Python operational component recipe explicitly"
#endif
#include <Python.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include "python_initial_platform.h"
#include "initial_loader_environment.h"

_Static_assert(PY_VERSION_HEX == 0x030c0cf0, "Selected CPython headers changed");
_Static_assert(sizeof(ACTQL_PYTHON_INITIAL_SOURCE_SHA) == 41,
  "Original source identity is required");
_Static_assert(sizeof(ACTQL_PYTHON_INITIAL_RECIPE_SHA) == 65,
  "Original recipe identity is required");

/* Finite supplied Native initial-control facility, not an all-input demand
 * guarantee or normal numerical profile. Two additional MI217 segments cover
 * the same mapping's metadata and maximum alignment loss. All outside-arena
 * services, loader/prelude, Worker and VM originals remain separate. */
static const size_t python_managed_selection[4] = {
  (size_t)128 * 1024 * 1024, (size_t)64 * 1024 * 1024,
  (size_t)128 * 1024 * 1024, 1
};

struct actql_native_python_initial_platform_original {
  pid_t process;
  pthread_t thread;
  PyInterpreterState *interpreter;
  PyThreadState *python_thread;
  int64_t interpreter_id;
  uint64_t thread_id;
  const char *source;
  const char *recipe;
  PyMemAllocatorEx allocators[3];
  actql_native_loader_environment environment;
  actql_native_initial_managed_original *managed;
  bool refused;
};
static actql_native_python_initial_platform_original python_original;
/* 0 untouched, 1 attempted/partial, 2 ready, 3 default restored. Neither
 * restoration nor a failed attempt returns the process lifetime to zero. */
static _Atomic int python_phase;

static bool python_original_thread(
    actql_native_python_initial_platform_original *original) {
  return original == &python_original && original->process == getpid() &&
    pthread_equal(original->thread, pthread_self());
}

static bool same_allocator(const PyMemAllocatorEx *left,
    const PyMemAllocatorEx *right) {
  return left->ctx == right->ctx && left->malloc == right->malloc &&
    left->calloc == right->calloc && left->realloc == right->realloc &&
    left->free == right->free;
}

static bool python_service_current(
    actql_native_python_initial_platform_original *original) {
  /* Never call CAPI first on a foreign thread/fork or dereference an unknown
   * pointer. PYFUNCTYPE/PyDLL callers must retain the original interpreter GIL. */
  if (!python_original_thread(original) || original->refused ||
      !PyGILState_Check()) return false;
  if (PyInterpreterState_Get() != original->interpreter ||
      PyThreadState_Get() != original->python_thread ||
      PyInterpreterState_GetID(original->interpreter) != original->interpreter_id ||
      PyThreadState_GetID(original->python_thread) != original->thread_id ||
      !actql_native_loader_environment_current(&original->environment)) {
    original->refused = true;
    return false;
  }
  for (int index = 0; index < 3; ++index) {
    PyMemAllocatorEx current;
    PyMem_GetAllocator(index, &current);
    if (!same_allocator(&current, &original->allocators[index])) {
      original->refused = true;
      return false;
    }
  }
  return true;
}

bool actql_native_python_initial_platform_managed_selection(
    actql_native_python_initial_platform_original *original, size_t out[4]) {
  int phase = atomic_load_explicit(&python_phase, memory_order_acquire);
  if ((phase != 1 && phase != 2) || !out ||
      !python_service_current(original)) return false;
  for (size_t index = 0; index < 4; ++index)
    out[index] = python_managed_selection[index];
  return true;
}

#include "initial_managed.inc"

int actql_native_python_initial_platform_begin_into(
    actql_native_python_initial_platform_original **slot) {
  if (!slot || *slot) return ACTQL_INITIAL_MANAGED_INVALID;
  /* Unsupported runtime refuses before claiming an original or invoking MI.
   * The producer independently binds the selected interpreter/component ABI. */
  if (!PyGILState_Check() || strncmp(Py_GetVersion(), "3.12.12 ", 8) != 0)
    return ACTQL_INITIAL_MANAGED_VERSION;
  size_t candidate[4] = {0};
  if (!actql_initial_managed_prepare_candidate(python_managed_selection[2], candidate))
    return ACTQL_INITIAL_MANAGED_AREA;
  for (size_t index = 0; index < 4; ++index)
    if (candidate[index] != python_managed_selection[index])
      return ACTQL_INITIAL_MANAGED_AREA;
  int untouched = 0;
  if (!atomic_compare_exchange_strong_explicit(&python_phase, &untouched, 1,
      memory_order_acq_rel, memory_order_acquire))
    return ACTQL_INITIAL_MANAGED_INVALID;
  python_original.process = getpid();
  python_original.thread = pthread_self();
  python_original.interpreter = PyInterpreterState_Get();
  python_original.python_thread = PyThreadState_Get();
  python_original.interpreter_id = PyInterpreterState_GetID(python_original.interpreter);
  python_original.thread_id = PyThreadState_GetID(python_original.python_thread);
  python_original.source = ACTQL_PYTHON_INITIAL_SOURCE_SHA;
  python_original.recipe = ACTQL_PYTHON_INITIAL_RECIPE_SHA;
  *slot = &python_original;
  for (int index = 0; index < 3; ++index) {
    PyMem_GetAllocator(index, &python_original.allocators[index]);
    PyMemAllocatorEx *allocator = &python_original.allocators[index];
    if (!allocator->malloc || !allocator->calloc || !allocator->realloc ||
        !allocator->free) {
      python_original.refused = true;
      return ACTQL_INITIAL_MANAGED_PARENT;
    }
  }
  if (!actql_native_loader_environment_capture(&python_original.environment)) {
    python_original.refused = true;
    return ACTQL_INITIAL_MANAGED_PARENT;
  }
  python_original.managed =
    actql_native_python_initial_managed_begin(&python_original);
  if (!python_original.managed) return ACTQL_INITIAL_MANAGED_PARENT;
  int issue = actql_native_initial_managed_issue(python_original.managed);
  if (issue != 0) return issue;
  atomic_store_explicit(&python_phase, 2, memory_order_release);
  return 0;
}

bool actql_native_python_initial_platform_current(
    actql_native_python_initial_platform_original *original) {
  return atomic_load_explicit(&python_phase, memory_order_acquire) == 2 &&
    python_service_current(original) &&
    actql_native_initial_managed_current(original->managed);
}

int actql_native_python_initial_platform_restore(
    actql_native_python_initial_platform_original *original) {
  if (!python_original_thread(original)) return ACTQL_INITIAL_MANAGED_INVALID;
  int phase = atomic_load_explicit(&python_phase, memory_order_acquire);
  if (phase == 3) return 1;
  if (phase != 1 && phase != 2) return ACTQL_INITIAL_MANAGED_INVALID;
  /* Cleanup does not require the now-unavailable normal Python/loader view.
   * Restore only this actual managed default; retain all partial mappings,
   * registrations, Python/module references and escaped process aliases. */
  int result = original->managed ?
    actql_native_initial_managed_restore(original->managed) : 1;
  if (result == 1)
    atomic_store_explicit(&python_phase, 3, memory_order_release);
  return result;
}
