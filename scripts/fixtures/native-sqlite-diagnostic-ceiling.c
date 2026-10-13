// Diagnostic-only counterexamples against the actual FFI. SQLite callbacks are
// injected; this does not establish kernel/SQLite faults or Run cancellation.
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>
static int allocation_failure;
static size_t allocation_max;
static void *fixture_malloc(size_t size) {
  if (size > allocation_max) allocation_max = size;
  return allocation_failure ? NULL : malloc(size);
}
#define malloc fixture_malloc
#include "../../src/platform_native/sqlite/sqlite_stub.c"
#undef malloc

static const char *message;
static int close_calls;
static int commits;
static const char *fixture_errmsg(sqlite3 *database) {
  assert(database != NULL);
  return message;
}
static int fixture_close(sqlite3 *database) {
  assert(database != NULL);
  close_calls++;
  return SQLITE_BUSY;
}
static int fixture_exec(sqlite3 *db, const char *sql,
  int (*callback)(void *, int, char **, char **), void *context, char **error) {
  (void)callback; (void)context;
  assert(db != NULL && strcmp(sql, "COMMIT") == 0 && error != NULL);
  commits++;
  *error = NULL;
  return SQLITE_OK;
}
static void expect_bytes(moonbit_bytes_t bytes, const char *expected) {
  size_t n = strlen(expected);
  assert((size_t)Moonbit_array_length(bytes) == n);
  assert(n == 0 || memcmp(bytes, expected, n) == 0);
  moonbit_decref(bytes);
}
int main(void) {
  actql_native_sqlite_library library = {0};
  library.diagnostic_ceiling = 4;
  library.errmsg = fixture_errmsg;
  library.close_v2 = fixture_close;
  library.exec = fixture_exec;
  actql_native_sqlite_database db = {0};
  db.library = &library;
  db.database = (sqlite3 *)&db;
  db.opened = true;
  db.max_body_bytes = 0; // Row limits do not supply the diagnostic limit.
  db.diagnostic_ceiling = library.diagnostic_ceiling;
  message = "abcd";
  actql_database_error(&db, "unused");
  assert(allocation_max == 5);
  expect_bytes(actql_native_sqlite_database_error(&db), "abcd");
  puts("exact diagnostic: PASS");
  message = "abcde";
  actql_database_error(&db, "unused");
  assert(db.error == NULL && allocation_max == 5);
  expect_bytes(actql_native_sqlite_database_error(&db), "");
  puts("one-over omits whole detail: PASS");
  message = "\xc3\xa9\xc3\xa9";
  actql_database_error(&db, "unused");
  expect_bytes(actql_native_sqlite_database_error(&db), message);
  message = "\xc3\xa9\xc3\xa9x";
  actql_database_error(&db, "unused");
  expect_bytes(actql_native_sqlite_database_error(&db), "");
  puts("UTF8 bytes, no partial prefix: PASS");
  // A protected page follows exactly ceiling+1 readable bytes. No strlen or
  // scan beyond that bound is allowed, even before the first allocation.
  size_t page = (size_t)sysconf(_SC_PAGESIZE);
  char *pages = mmap(NULL, page * 2, PROT_READ | PROT_WRITE,
    MAP_ANON | MAP_PRIVATE, -1, 0);
  assert(pages != MAP_FAILED && mprotect(pages + page, page, PROT_NONE) == 0);
  message = pages + page - 5;
  memset((char *)message, 'x', 5);
  actql_database_error(&db, "unused");
  expect_bytes(actql_native_sqlite_database_error(&db), "");
  assert(munmap(pages, page * 2) == 0);
  puts("bounded scan before C copy: PASS");
  message = "ok";
  allocation_failure = 1;
  actql_database_error(&db, "unused");
  allocation_failure = 0;
  assert(db.error == NULL && db.opened);
  expect_bytes(actql_native_sqlite_database_error(&db), "");
  puts("diagnostic allocation failure preserves handle: PASS");
  // Cleanup must remain failed, retain its handle, and retry the same Owner.
  message = "oversized cleanup detail";
  assert(actql_native_sqlite_close_checked(&db) == 0);
  assert(actql_native_sqlite_close_checked(&db) == 0);
  assert(close_calls == 2 && db.opened && db.database != NULL);
  expect_bytes(actql_native_sqlite_database_error(&db), "");
  assert(actql_operation_code(SQLITE_BUSY) == 3);
  assert(actql_operation_code(SQLITE_IOERR) == -1);
  puts("cleanup and Physical codes unchanged: PASS");
  // The existing injected lost commit reply is a failure, even though COMMIT
  // succeeded. Diagnostics do not clear an adapter's transaction fence.
  db.test_commit_reply_failures = 1;
  actql_native_sqlite_database_fence_transactions(&db);
  assert(actql_native_sqlite_database_commit(&db) == 4 && commits == 1);
  assert(actql_native_sqlite_database_transaction_fenced(&db) == 1);
  expect_bytes(actql_native_sqlite_database_error(&db), "");
  puts("commit reply loss retains fence: PASS");
  actql_replace_error(&library.error, library.diagnostic_ceiling, "longer");
  expect_bytes(actql_native_sqlite_library_error(&library), "");
  free(db.error); free(library.error);
  puts("library diagnostic uses same ceiling: PASS");
  puts("diagnostic cases: 8/8");
  return 0;
}
