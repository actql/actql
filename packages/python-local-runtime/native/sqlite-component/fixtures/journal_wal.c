/* Actual selected SQLite component and the original Native Journal adapter.
 * Private component evidence only: no installed command or funding issuer. */
#define _DARWIN_C_SOURCE
#define _XOPEN_SOURCE 700
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "owned_capacity.h"
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
        strcmp(name, "command-record-bounds") == 0);
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
    actql_read_context *context = NULL;
    assert(actql_native_owned_acquire(domain_bytes,
        1, recipe, &lease) == 0);
    assert(actql_native_owned_transfer(lease, 1, recipe) == 0);
    assert(actql_native_owned_enter(lease) == 0);
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

    if (command_bounds) {
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
    assert(actql_native_sqlite_library_close_checked(library) == 1);
    moonbit_decref(library);
    assert(actql_read_context_leave(context) == 0);
    assert(actql_native_owned_leave(lease) == 0);
    assert(actql_read_context_release_after_owner_ack(context) == 0);
    assert(actql_read_context_try_close(&context) == 0);
    assert(actql_native_owned_try_close(&lease) == 0);
    printf("{\"case\":\"%s\",\"passed\":true,\"originalsClosed\":true,"
        "\"domainPages\":%zu,\"heapPages\":%zu,\"installed\":false}\n",
        name, domain_bytes / (size_t)sysconf(_SC_PAGESIZE),
        heap_bytes / (size_t)sysconf(_SC_PAGESIZE));
    return 0;
}
