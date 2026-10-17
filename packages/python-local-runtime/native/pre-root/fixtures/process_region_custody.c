/* Actual C carrier/descriptor checks, not a Native scoped-stop proof. The
 * pinned stock Moon runtime supplies this fixture's finite external controls;
 * no claim is made that the 64-page arena funds those controls or the VM. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include "../../../../../src/platform_native/host_bootstrap/bootstrap_stub.c"

static int cases;
static void check(int condition, const char *name) {
    if (!condition) { fprintf(stderr, "process carrier failure: %s\n", name); exit(1); }
    printf("case:%d:%s\n", ++cases, name);
}

int main(void) {
    long selected_page = sysconf(_SC_PAGESIZE); assert(selected_page > 0);
    size_t page = (size_t)selected_page, bytes = 64 * page;
    char path[] = "/private/tmp/actql-process-carrier-XXXXXX";
    int descriptor = mkstemp(path);
    assert(descriptor >= 0 && unlink(path) == 0 && fchmod(descriptor, 0600) == 0 &&
           ftruncate(descriptor, (off_t)bytes) == 0);
    unsigned char recipe[32] = {37};
    actql_bootstrap_backing *backing = actql_bootstrap_acquire_fd(descriptor, (int64_t)bytes, 1, recipe);
    check(actql_bootstrap_status(backing) == 0 && actql_bootstrap_claim(backing, 1, recipe) == 0 &&
          actql_bootstrap_enter_scope(backing) == 0, "original selected backing and one transfer");
    actql_bootstrap_extent *extent = actql_bootstrap_allocate(backing, (int64_t)(48 * page));
    actql_bootstrap_region *loan = actql_bootstrap_lend_region(backing, extent, 0, (int64_t)(48 * page), 1);
    actql_bootstrap_view *view = actql_bootstrap_map_region(backing, extent, loan, descriptor,
        (int64_t)page, (int64_t)(32 * page));
    actql_bootstrap_domain *domain = actql_bootstrap_acquire_domain(view);
    check(actql_bootstrap_extent_status(extent) == 0 && actql_bootstrap_region_status(loan) == 0 &&
          actql_bootstrap_view_status(view) == 0 && actql_bootstrap_domain_status(domain) == 0 &&
          actql_bootstrap_transfer_domain(domain) == 0 && actql_bootstrap_leave_scope(backing) == 0,
          "same provider exclusive view and original domain");
    actql_owned_capacity *original = domain->lease;
    void *mapping = view->view.mapping;
    actql_bootstrap_process_region *pending = actql_bootstrap_capture_process_region(view, domain, -1);
    check(actql_bootstrap_process_region_status(pending) == ACTQL_OWNED_INVALID &&
          pending->descriptor == -1 && !pending->closed && domain->lease == original,
          "pre-start descriptor refusal retains original primary result");
    check(actql_bootstrap_abandon_prepared_process_region(pending) == 0 &&
          actql_bootstrap_abandon_prepared_process_region(pending) == 0 && pending->closed &&
          actql_bootstrap_process_region_status(pending) == ACTQL_OWNED_INVALID &&
          domain->lease == original && view->view.mapping == mapping && view->view.domain_live,
          "abandonment closes capture only and never promotes primary refusal");
    actql_bootstrap_process_region *record = actql_bootstrap_capture_process_region(view, domain, descriptor);
    int captured = record->descriptor;
    check(actql_bootstrap_process_region_status(record) == 0 && captured >= 0 && captured != descriptor &&
          fcntl(captured, F_GETFD) >= 0 && domain->lease == original,
          "original capture owns a separate descriptor before startup");
    pid_t child = fork(); assert(child >= 0);
    if (child == 0) _exit(0);
    int status = 0;
    assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    /* This manual physical observation does not exercise or issue the Native
     * opaque proof. That proof must guard this port in the real caller. */
    check(actql_bootstrap_retire_stopped_process_region(record, child) == 0 &&
          record->closed && record->unmapped && record->unborrowed_cleanup &&
          domain->lease == NULL && view->view.mapping == NULL &&
          fcntl(captured, F_GETFD) < 0 && fcntl(descriptor, F_GETFD) >= 0,
          "stopped unborrowed startup follows ordinary domain close and separate FD cleanup");
    check(actql_bootstrap_retire_stopped_process_region(record, child) == 0 &&
          actql_bootstrap_retire_stopped_process_region(record, child + 1) == ACTQL_OWNED_INVALID &&
          !record->close_unknown && fcntl(descriptor, F_GETFD) >= 0,
          "cached original cleanup does not accept a foreign child or repeat FD close");
    check(actql_bootstrap_return_region(backing, extent, loan) == 0 &&
          actql_bootstrap_retire(backing, extent) == 0 && actql_bootstrap_close(backing) == 0 &&
          backing->lease == NULL && close(descriptor) == 0,
          "outer allocation backing and original caller FD retire separately");
    printf("{\"discovered\":8,\"executed\":%d,\"passed\":%d,\"failed\":0,"
           "\"fixture_pages\":64,\"Native_stop_proof\":false,\"Rust\":0,\"VM\":0}\n", cases, cases);
    return cases == 8 ? 0 : 1;
}
