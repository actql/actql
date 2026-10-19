/* Actual pinned allocator diagnostic, not an installed envelope or supplier.
 * Link this entry before the runtime object's automatic initializer. */
#include "moonbit.h"
#include "../initial_managed_mimalloc217.h"
#include <assert.h>
#include <mach-o/dyld.h>
#include <crt_externs.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include "../command_platform.h"

struct actql_native_command_platform_original { int original; };
static struct actql_native_command_platform_original entry;
static const char *mode;
static unsigned init_calls, mapping_calls, registration_calls, heap_calls;
static bool selection_changed;

bool actql_native_command_platform_managed_selection(
    actql_native_command_platform_original *original, size_t out[4]) {
  if (original != &entry || !strcmp(mode, "missing")) return false;
  out[0] = !strcmp(mode, "invalid") ? 1 : (size_t)64 * 1024 * 1024;
  out[1] = (size_t)64*1024*1024 + (selection_changed ? 1 : 0);
  out[2] = 1048576;
  out[3] = 1;
  return true;
}

static void observed_init(void) { ++init_calls; mi_process_init(); }
static void *observed_mapping(void *address, size_t bytes, int protection,
    int flags, int fd, off_t offset) {
  ++mapping_calls;
  if (!strcmp(mode, "mapping-failed")) return MAP_FAILED;
  return mmap(address, bytes, protection, flags, fd, offset);
}
static bool observed_registration(void *address, size_t bytes, bool committed,
    bool large, bool zero, int numa, bool exclusive, int *id) {
  ++registration_calls;
  if (!strcmp(mode, "registration-failed") && registration_calls == 2) return false;
  return mi_manage_os_memory_ex(address, bytes, committed, large, zero, numa, exclusive, id);
}
static mi_heap_t *observed_heap(int id) {
  ++heap_calls;
  return !strcmp(mode, "partial") ? NULL : mi_heap_new_in_arena(id);
}
#define mi_process_init observed_init
#define mmap observed_mapping
#define mi_manage_os_memory_ex observed_registration
#define mi_heap_new_in_arena observed_heap
#include "../initial_managed.inc"
#undef mi_process_init
#undef mmap
#undef mi_manage_os_memory_ex
#undef mi_heap_new_in_arena

static actql_native_initial_managed_original *receiver;
__attribute__((constructor)) static void original_entry(void) {
  int argc = *_NSGetArgc();
  char **argv = *_NSGetArgv();
  assert(argc == 2);
  mode = argv[1];
  receiver = actql_native_initial_managed_begin(&entry);
  if (!strcmp(mode, "environment-refusal")) {
    assert(receiver == NULL && init_calls == 0 && mapping_calls == 0 && registration_calls == 0 && heap_calls == 0);
    /* Refuse before the later automatic allocator initializer can consume the
     * deliberately supplied option. No acquired physical resource is ACKed. */
    const char result[] = "initial managed environment refusal passed\n";
    assert(write(STDOUT_FILENO, result, sizeof(result)-1) == sizeof(result)-1);
    _exit(0);
  }
}

extern size_t mi_usable_size(const void *);
extern void *mi_heap_malloc(mi_heap_t *, size_t);
static bool contains(const void *start, size_t n, const void *p, size_t bytes) {
  uintptr_t first = (uintptr_t)start, address = (uintptr_t)p;
  return address >= first && address - first <= n && bytes <= n-(address-first);
}
static void *foreign_thread(void *unused) {
  (void)unused;
  assert(!actql_native_initial_managed_current(receiver));
  assert(actql_native_initial_managed_restore(receiver) == ACTQL_INITIAL_MANAGED_INVALID);
  assert(actql_native_initial_managed_begin(&entry) == NULL);
  return NULL;
}

