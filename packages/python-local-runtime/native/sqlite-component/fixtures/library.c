/* Actual selected component + original Native adapter, with one retained
 * physical provider. No Host/Run admission or installed product is exercised. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "owned_capacity.h"
#include "scoped_read.h"
#include <unistd.h>
#include "retirement_fault.h"
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
static actql_native_sqlite_database *database(actql_native_sqlite_library *library) {
    actql_native_sqlite_database *db = actql_native_sqlite_open_database(
        library, (moonbit_bytes_t)":memory:", 8, 65536);
    fprintf(stderr, "Native journal initialization: ready=%d error=%s\n",
        actql_native_sqlite_database_ready(db), db && db->error ? db->error : "<omitted>");
    assert(db && actql_native_sqlite_database_ready(db));
    return db;
}
static void close_database(actql_native_sqlite_database *db) {
    assert(actql_native_sqlite_close_checked(db) == 1);
    moonbit_decref(db);
}
static int (*original_exec)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **);
static unsigned commits;
static int observed_exec(sqlite3 *db, const char *sql,
    int (*callback)(void *, int, char **, char **), void *context, char **error) {
    if (!strcmp(sql, "COMMIT")) commits++;
    return original_exec(db, sql, callback, context, error);
}

int main(int argc, char **argv) {
    assert(argc == 3);
    const char *name = argv[1], *path = argv[2];
    original value = fresh();
    assert(!actql_native_sqlite_selected_current_scope());
    assert(!actql_native_sqlite_library_acquired(NULL));
    if (!strcmp(name, "missing-current")) {
        assert(actql_native_sqlite_load_current_component((moonbit_bytes_t)path,
            (int32_t)strlen(path), 128, 32 * (int64_t)sysconf(_SC_PAGESIZE)) == NULL);
    }
    enter(value);
    assert(actql_native_sqlite_selected_current_scope());
    if (!strcmp(name, "missing-component")) {
        const char *missing = "/actql/no-selected-component/library.dylib";
        actql_native_sqlite_library *partial = actql_native_sqlite_load_current_component(
            (moonbit_bytes_t)missing, (int32_t)strlen(missing), 128,
            32 * (int64_t)sysconf(_SC_PAGESIZE));
        assert(actql_native_sqlite_library_acquired(partial));
        assert(!actql_native_sqlite_library_ready(partial));
        assert(partial->selected_context == value.context && partial->selected_context_user);
        /* The bounded diagnostic contract permits omission when the platform
         * loader detail exceeds the original ceiling. Custody cannot depend
         * on that optional detail being allocated or publicly available. */
        assert(partial->dynamic_library == NULL);
        assert(partial->error == NULL || strlen(partial->error) <= 128);
        assert(actql_native_sqlite_library_close_checked(partial) == 1);
        assert(actql_native_sqlite_library_close_checked(partial) == 1);
        moonbit_decref(partial);
        leave(value); finish(&value);
        goto passed;
    }
    actql_native_sqlite_library *library = actql_native_sqlite_load_current_component(
        (moonbit_bytes_t)path, (int32_t)strlen(path), 128, 32 * (int64_t)sysconf(_SC_PAGESIZE));
    assert(actql_native_sqlite_library_acquired(library) && actql_native_sqlite_library_ready(library));
    assert(library->selected_context == value.context && library->component_owned);
    assert(actql_native_owned_contains_live_span(value.lease, library, sizeof(*library)) == 0);

    if (!strcmp(name, "missing-current")) {
        assert(library->database_children == 0);
    } else if (!strcmp(name, "buffer-alias")) {
        actql_replace_error_for(library, &library->error, 128, "original e\xcc\x81\r\n!");
        assert(library->error && actql_native_owned_contains_live_span(value.lease,
            library->error, strlen(library->error) + 1) == 0);
        moonbit_bytes_t bytes = actql_native_sqlite_library_error(library);
        moonbit_incref(bytes);
        assert(actql_native_owned_contains_live_span(value.lease, bytes,
            (size_t)Moonbit_array_length(bytes)) == 0);
        assert(library->component_close() == ACTQL_SQLITE_COMPONENT_BUSY);
        assert(actql_native_sqlite_library_close_checked(library) == 1);
        moonbit_decref(library);
        leave(value);
        assert(actql_read_context_release_after_owner_ack(value.context) == 0);
        assert(actql_read_context_try_close(&value.context) == ACTQL_OWNED_BUSY);
        assert(memcmp(bytes, "original e\xcc\x81\r\n!", (size_t)Moonbit_array_length(bytes)) == 0);
        moonbit_decref(bytes);
        assert(actql_read_context_try_close(&value.context) == ACTQL_OWNED_BUSY);
        moonbit_decref(bytes);
        assert(actql_read_context_try_close(&value.context) == 0);
        assert(actql_native_owned_try_close(&value.lease) == 0);
        goto passed;
    } else if (!strcmp(name, "retirement-retry")) {
        actql_native_sqlite_database *db = database(library);
        close_database(db);
        actql_fixture_retirement_arm();
        assert(actql_native_sqlite_library_close_checked(library) == 0);
        assert(actql_fixture_retirement_calls() == 1 && library->closing && library->component_owned);
        assert(library->selected_api == NULL && library->selected_context_user);
        assert(library->dynamic_library != NULL && library->module_close_result == 0);
        assert(!actql_native_sqlite_library_ready(library));
        assert(actql_adapter_allocate(library, 1) == NULL);
        assert(actql_native_sqlite_library_close_checked(library) == 1);
        assert(actql_fixture_retirement_calls() == 2 && !library->component_owned &&
            !library->selected_context_user && library->dynamic_library == NULL);
    } else if (!strcmp(name, "partial-open")) {
        actql_native_sqlite_database *db = actql_native_sqlite_open_database(
            library, (moonbit_bytes_t)"/dev/null/actql-no-database", 27, 64);
        assert(db && !actql_native_sqlite_database_ready(db));
        assert(library->database_children == 1);
        assert(actql_native_sqlite_library_close_checked(library) == 0);
        close_database(db);
        assert(library->database_children == 0);
    } else {
        actql_native_sqlite_database *db = database(library);
        assert(library->database_children == 1);
        if (!strcmp(name, "journal-cas")) {
            const unsigned char body[] = {'e', 0xcc, 0x81, '\r', '\n', 0, '!'};
            assert(actql_native_sqlite_database_insert(db, (moonbit_bytes_t)"ns", 2,
                (moonbit_bytes_t)"key", 3, (moonbit_bytes_t)body, sizeof(body)) == 0);
            assert(actql_native_sqlite_database_compare_exchange(db, (moonbit_bytes_t)"ns", 2,
                (moonbit_bytes_t)"key", 3, 5, (moonbit_bytes_t)"wrong", 5) == 2);
            assert(actql_native_sqlite_database_read_with_body_limit(db, (moonbit_bytes_t)"ns", 2,
                (moonbit_bytes_t)"key", 3, 6) == 4);
            assert(actql_native_sqlite_database_read(db, (moonbit_bytes_t)"ns", 2,
                (moonbit_bytes_t)"key", 3) == 0);
            assert(db->result_revision == 0 && db->result_body_length == 7);
            assert(memcmp(db->result_body, body, 7) == 0);
            assert(actql_native_owned_contains_live_span(value.lease, db->result_body, 7) == 0);
            assert(actql_native_sqlite_database_read(db, (moonbit_bytes_t)"other", 5,
                (moonbit_bytes_t)"key", 3) == 1);
        } else if (!strcmp(name, "foreign-current")) {
            leave(value);
            original foreign = fresh(); enter(foreign);
            assert(!actql_native_sqlite_library_current(library));
            assert(actql_native_sqlite_database_read(db, (moonbit_bytes_t)"ns", 2,
                (moonbit_bytes_t)"key", 3) == 5);
            assert(actql_native_sqlite_close_checked(db) == 0);
            assert(actql_native_sqlite_library_close_checked(library) == 0);
            assert(db->database && !library->closing);
            leave(foreign); finish(&foreign); enter(value);
        } else if (!strcmp(name, "statement-close")) {
            sqlite3_stmt *statement = NULL;
            assert(library->prepare_v2(db->database, "SELECT 1 AS n", -1, &statement, NULL) == SQLITE_OK);
            assert(library->step(statement) == SQLITE_ROW);
            assert(library->column_int64(statement, 0) == 1);
            assert(actql_native_sqlite_close_checked(db) == 0);
            assert(db->database && db->opened && !library->closing);
            assert(actql_native_sqlite_library_close_checked(library) == 0);
            assert(library->finalize(statement) == SQLITE_OK);
        } else if (!strcmp(name, "adapter-heap-alias")) {
            /* Distinct adapter buffers are interior to one MEMSYS5 extent, not
             * one additional provider page per request. Keep the original table
             * and DB custody until every buffer is actually returned. */
            void *buffers[64] = {0};
            for (size_t i = 0; i < 64; i++) {
                buffers[i] = actql_adapter_allocate(library, 13);
                assert(buffers[i] != NULL);
                assert(actql_native_owned_contains_live_span(value.lease, buffers[i], 13) == 0);
                memset(buffers[i], 23, 13);
            }
            assert(actql_native_sqlite_library_close_checked(library) == 0);
            for (size_t i = 0; i < 64; i++) {
                assert(((unsigned char *)buffers[i])[12] == 23);
                actql_adapter_free(library, buffers[i]);
            }
        } else if (!strcmp(name, "lost-commit-reply")) {
            original_exec = library->exec; library->exec = observed_exec;
            assert(actql_native_sqlite_database_begin_immediate(db) == 0);
            assert(actql_native_sqlite_database_insert(db, (moonbit_bytes_t)"ns", 2,
                (moonbit_bytes_t)"key", 3, (moonbit_bytes_t)"original", 8) == 0);
            actql_native_sqlite_test_fail_commit_reply(db, 1);
            assert(actql_native_sqlite_database_commit(db) == 4 && commits == 1);
            actql_native_sqlite_database_fence_transactions(db);
            assert(actql_native_sqlite_database_read(db, (moonbit_bytes_t)"ns", 2,
                (moonbit_bytes_t)"key", 3) == 0);
            assert(db->result_revision == 0 && db->result_body_length == 8 &&
                memcmp(db->result_body, "original", 8) == 0);
            assert(actql_native_sqlite_database_transaction_fenced(db) && commits == 1);
        } else assert(!"Undiscovered selected Library case");
        close_database(db);
    }
    assert(actql_native_sqlite_library_close_checked(library) == 1);
    assert(actql_native_sqlite_library_close_checked(library) == 1);
    moonbit_decref(library);
    leave(value); finish(&value);
passed:
    printf("{\"case\":\"%s\",\"pass\":true,\"host_pages\":64,\"Host\":0,\"Run\":0}\n", name);
    return 0;
}
