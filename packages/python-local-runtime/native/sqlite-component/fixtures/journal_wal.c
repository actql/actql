/* Actual selected SQLite component and the original Native Journal adapter.
 * Private component evidence only: no installed command or funding issuer. */
#define _DARWIN_C_SOURCE
#define _XOPEN_SOURCE 700
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "owned_capacity.h"
#include "owned_region.h"
#include "scoped_read.h"
#include "../../../../../src/platform_native/sqlite/sqlite_stub.c"
#include "../../../../../src/platform_native/remote_journal/inspection_stub.c"

static const unsigned char recipe[32] = {17};

static void close_database(actql_native_sqlite_database *database) {
    assert(actql_native_sqlite_close_checked(database) == 1);
    moonbit_decref(database);
}

static void read_original(actql_native_sqlite_database *database) {
    assert(actql_native_sqlite_database_read(database,
        (moonbit_bytes_t)"ns", 2, (moonbit_bytes_t)"key", 3) == 0);
    assert(database->result_revision == 0 && database->result_body_length == 8);
    assert(memcmp(database->result_body, "original", 8) == 0);
}

int main(int argc, char **argv) {
    assert(argc == 4);
    const char *name = argv[1], *component = argv[2], *directory = argv[3];
    assert(strcmp(name, "wal-copy") == 0 || strcmp(name, "missing-index") == 0 ||
        strcmp(name, "exclusive-conflict") == 0 ||
        strcmp(name, "command-record-bounds") == 0 ||
        strcmp(name, "domain-facility-exhaustion") == 0 ||
        strcmp(name, "finite-facility-exhaustion") == 0);
    const bool facility_exhaustion = strcmp(name, "finite-facility-exhaustion") == 0;
    const bool domain_exhaustion = strcmp(name, "domain-facility-exhaustion") == 0;
    const bool command_bounds = strcmp(name, "command-record-bounds") == 0;
    /* A predeclared component-only capacity candidate, not an installed entry
     * profile. Exercise the normal command's original 8-row/131072-byte inputs;
     * no small conformance heap is promoted into ordinary capacity. */
    const size_t heap_bytes = command_bounds ? 8 * 1024 * 1024
        : 32 * (size_t)sysconf(_SC_PAGESIZE);
    const size_t domain_bytes = command_bounds ? 16 * 1024 * 1024
        : 64 * (size_t)sysconf(_SC_PAGESIZE);
    assert(mkdir(directory, 0700) == 0);
    char path[4096];
    assert(snprintf(path, sizeof(path), "%s/original%%?#.sqlite3", directory) > 0);
    int fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0600);
    struct stat owned;
    assert(fd >= 0 && fstat(fd, &owned) == 0 && owned.st_size == 0);
    assert(close(fd) == 0);

    actql_owned_capacity *lease = NULL;
    actql_owned_capacity *parent = NULL;
    actql_owned_extent_loan loan = {0};
    actql_owned_extent_reference reference = {0};
    actql_owned_extent_view view = {0};
    void *parent_allocation = NULL;
    int backing_fd = -1;
    char backing_path[4096];
    void *escaped_file = NULL;
    actql_read_context *context = NULL;
    if (domain_exhaustion) {
        const size_t page = (size_t)sysconf(_SC_PAGESIZE);
        assert(snprintf(backing_path, sizeof(backing_path), "%s/domain-backing", directory) > 0);
        backing_fd = open(backing_path, O_RDWR | O_CREAT | O_EXCL, 0600);
        assert(backing_fd >= 0 && ftruncate(backing_fd, (off_t)(128 * page)) == 0);
        assert(actql_native_owned_acquire_fd(backing_fd, 128 * page, 1, recipe, &parent) == 0);
        assert(actql_native_owned_transfer(parent, 1, recipe) == 0);
        assert(actql_native_owned_enter(parent) == 0);
        assert(actql_native_owned_allocate(parent, 80 * page, 1, &parent_allocation) == 0);
        assert(actql_native_owned_lend_extent(parent, parent_allocation, true, &loan) == 0);
        assert(actql_native_owned_project_extent(&loan, &reference) == 0);
        assert(actql_native_owned_map_extent_payload(backing_fd, &reference, page, domain_bytes, &view) == 0);
        assert(actql_native_owned_acquire_extent_domain(&view, &lease) == 0);
        assert(actql_native_owned_leave(parent) == 0);
    } else {
        assert(actql_native_owned_acquire(domain_bytes, 1, recipe, &lease) == 0);
    }
    assert(actql_native_owned_transfer(lease, 1, recipe) == 0);
    assert(actql_native_owned_enter(lease) == 0);
    /* One diagnostic whole-domain ceiling before its first context/receiver.
     * It includes controls, managed slabs and the separate contained heap;
     * it is not residual demand, another backing or an ordinary profile. */
    const size_t domain_ceiling = 48 * (size_t)sysconf(_SC_PAGESIZE);
    if (domain_exhaustion)
        assert(actql_native_owned_bound_allocations(lease, domain_ceiling) == 0);
    assert(actql_read_context_create(lease, &context) == 0);
    assert(actql_read_context_retain(context) == 0);
    assert(actql_read_context_enter(context) == 0);
    actql_native_sqlite_library *library = actql_native_sqlite_load_current_component(
        (moonbit_bytes_t)component, (int32_t)strlen(component), 128,
        (int64_t)heap_bytes);
    assert(library && actql_native_sqlite_library_ready(library));
    actql_native_sqlite_database *writer = actql_native_sqlite_initialize_owned_journal_database(
        library, (moonbit_bytes_t)path, (int32_t)strlen(path),
        owned.st_dev, owned.st_ino, command_bounds ? 131072 : 65536);
    fprintf(stderr, "selected writer ready=%d error=%s\n",
        actql_native_sqlite_database_ready(writer), writer->error ? writer->error : "<none>");
    assert(actql_native_sqlite_database_ready(writer));
    assert(actql_original_journal_wal_port(library,
        "actql_sqlite_component_heap_wal")(writer->database) == 0);
    if (!command_bounds) assert(actql_native_sqlite_database_insert(writer,
        (moonbit_bytes_t)"ns", 2, (moonbit_bytes_t)"key", 3,
        (moonbit_bytes_t)"original", 8) == 0);

    if (domain_exhaustion) {
        const actql_sqlite_component_api *original_api = library->selected_api;
        sqlite3 *original_database = writer->database;
        void *original_module = library->dynamic_library;
        uint64_t before[16] = {0};
        assert(actql_native_owned_inventory(lease, before, 16) == 0);
        assert(before[0] == domain_bytes && before[3] <= domain_ceiling);
        assert(before[4] <= domain_ceiling && before[3] >= heap_bytes);
        /* Fill only SAME-domain File extents after the real managed Library/
         * Database and private heap exist. Exhaustion must not use the unused
         * tail of the larger mapping or fall through to stock allocation. */
        void *held[64] = {0};
        size_t count = 0;
        const size_t requests[] = {(size_t)sysconf(_SC_PAGESIZE), 16};
        for (size_t kind = 0; kind < sizeof(requests)/sizeof(requests[0]); ++kind) {
            while (count < 64) {
                void *block = actql_native_file_scoped_allocate(requests[kind]);
                if (!block) break;
                held[count++] = block;
            }
            assert(count < 64);
        }
        assert(count > 0 && count < 64);
        assert(actql_native_file_scoped_allocate(16) == NULL);
        uint64_t full[16] = {0};
        assert(actql_native_owned_inventory(lease, full, 16) == 0);
        assert(full[3] == domain_ceiling && full[4] == domain_ceiling);
        assert(full[0] > full[3]); /* The original mapping was not resized. */
        assert(library->selected_api == original_api && library->dynamic_library == original_module);
        assert(writer->database == original_database && writer->opened);
        assert(actql_native_owned_bound_allocations(lease, domain_bytes) != 0);
        /* Child cleanup cannot acknowledge this independently retained File
         * payload. Releasing it permits only same-ceiling reuse, not refill or
         * a new DB/library/claim after exhaustion. */
        assert(actql_read_context_try_close(&context) != 0 && context != NULL);
        escaped_file = held[0];
        memset(escaped_file, 0xa5, 16);
        for (size_t i = 1; i < count; ++i) actql_native_file_scoped_free(held[i]);
        uint64_t released[16] = {0};
        assert(actql_native_owned_inventory(lease, released, 16) == 0);
        assert(released[3] > before[3] && released[3] < full[3]);
        assert(released[4] == domain_ceiling);
        assert(actql_native_owned_contains_live_span(lease, escaped_file, 16) == 0);
        assert(library->selected_api == original_api && writer->database == original_database);
        /* No read retry, inspection, replacement or reopen follows. */
    } else if (facility_exhaustion) {
        /* The diagnostic's declared finite facility may refuse. This is not
         * an all-input demand bound or a command profile. Every held block is
         * issued by this SAME component API and freed through that API. */
        const actql_sqlite_component_api *original_api = library->selected_api;
        sqlite3 *original_database = writer->database;
        void *original_module = library->dynamic_library;
        void *held[1024] = {0};
        size_t held_count = 0;
        const size_t requests[] = {8192, 1024, 128, 16};
        for (size_t kind = 0; kind < sizeof(requests) / sizeof(requests[0]); kind++) {
            while (held_count < 1024) {
                void *block = original_api->allocate_memory(requests[kind]);
                if (block == NULL) break;
                held[held_count++] = block;
            }
            assert(held_count < 1024);
        }
        assert(held_count > 0 && original_api->allocate_memory(16) == NULL);
        sqlite3_stmt *statement = NULL;
        assert(original_api->prepare_v2(original_database,
            "SELECT body FROM actql_records WHERE namespace='ns'",
            -1, &statement, NULL) == SQLITE_NOMEM);
        assert(statement == NULL);
        assert(actql_native_sqlite_database_read(writer,
            (moonbit_bytes_t)"ns", 2, (moonbit_bytes_t)"key", 3) == -1);
        assert(writer->database == original_database && writer->opened);
        assert(library->selected_api == original_api &&
            library->dynamic_library == original_module && library->database_children == 1);
        assert(library->component_close() == ACTQL_SQLITE_COMPONENT_BUSY);
        for (size_t i = 0; i < held_count; i++) original_api->free_memory(held[i]);
        /* No retry of the failed read, replacement heap, reopen or new bind.
         * Only the original DB/Library and separate parent cleanup follow. */
    } else if (command_bounds) {
        /* Both supplied bytes are original entered-Read allocations. The
         * adapter's own key/body copies live inside the SAME MEMSYS5 heap. */
        moonbit_bytes_t body = moonbit_make_bytes_raw(131072);
        moonbit_bytes_t key = moonbit_make_bytes_raw(512);
        memset(key, 'k', 512);
        for (int row = 0; row < 8; row++) {
            key[511] = (unsigned char)('0' + row);
            memset(body, 'A' + row, 131072);
            assert(actql_native_sqlite_database_insert(writer,
                (moonbit_bytes_t)"bounded", 7, key, 512, body, 131072) == 0);
        }
        actql_journal_inspection *snapshot = inspection_open_bounded(
            (moonbit_bytes_t)path, (int32_t)strlen(path), 8 * 1024 * 1024);
        assert(snapshot && snapshot->ready && snapshot->count == 2);
        assert(actql_journal_inspection_prepare_private_index(snapshot));
        actql_native_sqlite_database *copy = actql_native_sqlite_open_journal_inspection_database(
            library, (moonbit_bytes_t)snapshot->copy,
            (int32_t)strlen(snapshot->copy), 131072);
        assert(copy && copy->opened && actql_native_sqlite_inspection_schema(copy));
        assert(copy->journal_inspection_observer(copy->database) == 0);
        assert(actql_native_sqlite_database_scan_after_with_body_limit(copy,
            (moonbit_bytes_t)"bounded", 7, key, 0, 131071) == 4);
        assert(copy->result_key == NULL && copy->result_body == NULL);
        for (int row = 0; row < 8; row++) {
            assert(actql_native_sqlite_database_scan_after_with_body_limit(copy,
                (moonbit_bytes_t)"bounded", 7, key, row == 0 ? 0 : 512, 131072) == 0);
            assert(copy->result_key_length == 512);
            assert(copy->result_key[511] == (unsigned char)('0' + row));
            memcpy(key, copy->result_key, 512);
            assert(copy->result_revision == 0 && copy->result_body_length == 131072);
            for (size_t index = 0; index < 131072; index++)
                assert(copy->result_body[index] == (unsigned char)('A' + row));
        }
        assert(actql_native_sqlite_database_scan_after_with_body_limit(copy,
            (moonbit_bytes_t)"bounded", 7, key, 512, 131072) == 1);
        assert(actql_journal_inspection_validate(snapshot));
        close_database(copy);
        assert(inspection_close(snapshot));
        assert(actql_original_journal_wal_port(library,
            "actql_sqlite_component_descriptor_ack")(NULL) == 0);
        moonbit_decref(snapshot);
        moonbit_decref(key);
        moonbit_decref(body);
    } else if (strcmp(name, "exclusive-conflict") == 0) {
        actql_native_sqlite_database *second = actql_native_sqlite_open_existing_journal_database(
            library, (moonbit_bytes_t)path, (int32_t)strlen(path), 65536);
        assert(second && !actql_native_sqlite_database_ready(second));
        close_database(second);
        read_original(writer);
    } else {
        actql_journal_inspection *snapshot = inspection_open_bounded(
            (moonbit_bytes_t)path, (int32_t)strlen(path), 8 * 1024 * 1024);
        assert(snapshot && snapshot->ready && snapshot->count == 2);
        if (strcmp(name, "wal-copy") == 0) {
            assert(actql_journal_inspection_prepare_private_index(snapshot));
            assert(actql_journal_inspection_private_index_ready(snapshot));
        }
        fprintf(stderr, "original inspection copy=%s\n", snapshot->copy);
        actql_native_sqlite_database *copy = actql_native_sqlite_open_journal_inspection_database(
            library, (moonbit_bytes_t)snapshot->copy, (int32_t)strlen(snapshot->copy), 65536);
        assert(copy != NULL);
        if (strcmp(name, "wal-copy") == 0) {
            fprintf(stderr, "selected copy ready=%d error=%s\n", copy->opened,
                copy->error ? copy->error : "<none>");
            assert(copy->opened && actql_native_sqlite_inspection_schema(copy));
            assert(copy->journal_inspection_observer(copy->database) == 0);
            read_original(copy); /* The committed row is still in copied WAL. */
            assert(library->exec(copy->database,
                "DELETE FROM actql_records", NULL, NULL, NULL) == SQLITE_READONLY);
            assert(actql_journal_inspection_validate(snapshot));
            assert(actql_journal_inspection_private_index_ready(snapshot));
        } else {
            assert(!copy->opened && copy->database == NULL);
        }
        close_database(copy);
        assert(inspection_close(snapshot));
        assert(actql_original_journal_wal_port(library,
            "actql_sqlite_component_descriptor_ack")(NULL) == 0);
        moonbit_decref(snapshot);
    }
    close_database(writer);
    if (!facility_exhaustion && !domain_exhaustion) {
        /* Generic restoration remains the generic route and sees the same row. */
        actql_native_sqlite_database *generic = actql_native_sqlite_open_existing_database(
            library, (moonbit_bytes_t)path, (int32_t)strlen(path),
            command_bounds ? 131072 : 65536);
        assert(generic && actql_native_sqlite_database_ready(generic));
        assert(generic->journal_descriptor_ack == NULL);
        if (command_bounds) {
            unsigned char key[512]; memset(key, 'k', sizeof(key)); key[511] = '0';
            assert(actql_native_sqlite_database_read(generic,
                (moonbit_bytes_t)"bounded", 7, key, sizeof(key)) == 0);
            assert(generic->result_body_length == 131072 && generic->result_body[0] == 'A');
        } else read_original(generic);
        close_database(generic);
    }
    assert(actql_native_sqlite_library_close_checked(library) == 1);
    moonbit_decref(library);
    if (domain_exhaustion) {
        /* The actual child Library/module has acknowledged retirement, but
         * the SAME domain still owns this independent File alias. */
        assert(escaped_file != NULL);
        assert(actql_native_owned_contains_live_span(lease, escaped_file, 16) == 0);
        for (size_t i = 0; i < 16; ++i) assert(((unsigned char *)escaped_file)[i] == 0xa5);
    }
    assert(actql_read_context_leave(context) == 0);
    assert(actql_native_owned_leave(lease) == 0);
    assert(actql_read_context_release_after_owner_ack(context) == 0);
    if (domain_exhaustion) {
        assert(actql_read_context_try_close(&context) == ACTQL_OWNED_BUSY && context != NULL);
        assert(actql_native_owned_close_extent_view(&view) == ACTQL_OWNED_BUSY);
        /* Free through the original provider AFTER scope leave, without
         * reopening Read or invoking any function from the closed component. */
        actql_native_file_scoped_free(escaped_file);
        escaped_file = NULL;
    }
    assert(actql_read_context_try_close(&context) == 0);
    if (domain_exhaustion) {
        assert(actql_native_owned_close_extent_view(&view) == ACTQL_OWNED_BUSY);
        assert(actql_native_owned_close_extent_domain(&view, &lease) == 0 && lease == NULL);
        assert(actql_native_owned_close_extent_view(&view) == 0);
        assert(actql_native_owned_return_extent(&loan) == 0);
        assert(actql_native_owned_enter(parent) == 0);
        assert(actql_native_owned_retire(parent, parent_allocation) == 0);
        assert(actql_native_owned_leave(parent) == 0);
        assert(actql_native_owned_try_close(&parent) == 0 && parent == NULL);
        assert(close(backing_fd) == 0 && unlink(backing_path) == 0);
    } else {
        assert(actql_native_owned_try_close(&lease) == 0);
    }
    printf("{\"case\":\"%s\",\"passed\":true,\"originalsClosed\":true,"
        "\"domainPages\":%zu,\"heapPages\":%zu,\"installed\":false}\n",
        name, domain_bytes / (size_t)sysconf(_SC_PAGESIZE),
        heap_bytes / (size_t)sysconf(_SC_PAGESIZE));
    return 0;
}
