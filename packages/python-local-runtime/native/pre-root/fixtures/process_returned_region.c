/* Physical regression only. This standalone fixture manually observes its own
 * disposable child; it does not issue NativeScopedExecutorStop or fund a VM. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include "../../../../../src/platform_native/host_bootstrap/bootstrap_stub.c"

int main(void) {
    long selected = sysconf(_SC_PAGESIZE); assert(selected > 0);
    size_t page = (size_t)selected;
    char path[] = "/private/tmp/actql-returned-region-XXXXXX";
    int fd = mkstemp(path);
    assert(fd >= 0 && fchmod(fd, 0600) == 0 && ftruncate(fd, (off_t)(64 * page)) == 0);
    printf("original:%s\n", path); fflush(stdout);
    unsigned char recipe[32] = {43};
    actql_bootstrap_backing *backing = actql_bootstrap_acquire_fd(fd, 64 * page, 7, recipe);
    assert(actql_bootstrap_status(backing) == 0 && actql_bootstrap_claim(backing, 7, recipe) == 0 &&
           actql_bootstrap_enter_scope(backing) == 0);
    actql_bootstrap_extent *extent = actql_bootstrap_allocate(backing, 48 * page);
    actql_bootstrap_region *loan = actql_bootstrap_lend_region(backing, extent, 0, 48 * page, 1);
    actql_bootstrap_view *view = actql_bootstrap_map_region(backing, extent, loan, fd, page, 32 * page);
    actql_bootstrap_domain *domain = actql_bootstrap_acquire_domain(view);
    assert(actql_bootstrap_domain_status(domain) == 0 &&
           actql_bootstrap_transfer_domain(domain) == 0 && actql_bootstrap_leave_scope(backing) == 0);
    actql_bootstrap_process_region *record = actql_bootstrap_capture_process_region(view, domain, fd);
    assert(actql_bootstrap_process_region_status(record) == 0);
    int returned[2]; assert(pipe(returned) == 0);
    pid_t child = fork(); assert(child >= 0);
    if (child == 0) {
        close(returned[0]);
        actql_owned_extent_reference reference = view->view.extent;
        assert(munmap(view->view.mapping, view->view.length) == 0 &&
               munmap(backing->lease, 64 * page) == 0);
        actql_owned_extent_view local = {0}; actql_owned_capacity *holding = NULL;
        assert(actql_native_owned_map_extent_payload(fd, &reference, page, 32 * page, &local) == 0 &&
               actql_native_owned_borrow_extent_domain(&local, &holding) == 0 &&
               actql_native_owned_enter(holding) == 0);
        void *value = NULL;
        assert(actql_native_owned_allocate(holding, 24, 1, &value) == 0 &&
               actql_native_owned_retire(holding, value) == 0 &&
               actql_native_owned_leave(holding) == 0 &&
               actql_native_owned_return_extent_domain_borrow(&local, &holding) == 0 &&
               holding == NULL && actql_native_owned_close_extent_view(&local) == 0);
        assert(write(returned[1], "R", 1) == 1 && close(returned[1]) == 0 && close(fd) == 0);
        _exit(0);
    }
    assert(close(returned[1]) == 0);
    char ready = 0; assert(read(returned[0], &ready, 1) == 1 && ready == 'R');
    int status = 0; assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    assert(atomic_load_explicit(&domain->lease->domain_borrower_pid, memory_order_acquire) == 0 &&
           domain->lease->domain_borrow_attempted && domain->lease->closing);
    assert(actql_native_owned_domain_unborrowed(domain->lease, &view->view) == ACTQL_OWNED_BUSY &&
           actql_native_owned_domain_has_child(domain->lease, getpid(), child) == ACTQL_OWNED_INVALID);
    int result = actql_bootstrap_retire_stopped_process_region(record, child);
    printf("{\"discovered\":6,\"executed\":6,\"passed\":%d,\"failed\":%d,"
           "\"retirement_status\":%d,\"child_borrow_returned\":true,"
           "\"parent_cleanup_acknowledged\":%s,\"Native_stop_proof\":false,\"fixture_pages\":64}\n",
           result == 0 ? 6 : 5, result == 0 ? 0 : 1, result, result == 0 ? "true" : "false");
    fflush(stdout);
    if (result != 0) return 1;
    assert(record->closed && record->unmapped && domain->lease == NULL && view->view.mapping == NULL &&
           actql_bootstrap_retire_stopped_process_region(record, child) == 0 &&
           actql_bootstrap_retire_stopped_process_region(record, child + 1) == ACTQL_OWNED_INVALID &&
           actql_bootstrap_return_region(backing, extent, loan) == 0 &&
           actql_bootstrap_retire(backing, extent) == 0 && actql_bootstrap_close(backing) == 0 &&
           close(fd) == 0 && close(returned[0]) == 0);
    return 0;
}
