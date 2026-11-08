/* A real attached growth whose response is withheld keeps its original
 * cap/receipt. Reconciliation observes it; it never reruns acquisition. */
#include <stdio.h>
#include <stdlib.h>
#include "../owned_capacity.c"
static int checks;
#define CHECK(condition) do { \
    checks++; \
    if (!(condition)) { fprintf(stderr, "Read bound reconcile check %d failed\n", checks); return 1; } \
} while (0)
int main(void) {
    const size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char recipe[32] = {97};
    actql_owned_capacity *parent = NULL, *domain = NULL;
    void *storage = NULL;
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
    uint64_t serial = 0;
    CHECK(actql_native_owned_quote_checked_read_growth(domain, 12 * page, &serial) == 0 &&
        actql_native_owned_acquire_domain_growth(domain, serial) == 0);
    const size_t cap = domain->allocation_ceiling_pages, bytes = parent->length;
    unsigned outcome = 0;
    CHECK(cap > 8 && parent->pending_growth_domain == domain &&
        actql_native_owned_reconcile_domain_growth(domain, &view, serial, &outcome) != 0 && outcome == 0);
    CHECK(actql_native_owned_leave(domain) == 0);
    actql_owned_extent_view copied = view;
    CHECK(actql_native_owned_reconcile_domain_growth(domain, &copied, serial, &outcome) != 0 &&
        actql_native_owned_reconcile_domain_growth(domain, &view, serial + 1, &outcome) != 0 && outcome == 0);
    CHECK(actql_native_owned_reconcile_domain_growth(domain, &view, serial, &outcome) == 0 &&
        outcome == ACTQL_OWNED_GROWTH_ATTACHED_COMMITTED &&
        domain->allocation_ceiling_pages == cap && parent->length == bytes &&
        parent->pending_growth_domain == NULL);
    CHECK(actql_native_owned_close_extent_domain(&view, &domain) == 0 && domain == NULL);
    CHECK(actql_native_owned_close_extent_view(&view) == 0 && actql_native_owned_return_extent(&loan) == 0 &&
        actql_native_owned_retire(parent, storage) == 0);
    CHECK(actql_native_owned_try_close(&parent) == 0 && parent == NULL);
    printf("{\"read_bound_reconcile_cases\":%d,\"passed\":%d}\n", checks, checks);
    return 0;
}
