/* Included once by the selected executable's existing entry, before its first
 * covered allocator call. This is its original physical binding, not another
 * bootstrap Owner, registry or public allocator. No heap/arena deletion occurs:
 * escaped managed allocations and process-lived registrations keep their same
 * initial responsibility after restoring the previous default. */
#if defined(ACTQL_PYTHON_INITIAL_OPERATIONAL_ENTRY)
#include "python_initial_platform.h"
#else
#include "command_platform.h"
#endif
#include <stdatomic.h>
#include <stdint.h>
#include <pthread.h>
#include <unistd.h>
#include <sys/mman.h>

#if defined(ACTQL_PYTHON_INITIAL_OPERATIONAL_ENTRY) && defined(__APPLE__) && defined(__aarch64__)
/* Exact selected private MI ABI. A previously initialized object cannot be
 * adopted as this Python entrance's fresh original, even with no arena yet. */
extern bool _mi_process_is_initialized;
#endif

#if defined(__APPLE__) && defined(__aarch64__)
#include <crt_externs.h>
#include "initial_managed_mimalloc217.h"
/* Actual selected 64-bit toolchain geometry. The entry recipe must qualify
 * this runtime object/ABI, not infer the granularity from a successful probe.
 * Preselect whole segments before reservation; reject any observed mismatch. */
#define ACTQL_INITIAL_MI_SEGMENT_BYTES ((size_t)32 * 1024 * 1024)

/* Exact selected 2.1.7 option ABI: no startup reserve, no dynamic general
 * arena growth, no OS allocation fallback, and no destructive exit shortcut.
 * Defaults/selection and the five previous values stay with this original. */
static const int actql_initial_mi_options[5] = {7, 9, 17, 22, 23};
static const long actql_initial_mi_values[5] = {0, 0, 1, 0, 0};

static bool actql_initial_managed_geometry(const size_t selection[4]) {
  const size_t segment = ACTQL_INITIAL_MI_SEGMENT_BYTES;
  if (selection[0] > SIZE_MAX-2*segment || selection[1] < 2*segment ||
      !selection[2] || selection[2] > selection[0]) return false;
  /* The pinned object registers each arena with 152 bytes plus five 64-bit
   * bitmaps per field, and at most 15 alignment bytes. Both registrations
   * must fit its existing 8192-byte static registration storage. This is a
   * private geometry bound, not a public payload or numerical profile. */
  size_t blocks = selection[0]/segment;
  size_t fields = blocks/64 + (blocks%64 != 0);
  return fields <= (8192-2*(152+15)-40)/40;
}

/* A private finite candidate for this SAME actual allocator geometry. The
 * source-bound allocation volume selects whole payload segments, not an
 * all-input fit guarantee: headers/fragmentation/realloc overlap may exhaust
 * it. No mapping, registration, options or initial admission occurs here. */
static bool actql_initial_managed_prepare_candidate(
    size_t volume, size_t out[4]) {
  const size_t segment = ACTQL_INITIAL_MI_SEGMENT_BYTES;
  if (!out || !volume || volume > SIZE_MAX-(segment-1)) return false;
  size_t payload = ((volume+segment-1)/segment)*segment;
  size_t selection[4] = {payload, 2*segment, volume, 1};
  if (!actql_initial_managed_geometry(selection)) return false;
  for (size_t index = 0; index < 4; ++index) out[index] = selection[index];
  return true;
}

static bool actql_initial_managed_contains(const void *base, size_t bytes,
    const void *allocation, size_t length) {
  uintptr_t first = (uintptr_t)base, address = (uintptr_t)allocation;
  return address >= first && address-first <= bytes &&
    length <= bytes-(address-first);
}

