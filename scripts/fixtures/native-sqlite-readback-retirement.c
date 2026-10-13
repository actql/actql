// Readback-lifetime counterexamples against the exact FFI. Close callbacks
// are injected; this is not a real SQLite fault, Native Host or Run test.
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uintptr_t tracked_body, tracked_key;
static int storage_frees;
static void fixture_free(void *pointer) {
  if (pointer != NULL && ((uintptr_t)pointer == tracked_body ||
      (uintptr_t)pointer == tracked_key)) storage_frees++;
  free(pointer);
}
#define free fixture_free
#include "../../src/platform_native/sqlite/sqlite_stub.c"
#undef free

static int close_code, close_calls;
static int fixture_close(sqlite3 *database) {
  assert(database != NULL);
  close_calls++;
  return close_code;
}
static const char *fixture_error(sqlite3 *database) {
  assert(database != NULL);
  return "pending";
}
static void install_storage(actql_native_sqlite_database *database) {
  database->result_body = malloc(6);
  database->result_key = malloc(5);
  assert(database->result_body != NULL && database->result_key != NULL);
  memcpy(database->result_body, "e\xcc\x81\r\n!", 6);
  memcpy(database->result_key, "input", 5);
  database->result_body_length = 6;
  database->result_key_length = 5;
  database->result_revision = 7;
  database->result_capacity_bytes = 31;
  database->result_capacity_objects = 2;
  tracked_body = (uintptr_t)database->result_body;
  tracked_key = (uintptr_t)database->result_key;
  storage_frees = 0;
}
static void check_copy(moonbit_bytes_t body, moonbit_bytes_t key) {
  assert(Moonbit_array_length(body) == 6 &&
    memcmp(body, "e\xcc\x81\r\n!", 6) == 0);
  assert(Moonbit_array_length(key) == 5 && memcmp(key, "input", 5) == 0);
}
// Local structural observation also permits the unchanged parent FFI to serve
// as the failing control; it is not a new product cleanup predicate.
static bool fixture_storage_empty(actql_native_sqlite_database *database) {
  return database->result_body == NULL && database->result_key == NULL &&
    database->result_body_length == 0 && database->result_key_length == 0 &&
    database->result_revision == 0 && database->result_capacity_bytes == 0 &&
    database->result_capacity_objects == 0;
}
int main(void) {
  actql_native_sqlite_library library = {0};
  library.close_v2 = fixture_close;
  library.errmsg = fixture_error;
  actql_native_sqlite_database database = {0};
  database.library = &library;
  database.database = (sqlite3 *)&database;
  database.opened = true;
  database.diagnostic_ceiling = 16;
  install_storage(&database);
  moonbit_bytes_t body = actql_native_sqlite_database_result_body(&database);
  moonbit_bytes_t key = actql_native_sqlite_database_result_key(&database);
  check_copy(body, key);
  puts("returned body/key are independent copies: PASS");

  close_code = SQLITE_BUSY;
  assert(actql_native_sqlite_close_checked(&database) == 0);
  assert(database.opened && database.database != NULL && storage_frees == 0);
  assert(!fixture_storage_empty(&database));
  assert(database.result_revision == 7 &&
    database.result_capacity_bytes == 31 && database.result_capacity_objects == 2);
  assert(database.error != NULL && strcmp(database.error, "pending") == 0);
  check_copy(body, key);
  puts("failed close keeps original storage and diagnostic: PASS");

  close_code = SQLITE_OK;
  assert(actql_native_sqlite_close_checked(&database) == 1);
  assert(!database.opened && database.database == NULL && storage_frees == 2);
  assert(fixture_storage_empty(&database));
  assert(database.error != NULL && strcmp(database.error, "pending") == 0);
  check_copy(body, key);
  puts("successful close retires only C storage: PASS");

  assert(actql_native_sqlite_close_checked(&database) == 1);
  assert(storage_frees == 2 && close_calls == 2);
  actql_clear_result(&database);
  assert(storage_frees == 2 && database.error == NULL);
  check_copy(body, key);
  moonbit_decref(body);
  moonbit_decref(key);
  puts("duplicate close and later clear do not double free: PASS");

  database.database = (sqlite3 *)&database;
  database.opened = true;
  install_storage(&database);
  close_code = SQLITE_BUSY;
  actql_native_sqlite_close_database(&database);
  assert(database.opened && storage_frees == 0);
  assert(!fixture_storage_empty(&database));
  puts("ordinary failed close keeps storage: PASS");
  close_code = SQLITE_OK;
  actql_native_sqlite_close_database(&database);
  assert(!database.opened && storage_frees == 2);
  assert(fixture_storage_empty(&database));
  actql_native_sqlite_close_database(&database);
  assert(storage_frees == 2 && close_calls == 4);
  puts("ordinary success and duplicate close retire once: PASS");
  return 0;
}
