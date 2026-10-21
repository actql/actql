/* Same-provider local view counter. No worker, Core grant or normal profile. */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/mman.h>
#include <errno.h>
static int unmaps;
static int fail_protection;
static int observed_unmap(void *address, size_t length) {
    unmaps++;
    return munmap(address, length);
}
static int observed_protect(void *address, size_t length, int protection) {
    if (fail_protection) { fail_protection--; errno = EIO; return -1; }
    return mprotect(address, length, protection);
}
#define munmap observed_unmap
#define mprotect observed_protect
#include "owned_capacity.c"
#undef mprotect
#undef munmap
/* The standalone counter retains fail-stop semantics without the product main. */
void moonbit_panic(void) { abort(); }
static int assertions;
#define CHECK(name, condition) do { \
    if (!(condition)) { fprintf(stderr, "local domain: %s\n", name); return 1; } \
    assertions++; \
} while (0)
int main(void) {
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char recipe[32] = {93};
    actql_owned_capacity *parent = NULL, *domain = NULL, *duplicate = NULL;
    CHECK("one anonymous actual parent", actql_native_owned_acquire(64 * page, 8, recipe, &parent) == 0 &&
        actql_native_owned_transfer(parent, 8, recipe) == 0 && actql_native_owned_enter(parent) == 0);
    void *allocation = NULL;
    CHECK("same original allocation", actql_native_owned_allocate(parent, 24 * page, page, &allocation) == 0);
    actql_owned_extent_loan loan = {0}, overlap = {0}, regular = {0};
    CHECK("generic FD loan remains unavailable", actql_native_owned_lend_extent_range(parent, allocation,
        0, 24 * page, true, &regular) == ACTQL_OWNED_INVALID && regular.original == NULL);
    CHECK("local sibling requires exclusive writer", actql_native_owned_lend_in_process_extent_range(parent,
        allocation, 0, 24 * page, false, &regular) == ACTQL_OWNED_INVALID && regular.original == NULL);
    CHECK("local original loan", actql_native_owned_lend_in_process_extent_range(parent, allocation,
        0, 24 * page, true, &loan) == 0);
    actql_owned_extent_reference transport = {0};
    CHECK("local loan is not FD transport", actql_native_owned_project_extent(&loan, &transport) == ACTQL_OWNED_INVALID);
    CHECK("actual overlap excludes other users", actql_native_owned_lend_in_process_extent_range(parent,
        allocation, page, page, true, &overlap) == ACTQL_OWNED_BUSY &&
        actql_native_owned_retire(parent, allocation) == ACTQL_OWNED_BUSY);
    actql_owned_extent_view view = {0}, second = {0};
    actql_owned_extent_loan copied_loan = loan;
    CHECK("copied original refuses", actql_native_owned_view_in_process_extent(&copied_loan,
        page, 16 * page, &second) == ACTQL_OWNED_INVALID && second.original == NULL);
    CHECK("same mapping exact bounded payload", actql_native_owned_view_in_process_extent(&loan,
        page, 16 * page, &view) == 0 && view.mapping == allocation && view.length == 24 * page &&
        actql_native_owned_return_extent(&loan) == ACTQL_OWNED_BUSY && unmaps == 0);
    CHECK("one local view only", actql_native_owned_view_in_process_extent(&loan,
        page, 16 * page, &second) == ACTQL_OWNED_BUSY && second.original == NULL);
    actql_owned_extent_view copied_view = view;
    CHECK("copied view cannot acquire", actql_native_owned_acquire_extent_domain(&copied_view, &domain) == ACTQL_OWNED_INVALID && domain == NULL);
    CHECK("actual domain uses parent payload", actql_native_owned_acquire_extent_domain(&view, &domain) == 0 &&
        domain == (void *)((unsigned char *)allocation + page) && !domain->fd_backed &&
        domain->length == 16 * page && domain->control_pages > 0 && unmaps == 0 &&
        actql_native_owned_domain_matches_view(domain, &view, getpid()) == 0);
    size_t child_control_bytes = domain->control_pages * page;
    CHECK("local domain not process transport", actql_native_owned_borrow_extent_domain(&view, &duplicate) == ACTQL_OWNED_INVALID &&
        duplicate == NULL && actql_native_owned_close_extent_view(&view) == ACTQL_OWNED_BUSY);
    CHECK("leave same parent", actql_native_owned_leave(parent) == 0 &&
        actql_native_owned_transfer_original_domain(domain) == 0);
    pid_t child = fork();
    if (child == 0) {
        int result = actql_native_owned_enter(parent) == ACTQL_OWNED_BUSY &&
            actql_native_owned_try_close(&parent) == ACTQL_OWNED_BUSY &&
            actql_native_owned_enter(domain) == ACTQL_OWNED_BUSY &&
            actql_native_owned_close_extent_view(&view) == ACTQL_OWNED_BUSY &&
            actql_native_owned_close_extent_domain(&view, &domain) == ACTQL_OWNED_INVALID &&
            actql_native_owned_return_extent(&loan) == ACTQL_OWNED_INVALID;
        _exit(result ? 0 : 2);
    }
    int status = 0;
    CHECK("fork cannot adopt or retire original", child > 0 && waitpid(child, &status, 0) == child &&
        WIFEXITED(status) && WEXITSTATUS(status) == 0);
    CHECK("parent close stays pending", actql_native_owned_try_close(&parent) == ACTQL_OWNED_BUSY && parent != NULL && unmaps == 0);
    void *value = NULL;
    CHECK("same child native allocation and active lifetime", actql_native_owned_enter(domain) == 0 &&
        actql_native_owned_allocate(domain, page, 1, &value) == 0 &&
        actql_native_owned_contains_live_span(domain, value, page) == 0 &&
        actql_native_owned_close_extent_domain(&view, &domain) == ACTQL_OWNED_BUSY &&
        actql_native_owned_leave(domain) == 0);
    CHECK("live allocation keeps original", actql_native_owned_close_extent_domain(&view, &domain) == ACTQL_OWNED_BUSY && domain != NULL);
    fail_protection = 1;
    CHECK("partial retirement keeps same domain", actql_native_owned_retire(domain, value) == ACTQL_OWNED_PHYSICAL_FAILURE &&
        domain != NULL && view.domain_live && actql_native_owned_return_extent(&loan) == ACTQL_OWNED_BUSY);
    CHECK("same child retirement without parent unmap", actql_native_owned_close_extent_domain(&view, &domain) == 0 &&
        domain == NULL && actql_native_owned_close_extent_domain(&view, &domain) == 0 && unmaps == 0);
    CHECK("view ACK is separate from loan and parent", actql_native_owned_return_extent(&loan) == ACTQL_OWNED_BUSY &&
        actql_native_owned_close_extent_view(&view) == 0 && !loan.local_view_live && !loan.returned && unmaps == 0);
    CHECK("spent view cannot be reissued", actql_native_owned_view_in_process_extent(&loan,
        page, 16 * page, &second) == ACTQL_OWNED_BUSY &&
        actql_native_owned_acquire_extent_domain(&view, &duplicate) == ACTQL_OWNED_INVALID && duplicate == NULL);
    CHECK("same loan then parent actual retirement", actql_native_owned_return_extent(&loan) == 0 &&
        actql_native_owned_retire(parent, allocation) == 0 && actql_native_owned_try_close(&parent) == 0 &&
        parent == NULL && unmaps == 1);
    printf("{\"in_process_domain_assertions\":%d,\"passed\":%d,\"loan_bytes\":%zu,\"view_bytes\":%zu,\"child_control_bytes\":%zu,\"ordinary_command\":0}\n", assertions, assertions, sizeof(loan), sizeof(view), child_control_bytes);
    return assertions == 23 ? 0 : 3;
}
