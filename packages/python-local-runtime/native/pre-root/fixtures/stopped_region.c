/* Physical leaf conformance only. This fixture does not issue the Native
 * process Owner's opaque stop proof or establish handler/Wasmtime acceptance. */
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>

static void *failed_mapping;
static int fail_unmap;
static int fixture_munmap(void *address, size_t length) {
    if (address == failed_mapping && fail_unmap) {
        fail_unmap = 0;
        errno = EIO;
        return -1;
    }
    return munmap(address, length);
}
#define munmap fixture_munmap
#include "../owned_capacity.c"
#undef munmap

static int cases;
static void check(int condition, const char *name) {
    if (!condition) { fprintf(stderr, "stopped-region failure: %s\n", name); exit(1); }
    printf("case:%d:%s\n", ++cases, name);
}

int main(void) {
    long selected_page = sysconf(_SC_PAGESIZE); assert(selected_page > 0);
    size_t page = (size_t)selected_page, bytes = 64 * page;
    char path[] = "/tmp/actql-stopped-region-XXXXXX";
    int fd = mkstemp(path);
    assert(fd >= 0 && unlink(path) == 0 && fchmod(fd, 0600) == 0 &&
           ftruncate(fd, (off_t)bytes) == 0);
    unsigned char recipe[32] = {41};
    actql_owned_capacity *root = NULL, *domain = NULL;
    void *allocation = NULL;
    actql_owned_extent_loan loan = {0};
    actql_owned_extent_reference reference = {0};
    actql_owned_extent_view view = {0};
    check(actql_native_owned_acquire_fd(fd, bytes, 1, recipe, &root) == 0 &&
          actql_native_owned_transfer(root, 1, recipe) == 0 &&
          actql_native_owned_enter(root) == 0 &&
          actql_native_owned_allocate(root, 48 * page, 1, &allocation) == 0 &&
          actql_native_owned_lend_extent(root, allocation, true, &loan) == 0 &&
          actql_native_owned_project_extent(&loan, &reference) == 0 &&
          actql_native_owned_leave(root) == 0, "one original 64-page backing and exclusive loan");
    check(actql_native_owned_map_extent_payload(fd, &reference, page, 32 * page, &view) == 0 &&
          actql_native_owned_acquire_extent_domain(&view, &domain) == 0 &&
          actql_native_owned_transfer(domain, 1, recipe) == 0,
          "same original domain, without a second reserve");
    actql_owned_capacity *original_domain = domain;
    check(actql_native_owned_domain_unborrowed(domain, &view) == 0,
          "physical pre-start observation does not issue launch permission");
    check(actql_native_owned_unmap_stopped_child_domain(&view, &domain) == ACTQL_OWNED_INVALID &&
          domain == original_domain && view.mapping != NULL,
          "never-borrowed domain is not stopped-child retirement");
    int ready[2], finish[2]; assert(pipe(ready) == 0 && pipe(finish) == 0);
    pid_t child = fork(); assert(child >= 0);
    if (child == 0) {
        assert(close(ready[0]) == 0 && close(finish[1]) == 0);
        assert(munmap(view.mapping, view.length) == 0 && munmap(root, bytes) == 0);
        actql_owned_extent_view child_view = {0};
        actql_owned_capacity *borrow = NULL;
        void *retained = NULL;
        assert(actql_native_owned_map_extent_payload(fd, &reference, page, 32 * page, &child_view) == 0 &&
               actql_native_owned_borrow_extent_domain(&child_view, &borrow) == 0 &&
               actql_native_owned_enter(borrow) == 0 &&
               actql_native_owned_allocate(borrow, 64, 1, &retained) == 0 &&
               actql_native_owned_leave(borrow) == 0);
        /* Retain a real physical allocation; the Rust-specific 64-byte origin
         * is tested separately with the unchanged real handler fixture. */
        assert(actql_native_owned_return_extent_domain_borrow(&child_view, &borrow) == ACTQL_OWNED_BUSY);
        assert(borrow != NULL && child_view.domain_live);
        char value = 'R'; assert(write(ready[1], &value, 1) == 1);
        assert(read(finish[0], &value, 1) == 1 && value == 'F');
        assert(close(fd) == 0 && close(ready[1]) == 0 && close(finish[0]) == 0);
        _exit(0);
    }
    assert(close(ready[1]) == 0 && close(finish[0]) == 0);
    char value = 0; assert(read(ready[0], &value, 1) == 1 && value == 'R');
    check(actql_native_owned_domain_unborrowed(domain, &view) == ACTQL_OWNED_BUSY,
          "original borrow prevents another pre-start observation");
    check(actql_native_owned_close_extent_domain(&view, &domain) == ACTQL_OWNED_BUSY &&
          domain == original_domain && !loan.returned,
          "ordinary domain close refuses the live original borrower");
    assert(write(finish[1], "F", 1) == 1);
    int status = 0;
    assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    check(atomic_load(&domain->domain_borrower_pid) == child &&
          actql_native_owned_close_extent_domain(&view, &domain) == ACTQL_OWNED_BUSY &&
          domain == original_domain && view.domain_live && !loan.returned,
          "observed process exit does not clear borrower or weaken ordinary close");
    actql_owned_extent_view copied = view;
    check(actql_native_owned_unmap_stopped_child_domain(&copied, &domain) == ACTQL_OWNED_INVALID &&
          domain == original_domain && view.mapping != NULL,
          "copied view cannot retire original mapping");
    actql_owned_capacity *foreign = root;
    check(actql_native_owned_unmap_stopped_child_domain(&view, &foreign) == ACTQL_OWNED_INVALID &&
          foreign == root && domain == original_domain && view.domain_live,
          "foreign lease preserves both originals");
    bool writable = view.extent.writable;
    view.extent.writable = false;
    check(actql_native_owned_unmap_stopped_child_domain(&view, &domain) == ACTQL_OWNED_INVALID &&
          domain == original_domain, "nonexclusive material is refused");
    view.extent.writable = writable;
    failed_mapping = view.mapping; fail_unmap = 1;
    check(actql_native_owned_unmap_stopped_child_domain(&view, &domain) == ACTQL_OWNED_PHYSICAL_FAILURE &&
          domain == original_domain && view.mapping == failed_mapping && view.domain_live &&
          !loan.returned && atomic_load(&domain->domain_borrower_pid) == child,
          "failed physical unmap preserves original mapping lease and borrower");
    /* The physical call below is not a Native scoped-stop acceptance. Its
     * trusted-caller requirement is exercised at that actual Owner separately. */
    check(actql_native_owned_unmap_stopped_child_domain(&view, &domain) == 0 &&
          domain == NULL && view.mapping == NULL && !view.domain_live && !loan.returned,
          "physical unmap clears only its exact mapping and local slot");
    actql_owned_capacity *retained_header = (void *)((unsigned char *)allocation + page);
    check(atomic_load(&retained_header->domain_borrower_pid) == child &&
          retained_header->domain_borrow_attempted,
          "physical unmap neither resets original header nor publishes normal borrow return");
    check(close(fd) == 0 && close(ready[0]) == 0 && close(finish[1]) == 0 &&
          actql_native_owned_return_extent(&loan) == 0 &&
          actql_native_owned_enter(root) == 0 &&
          actql_native_owned_retire(root, allocation) == 0 &&
          actql_native_owned_leave(root) == 0 && actql_native_owned_try_close(&root) == 0 && root == NULL,
          "separate descriptor loan allocation and original root cleanup");
    printf("{\"discovered\":14,\"executed\":%d,\"passed\":%d,\"failed\":0,"
           "\"fixture_pages\":64,\"Native_stop_proof\":false,\"Rust\":0,\"VM\":0}\n", cases, cases);
    return cases == 14 ? 0 : 1;
}
