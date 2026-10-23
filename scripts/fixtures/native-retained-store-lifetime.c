/* Exercise the production lifetime observer against a real SQLite handle and
 * controlled original-route states. No Host, entered Read or grant is issued. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <pthread.h>
#include <sys/wait.h>
#include "../../src/platform_native/sqlite/sqlite_stub.c"

void actql_native_timing_count(int32_t tag) { (void)tag; }
static int callbacks;
static int32_t route(void *receiver, void *library, int32_t tag) {
  (void)receiver; (void)library; (void)tag; callbacks++; return 0;
}
static void *foreign_thread(void *pointer) {
  assert(actql_native_sqlite_database_retained_data_current(pointer) == 4);
  return NULL;
}
int main(void) {
  actql_native_sqlite_library library = {0};
  library.dynamic_library = dlopen("/usr/lib/libsqlite3.dylib", RTLD_NOW | RTLD_LOCAL);
  assert(library.dynamic_library != NULL);
  actql_native_sqlite_database database = {0};
  database.library = &library;
  database.process = getpid();
  assert(sqlite3_open(":memory:", &database.database) == SQLITE_OK);
  database.opened = true;
  assert(actql_native_sqlite_database_retained_data_current(&database) == 0);
  assert(sqlite3_get_autocommit(database.database));
  assert(sqlite3_total_changes(database.database) == 0);
  puts("open original without SQL or allocation: PASS");

  database.opened = false;
  assert(actql_native_sqlite_database_retained_data_current(&database) == 1);
  database.opened = true;
  library.closing = true;
  assert(actql_native_sqlite_database_retained_data_current(&database) == 2);
  library.closing = false;
  database.transaction_fenced = 1;
  assert(actql_native_sqlite_database_retained_data_current(&database) == 3);
  database.transaction_fenced = 0;
  database.journal_pin_close_unknown = true;
  assert(actql_native_sqlite_database_retained_data_current(&database) == 3);
  database.journal_pin_close_unknown = false;
  puts("closed Library and uncertain database refuse: PASS");

  actql_native_store_operation original = {0};
  original.library = &library;
  original.receiver = &callbacks;
  original.route = route;
  original.process = getpid();
  original.thread = pthread_self();
  original.bound_database = &database;
  original.activated = true;
  database.store_operation = &original;
  assert(actql_native_sqlite_database_retained_data_current(&database) == 0);
  bool *pending[] = {&original.calling, &original.flight, &original.sql};
  for (size_t i = 0; i < sizeof(pending) / sizeof(pending[0]); i++) {
    *pending[i] = true;
    assert(actql_native_sqlite_database_retained_data_current(&database) == 3);
    *pending[i] = false;
  }
  bool *unavailable[] = {&original.failed, &original.cleanup_only,
    &original.closed, &original.database_closed};
  for (size_t i = 0; i < sizeof(unavailable) / sizeof(unavailable[0]); i++) {
    *unavailable[i] = true;
    assert(actql_native_sqlite_database_retained_data_current(&database) == 4);
    assert(*unavailable[i]);
    *unavailable[i] = false;
  }
  original.bound_database = NULL;
  assert(actql_native_sqlite_database_retained_data_current(&database) == 4);
  original.bound_database = &database;
  assert(callbacks == 0);
  puts("idle exact route only and no callback or failure reset: PASS");

  pthread_t thread;
  assert(pthread_create(&thread, NULL, foreign_thread, &database) == 0);
  assert(pthread_join(thread, NULL) == 0);
  pid_t child = fork();
  assert(child >= 0);
  if (child == 0) _exit(actql_native_sqlite_database_retained_data_current(&database) == 1 ? 0 : 1);
  int status;
  assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
  assert(callbacks == 0 && actql_native_sqlite_database_retained_data_current(&database) == 0);
  puts("foreign process and thread refuse without changing original: PASS");

  assert(sqlite3_close(database.database) == SQLITE_OK);
  database.database = NULL;
  database.opened = false;
  assert(actql_native_sqlite_database_retained_data_current(&database) == 1);
  assert(dlclose(library.dynamic_library) == 0);
  library.dynamic_library = NULL;
  puts("separate actual database and module cleanup: PASS");
  puts("Retained Store lifetime C cases: 5/5");
  return 0;
}
