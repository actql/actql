/* Exact C carrier/lifetime diagnostic, not Common Resource or installed funding
 * evidence. Marker objects stand only for retained nominal references. */
#include <assert.h>
#include <stdio.h>
#include "moonbit_runtime.h"
#include "bootstrap_stub.c"

static unsigned finalized;
static void marker_finalizer(void *value) { (void)value; finalized++; }
static void *marker(void) { return moonbit_make_external_object(marker_finalizer, 8); }

struct foreign_thread_probe {
    actql_bootstrap_working_origin *origin;
    actql_bootstrap_region *loan;
    actql_bootstrap_view *view;
    actql_bootstrap_domain *domain;
    void *nominal;
    int bind, revoke;
};
static void *foreign_thread(void *arg) {
    struct foreign_thread_probe *probe = arg;
    probe->bind = working_origin_bind(probe->origin, probe->loan, probe->view,
                                      probe->domain, probe->nominal);
    probe->revoke = working_origin_revoke_after_domain_retirement(probe->origin);
    return NULL;
}

static void exercise(unsigned mode) {
    const unsigned char recipe[32] = {19};
    int64_t page = actql_bootstrap_page_bytes();
    actql_bootstrap_backing *root = actql_bootstrap_acquire(128 * page, 23, recipe);
    assert(actql_bootstrap_status(root) == 0);
    assert(actql_bootstrap_claim(root, 23, recipe) == 0);
    assert(actql_bootstrap_enter_scope(root) == 0);
    actql_bootstrap_extent *extent = actql_bootstrap_allocate_in_process_domain(root, 24 * page);
    assert(extent->status == 0);
    actql_bootstrap_extent *ordinary = actql_bootstrap_allocate_in_process_domain(root, 24 * page);
    assert(ordinary->status == 0);
    actql_bootstrap_region *ordinary_loan = actql_bootstrap_lend_region_in_process(root, ordinary, 0, 24 * page, 1);
    assert(ordinary_loan->status == 0);
    actql_bootstrap_view *ordinary_view = actql_bootstrap_view_region_in_process(root, ordinary, ordinary_loan, 0, 24 * page);
    assert(ordinary_view->status == 0);
    actql_bootstrap_domain *ordinary_domain = actql_bootstrap_acquire_domain(ordinary_view);
    assert(ordinary_domain->status == 0);
    assert(actql_bootstrap_transfer_domain(ordinary_domain) == 0);
    void *capacity = marker(), *allocation = marker(), *borrow = marker();
    unsigned before = finalized;
    /* Only the fixed carrier is allocated inside this one-request cohort. */
    assert(working_origin_raw_bytes() > 0);
    assert(actql_bootstrap_prepare_root_control(root, working_origin_raw_bytes(), 1) == 0);
    assert(working_origin_select(root, extent, capacity, allocation, borrow) == NULL);
    assert(actql_bootstrap_enter_root_control(root) == 0);
    /* Existing ordinary physical lending cannot be retrofitted, even with
     * a funded unused constructor slot. Rejection consumes no selection. */
    assert(working_origin_select(root, ordinary, capacity, allocation, borrow) == NULL);
    assert(!ordinary->working_selected);
    assert(root->control_context->managed_remaining == 1);
    actql_bootstrap_working_origin *origin = working_origin_select(root, extent, capacity, allocation, borrow);
    assert(origin != NULL && !origin->bound && !origin->bind_attempted);
    assert(working_origin_select(root, extent, capacity, allocation, borrow) == NULL);
    assert(actql_bootstrap_leave_root_control(root) == 0);
    moonbit_decref(capacity); moonbit_decref(allocation); moonbit_decref(borrow);
    assert(finalized == before);
    if (mode == 0) {
        assert(working_origin_revoke_after_domain_retirement(origin) == 0);
        assert(finalized == before + 3);
        assert(origin->revoked && origin->root == NULL);
        assert(working_origin_revoke_after_domain_retirement(origin) == 0);
    } else {
        actql_bootstrap_region *loan = actql_bootstrap_lend_region_in_process(root, extent, 0, 24 * page, 1);
        assert(loan->status == 0);
        actql_bootstrap_view *view = actql_bootstrap_view_region_in_process(root, extent, loan, 0, 24 * page);
        assert(view->status == 0);
        actql_bootstrap_domain *domain = actql_bootstrap_acquire_domain(view);
        assert(domain->status == 0);
        void *nominal = marker();
        if (mode != 2) assert(actql_bootstrap_transfer_domain(domain) == 0);
        assert(working_origin_bind(origin, ordinary_loan, view, domain, nominal) != 0);
        assert(working_origin_bind(origin, loan, ordinary_view, domain, nominal) != 0);
        assert(working_origin_bind(origin, loan, view, ordinary_domain, nominal) != 0);
        assert(!origin->bind_attempted && origin->domain == NULL);
        /* A distinct thread observes immutable originals only; no allocator
         * scope is entered and the caller waits before any further mutation. */
        struct foreign_thread_probe probe = {origin, loan, view, domain, nominal, 0, 0};
        pthread_t thread;
        assert(pthread_create(&thread, NULL, foreign_thread, &probe) == 0);
        assert(pthread_join(thread, NULL) == 0);
        assert(probe.bind != 0 && probe.revoke != 0 && !origin->bind_attempted);
        /* Negative saved-process snapshot, not a fork/cross-process runtime
         * acceptance claim. Never fork a live shared allocator for this test. */
        origin->process = -1;
        assert(working_origin_bind(origin, loan, view, domain, nominal) != 0);
        assert(working_origin_revoke_after_domain_retirement(origin) != 0);
        origin->process = getpid();
        assert(!origin->bind_attempted);
        assert(actql_bootstrap_enter_root_control(root) == 0);
        if (mode == 3) origin->root_generation++;
        int bind = working_origin_bind(origin, loan, view, domain, nominal);
        assert((bind == 0) == (mode == 1 || mode == 4));
        assert(origin->bind_attempted && origin->domain == domain);
        assert(working_origin_bind(origin, loan, view, domain, nominal) != 0);
        assert(actql_bootstrap_leave_root_control(root) == 0);
        moonbit_decref(nominal);
        assert(finalized == before);
        assert(working_origin_revoke_after_domain_retirement(origin) == ACTQL_OWNED_BUSY);
        /* Drop the original external aliases too. The carrier, not the stack
         * pointer copies, must retain the entire physical wrapper chain. */
        moonbit_decref(domain); moonbit_decref(view); moonbit_decref(loan);
        assert(origin->domain->view == origin->view && origin->view->loan == origin->loan);
        assert(actql_bootstrap_leave_scope(root) == 0);
        if (mode == 4) {
            assert(actql_bootstrap_enter_domain(domain) == 0);
            assert(actql_bootstrap_close_domain(view, domain) != 0);
            assert(working_origin_revoke_after_domain_retirement(origin) == ACTQL_OWNED_BUSY);
            assert(finalized == before);
            assert(actql_bootstrap_leave_domain(domain) == 0);
        }
        assert(actql_bootstrap_close_domain(view, domain) == 0);
        assert(finalized == before);
        /* The existing cleanup owner retains the wrappers before revocation;
         * revocation acknowledges no view/loan/allocation cleanup itself. */
        moonbit_incref(domain); moonbit_incref(view); moonbit_incref(loan);
        assert(working_origin_revoke_after_domain_retirement(origin) == 0);
        assert(finalized == before + 4);
        assert(working_origin_bind(origin, loan, view, domain, NULL) != 0);
        assert(actql_bootstrap_close_region_view(root, extent, loan, view) == 0);
        assert(actql_bootstrap_return_region(root, extent, loan) == 0);
        moonbit_decref(domain); moonbit_decref(view); moonbit_decref(loan);
        assert(actql_bootstrap_enter_scope(root) == 0);
    }
    assert(actql_bootstrap_close_domain(ordinary_view, ordinary_domain) == 0);
    assert(actql_bootstrap_close_region_view(root, ordinary, ordinary_loan, ordinary_view) == 0);
    assert(actql_bootstrap_return_region(root, ordinary, ordinary_loan) == 0);
    assert(actql_bootstrap_retire(root, ordinary) == 0);
    moonbit_decref(ordinary_domain); moonbit_decref(ordinary_view);
    moonbit_decref(ordinary_loan); moonbit_decref(ordinary);
    /* Carrier storage remains a real root Read alias until its last decref. */
    assert(actql_bootstrap_close_root_control(root) != 0);
    moonbit_decref(origin);
    assert(actql_bootstrap_close_root_control(root) == 0);
    assert(actql_bootstrap_retire(root, extent) == 0);
    assert(actql_bootstrap_leave_scope(root) == 0);
    assert(actql_bootstrap_close(root) == 0);
    moonbit_decref(extent); moonbit_decref(root);
}

int main(void) {
    for (unsigned mode = 0; mode < 5; mode++) exercise(mode);
    puts("{\"passed\":5,\"failed\":0}");
    return 0;
}
