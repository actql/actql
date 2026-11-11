/* Real fragmented placement/growth and current-loss refusal on one original.
 * No Common claim or product permission is issued by this physical fixture. */
#include <stdio.h>
#include <stdlib.h>
#include "../owned_capacity.c"
static int checks;
#define CHECK(condition) do { \
    checks++; \
    if (!(condition)) { fprintf(stderr, "working request check %d failed\n", checks); return 1; } \
} while (0)
int main(void) {
    const size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char recipe[32] = {83};
    actql_owned_capacity *parent = NULL, *domain = NULL;
    void *storage = NULL, *old[5] = {0}, *constructed = NULL;
    actql_owned_extent_loan loan = {0}; actql_owned_extent_view view = {0};
    CHECK(actql_native_owned_acquire(64 * page, 1, recipe, &parent) == 0 &&
        actql_native_owned_transfer(parent, 1, recipe) == 0 && actql_native_owned_enter(parent) == 0);
    CHECK(actql_native_owned_allocate_in_process_domain(parent, 16 * page, &storage) == 0 &&
        actql_native_owned_lend_in_process_domain(parent, storage, 16 * page, &loan) == 0 &&
        actql_native_owned_view_in_process_domain(&loan, &view) == 0 &&
        actql_native_owned_acquire_extent_domain(&view, &domain) == 0 &&
        actql_native_owned_transfer_original_domain(domain) == 0 && actql_native_owned_leave(parent) == 0);
    actql_owned_extent_view copied = view;
    CHECK(actql_native_owned_domain_growth_eligible(domain, &view) == 1 &&
        actql_native_owned_domain_growth_eligible(domain, &copied) == 0 &&
        actql_native_owned_working_request_status(domain, page) == -1);
    CHECK(actql_native_owned_prepare_domain_growth(domain, &view) == 0 &&
        actql_native_owned_enter(domain) == 0 && actql_native_owned_bound_allocations(domain, 15 * page) == 0);
    CHECK(actql_native_owned_working_request_status(domain, 6 * page) == 0);
    for (int i = 0; i < 5; i++) {
        CHECK(actql_native_owned_allocate(domain, 2 * page, page, &old[i]) == 0);
        ((unsigned char *)old[i])[0] = (unsigned char)(i + 40);
    }
    CHECK(actql_native_owned_retire(domain, old[1]) == 0 &&
        actql_native_owned_retire(domain, old[3]) == 0);
    CHECK(actql_native_owned_working_request_status(domain, 6 * page) == 1);
    const size_t ceiling = domain->allocation_ceiling_pages;
    uint64_t serial = 0;
    CHECK(actql_native_owned_quote_domain_growth(domain, 6 * page, &serial) == 0 &&
        actql_native_owned_acquire_domain_growth(domain, serial) == 0 &&
        actql_native_owned_finish_domain_growth(domain, serial) == 0 &&
        domain->allocation_ceiling_pages == ceiling);
    CHECK(actql_native_owned_working_request_status(domain, 6 * page) == 0 &&
        actql_native_owned_allocate(domain, 6 * page, page, &constructed) == 0);
    size_t offset = 0;
    CHECK(owned_pointer_offset(domain, constructed, &offset) && offset >= 16 * page &&
        ((unsigned char *)old[0])[0] == 40 && ((unsigned char *)old[4])[0] == 44);
    CHECK(actql_native_owned_working_request_status(domain, 2 * page) == -1);
    CHECK(actql_native_owned_retire(domain, constructed) == 0);
    uint64_t next = 0;
    CHECK(actql_native_owned_quote_domain_growth(domain, page, &next) == 0);
    const size_t before = parent->length;
    // Exact Owner-current loss between quotation and physical acquisition.
    parent->closing = true;
    CHECK(actql_native_owned_acquire_domain_growth(domain, next) != 0 &&
        domain->growth.outcome == ACTQL_OWNED_GROWTH_NO_ACQUISITION &&
        domain->growth.pending == NULL && parent->length == before &&
        actql_native_owned_cancel_domain_growth_quote(domain, next) == 0);
    CHECK(actql_native_owned_retire(domain, old[0]) == 0 &&
        actql_native_owned_retire(domain, old[2]) == 0 &&
        actql_native_owned_retire(domain, old[4]) == 0 && actql_native_owned_leave(domain) == 0);
    CHECK(actql_native_owned_close_extent_domain(&view, &domain) == 0 &&
        actql_native_owned_close_extent_view(&view) == 0 &&
        actql_native_owned_return_extent(&loan) == 0 &&
        actql_native_owned_retire(parent, storage) == 0 &&
        actql_native_owned_try_close(&parent) == 0 && parent == NULL);
    printf("{\"working_request_cases\":%d,\"passed\":%d}\n", checks, checks);
    return 0;
}