int main(void) {
  if (!strcmp(mode, "environment-vectors")) {
    char *ordinary[] = {"PATH=/usr/bin", "MIMALLOCX_RESERVE_OS_MEMORY=1G", NULL};
    char *upper[] = {"MIMALLOC_RESERVE_OS_MEMORY=1G", NULL};
    char *mixed[] = {"miMAlloC_unrecognized_option=0", NULL};
    char *empty[] = {"mimalloc_=", NULL};
    static char *many[10001];
    assert(actql_initial_managed_environment_supported(NULL));
    assert(actql_initial_managed_environment_supported(ordinary));
    assert(!actql_initial_managed_environment_supported(upper));
    assert(!actql_initial_managed_environment_supported(mixed));
    assert(!actql_initial_managed_environment_supported(empty));
    for (size_t i = 0; i < 10000; ++i) many[i] = "X=";
    many[9999] = NULL;
    assert(actql_initial_managed_environment_supported(many));
    many[9999] = "X=";
    assert(!actql_initial_managed_environment_supported(many));
    assert(actql_native_initial_managed_restore(receiver) == 1);
    puts("initial managed environment vectors passed");
    return 0;
  }
  if (!strcmp(mode, "missing") || !strcmp(mode, "invalid")) {
    assert(receiver == NULL);
    assert(init_calls == 0 && mapping_calls == 0 && registration_calls == 0 && heap_calls == 0);
    puts("initial managed refusal passed");
    return 0;
  }
  assert(receiver && mapping_calls == 1 && receiver->options_attempted);
  assert(receiver->previous_options[0] == 0 && receiver->previous_options[1] == 0 &&
    receiver->previous_options[2] == 0 && receiver->previous_options[3] == 0 &&
    receiver->previous_options[4] == 1048576);
  if (!strcmp(mode, "mapping-failed") || !strcmp(mode, "registration-failed")) {
    if (!strcmp(mode, "mapping-failed")) {
      assert(actql_native_initial_managed_issue(receiver) == ACTQL_INITIAL_MANAGED_MAPPING);
      assert(!receiver->mapping_acquired && init_calls == 0 && registration_calls == 0);
    } else {
      assert(actql_native_initial_managed_issue(receiver) == ACTQL_INITIAL_MANAGED_RESERVE);
      assert(receiver->mapping_acquired && init_calls == 1 && registration_calls == 2);
      size_t metadata=0;
      assert(mi_arena_area(receiver->metadata_arena_id,&metadata) == receiver->metadata_area);
      assert(metadata == ACTQL_INITIAL_MI_SEGMENT_BYTES);
    }
    assert(heap_calls == 0 && !actql_native_initial_managed_current(receiver));
    assert(actql_native_initial_managed_begin(&entry) == NULL);
    assert(actql_native_initial_managed_restore(receiver) == 1);
    assert(mi_option_get(17) == 1 && mi_option_get(23) == 0);
    puts("initial managed partial backing passed");
    return 0;
  }
  assert(init_calls == 1 && registration_calls == 2 && heap_calls == 1);
  assert(receiver->metadata_setup_attempted && receiver->payload_registration_attempted);
  assert(receiver->mapping_acquired && receiver->mapping_bytes == (size_t)128*1024*1024);
  assert(contains(receiver->mapping, receiver->mapping_bytes, receiver->metadata_area,
    ACTQL_INITIAL_MI_SEGMENT_BYTES));
  assert(contains(receiver->mapping, receiver->mapping_bytes, receiver->area,
    receiver->reserved_bytes));
  assert((uintptr_t)receiver->metadata_area+ACTQL_INITIAL_MI_SEGMENT_BYTES == (uintptr_t)receiver->area);
  assert(receiver->area && receiver->reserved_bytes == (size_t)64*1024*1024);
  assert(actql_native_initial_managed_begin(&entry) == NULL);
  struct actql_native_initial_managed_original copied = *receiver;
  assert(!actql_native_initial_managed_current(&copied));
  assert(actql_native_initial_managed_restore(&copied) == ACTQL_INITIAL_MANAGED_INVALID);
  if (!strcmp(mode, "partial")) {
    assert(actql_native_initial_managed_issue(receiver) == ACTQL_INITIAL_MANAGED_HEAP);
    assert(!receiver->switch_attempted);
    assert(!actql_native_initial_managed_current(receiver));
    assert(actql_native_initial_managed_restore(receiver) == 1);
  } else {
    /* The runtime's later automatic initializer must not replace this heap. */
    assert(actql_native_initial_managed_issue(receiver) == 0);
    assert(actql_native_initial_managed_current(receiver));
    if (!strcmp(mode, "changed-default")) {
      assert(mi_heap_set_default(receiver->previous_default) == receiver->heap);
      assert(actql_native_initial_managed_restore(receiver) == ACTQL_INITIAL_MANAGED_PENDING);
      assert(mi_heap_get_default() == receiver->previous_default);
      assert(!actql_native_initial_managed_current(receiver));
      assert(mi_heap_set_default(receiver->heap) == receiver->previous_default);
    } else if (!strcmp(mode, "backing-exhaustion")) {
      assert(mi_heap_malloc(receiver->previous_default,
        2*ACTQL_INITIAL_MI_SEGMENT_BYTES) == NULL);
      assert(mi_heap_malloc(receiver->heap,
        receiver->reserved_bytes+ACTQL_INITIAL_MI_SEGMENT_BYTES) == NULL);
      size_t extra = 0;
      assert(mi_arena_area(3, &extra) == NULL && extra == 0);
      assert(actql_native_initial_managed_current(receiver));
    } else if (!strcmp(mode, "options-changed")) {
      mi_option_set(17, 0);
      assert(!actql_native_initial_managed_current(receiver));
    } else if (!strcmp(mode, "changed-selection")) {
      selection_changed = true;
      assert(!actql_native_initial_managed_current(receiver));
    } else {
      assert(!strcmp(mode, "ready"));
      pthread_t thread;
      assert(pthread_create(&thread, NULL, foreign_thread, NULL) == 0);
      assert(pthread_join(thread, NULL) == 0);
      assert(actql_native_initial_managed_current(receiver));
    }
    assert(contains(receiver->metadata_area, ACTQL_INITIAL_MI_SEGMENT_BYTES,
      receiver->heap, mi_usable_size(receiver->heap)));
    moonbit_string_t alias = moonbit_make_string(128, 'r');
    void *allocation = Moonbit_object_header(alias);
    assert(contains(receiver->area, receiver->reserved_bytes, allocation,
      mi_usable_size(allocation)));
    assert(actql_native_initial_managed_restore(receiver) == 1);
    assert(alias[0] == 'r' && alias[127] == 'r');
    moonbit_decref(alias);
  }
  assert(!actql_native_initial_managed_current(receiver));
  assert(mi_heap_get_default() == receiver->previous_default);
  assert(actql_native_initial_managed_restore(receiver) == 1);
  assert(init_calls == 1 && mapping_calls == 1 && registration_calls == 2 && heap_calls == 1);
  assert(mi_option_get(17) == (!strcmp(mode,"options-changed") ? 0 : 1));
  assert(mi_option_get(23) == 0);
  size_t retained = 0;
  assert(mi_arena_area(receiver->arena_id, &retained) == receiver->area);
  assert(retained == receiver->reserved_bytes);
  assert(actql_native_initial_managed_begin(&entry) == NULL);
  /* A restored default is not an arena/metadata retirement acknowledgment. */
  puts("initial managed original custody passed");
  return 0;
}