/* The selected allocator's startup options can reserve other arenas or alter
 * process-lived cleanup. This profile selects its pinned finite options, not
 * ambient allocator customization. Observe the actual startup vector without getenv,
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

#if !defined(__APPLE__) || !defined(__aarch64__)
static bool actql_initial_managed_prepare_candidate(
    size_t volume, size_t out[4]) {
  (void)volume; (void)out;
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
  ACTQL_INITIAL_MANAGED_DEFAULT = -8,
  ACTQL_INITIAL_MANAGED_OPTIONS = -9,
  ACTQL_INITIAL_MANAGED_MAPPING = -10,
  ACTQL_INITIAL_MANAGED_METADATA = -11
};

struct actql_native_initial_managed_original {
#if defined(ACTQL_PYTHON_INITIAL_OPERATIONAL_ENTRY)
  actql_native_python_initial_platform_original *python_entry;
#else
  actql_native_command_platform_original *entry;
#endif
  pid_t process;
  pthread_t thread;
  size_t selection[4];
  void *mapping;
  size_t mapping_bytes;
  void *metadata_area;
  int metadata_arena_id;
  long previous_options[5];
  bool options_attempted;
  bool mapping_attempted;
  bool mapping_acquired;
  bool metadata_registration_attempted;
  void *area;
  size_t reserved_bytes;
  void *previous_default;
  void *heap;
  void *observed_previous;
  int arena_id;
  int issue;
  bool payload_registration_attempted;
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

#if defined(ACTQL_PYTHON_INITIAL_OPERATIONAL_ENTRY)
actql_native_initial_managed_original *actql_native_python_initial_managed_begin(
    actql_native_python_initial_platform_original *entry) {
#else
actql_native_initial_managed_original *actql_native_initial_managed_begin(
    actql_native_command_platform_original *entry) {
#endif
#if defined(__APPLE__) && defined(__aarch64__)
  size_t selection[4] = {0};
  if (!entry ||
#if defined(ACTQL_PYTHON_INITIAL_OPERATIONAL_ENTRY)
      !actql_native_python_initial_platform_managed_selection(entry, selection) ||
      /* Observe MI state only on the original entry's confirmed thread. */
      _mi_process_is_initialized ||
#else
      !actql_native_command_platform_managed_selection(entry, selection) ||
#endif
      selection[0] < ACTQL_INITIAL_MI_SEGMENT_BYTES ||
      selection[0] % ACTQL_INITIAL_MI_SEGMENT_BYTES != 0 || !selection[1] ||
      !actql_initial_managed_geometry(selection) || selection[3] != 1 ||
      !actql_initial_managed_environment_supported(*_NSGetEnviron()))
    return NULL;
  int expected = 0;
  if (!atomic_compare_exchange_strong_explicit(&actql_initial_managed_state,
      &expected, 1, memory_order_acq_rel, memory_order_acquire)) return NULL;
  actql_native_initial_managed_original *original = &actql_initial_managed;
#if defined(ACTQL_PYTHON_INITIAL_OPERATIONAL_ENTRY)
  original->python_entry = entry;
#else
  original->entry = entry;
