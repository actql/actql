/* Physical C boundary only. Core admission/current permissions, the installed
 * managed caller and normal funding are not issued by this fixture. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
#include "moonbit_runtime.h"
#include BOOTSTRAP_SOURCE
#include FILESYSTEM_SOURCE
#undef malloc
#undef calloc
#undef free
#undef strdup
typedef struct {
    int fd;
    actql_bootstrap_backing *parent;
    actql_bootstrap_extent *extent;
    actql_bootstrap_region *loan;
    actql_bootstrap_view *view;
    actql_bootstrap_domain *domain;
} fixture;

static const unsigned char recipe[32] = {61};

static fixture open_fixture(void) {
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    char path[] = "/private/tmp/actql-read-bridge-XXXXXX";
    fixture f = {0};
    f.fd = mkstemp(path);
    assert(f.fd >= 0 && unlink(path) == 0 && fchmod(f.fd, 0600) == 0);
    assert(ftruncate(f.fd, (off_t)(64 * page)) == 0);
    f.parent = actql_bootstrap_acquire_fd(f.fd, (int64_t)(64 * page), 1, recipe);
    assert(actql_bootstrap_status(f.parent) == 0);
    assert(actql_bootstrap_claim(f.parent, 1, recipe) == 0);
    assert(actql_bootstrap_enter_scope(f.parent) == 0);
    f.extent = actql_bootstrap_allocate(f.parent, (int64_t)(24 * page));
    assert(actql_bootstrap_extent_status(f.extent) == 0);
    f.loan = actql_bootstrap_lend_region(f.parent, f.extent, 0,
                                       (int64_t)(24 * page), 1);
    assert(actql_bootstrap_region_status(f.loan) == 0);
    assert(actql_bootstrap_leave_scope(f.parent) == 0);
    f.view = actql_bootstrap_map_region(f.parent, f.extent, f.loan, f.fd,
                                       (int64_t)page, (int64_t)(16 * page));
    assert(actql_bootstrap_view_status(f.view) == 0);
    f.domain = actql_bootstrap_acquire_domain(f.view);
    assert(actql_bootstrap_domain_status(f.domain) == 0);
    assert(actql_bootstrap_transfer_domain(f.domain) == 0);
    return f;
}

static void close_fixture(fixture *f) {
    assert(actql_bootstrap_close_read_context(f->domain) == 0);
    assert(actql_bootstrap_close_domain(f->view, f->domain) == 0);
    assert(actql_bootstrap_close_region_view(f->parent, f->extent, f->loan, f->view) == 0);
    assert(actql_bootstrap_return_region(f->parent, f->extent, f->loan) == 0);
    assert(actql_bootstrap_retire(f->parent, f->extent) == 0);
    assert(actql_bootstrap_close(f->parent) == 0);
    assert(close(f->fd) == 0);
    f->fd = -1;
    moonbit_decref(f->domain);
    moonbit_decref(f->view);
    moonbit_decref(f->loan);
    moonbit_decref(f->extent);
    moonbit_decref(f->parent);
}


static void current_missing(void) {
    actql_native_filesystem_root *root = NULL;
    assert(actql_bootstrap_current_read_context() == NULL);
    assert(actql_native_filesystem_scoped_open_current_root(
        (moonbit_bytes_t)"/not-acquired", 13, 16, &root) == ACTQL_OWNED_INVALID);
    assert(root == NULL);
}

static moonbit_bytes_t encoded_path(const char *path) {
    size_t length = strlen(path);
    assert(length < INT32_MAX);
    moonbit_bytes_t bytes = moonbit_make_bytes((int32_t)length, 0);
    memcpy(bytes, path, length);
    return bytes;
}

static void successful_root_reader(const char *path) {
    fixture f = open_fixture();
    assert(actql_bootstrap_prepare_read_context(f.domain) == 0);
    assert(actql_bootstrap_enter_read_context(f.domain) == 0);
    actql_read_context *original = actql_bootstrap_current_read_context();
    moonbit_bytes_t path_bytes = encoded_path(path);
    actql_native_filesystem_root *root = NULL;
    assert(actql_native_filesystem_scoped_open_current_root(path_bytes,
        (int32_t)strlen(path), 16, &root) == 0);
    moonbit_decref(path_bytes);
    assert(root != NULL && actql_native_filesystem_root_ready(root));
    assert(root->read_context == original && root->read_context_user);
    assert(actql_bootstrap_current_read_context() == original);
    int32_t physical = -100;
    assert(actql_native_filesystem_scoped_inspect_generation(root,
        (moonbit_bytes_t)"value", 5, &physical) == 0 && physical == 0);
    actql_native_filesystem_reader *reader = NULL;
    assert(actql_native_filesystem_scoped_open_reader(root,
        (moonbit_bytes_t)"value", 5, root->result_device, root->result_inode,
        root->result_size, &reader) == 0);
    assert(reader != NULL && reader->read_context == original && reader->ready);
    assert(actql_native_filesystem_scoped_reader_next(reader, 3, &physical) == 0 && physical == 0);
    moonbit_bytes_t alias = NULL;
    assert(actql_native_filesystem_scoped_reader_chunk(reader, &alias) == 0);
    assert(Moonbit_array_length(alias) == 3 && memcmp(alias, "abc", 3) == 0);
    assert(actql_native_filesystem_scoped_reader_close(reader, true, &physical) == 0 && physical == 0);
    assert(actql_native_filesystem_scoped_root_close(root, &physical) == 0 && physical == 0);
    assert(!root->read_context_user && !reader->read_context_user);
    assert(actql_bootstrap_leave_read_context(f.domain) == 0);
    assert(actql_bootstrap_current_read_context() == NULL);
    assert(actql_bootstrap_close_read_context(f.domain) == ACTQL_OWNED_BUSY);
    moonbit_decref(reader);
    moonbit_decref(root);
    assert(actql_bootstrap_close_read_context(f.domain) == ACTQL_OWNED_BUSY);
    assert(memcmp(alias, "abc", 3) == 0);
    moonbit_decref(alias);
    close_fixture(&f);
}

static void failed_original_root(const char *path) {
    fixture f = open_fixture();
    assert(actql_bootstrap_prepare_read_context(f.domain) == 0);
    assert(actql_bootstrap_enter_read_context(f.domain) == 0);
    actql_read_context *original = actql_bootstrap_current_read_context();
    char missing[4096];
    assert(snprintf(missing, sizeof(missing), "%s/later", path) > 0);
    moonbit_bytes_t bytes = encoded_path(missing);
    actql_native_filesystem_root *root = NULL;
    assert(actql_native_filesystem_scoped_open_current_root(bytes,
        (int32_t)strlen(missing), 16, &root) == 0);
    moonbit_decref(bytes);
    assert(root != NULL && !actql_native_filesystem_root_ready(root));
    assert(root->read_context == original && root->read_context_user);
    assert(mkdir(missing, 0700) == 0);
    assert(!actql_native_filesystem_root_ready(root));
    assert(actql_bootstrap_leave_read_context(f.domain) == 0);
    assert(actql_bootstrap_close_read_context(f.domain) == ACTQL_OWNED_BUSY);
    assert(actql_bootstrap_enter_read_context(f.domain) == 0);
    int32_t physical = -100;
    assert(actql_native_filesystem_scoped_root_close(root, &physical) == 0 && physical == 0);
    assert(!root->read_context_user && !actql_native_filesystem_root_ready(root));
    assert(actql_bootstrap_leave_read_context(f.domain) == 0);
    assert(actql_bootstrap_close_read_context(f.domain) == ACTQL_OWNED_BUSY);
    moonbit_decref(root);
    close_fixture(&f);
    assert(rmdir(missing) == 0);
}

int main(int argc, char **argv) {
    assert(argc == 2);
    current_missing(); puts("ACTQL_F_CURRENT_ROOT_CASE no-current PASS");
    successful_root_reader(argv[1]); puts("ACTQL_F_CURRENT_ROOT_CASE original-context-alias PASS");
    failed_original_root(argv[1]); puts("ACTQL_F_CURRENT_ROOT_CASE original-failure-custody PASS");
    return 0;
}
