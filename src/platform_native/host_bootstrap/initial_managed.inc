/* Included once by the selected executable's existing entry, before its first
 * covered allocator call. This is its original physical binding, not another
 * bootstrap Owner, registry or public allocator. No heap/arena deletion occurs:
 * escaped managed allocations and process-lived registrations keep their same
 * initial responsibility after restoring the previous default. */
#include "command_platform.h"
#include <stdatomic.h>
#include <stdint.h>
#include <pthread.h>
#include <unistd.h>

#if defined(__APPLE__) && defined(__aarch64__)
#include <crt_externs.h>
#include "initial_managed_mimalloc217.h"
/* Actual selected 64-bit toolchain geometry. The entry recipe must qualify
 * this runtime object/ABI, not infer the granularity from a successful probe.
 * Preselect whole segments before reservation; reject any observed mismatch. */
#define ACTQL_INITIAL_MI_SEGMENT_BYTES ((size_t)32 * 1024 * 1024)

/* The selected allocator's startup options can reserve other arenas or alter
 * process-lived cleanup. This profile selects its pinned defaults, not ambient
 * allocator customization. Observe the actual startup vector without getenv,
 * value parsing, copying or allocation. The selected Unix runtime examines at
 * most 10000 entries case-insensitively; refuse an unterminated bounded census
 * too. No unsupported option is silently rewritten or ignored. */
static bool actql_initial_managed_environment_supported(char *const *environment) {
  if (!environment) return true;
  const char prefix[] = "mimalloc_";
  for (size_t index = 0; index < 10000; ++index) {
    const char *text = environment[index];
    if (!text) return true;
    size_t offset = 0;
    for (; offset < sizeof(prefix)-1; ++offset) {
      unsigned char value = (unsigned char)text[offset];
      if (value >= 'A' && value <= 'Z') value += 'a'-'A';
      if (value != (unsigned char)prefix[offset]) break;
    }
    if (offset == sizeof(prefix)-1) return false;
  }
  return false;
}
#endif

enum {
  ACTQL_INITIAL_MANAGED_INVALID = -1,
  ACTQL_INITIAL_MANAGED_PENDING = -2,
  ACTQL_INITIAL_MANAGED_VERSION = -3,
  ACTQL_INITIAL_MANAGED_PARENT = -4,
  ACTQL_INITIAL_MANAGED_RESERVE = -5,
  ACTQL_INITIAL_MANAGED_AREA = -6,
  ACTQL_INITIAL_MANAGED_HEAP = -7,
  ACTQL_INITIAL_MANAGED_DEFAULT = -8
};

struct actql_native_initial_managed_original {
  actql_native_command_platform_original *entry;
  pid_t process;
  pthread_t thread;
  size_t selection[4];
  void *area;
  size_t reserved_bytes;
  void *previous_default;
  void *heap;
  void *observed_previous;
  int arena_id;
  int issue;
  bool reserve_attempted;
  bool switch_attempted;
  bool closing;
  bool metadata_setup_attempted;
};

/* 0 unused, 1 setup/restore in flight, 2 selected, 3 partial, 4 restored.
 * Only this original's constructor thread may use/restore it. State publication
 * also prevents a competing/reentrant receiver from inheriting cleanup duty. */
static _Atomic int actql_initial_managed_state;
static actql_native_initial_managed_original actql_initial_managed;

static bool actql_initial_managed_thread(
    actql_native_initial_managed_original *original) {
  return original == &actql_initial_managed &&
    original->process == getpid() &&
    pthread_equal(original->thread, pthread_self());
}