#endif
  original->process = getpid();
  original->thread = pthread_self();
  for (size_t index = 0; index < 4; ++index)
    original->selection[index] = selection[index];
  /* Retain the actual entry before option setup, mapping or registration.
   * The selected runtime uses these exact public option indices. Mutations
   * and the original values belong to this process lifetime, not a child. */
  original->issue = ACTQL_INITIAL_MANAGED_VERSION;
  if (mi_version() != 217) goto partial;
  original->issue = ACTQL_INITIAL_MANAGED_OPTIONS;
  original->options_attempted = true;
  for (size_t index = 0; index < 5; ++index) {
    original->previous_options[index] = mi_option_get(actql_initial_mi_options[index]);
    mi_option_set(actql_initial_mi_options[index], actql_initial_mi_values[index]);
    if (mi_option_get(actql_initial_mi_options[index]) != actql_initial_mi_values[index])
      goto partial;
  }
  original->issue = ACTQL_INITIAL_MANAGED_MAPPING;
  original->mapping_bytes = selection[0] + 2*ACTQL_INITIAL_MI_SEGMENT_BYTES;
  original->mapping_attempted = true;
  original->mapping = mmap(NULL, original->mapping_bytes, PROT_READ | PROT_WRITE,
    MAP_PRIVATE | MAP_ANON, -1, 0);
  if (original->mapping == MAP_FAILED) goto partial;
  original->mapping_acquired = true;
  uintptr_t base = (uintptr_t)original->mapping;
  if (!base || base > UINTPTR_MAX-original->mapping_bytes) goto partial;
  uintptr_t aligned = (base + ACTQL_INITIAL_MI_SEGMENT_BYTES-1) &
    ~(uintptr_t)(ACTQL_INITIAL_MI_SEGMENT_BYTES-1);
  original->metadata_area = (void *)aligned;
  original->area = (void *)(aligned + ACTQL_INITIAL_MI_SEGMENT_BYTES);
  original->reserved_bytes = selection[0];
  /* Initialize inside the covered lifetime before observing the actual parent.
   * Additional allocator reservations are disabled before this first init. */
  original->issue = ACTQL_INITIAL_MANAGED_PARENT;
  original->metadata_setup_attempted = true;
  mi_process_init();
  original->previous_default = mi_heap_get_default();
  if (!original->previous_default) goto partial;
  /* One actual fresh process registration sequence, with a source-qualified
   * static-registration bound checked before use. No general arena or OS
   * fallback may substitute for this backing. */
  size_t existing = 0;
  if (mi_arena_area(1, &existing) != NULL) goto partial;
  original->issue = ACTQL_INITIAL_MANAGED_METADATA;
  original->metadata_registration_attempted = true;
  if (!mi_manage_os_memory_ex(original->metadata_area, ACTQL_INITIAL_MI_SEGMENT_BYTES,
      true, false, true, -1, false, &original->metadata_arena_id) ||
      original->metadata_arena_id <= 0) goto partial;
  original->issue = ACTQL_INITIAL_MANAGED_RESERVE;
  original->payload_registration_attempted = true;
  if (!mi_manage_os_memory_ex(original->area, selection[0],
      true, false, true, -1, true, &original->arena_id) || original->arena_id <= 0)
    goto partial;
  original->issue = ACTQL_INITIAL_MANAGED_AREA;
  size_t observed = 0;
  if (mi_arena_area(original->metadata_arena_id, &observed) != original->metadata_area ||
      observed != ACTQL_INITIAL_MI_SEGMENT_BYTES ||
      mi_arena_area(original->arena_id, &observed) != original->area ||
      observed != selection[0]) goto partial;
  original->issue = ACTQL_INITIAL_MANAGED_HEAP;
  original->heap = mi_heap_new_in_arena(original->arena_id);
  if (!original->heap || original->heap == original->previous_default ||
      !actql_initial_managed_contains(original->metadata_area,
        ACTQL_INITIAL_MI_SEGMENT_BYTES, original->heap, mi_usable_size(original->heap)))
    goto partial;
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
  if (
#if defined(ACTQL_PYTHON_INITIAL_OPERATIONAL_ENTRY)
      !actql_native_python_initial_platform_managed_selection(original->python_entry, selection) ||
#else
      !actql_native_command_platform_managed_selection(original->entry, selection) ||
#endif
      !actql_initial_managed_environment_supported(*_NSGetEnviron()))
    return false;
  for (size_t index = 0; index < 4; ++index)
    if (selection[index] != original->selection[index]) return false;
  for (size_t index = 0; index < 5; ++index)
    if (mi_option_get(actql_initial_mi_options[index]) != actql_initial_mi_values[index])
      return false;
  if (mi_arena_area(original->metadata_arena_id, &bytes) != original->metadata_area ||
      bytes != ACTQL_INITIAL_MI_SEGMENT_BYTES) return false;
  return mi_heap_get_default() == original->heap &&
    mi_arena_area(original->arena_id, &bytes) == original->area &&
    bytes == original->reserved_bytes;
#else
  return false;
#endif
}

#if defined(ACTQL_PYTHON_INITIAL_OPERATIONAL_ENTRY)
bool actql_native_python_initial_managed_current(void) {
  return actql_native_initial_managed_current(&actql_initial_managed);
}
#endif

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
