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

/* Pure validator inputs only: one otherwise-complete table in the SAME
 * actual image as all its marker addresses. Never borrowed, invoked, installed
 * or accepted as a Library. A shape-guard mutation must fail these controls
 * rather than accidentally remain refused by unrelated image provenance. */
static actql_sqlite_component_api shape_probe;
static void shape_probe_entry(void) { }
static void check_shape_controls(void) {
    shape_probe.abi = 3;
    shape_probe.bytes = sizeof(shape_probe);
    shape_probe.instance = &shape_probe;
#define PROBE_PORT(name) shape_probe.name = (__typeof__(shape_probe.name))shape_probe_entry
    PROBE_PORT(allocate_memory); PROBE_PORT(libversion); PROBE_PORT(libversion_number);
    PROBE_PORT(open_v2); PROBE_PORT(close_v2); PROBE_PORT(errmsg); PROBE_PORT(exec);
    PROBE_PORT(free_memory); PROBE_PORT(prepare_v2); PROBE_PORT(bind_text);
    PROBE_PORT(bind_blob); PROBE_PORT(bind_int64); PROBE_PORT(step);
    PROBE_PORT(column_int64); PROBE_PORT(column_blob); PROBE_PORT(column_bytes);
    PROBE_PORT(finalize); PROBE_PORT(changes64); PROBE_PORT(busy_timeout);
    PROBE_PORT(get_autocommit); PROBE_PORT(reset); PROBE_PORT(clear_bindings);
#undef PROBE_PORT
    Dl_info image;
    assert(dladdr(&shape_probe, &image));
    assert(actql_component_api_original(&shape_probe, image.dli_fbase));
    shape_probe.abi = 2;
    assert(!actql_component_api_original(&shape_probe, image.dli_fbase));
    shape_probe.abi = 3;
    shape_probe.bytes = offsetof(actql_sqlite_component_api, reset);
    assert(!actql_component_api_original(&shape_probe, image.dli_fbase));
    shape_probe.bytes = sizeof(shape_probe);
    actql_sqlite_reset_fn reset = shape_probe.reset;
    shape_probe.reset = NULL;
    assert(!actql_component_api_original(&shape_probe, image.dli_fbase));
    shape_probe.reset = reset;
    actql_sqlite_clear_bindings_fn clear = shape_probe.clear_bindings;
    shape_probe.clear_bindings = NULL;
    assert(!actql_component_api_original(&shape_probe, image.dli_fbase));
    shape_probe.clear_bindings = clear;
    assert(actql_component_api_original(&shape_probe, image.dli_fbase));
}

int main(int argc, char **argv) {
    assert(argc == 2 || (argc == 3 && !strcmp(argv[2], "--abi-controls-only")));
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
    check_shape_controls();
    puts("actual selected ABI3 admits original complete ports and rejects ABI2 truncated or missing reset/clear: PASS");
    if (argc == 3) {
        assert(actql_native_sqlite_library_close_checked(library) == 1);
        moonbit_decref(library);
        leave(value);
        finish(&value);
        puts("Selected ABI controls C cases: 1/1");
        return 0;
    }

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
