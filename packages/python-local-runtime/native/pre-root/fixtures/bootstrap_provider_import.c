/* Finite imported-consumer conformance. No provider implementation or private
 * allocator/context layout is compiled here. Native/Core authority is not
 * modeled by these physical counters. Original 64/48 pages stay unchanged. */
#define ACTQL_BOOTSTRAP_IMPORT_PROVIDER 1
#include "../../../../../src/platform_native/host_bootstrap/bootstrap_stub.c"
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>

static int count;
static void require(bool condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL:%s\n", message); exit(2); }
    count++;
    printf("case:%d:%s\n", count, message);
    fflush(stdout);
}

int main(void) {
    long page = sysconf(_SC_PAGE_SIZE);
#if defined(__linux__)
    char path[] = "/tmp/actql-import-provider-XXXXXX";
#else
    char path[] = "/private/tmp/actql-import-provider-XXXXXX";
#endif
    int fd = mkstemp(path);
    if (fd < 0 || page <= 0 || ftruncate(fd, 64 * page) != 0) return 3;
    printf("fixture:%s\n", path); fflush(stdout);
    unsigned char recipe[32]; memset(recipe, 17, sizeof(recipe));
    require(actql_bootstrap_control_scope_clear() == 1 &&
        actql_bootstrap_current_read_context() == NULL,
        "initial raw read and owned scope clear");
    actql_bootstrap_backing *parent = actql_bootstrap_acquire_fd(fd, 64 * page, 1, recipe);
    require(actql_bootstrap_status(parent) == 0 &&
        actql_bootstrap_control_bytes(parent) > 0 &&
        actql_bootstrap_control_bytes(parent) < 64 * page &&
        actql_bootstrap_rounded_bytes(parent, 1) == page &&
        actql_bootstrap_rounded_bytes(parent, 0) == -1 &&
        actql_bootstrap_rounded_bytes(parent, 64 * page + 1) == -1 &&
        actql_native_owned_transfer_original_domain(parent->lease) == ACTQL_OWNED_INVALID &&
        actql_bootstrap_claim(parent, 1, recipe) == 0,
        "opaque control rounding and domain-only original transfer");
    require(actql_bootstrap_enter_scope(parent) == 0 &&
        actql_bootstrap_enter_scope(parent) == 0 &&
        actql_bootstrap_current_read_context() == NULL &&
        actql_bootstrap_control_scope_clear() == 0 &&
        actql_bootstrap_leave_scope(parent) == 0 &&
        actql_bootstrap_control_scope_clear() == 0 &&
        actql_bootstrap_leave_scope(parent) == 0 &&
        actql_bootstrap_control_scope_clear() == 1,
        "one owned leave is not an outer-frame ACK even with NULL valid read pointer");
    int parent_enter = actql_bootstrap_enter_scope(parent);
    actql_bootstrap_extent *extent = actql_bootstrap_allocate(parent, 48 * page);
    actql_bootstrap_region *loan = actql_bootstrap_lend_region(parent, extent, 0, 48 * page, 1);
    int parent_leave = actql_bootstrap_leave_scope(parent);
    actql_bootstrap_view *view = actql_bootstrap_map_region(parent, extent, loan, fd, 0, 48 * page);
    actql_bootstrap_domain *domain = actql_bootstrap_acquire_domain(view);
    printf("domain-status:enter=%d leave=%d extent=%d loan=%d view=%d domain=%d match=%d wrong-parent=%d child=%d\n",
        parent_enter, parent_leave, actql_bootstrap_extent_status(extent),
        actql_bootstrap_region_status(loan),
        actql_bootstrap_view_status(view), actql_bootstrap_domain_status(domain),
        actql_native_owned_domain_matches_view(domain->lease, &view->view, getpid()),
        actql_native_owned_domain_matches_view(parent->lease, &view->view, getpid()),
        actql_native_owned_domain_has_child(domain->lease, getpid(), getpid() + 1));
    fflush(stdout);
    require(parent_enter == 0 && parent_leave == 0 &&
        actql_bootstrap_control_scope_clear() == 1 &&
        actql_bootstrap_extent_status(extent) == 0 &&
        actql_bootstrap_region_status(loan) == 0 && actql_bootstrap_view_status(view) == 0 &&
        actql_bootstrap_domain_status(domain) == 0 &&
        actql_native_owned_domain_matches_view(domain->lease, &view->view, getpid()) == 0 &&
        actql_native_owned_domain_matches_view(parent->lease, &view->view, getpid()) == ACTQL_OWNED_INVALID &&
        actql_native_owned_domain_has_child(domain->lease, getpid(), getpid() + 1) == ACTQL_OWNED_INVALID &&
        actql_bootstrap_transfer_domain(domain) == 0 &&
        actql_bootstrap_transfer_domain(domain) == ACTQL_OWNED_INVALID,
        "same original view matches but wrong parent child or repeated transfer refuses");
    require(actql_bootstrap_prepare_read_context(domain) == 0 &&
        actql_bootstrap_enter_read_context(domain) == 0 &&
        actql_bootstrap_enter_read_context(domain) == 0 &&
        actql_bootstrap_current_read_context() != NULL &&
        actql_bootstrap_control_scope_clear() == 0 &&
        actql_bootstrap_leave_read_context(domain) == 0 &&
        actql_bootstrap_current_read_context() != NULL &&
        actql_bootstrap_control_scope_clear() == 0 &&
        actql_bootstrap_leave_read_context(domain) == 0 &&
        actql_bootstrap_control_scope_clear() == 1,
        "same provider nested read uses raw read and owned depth until final leave");
    pid_t child = fork();
    if (child == 0) _exit(actql_bootstrap_control_scope_clear() == 0 ? 0 : 7);
    int status = -1;
    require(child > 0 && waitpid(child, &status, 0) == child && WIFEXITED(status) &&
        WEXITSTATUS(status) == 0 && actql_bootstrap_control_scope_clear() == 1,
        "foreign fork observes conservative refusal without adopting inherited context");
    require(actql_bootstrap_enter_read_context(domain) == 0,
        "same original read remains usable after foreign observation");
    moonbit_bytes_t bytes = moonbit_make_bytes(16, 73); moonbit_incref(bytes);
    require(actql_bootstrap_leave_read_context(domain) == 0 &&
        actql_bootstrap_close_read_context(domain) == ACTQL_OWNED_BUSY,
        "escaped aliases retain the same original read retirement");
    moonbit_decref(bytes);
    require(actql_bootstrap_close_read_context(domain) == ACTQL_OWNED_BUSY,
        "first alias release is not last alias retirement");
    moonbit_decref(bytes);
    require(actql_bootstrap_close_read_context(domain) == 0 &&
        actql_bootstrap_close_read_context(domain) == 0 &&
        actql_bootstrap_close_domain(view, domain) == 0 &&
        actql_bootstrap_close_region_view(parent, extent, loan, view) == 0 &&
        actql_bootstrap_return_region(parent, extent, loan) == 0 &&
        actql_bootstrap_retire(parent, extent) == 0 && actql_bootstrap_close(parent) == 0 &&
        fcntl(fd, F_GETFD) >= 0 && actql_bootstrap_control_scope_clear() == 1,
        "child-first physical ACKs preserve independent original FD");
    moonbit_decref(domain); moonbit_decref(view); moonbit_decref(loan);
    moonbit_decref(extent); moonbit_decref(parent);
    require(close(fd) == 0 && unlink(path) == 0, "fixture closes only its separately owned FD");
    printf("{\"discovered\":11,\"executed\":%d,\"passed\":%d,\"failed\":0,"
        "\"host_pages\":64,\"domain_pages\":48,\"provider_copies\":1,"
        "\"normal_profile\":null,\"VM\":0,\"public_e2e\":0}\n", count, count);
    return count == 11 ? 0 : 3;
}
