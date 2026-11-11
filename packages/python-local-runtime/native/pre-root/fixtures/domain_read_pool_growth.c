/* Actual acquired-pool coverage is independent of a raw constructor span. */
#include <stdio.h>
#include <stdlib.h>
#include "../owned_capacity.c"
static int checks;
#define CHECK(condition) do { checks++; if (!(condition)) { \
    fprintf(stderr, "Read pool growth check %d failed\n", checks); return 1; } } while (0)
int main(void) {
    const size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char recipe[32] = {93};
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
        actql_native_owned_enter(domain) == 0 &&
        actql_native_owned_bound_working_allocations(domain, 4 * page, 32 * page) == 0);
    /* One raw page already fits. That is not enough backing for twelve more
     * usable pages required by simultaneously held logical reservations. */
    CHECK(actql_native_owned_checked_read_working_status(domain, page) == 0);
    uint64_t serial = 0, payload = 0, controls = 0, root_bytes = 0;
    CHECK(actql_native_owned_quote_checked_read_growth_covering(domain, page, 12 * page, &serial) == 0 &&
        actql_native_owned_domain_growth_scalar(domain, serial, 5, &payload) == 0 &&
        actql_native_owned_domain_growth_scalar(domain, serial, 6, &controls) == 0 &&
        actql_native_owned_domain_growth_scalar(domain, serial, 3, &root_bytes) == 0 &&
        payload > controls && payload - controls >= 12 * page && root_bytes > payload);
    CHECK(actql_native_owned_acquire_domain_growth(domain, serial) == 0 &&
        actql_native_owned_finish_domain_growth(domain, serial) == 0 &&
        domain->allocation_ceiling_pages <= 32 && domain->allocation_maximum_pages == 32);
    CHECK(actql_native_owned_allocate(domain, 12 * page, page, &constructed) == 0 &&
        actql_native_owned_contains_live_span(domain, constructed, 12 * page) == 0 &&
        actql_native_owned_retire(domain, constructed) == 0);
    uint64_t refused = 0;
    CHECK(actql_native_owned_quote_checked_read_growth_covering(domain, 33 * page, page, &refused) != 0 &&
        refused == 0 && domain->allocation_maximum_pages == 32 && actql_native_owned_leave(domain) == 0);
    CHECK(actql_native_owned_close_extent_domain(&view, &domain) == 0 &&
        actql_native_owned_close_extent_view(&view) == 0 && actql_native_owned_return_extent(&loan) == 0 &&
        actql_native_owned_retire(parent, storage) == 0);
    CHECK(actql_native_owned_try_close(&parent) == 0 && parent == NULL);
    printf("{\"read_pool_growth_cases\":%d,\"passed\":%d}\n", checks, checks);
    return 0;
}