actql_native_initial_managed_original *actql_native_initial_managed_begin(
    actql_native_command_platform_original *entry) {
#if defined(__APPLE__) && defined(__aarch64__)
  size_t selection[4] = {0};
  if (!entry || !actql_native_command_platform_managed_selection(entry, selection) ||
      selection[0] < ACTQL_INITIAL_MI_SEGMENT_BYTES ||
      selection[0] % ACTQL_INITIAL_MI_SEGMENT_BYTES != 0 || !selection[1] ||
      !selection[2] || selection[2] > selection[0] || selection[3] != 1 ||
      !actql_initial_managed_environment_supported(*_NSGetEnviron()))
    return NULL;
  int expected = 0;
  if (!atomic_compare_exchange_strong_explicit(&actql_initial_managed_state,
      &expected, 1, memory_order_acq_rel, memory_order_acquire)) return NULL;
  actql_native_initial_managed_original *original = &actql_initial_managed;
  original->entry = entry;
  original->process = getpid();
  original->thread = pthread_self();
  for (size_t index = 0; index < 4; ++index)
    original->selection[index] = selection[index];
  /* Publish custody before any allocator setup. Failure cannot return a fresh
   * empty receiver or lose an arena/parent metadata attempt. */
  original->issue = ACTQL_INITIAL_MANAGED_VERSION;
  if (mi_version() != 217) goto partial;
  original->issue = ACTQL_INITIAL_MANAGED_PARENT;
  /* The selected entry runs before the runtime's automatic initializer.
   * Initialize inside this already covered metadata lifetime before observing
   * the actual parent default; a pre-init empty-heap sentinel is not a parent. */
  original->metadata_setup_attempted = true;
  mi_process_init();
  original->previous_default = mi_heap_get_default();
  if (!original->previous_default) goto partial;
  original->issue = ACTQL_INITIAL_MANAGED_RESERVE;
  original->reserve_attempted = true;
  if (mi_reserve_os_memory_ex(selection[0], false, false, true,
      &original->arena_id) != 0 || original->arena_id <= 0) goto partial;
  original->issue = ACTQL_INITIAL_MANAGED_AREA;
  original->area = mi_arena_area(original->arena_id, &original->reserved_bytes);
  if (!original->area || original->reserved_bytes != selection[0]) goto partial;
  original->issue = ACTQL_INITIAL_MANAGED_HEAP;
  original->heap = mi_heap_new_in_arena(original->arena_id);
  if (!original->heap || original->heap == original->previous_default) goto partial;
  original->issue = ACTQL_INITIAL_MANAGED_DEFAULT;
  /* A changed parent is not permission to replace an unrelated default. */
  if (mi_heap_get_default() != original->previous_default) goto partial;
  original->switch_attempted = true;
  original->observed_previous = mi_heap_set_default(original->heap);
  if (original->observed_previous != original->previous_default ||
      mi_heap_get_default() != original->heap) goto partial;
  original->issue = 0;
  atomic_store_explicit(&actql_initial_managed_state, 2, memory_order_release);
  return original;
partial:
  atomic_store_explicit(&actql_initial_managed_state, 3, memory_order_release);
  return original;
#else
  (void)entry;
  return NULL;
#endif
}

bool actql_native_initial_managed_current(
    actql_native_initial_managed_original *original) {
  if (atomic_load_explicit(&actql_initial_managed_state, memory_order_acquire) != 2 ||
      !actql_initial_managed_thread(original) || original->closing) return false;
#if defined(__APPLE__) && defined(__aarch64__)
  size_t selection[4] = {0}, bytes = 0;
  if (!actql_native_command_platform_managed_selection(original->entry, selection) ||
      !actql_initial_managed_environment_supported(*_NSGetEnviron()))
    return false;
  for (size_t index = 0; index < 4; ++index)
    if (selection[index] != original->selection[index]) return false;
  return mi_heap_get_default() == original->heap &&
    mi_arena_area(original->arena_id, &bytes) == original->area &&
    bytes == original->reserved_bytes;
#else
  return false;
#endif
}

int actql_native_initial_managed_issue(
    actql_native_initial_managed_original *original) {
  int state = atomic_load_explicit(&actql_initial_managed_state, memory_order_acquire);
  if ((state != 2 && state != 3 && state != 4) ||
      !actql_initial_managed_thread(original)) return ACTQL_INITIAL_MANAGED_INVALID;
  return original->issue;
}

int actql_native_initial_managed_restore(
    actql_native_initial_managed_original *original) {
  int state = atomic_load_explicit(&actql_initial_managed_state, memory_order_acquire);
  if ((state != 2 && state != 3 && state != 4) ||
      !actql_initial_managed_thread(original)) return ACTQL_INITIAL_MANAGED_INVALID;
  if (state == 4) return 1;
#if defined(__APPLE__) && defined(__aarch64__)
  int expected = state;
  if (!atomic_compare_exchange_strong_explicit(&actql_initial_managed_state,
      &expected, 1, memory_order_acq_rel, memory_order_acquire))
    return ACTQL_INITIAL_MANAGED_PENDING;
  original->closing = true;
  bool restored = !original->previous_default && !original->switch_attempted;
  if (original->previous_default) {
    void *current = mi_heap_get_default();
    if (!original->switch_attempted) {
      restored = current == original->previous_default;
    } else if (current == original->heap) {
      restored = mi_heap_set_default(original->previous_default) == original->heap &&
        mi_heap_get_default() == original->previous_default;
    }
  }
  atomic_store_explicit(&actql_initial_managed_state, restored ? 4 : state,
    memory_order_release);
  return restored ? 1 : ACTQL_INITIAL_MANAGED_PENDING;
#else
  return ACTQL_INITIAL_MANAGED_INVALID;
#endif
}
