/* Actual pinned allocator diagnostic, not an installed envelope or supplier.
 * Link this entry before the runtime object's automatic initializer. */
#include "moonbit.h"
#include "../initial_managed_mimalloc217.h"
#include <assert.h>
#include <mach-o/dyld.h>
#include <crt_externs.h>
#include <stdio.h>
#include <string.h>
#include "../command_platform.h"

struct actql_native_command_platform_original { int original; };
static struct actql_native_command_platform_original entry;
static const char *mode;
static unsigned init_calls, reserve_calls, heap_calls;
static bool selection_changed;

bool actql_native_command_platform_managed_selection(
    actql_native_command_platform_original *original, size_t out[4]) {
  if (original != &entry || !strcmp(mode, "missing")) return false;
  out[0] = !strcmp(mode, "invalid") ? 1 : (size_t)64 * 1024 * 1024;
  out[1] = selection_changed ? 2 : 1;
  out[2] = 1048576;
  out[3] = 1;
  return true;
}

static void observed_init(void) { ++init_calls; mi_process_init(); }
static int observed_reserve(size_t n, bool commit, bool large, bool exclusive,
    int *id) {
  ++reserve_calls;
  return mi_reserve_os_memory_ex(n, commit, large, exclusive, id);
}
static mi_heap_t *observed_heap(int id) {
  ++heap_calls;
  return !strcmp(mode, "partial") ? NULL : mi_heap_new_in_arena(id);
}
#define mi_process_init observed_init
#define mi_reserve_os_memory_ex observed_reserve
#define mi_heap_new_in_arena observed_heap
#include "../initial_managed.inc"
#undef mi_process_init
#undef mi_reserve_os_memory_ex
#undef mi_heap_new_in_arena

static actql_native_initial_managed_original *receiver;
__attribute__((constructor)) static void original_entry(void) {
  int argc = *_NSGetArgc();
  char **argv = *_NSGetArgv();
  assert(argc == 2);
  mode = argv[1];
  receiver = actql_native_initial_managed_begin(&entry);
  if (!strcmp(mode, "environment-refusal")) {
    assert(receiver == NULL && init_calls == 0 && reserve_calls == 0 && heap_calls == 0);
    /* Refuse before the later automatic allocator initializer can consume the
     * deliberately supplied option. No acquired physical resource is ACKed. */
    const char result[] = "initial managed environment refusal passed\n";
    assert(write(STDOUT_FILENO, result, sizeof(result)-1) == sizeof(result)-1);
    _exit(0);
  }
}

extern size_t mi_usable_size(const void *);
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
    assert(init_calls == 0 && reserve_calls == 0 && heap_calls == 0);
    puts("initial managed refusal passed");
    return 0;
  }
  assert(receiver && init_calls == 1 && reserve_calls == 1 && heap_calls == 1);
  assert(receiver->metadata_setup_attempted && receiver->reserve_attempted);
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
  assert(init_calls == 1 && reserve_calls == 1 && heap_calls == 1);
  size_t retained = 0;
  assert(mi_arena_area(receiver->arena_id, &retained) == receiver->area);
  assert(retained == receiver->reserved_bytes);
  assert(actql_native_initial_managed_begin(&entry) == NULL);
  /* A restored default is not an arena/metadata retirement acknowledgment. */
  puts("initial managed original custody passed");
  return 0;
}
