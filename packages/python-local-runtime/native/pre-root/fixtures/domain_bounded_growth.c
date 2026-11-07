/* Actual checked same-domain growth preserves the original allocation bound.
 * A larger physical mapping is not a larger logical allocation allowance. */
#include <stdio.h>
#include <stdlib.h>
#include "../owned_capacity.c"

static int checks;
#define CHECK(condition) do { \
    checks++; \
    if (!(condition)) { fprintf(stderr, "bounded growth check %d failed\n", checks); return 1; } \
} while (0)

int main(void) {
    const size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char recipe[32] = {79};
    actql_owned_capacity *parent = NULL, *domain = NULL;
    void *storage = NULL, *old = NULL, *filled = NULL, *refused = NULL;
    actql_owned_extent_loan loan = {0};
    actql_owned_extent_view view = {0};
    CHECK(actql_native_owned_acquire(64 * page, 1, recipe, &parent) == 0 &&
        actql_native_owned_transfer(parent, 1, recipe) == 0 &&
        actql_native_owned_enter(parent) == 0);
    CHECK(actql_native_owned_allocate_in_process_domain(parent, 16 * page, &storage) == 0 &&
        actql_native_owned_lend_in_process_domain(parent, storage, 16 * page, &loan) == 0 &&
        actql_native_owned_view_in_process_domain(&loan, &view) == 0 &&
        actql_native_owned_acquire_extent_domain(&view, &domain) == 0 &&
        actql_native_owned_transfer_original_domain(domain) == 0 &&
        actql_native_owned_leave(parent) == 0);
    CHECK(actql_native_owned_enter(domain) == 0 &&
        actql_native_owned_bound_allocations(domain, 12 * page) == 0 &&
        actql_native_owned_leave(domain) == 0);
    const size_t ceiling = domain->allocation_ceiling_pages;
    actql_owned_capacity *const original = domain;
    CHECK(actql_native_owned_prepare_domain_growth(domain, &view) == 0 &&
        actql_native_owned_enter(domain) == 0 &&
        actql_native_owned_allocate(domain, 2 * page, page, &old) == 0);
    ((unsigned char *)old)[0] = 97;
    uint64_t serial = 0;
    CHECK(actql_native_owned_quote_domain_growth(domain, 8 * page, &serial) == 0 && serial > 0);
    CHECK(actql_native_owned_acquire_domain_growth(domain, serial) == 0 &&
        actql_native_owned_finish_domain_growth(domain, serial) == 0);
    CHECK(domain == original && domain->length > 16 * page &&
        domain->allocation_ceiling_pages == ceiling && ((unsigned char *)old)[0] == 97);
    const size_t remaining = ceiling - domain->occupied_pages;
    CHECK(remaining > 0 && actql_native_owned_allocate(domain, remaining * page, page, &filled) == 0);
    CHECK(actql_native_owned_allocate(domain, page, page, &refused) == ACTQL_OWNED_EXHAUSTED && refused == NULL);
    uint64_t next = 0;
    CHECK(actql_native_owned_quote_domain_growth(domain, page, &next) == ACTQL_OWNED_EXHAUSTED &&
        next == 0 && domain->growth.pending == NULL && parent->pending_growth_domain == NULL);
    CHECK(actql_native_owned_retire(domain, old) == 0 &&
        actql_native_owned_retire(domain, filled) == 0 && actql_native_owned_leave(domain) == 0);
    CHECK(actql_native_owned_close_extent_domain(&view, &domain) == 0 && domain == NULL &&
        !loan.returned && view.map_confirmed);
    CHECK(actql_native_owned_close_extent_view(&view) == 0 &&
        actql_native_owned_return_extent(&loan) == 0 &&
        actql_native_owned_retire(parent, storage) == 0);
    CHECK(actql_native_owned_try_close(&parent) == 0 && parent == NULL);
    printf("{\"bounded_domain_growth_cases\":%d,\"passed\":%d}\n", checks, checks);
    return 0;
}
