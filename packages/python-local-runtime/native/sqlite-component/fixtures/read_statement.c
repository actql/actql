/* Actual private selected component, original read allocator and Native
 * adapter. No installed Host, Account grant or normal profile is supplied. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include "owned_capacity.h"
#include "scoped_read.h"
#include "../../../../../src/platform_native/sqlite/sqlite_stub.c"

typedef struct { actql_owned_capacity *lease; actql_read_context *context; } original;
static const unsigned char recipe[32] = {17};
static original fresh(void) {
    original value = {0};
    assert(actql_native_owned_acquire(64 * (size_t)sysconf(_SC_PAGESIZE), 1, recipe, &value.lease) == 0);
    assert(actql_native_owned_transfer(value.lease, 1, recipe) == 0);
    assert(actql_native_owned_enter(value.lease) == 0);
    assert(actql_read_context_create(value.lease, &value.context) == 0);
    assert(actql_read_context_retain(value.context) == 0);
    assert(actql_native_owned_leave(value.lease) == 0);
    return value;
}
static void enter(original value) {
    assert(actql_native_owned_enter(value.lease) == 0);
    assert(actql_read_context_enter(value.context) == 0);
}
static void leave(original value) {
    assert(actql_read_context_leave(value.context) == 0);
    assert(actql_native_owned_leave(value.lease) == 0);
}
static void finish(original *value) {
    assert(actql_read_context_release_after_owner_ack(value->context) == 0);
    assert(actql_read_context_try_close(&value->context) == 0);
    assert(actql_native_owned_try_close(&value->lease) == 0);
}
static actql_sqlite_prepare_v2_fn original_prepare;
static int ordinary_prepares;
static int observed_prepare(sqlite3 *db, const char *sql, int bytes,
    sqlite3_stmt **out, const char **tail) {
    if (!strcmp(sql, "SELECT revision, body FROM actql_records WHERE namespace = ?1 AND record_key = ?2"))
        ordinary_prepares++;
    return original_prepare(db, sql, bytes, out, tail);
}

int main(int argc, char **argv) {
    assert(argc == 2);
    original value = fresh();
    enter(value);
    actql_native_sqlite_library *library = actql_native_sqlite_load_current_component(
        (moonbit_bytes_t)argv[1], (int32_t)strlen(argv[1]), 128,
        32 * (int64_t)sysconf(_SC_PAGESIZE));
    assert(library && actql_native_sqlite_library_ready(library));
    const actql_sqlite_component_api *api = library->selected_api;
    Dl_info image;
    assert(api && api->abi == 3 && api->bytes == sizeof(*api));
    assert(dladdr(api, &image) && actql_component_api_original(api, image.dli_fbase));
    actql_sqlite_component_api wrong = *api;
    wrong.instance = &wrong;
    wrong.abi = 2;
    assert(!actql_component_api_original(&wrong, image.dli_fbase));
    wrong.abi = 3;
    wrong.bytes = offsetof(actql_sqlite_component_api, reset);
    assert(!actql_component_api_original(&wrong, image.dli_fbase));
    wrong.bytes = sizeof(wrong);
    wrong.reset = NULL;
    assert(!actql_component_api_original(&wrong, image.dli_fbase));
    wrong.reset = api->reset;
    wrong.clear_bindings = NULL;
    assert(!actql_component_api_original(&wrong, image.dli_fbase));
    puts("actual selected ABI3 admits original complete ports and rejects ABI2 truncated or missing reset/clear: PASS");

    actql_native_sqlite_database *db = actql_native_sqlite_open_database(
        library, (moonbit_bytes_t)":memory:", 8, 65536);
    assert(db && actql_native_sqlite_database_ready(db));
    assert(actql_native_sqlite_database_insert(db, (moonbit_bytes_t)"first", 5,
        (moonbit_bytes_t)"one", 3, (moonbit_bytes_t)"original", 8) == 0);
    assert(actql_native_sqlite_database_insert(db, (moonbit_bytes_t)"second", 6,
        (moonbit_bytes_t)"two", 3, (moonbit_bytes_t)"different", 9) == 0);
    original_prepare = library->prepare_v2;
    library->prepare_v2 = observed_prepare; /* Count only; invoke SAME original port. */
    assert(actql_native_sqlite_database_read(db, (moonbit_bytes_t)"first", 5,
        (moonbit_bytes_t)"one", 3) == 0);
    assert(db->result_body_length == 8 && !memcmp(db->result_body, "original", 8));
    assert(actql_native_sqlite_database_read(db, (moonbit_bytes_t)"second", 6,
        (moonbit_bytes_t)"two", 3) == 0);
    assert(db->result_body_length == 9 && !memcmp(db->result_body, "different", 9));
    assert(ordinary_prepares == 1 && db->record_read_statement && !db->record_read_in_use);
    leave(value);
    assert(actql_native_sqlite_database_read(db, (moonbit_bytes_t)"first", 5,
        (moonbit_bytes_t)"one", 3) == 5);
    assert(actql_native_sqlite_close_checked(db) == 0);
    original other = fresh();
    enter(other);
    assert(actql_native_sqlite_database_read(db, (moonbit_bytes_t)"first", 5,
        (moonbit_bytes_t)"one", 3) == 5);
    assert(actql_native_sqlite_close_checked(db) == 0 && ordinary_prepares == 1);
    leave(other);
    finish(&other);
    enter(value);
    assert(actql_native_sqlite_database_read(db, (moonbit_bytes_t)"first", 5,
        (moonbit_bytes_t)"one", 3) == 0 && ordinary_prepares == 1);
    db->test_close_failures = 1;
    assert(actql_native_sqlite_close_checked(db) == 0 && db->record_read_statement);
    assert(actql_native_sqlite_close_checked(db) == 1 && db->record_read_statement == NULL);
    moonbit_decref(db);
    assert(library->database_children == 0);
    assert(actql_native_sqlite_library_close_checked(library) == 1);
    moonbit_decref(library);
    leave(value);
    finish(&value);
    puts("actual selected same-Database reuse keeps foreign-current refusal and original child-first close: PASS");
    puts("Selected read statement C cases: 2/2");
    return 0;
}
