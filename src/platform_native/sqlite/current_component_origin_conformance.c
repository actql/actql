/* Standalone physical FFI conformance. Compile against the selected original
 * provider's derived headers and link that ONE provider, not another runtime.
 * Arguments: component image, fresh owned database path. This fixture observes
 * physical context/heap facts, never Host permission or a normal profile. */
#define ACTQL_SCOPED_READ_ALLOCATOR 1
#include "sqlite_stub.c"
#include "scoped_read.h"
#include <assert.h>

typedef struct {
  actql_owned_capacity *lease;
  actql_read_context *context;
} original_domain;

static const unsigned char fixture_recipe[32] = {41};

static original_domain fresh_domain(void) {
  original_domain value = {0};
  size_t bytes = 64 * (size_t)sysconf(_SC_PAGESIZE);
  assert(actql_native_owned_acquire(bytes, 1, fixture_recipe, &value.lease) == 0);
  assert(actql_native_owned_transfer(value.lease, 1, fixture_recipe) == 0);
  assert(actql_native_owned_enter(value.lease) == 0);
  assert(actql_read_context_create(value.lease, &value.context) == 0);
  assert(actql_read_context_retain(value.context) == 0);
  assert(actql_native_owned_leave(value.lease) == 0);
  return value;
}

static void enter_domain(original_domain value) {
  assert(actql_native_owned_enter(value.lease) == 0);
  assert(actql_read_context_enter(value.context) == 0);
}

static void leave_domain(original_domain value) {
  assert(actql_read_context_leave(value.context) == 0);
  assert(actql_native_owned_leave(value.lease) == 0);
}

static void finish_domain(original_domain *value) {
  assert(actql_read_context_release_after_owner_ack(value->context) == 0);
  assert(actql_read_context_try_close(&value->context) == 0);
  assert(value->context == NULL);
  assert(actql_native_owned_try_close(&value->lease) == 0);
  assert(value->lease == NULL);
}

int main(int argc, char **argv) {
  assert(argc == 3);
  struct stat absent;
  assert(lstat(argv[2], &absent) < 0 && errno == ENOENT);
  Dl_info original, observed, consumer;
  assert(dladdr((void *)actql_bootstrap_current_read_context, &original));
  const void *entries[] = {(void *)actql_native_owned_acquire,
    (void *)actql_native_owned_current, (void *)actql_read_context_create,
    (void *)actql_read_context_enter, (void *)actql_native_file_scoped_allocate};
  for (size_t i = 0; i < sizeof(entries) / sizeof(entries[0]); i++) {
    assert(dladdr(entries[i], &observed));
    assert(observed.dli_fbase == original.dli_fbase);
  }
  assert(dladdr((void *)actql_native_sqlite_database_current_component_matches_heap,
                &consumer));
  assert(consumer.dli_fbase != original.dli_fbase);
  puts("{\"case\":\"single-provider\",\"pass\":true}");
  original_domain first = fresh_domain(), foreign = fresh_domain();
  enter_domain(first);
  const int64_t heap = 32 * (int64_t)sysconf(_SC_PAGESIZE);
  actql_native_sqlite_library *library = actql_native_sqlite_load_current_component(
    (moonbit_bytes_t)argv[1], (int32_t)strlen(argv[1]), 128, heap);
  assert(library != NULL && actql_native_sqlite_library_ready(library));
  assert(library->selected_heap_bytes == heap);
  actql_native_sqlite_database *database = actql_native_sqlite_open_database(
    library, (moonbit_bytes_t)argv[2], (int32_t)strlen(argv[2]), 1024);
  assert(database != NULL && actql_native_sqlite_database_ready(database));
  assert(actql_native_sqlite_database_current_component_matches_heap(database, heap));
  puts("{\"case\":\"original-current-heap\",\"pass\":true}");
  assert(actql_native_sqlite_database_insert(database,
    (moonbit_bytes_t)"origin", 6, (moonbit_bytes_t)"same", 4,
    (moonbit_bytes_t)"original", 8) == 1);
  assert(actql_native_sqlite_database_read(database,
    (moonbit_bytes_t)"origin", 6, (moonbit_bytes_t)"same", 4) == 1);
  unsigned char *body = database->result_body;
  const int32_t body_length = database->result_body_length;
  const int64_t revision = database->result_revision;
  const int64_t wrong[] = {-1, 0, 4095, heap - 1, heap + 1, INT64_MAX};
  for (size_t i = 0; i < sizeof(wrong) / sizeof(wrong[0]); i++)
    assert(!actql_native_sqlite_database_current_component_matches_heap(database, wrong[i]));
  assert(database->result_body == body && database->result_body_length == body_length);
  assert(database->result_revision == revision && body_length == 8);
  assert(memcmp(database->result_body, "original", 8) == 0);
  puts("{\"case\":\"wrong-heap-preserves-readback\",\"pass\":true}");
  leave_domain(first);
  assert(!actql_native_sqlite_database_current_component_matches_heap(database, heap));
  enter_domain(foreign);
  assert(!actql_native_sqlite_database_current_component_matches_heap(database, heap));
  leave_domain(foreign);
  finish_domain(&foreign);
  enter_domain(first);
  assert(actql_native_sqlite_database_current_component_matches_heap(database, heap));
  puts("{\"case\":\"missing-and-foreign-context\",\"pass\":true}");
  pid_t child = fork();
  assert(child >= 0);
  if (child == 0) {
    /* This predicate short-circuits at the original PID. No inherited SQLite
     * operation, cleanup, allocator or context mutation is attempted. */
    _exit(actql_native_sqlite_database_current_component_matches_heap(database, heap) ? 1 : 0);
  }
  int status;
  assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
  puts("{\"case\":\"inherited-process-refused\",\"pass\":true}");
  assert(actql_native_sqlite_close_checked(database));
  assert(!actql_native_sqlite_database_current_component_matches_heap(database, heap));
  assert(library->selected_heap_bytes == heap);
  moonbit_decref(database);
  assert(library->database_children == 0);
  assert(actql_native_sqlite_library_close_checked(library));
  assert(library->selected_heap_bytes == heap);
  moonbit_decref(library);
  leave_domain(first);
  finish_domain(&first);
  puts("{\"case\":\"checked-retirement\",\"pass\":true}");
  puts("{\"physicalCases\":6,\"pass\":true,\"moonTests\":0,\"normalProfile\":null,\"publicE2E\":0}");
  return 0;
}
