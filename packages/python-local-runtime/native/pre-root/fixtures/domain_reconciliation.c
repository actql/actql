/* Scalar recovery of the same retained receipt, before managed cleanup needs
 * more backing. Reuse the original physical supplier and fault-injection ports. */
#define main original_domain_supplier_main
#include "domain_supplier.c"
#undef main

static int reconcile_case(int attached, int partial, int closing) {
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char recipe[32] = {71};
    actql_owned_capacity *parent = NULL, *domain = NULL;
    actql_owned_extent_loan loan = {0};
    actql_owned_extent_view view = {0};
    void *storage = NULL, *old = NULL;
    CHECK("recovery original graph", actql_native_owned_acquire(12 * page, 17, recipe, &parent) == 0 &&
        actql_native_owned_transfer(parent, 17, recipe) == 0 && actql_native_owned_enter(parent) == 0 &&
        actql_native_owned_allocate_in_process_domain(parent, 8 * page, &storage) == 0 &&
        actql_native_owned_lend_in_process_domain(parent, storage, 8 * page, &loan) == 0 &&
        actql_native_owned_view_in_process_domain(&loan, &view) == 0 &&
        actql_native_owned_acquire_extent_domain(&view, &domain) == 0 &&
        actql_native_owned_transfer_original_domain(domain) == 0 && actql_native_owned_leave(parent) == 0 &&
        actql_native_owned_prepare_domain_growth(domain, &view) == 0 && actql_native_owned_enter(domain) == 0);
    uint64_t cancelled = 0;
    CHECK("unacquired serial cancellation", actql_native_owned_quote_domain_growth(domain, page, &cancelled) == 0 &&
        actql_native_owned_cancel_domain_growth_quote(domain, cancelled) == 0 && actql_native_owned_leave(domain) == 0);
    unsigned outcome = 0;
    CHECK("no acquisition is its own terminal fact", actql_native_owned_reconcile_domain_growth(domain, &view, cancelled, &outcome) == 0 &&
        outcome == ACTQL_OWNED_GROWTH_NO_ACQUISITION && parent->length == 12 * page && domain->length == 8 * page);
    CHECK("original child reenters separately", actql_native_owned_enter(domain) == 0);
#ifdef ACTQL_DOMAIN_GROWTH_READ
    actql_read_context *context = NULL;
    if (!closing) {
        CHECK("retained Read before receipt", actql_read_context_create(domain, &context) == 0 &&
            actql_read_context_retain(context) == 0 && actql_read_context_enter(context) == 0);
        old = actql_native_file_scoped_allocate(page);
    } else {
        CHECK("raw alias before closing probe", actql_native_owned_allocate(domain, page, page, &old) == 0);
    }
#else
    CHECK("raw alias before receipt", actql_native_owned_allocate(domain, page, page, &old) == 0);
#endif
    CHECK("old alias exists", old != NULL);
    ((unsigned char *)old)[0] = 103;
    uint64_t serial = 0;
    CHECK("next quote resets only its own outcome", actql_native_owned_quote_domain_growth(domain, 16 * page, &serial) == 0 &&
        serial > cancelled && domain->growth.outcome == ACTQL_OWNED_GROWTH_PENDING);
    if (!attached && partial != 4) fail_allocate = 2;
    if (partial == 4) {
        fault_domain = domain; inject_original_closing = 1; inject_attach_refusal = 1;
    }
    int acquired = actql_native_owned_acquire_domain_growth(domain, serial);
    inject_original_closing = 0;
    struct owned_growth_receipt *receipt = domain->growth.pending;
    CHECK("exact acquired receipt retained", acquired == (attached ? ACTQL_OWNED_OK : partial == 4 ? ACTQL_OWNED_BUSY : ACTQL_OWNED_PHYSICAL_FAILURE) &&
        receipt != NULL && receipt->allocation != NULL && parent->pending_growth_domain == domain);
    CHECK("partial receipt keeps its actual loan and view stages", attached || partial == 4
        ? receipt->loan.original == &receipt->loan && receipt->view.original == &receipt->view &&
          receipt->view.mapping != NULL && receipt->view.domain_live == (bool)attached
        : receipt->loan.original == NULL && receipt->view.original == NULL);
    if (partial && partial != 4) domain->growth.state = OWNED_GROWTH_PARTIAL; /* Lost post-attach state ACK. */
    if (partial == 2) domain->growth.domain_controls += 1; /* Contradictory acknowledged geometry. */
    if (partial == 3) domain->growth.parent_controls += 1;
    outcome = 0;
    CHECK("recovery adds no entered scope authority", actql_native_owned_reconcile_domain_growth(domain, &view, serial, &outcome) == ACTQL_OWNED_INVALID &&
        outcome == 0 && parent->pending_growth_domain == domain);
#ifdef ACTQL_DOMAIN_GROWTH_READ
    CHECK("leave Read and owned scope before recovery", (context == NULL || actql_read_context_leave(context) == 0) &&
        actql_native_owned_leave(domain) == 0 && (context == NULL || actql_read_context_release_after_owner_ack(context) == 0));
#else
    CHECK("leave original scope before recovery", actql_native_owned_leave(domain) == 0);
#endif
    actql_owned_extent_view copied = view;
    CHECK("copied view and stale serial refuse unchanged", actql_native_owned_reconcile_domain_growth(domain, &copied, serial, &outcome) == ACTQL_OWNED_INVALID &&
        actql_native_owned_reconcile_domain_growth(domain, &view, cancelled, &outcome) == ACTQL_OWNED_INVALID &&
        outcome == 0 && parent->pending_growth_domain == domain);
    size_t root_bytes = parent->length, child_bytes = domain->length, occupied = parent->occupied_pages;
    if (partial == 2 || partial == 3) {
        CHECK("partial enum cannot override contradictory attached geometry", actql_native_owned_reconcile_domain_growth(domain, &view, serial, &outcome) == ACTQL_OWNED_INVALID &&
            outcome == 0 && parent->pending_growth_domain == domain && receipt->view.domain_live &&
            domain->length == child_bytes && parent->length == root_bytes && ((unsigned char *)old)[0] == 103);
#ifdef ACTQL_DOMAIN_GROWTH_READ
        if (context != NULL) {
            actql_native_file_scoped_free(old);
            CHECK("uncertain attachment retains Read through actual release", actql_read_context_try_close(&context) == 0 && context == NULL);
        } else {
            CHECK("uncertain attachment retains original raw alias", actql_native_owned_retire(domain, old) == 0);
        }
#else
        CHECK("uncertain attachment retains original raw alias", actql_native_owned_retire(domain, old) == 0);
#endif
        CHECK("only full original cleanup settles contradictory geometry", actql_native_owned_close_extent_domain(&view, &domain) == 0 && domain == NULL &&
            actql_native_owned_close_extent_view(&view) == 0 && actql_native_owned_return_extent(&loan) == 0 &&
            actql_native_owned_retire(parent, storage) == 0 && actql_native_owned_try_close(&parent) == 0 && parent == NULL);
        return 0;
    }
    if (closing) {
        CHECK("real close probe stops admission but retains old alias", actql_native_owned_close_extent_domain(&view, &domain) == ACTQL_OWNED_BUSY &&
            domain != NULL && domain->closing && actql_native_owned_enter(domain) == ACTQL_OWNED_BUSY);
    } else {
        CHECK("old inactive alias prevents whole domain cleanup", ((unsigned char *)old)[0] == 103 && domain->active_scopes == 0);
    }
    if (!attached) {
        retirement_target = receipt->allocation; fail_retire = 1;
        CHECK("failed receipt retirement retains exact pending original", actql_native_owned_reconcile_domain_growth(domain, &view, serial, &outcome) == ACTQL_OWNED_PHYSICAL_FAILURE &&
            outcome == 0 && domain->growth.pending == receipt && parent->pending_growth_domain == domain &&
            parent->occupied_pages == occupied && !receipt->allocation_retired);
    } else {
        CHECK("attached view cannot be returned during reconciliation", actql_native_owned_close_extent_view(&receipt->view) == ACTQL_OWNED_BUSY &&
            actql_native_owned_return_extent(&receipt->loan) == ACTQL_OWNED_BUSY);
    }
    CHECK("same receipt reaches its distinct terminal outcome", actql_native_owned_reconcile_domain_growth(domain, &view, serial, &outcome) == 0 &&
        outcome == (attached ? ACTQL_OWNED_GROWTH_ATTACHED_COMMITTED : ACTQL_OWNED_GROWTH_CHILD_RETIRED_ROOT_RETAINED) &&
        parent->pending_growth_domain == NULL && domain->growth.pending == NULL && domain->growth.receipts == receipt &&
        domain->length == child_bytes && parent->length == root_bytes && ((unsigned char *)old)[0] == 103);
    CHECK("only unattached candidate pages return", parent->occupied_pages == occupied - (attached ? 0 : domain->growth.domain_bytes / page) &&
        receipt->allocation_retired == !attached && receipt->view.domain_live == (bool)attached);
    outcome = 0;
    CHECK("terminal observation is exact and idempotent", actql_native_owned_reconcile_domain_growth(domain, &view, serial, &outcome) == 0 &&
        outcome == domain->growth.outcome && parent->length == root_bytes && domain->length == child_bytes);
    uint64_t scalar = 0;
    CHECK("same terminal scalar exposes no new acquisition", actql_native_owned_domain_growth_scalar(domain, serial, 7, &scalar) == 0 &&
        scalar == outcome && actql_native_owned_acquire_domain_growth(domain, serial) == ACTQL_OWNED_INVALID);
    if (!closing) {
        uint64_t next = 0;
        CHECK("next quote advances only the original serial", actql_native_owned_enter(domain) == 0 &&
            actql_native_owned_quote_domain_growth(domain, page, &next) == 0 && next > serial &&
            actql_native_owned_leave(domain) == 0);
        outcome = 0;
        CHECK("old terminal cannot acknowledge reused slot", actql_native_owned_reconcile_domain_growth(domain, &view, serial, &outcome) == ACTQL_OWNED_INVALID &&
            outcome == 0 && actql_native_owned_cancel_domain_growth_quote(domain, next) == 0 &&
            actql_native_owned_reconcile_domain_growth(domain, &view, next, &outcome) == 0 &&
            outcome == ACTQL_OWNED_GROWTH_NO_ACQUISITION && parent->length == root_bytes);
    } else {
        CHECK("retirement never reopens original admission", domain->closing && actql_native_owned_enter(domain) == ACTQL_OWNED_BUSY);
        outcome = 0;
        CHECK("closing original retains terminal observation", actql_native_owned_reconcile_domain_growth(domain, &view, serial, &outcome) == 0 &&
            outcome == ACTQL_OWNED_GROWTH_CHILD_RETIRED_ROOT_RETAINED);
    }
    void *control = NULL;
    CHECK("parent allocation resumes while old child alias remains", actql_native_owned_enter(parent) == 0 &&
        actql_native_owned_allocate(parent, page, page, &control) == 0 && control != NULL &&
        actql_native_owned_retire(parent, control) == 0 && actql_native_owned_leave(parent) == 0 && ((unsigned char *)old)[0] == 103);
    if (attached) {
        void *newer = NULL;
        CHECK("attached prefix remains usable without reacquisition", actql_native_owned_enter(domain) == 0 &&
            actql_native_owned_allocate(domain, 12 * page, page, &newer) == 0 && newer != NULL &&
            actql_native_owned_retire(domain, newer) == 0 && actql_native_owned_leave(domain) == 0);
    } else {
        CHECK("unattached recovery does not stretch child extent", domain->length == 8 * page && view.payload_length == 8 * page);
    }
#ifdef ACTQL_DOMAIN_GROWTH_READ
    if (context != NULL) {
        CHECK("escaped Read remains independently live", actql_read_context_try_close(&context) == ACTQL_OWNED_BUSY && context != NULL);
        actql_native_file_scoped_free(old);
        CHECK("Read retires only after actual old alias release", actql_read_context_try_close(&context) == 0 && context == NULL);
    } else {
        CHECK("raw alias still belongs to original domain", actql_native_owned_retire(domain, old) == 0);
        CHECK("raw alias retirement leaves original view live", view.domain_live);
    }
#else
    CHECK("raw alias still belongs to original domain", actql_native_owned_retire(domain, old) == 0);
    CHECK("raw alias retirement leaves original view live", view.domain_live);
#endif
    CHECK("full child cleanup stays separate", actql_native_owned_close_extent_domain(&view, &domain) == 0 && domain == NULL &&
        actql_native_owned_close_extent_view(&view) == 0 && actql_native_owned_return_extent(&loan) == 0 &&
        actql_native_owned_retire(parent, storage) == 0 && actql_native_owned_try_close(&parent) == 0 && parent == NULL);
    return 0;
}

int main(void) {
    if (reconcile_case(0, 0, 0) || reconcile_case(1, 0, 0) ||
        reconcile_case(1, 1, 0) || reconcile_case(0, 0, 1) || reconcile_case(1, 2, 0) || reconcile_case(1, 3, 0) || reconcile_case(0, 4, 1)) return 1;
    printf("{\"native_domain_reconciliation_cases\":%d,\"passed\":%d}\n", discovered, passed);
    return discovered == passed ? 0 : 1;
}
