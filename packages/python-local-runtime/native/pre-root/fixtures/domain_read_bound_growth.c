/* Original physical Read-growth receipt only. Common declared-policy/window
 * admission is separate; scalar supplier calls are not a semantic grant. */
#include <stdio.h>
#include <stdlib.h>
#include "../owned_capacity.c"
static int checks;
#define CHECK(condition) do { \
    checks++; \
    if (!(condition)) { fprintf(stderr, "Read bound growth check %d failed\n", checks); return 1; } \
} while (0)
int main(void) {
    const size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char recipe[32] = {89};
    actql_owned_capacity *parent = NULL, *domain = NULL;
    void *storage = NULL, *constructed = NULL;
    actql_owned_extent_loan loan = {0}; actql_owned_extent_view view = {0};
    CHECK(actql_native_owned_acquire(16 * page, 1, recipe, &parent) == 0 &&
        actql_native_owned_transfer(parent, 1, recipe) == 0 && actql_native_owned_enter(parent) == 0);
    CHECK(actql_native_owned_allocate_in_process_domain(parent, 8 * page, &storage) == 0 &&
        actql_native_owned_lend_in_process_domain(parent, storage, 8 * page, &loan) == 0 &&
        actql_native_owned_view_in_process_domain(&loan, &view) == 0 &&
        actql_native_owned_acquire_extent_domain(&view, &domain) == 0 &&
        actql_native_owned_transfer_original_domain(domain) == 0 && actql_native_owned_leave(parent) == 0);
    CHECK(actql_native_owned_prepare_domain_growth(domain, &view) == 0 &&
        actql_native_owned_enter(domain) == 0 && actql_native_owned_bound_working_allocations(domain, 4 * page, 16 * page) == 0);
    CHECK(actql_native_owned_working_request_status(domain, 12 * page) == -1 &&
        actql_native_owned_checked_read_working_status(domain, 12 * page) == 1);
    uint64_t fixed = 0;
    CHECK(actql_native_owned_quote_domain_growth(domain, 2 * page, &fixed) == 0 &&
        actql_native_owned_acquire_domain_growth(domain, fixed) == 0 &&
        actql_native_owned_finish_domain_growth(domain, fixed) == 0 && domain->allocation_ceiling_pages == 4);
    const size_t old_domain = domain->length;
    uint64_t serial = 0;
    CHECK(actql_native_owned_quote_checked_read_growth(domain, 12 * page, &serial) == 0 &&
        domain->growth.ceiling_before == 4 && domain->growth.expand_read_bound);
    CHECK(actql_native_owned_acquire_domain_growth(domain, serial) == 0 &&
        actql_native_owned_finish_domain_growth(domain, serial) == 0 &&
        domain->allocation_ceiling_pages == 16 && domain->allocation_maximum_pages == 16 &&
        domain->allocation_ceiling_pages > 8 && parent->length <= 64 * page);
    CHECK(actql_native_owned_checked_read_working_status(domain, 12 * page) == 0 &&
        actql_native_owned_allocate(domain, 12 * page, page, &constructed) == 0);
    size_t offset = 0;
    CHECK(owned_pointer_offset(domain, constructed, &offset) && offset >= old_domain &&
        actql_native_owned_contains_live_span(domain, constructed, 12 * page) == 0);
    CHECK(actql_native_owned_checked_read_working_status(domain, 17 * page) == -1 &&
        domain->allocation_maximum_pages == 16);
    CHECK(actql_native_owned_retire(domain, constructed) == 0);
    uint64_t next = 0;
    CHECK(actql_native_owned_quote_checked_read_growth(domain, page, &next) == 0);
    const size_t before = parent->length, ceiling = domain->allocation_ceiling_pages;
    parent->closing = true;
    CHECK(actql_native_owned_acquire_domain_growth(domain, next) != 0 &&
        domain->growth.outcome == ACTQL_OWNED_GROWTH_NO_ACQUISITION &&
        domain->growth.pending == NULL && parent->length == before &&
        domain->allocation_ceiling_pages == ceiling &&
        actql_native_owned_cancel_domain_growth_quote(domain, next) == 0 &&
        actql_native_owned_leave(domain) == 0);
    CHECK(actql_native_owned_close_extent_domain(&view, &domain) == 0 &&
        actql_native_owned_close_extent_view(&view) == 0 &&
        actql_native_owned_return_extent(&loan) == 0 &&
        actql_native_owned_retire(parent, storage) == 0);
    CHECK(actql_native_owned_try_close(&parent) == 0 && parent == NULL);
    printf("{\"read_bound_growth_cases\":%d,\"passed\":%d}\n", checks, checks);
    return 0;
}
