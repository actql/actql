/* Explicit attachment to the same live local domain, never implicit backing. */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
static int fail_protect, unmaps;
static int observed_protect(void *address, size_t length, int protection) {
    if (fail_protect && protection == PROT_NONE) {
        fail_protect--; errno = EIO; return -1;
    }
    return mprotect(address, length, protection);
}
static int observed_unmap(void *address, size_t length) {
    unmaps++;
    return munmap(address, length);
}
#define mprotect observed_protect
#define munmap observed_unmap
#ifndef OWNED_SOURCE
#define OWNED_SOURCE "../owned_capacity.c"
#endif
#include OWNED_SOURCE
#undef mprotect
#undef munmap

static int discovered, passed;
#define CHECK(name, condition) do { \
    discovered++; \
    if (!(condition)) { fprintf(stderr, "domain growth failed: %s\n", name); return 1; } \
    passed++; \
} while (0)

static int domain_view(actql_owned_capacity *parent, size_t bytes, void **storage,
                        actql_owned_extent_loan *loan, actql_owned_extent_view *view) {
    int status = actql_native_owned_allocate_in_process_domain(parent, bytes, storage);
    if (status == 0) status = actql_native_owned_lend_in_process_domain(parent, *storage, bytes, loan);
    if (status == 0) status = actql_native_owned_view_in_process_domain(loan, view);
    return status;
}

static int physical_domain_growth(void) {
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char recipe[32] = {23};
    actql_owned_capacity *parent = NULL, *domain = NULL;
    void *first = NULL, *extra = NULL, *bounded_storage = NULL;
    actql_owned_extent_loan original_loan = {0}, extra_loan = {0}, bounded_loan = {0};
    actql_owned_extent_view original_view = {0}, extra_view = {0}, bounded_view = {0};
    CHECK("original small parent and domain", actql_native_owned_acquire(16 * page, 4, recipe, &parent) == 0 &&
        actql_native_owned_transfer(parent, 4, recipe) == 0 && actql_native_owned_enter(parent) == 0 &&
        domain_view(parent, 8 * page, &first, &original_loan, &original_view) == 0 &&
        actql_native_owned_acquire_extent_domain(&original_view, &domain) == 0);
    actql_owned_capacity *identity = domain;
    CHECK("separate explicitly bounded original", domain_view(parent, 4 * page, &bounded_storage, &bounded_loan, &bounded_view) == 0);
    uint64_t controls = 0;
    CHECK("same parent acquires actual added backing", actql_native_owned_grow(parent, 16 * page, 32 * page, &controls) == 0 &&
        domain_view(parent, 24 * page, &extra, &extra_loan, &extra_view) == 0 &&
        actql_native_owned_leave(parent) == 0);
    controls = 0;
    CHECK("unentered attachment refuses", actql_native_owned_attach_in_process_domain_segment(domain,
        &original_view, &extra_view, 8 * page, &controls) == ACTQL_OWNED_INVALID && controls == 0);
    actql_owned_capacity *bounded = NULL;
    CHECK("bind separate original ceiling", actql_native_owned_acquire_extent_domain(&bounded_view, &bounded) == 0 &&
        actql_native_owned_transfer_original_domain(bounded) == 0 && actql_native_owned_enter(bounded) == 0 &&
        actql_native_owned_bound_allocations(bounded, 3 * page) == 0);
    CHECK("existing allocation ceiling stays refused", actql_native_owned_attach_in_process_domain_segment(bounded,
        &bounded_view, &extra_view, 4 * page, &controls) == ACTQL_OWNED_INVALID && !extra_view.domain_attempted &&
        actql_native_owned_leave(bounded) == 0 && actql_native_owned_close_extent_domain(&bounded_view, &bounded) == 0);
    CHECK("close bounded original separately", actql_native_owned_close_extent_view(&bounded_view) == 0 &&
        actql_native_owned_return_extent(&bounded_loan) == 0 && actql_native_owned_retire(parent, bounded_storage) == 0);

    actql_owned_capacity *foreign = NULL;
    void *foreign_storage = NULL;
    actql_owned_extent_loan foreign_loan = {0};
    actql_owned_extent_view foreign_view = {0};
    CHECK("equal-recipe distinct actual parent", actql_native_owned_acquire(8 * page, 4, recipe, &foreign) == 0 &&
        actql_native_owned_transfer(foreign, 4, recipe) == 0 && actql_native_owned_enter(foreign) == 0 &&
        domain_view(foreign, 4 * page, &foreign_storage, &foreign_loan, &foreign_view) == 0 &&
        actql_native_owned_leave(foreign) == 0);
    CHECK("enter same original child", actql_native_owned_transfer_original_domain(domain) == 0 &&
        actql_native_owned_enter(domain) == 0);
    void *old = NULL, *newer = NULL;
    CHECK("old allocation fills original payload", actql_native_owned_allocate(domain,
        domain->length - domain->control_pages * page, page, &old) == 0);
    ((unsigned char *)old)[0] = 41;
    uint64_t before[16] = {0}, after[16] = {0};
    CHECK("snapshot before refusal", actql_native_owned_inventory(domain, before, 16) == 0);
    CHECK("foreign equal material does not bind", actql_native_owned_attach_in_process_domain_segment(domain,
        &original_view, &foreign_view, 8 * page, &controls) == ACTQL_OWNED_INVALID && !foreign_view.domain_attempted);
    actql_owned_extent_view copied = extra_view;
    CHECK("copied extra view refuses", actql_native_owned_attach_in_process_domain_segment(domain,
        &original_view, &copied, 8 * page, &controls) == ACTQL_OWNED_INVALID && !extra_view.domain_attempted);
    copied = original_view;
    CHECK("copied original view refuses", actql_native_owned_attach_in_process_domain_segment(domain,
        &copied, &extra_view, 8 * page, &controls) == ACTQL_OWNED_INVALID);
    CHECK("stale expected extent refuses unchanged", actql_native_owned_attach_in_process_domain_segment(domain,
        &original_view, &extra_view, 9 * page, &controls) == ACTQL_OWNED_INVALID && controls == 0 &&
        actql_native_owned_inventory(domain, after, 16) == 0 && memcmp(before, after, sizeof(before)) == 0 &&
        domain->rust_serial == 0 && domain->segments == NULL && !extra_view.domain_attempted);
    CHECK("no hidden root growth for carved child", actql_native_owned_grow(domain, 8 * page,
        24 * page, &controls) == ACTQL_OWNED_INVALID && controls == 0);
    CHECK("constructor refuses before explicit attachment", actql_native_owned_allocate(domain,
        12 * page, page, &newer) == ACTQL_OWNED_EXHAUSTED && newer == NULL);
    CHECK("attach already-held original-parent addition", actql_native_owned_attach_in_process_domain_segment(domain,
        &original_view, &extra_view, 8 * page, &controls) == 0 && controls > 0 && controls < 24 * page &&
        domain == identity && domain->length == 32 * page && extra_view.domain_live && unmaps == 0);
    CHECK("old original view and payload stay exact", original_view.payload_length == 8 * page &&
        original_loan.extent.length == 8 * page && domain->generation == 4 &&
        actql_native_owned_domain_matches_view(domain, &original_view, getpid()) == 0 &&
        ((unsigned char *)old)[0] == 41);
    controls = 0;
    CHECK("lost attachment result cannot replay", actql_native_owned_attach_in_process_domain_segment(domain,
        &original_view, &extra_view, 8 * page, &controls) == ACTQL_OWNED_INVALID && controls == 0 && domain->length == 32 * page);
    CHECK("duplicate addition refuses even with fresh size", actql_native_owned_attach_in_process_domain_segment(domain,
        &original_view, &extra_view, 32 * page, &controls) == ACTQL_OWNED_INVALID && controls == 0);
    CHECK("actual new allocation exceeds original domain", actql_native_owned_allocate(domain,
        12 * page, page, &newer) == 0 && ((unsigned char *)newer)[0] == 0 && ((unsigned char *)newer)[12 * page - 1] == 0);
    ((unsigned char *)newer)[0] = 72;
    CHECK("both segments exact containment", actql_native_owned_contains_live_span(domain, old, page) == 0 &&
        actql_native_owned_contains_live_span(domain, newer, 12 * page) == 0 &&
        actql_native_owned_contains_live_span(domain, newer, 12 * page + 1) == ACTQL_OWNED_INVALID &&
        actql_native_owned_contains_live_span(domain, domain->segments, 1) == ACTQL_OWNED_INVALID);
    CHECK("original and additional view cannot retire", actql_native_owned_close_extent_view(&original_view) == ACTQL_OWNED_BUSY &&
        actql_native_owned_close_extent_view(&extra_view) == ACTQL_OWNED_BUSY);
    CHECK("both parent loans and extents remain retained", actql_native_owned_return_extent(&original_loan) == ACTQL_OWNED_BUSY &&
        actql_native_owned_return_extent(&extra_loan) == ACTQL_OWNED_BUSY &&
        actql_native_owned_retire(parent, first) == ACTQL_OWNED_BUSY &&
        actql_native_owned_retire(parent, extra) == ACTQL_OWNED_BUSY);
    CHECK("cancellation cannot detach active child", actql_native_owned_close_extent_domain(&original_view, &domain) == ACTQL_OWNED_BUSY &&
        domain == identity && extra_view.domain_live && !domain->closing);
    actql_owned_extent_loan old_borrow = {0}, new_borrow = {0};
    actql_owned_extent_view old_alias = {0}, new_alias = {0};
    CHECK("old and new child borrowers overlap", actql_native_owned_lend_in_process_extent_range(domain, old, 0, page, true, &old_borrow) == 0 &&
        actql_native_owned_view_in_process_extent(&old_borrow, 0, page, &old_alias) == 0 &&
        actql_native_owned_lend_in_process_extent_range(domain, newer, 0, page, true, &new_borrow) == 0 &&
        actql_native_owned_view_in_process_extent(&new_borrow, 0, page, &new_alias) == 0 && old_borrow.owner == new_borrow.owner);
    CHECK("retained borrowers refuse both retirements", actql_native_owned_retire(domain, old) == ACTQL_OWNED_BUSY &&
        actql_native_owned_retire(domain, newer) == ACTQL_OWNED_BUSY);
    CHECK("same child borrower ACKs independently", actql_native_owned_close_extent_view(&old_alias) == 0 &&
        actql_native_owned_return_extent(&old_borrow) == 0 && actql_native_owned_close_extent_view(&new_alias) == 0 &&
        actql_native_owned_return_extent(&new_borrow) == 0);
    fail_protect = 1;
    CHECK("injected failed retirement retains original storage", actql_native_owned_retire(domain, newer) == ACTQL_OWNED_PHYSICAL_FAILURE &&
        extra_view.domain_live && ((unsigned char *)old)[0] == 41);
    CHECK("retire old then leave same domain", actql_native_owned_retire(domain, old) == 0 && actql_native_owned_leave(domain) == 0);
    fail_protect = 1;
    CHECK("failed cleanup cannot detach any added view", actql_native_owned_close_extent_domain(&original_view, &domain) == ACTQL_OWNED_PHYSICAL_FAILURE &&
        domain == identity && original_view.domain_live && extra_view.domain_live && unmaps == 0);
    CHECK("same cleanup retry detaches only child ownership", actql_native_owned_close_extent_domain(&original_view, &domain) == 0 && domain == NULL &&
        !original_view.domain_live && !extra_view.domain_live && !original_loan.returned && !extra_loan.returned && unmaps == 0);
    CHECK("view ACK still required after domain ACK", actql_native_owned_return_extent(&extra_loan) == ACTQL_OWNED_BUSY &&
        actql_native_owned_close_extent_view(&extra_view) == 0 && actql_native_owned_return_extent(&extra_loan) == 0);
    CHECK("parent retirement is a separate physical ACK", actql_native_owned_retire(parent, extra) == 0 &&
        actql_native_owned_close_extent_view(&original_view) == 0 && actql_native_owned_return_extent(&original_loan) == 0 &&
        actql_native_owned_retire(parent, first) == 0);
    CHECK("original parent releases both mappings", actql_native_owned_try_close(&parent) == 0 && parent == NULL && unmaps == 2);
    CHECK("refused foreign addition stays caller-owned", actql_native_owned_close_extent_view(&foreign_view) == 0 &&
        actql_native_owned_return_extent(&foreign_loan) == 0 && actql_native_owned_retire(foreign, foreign_storage) == 0 &&
        actql_native_owned_try_close(&foreign) == 0 && foreign == NULL && unmaps == 3);
    return 0;
}

#ifdef ACTQL_DOMAIN_GROWTH_READ
/* Standalone fail-stop boundary; no recovery or allocator fallback. */
void moonbit_panic(void) { abort(); }
static int escaped_read_growth(void) {
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char recipe[32] = {29};
    actql_owned_capacity *parent = NULL, *domain = NULL;
    void *first = NULL, *extra = NULL;
    actql_owned_extent_loan loan = {0}, extra_loan = {0};
    actql_owned_extent_view view = {0}, extra_view = {0};
    uint64_t controls = 0;
    CHECK("Read original parent lends both actual segments", actql_native_owned_acquire(16 * page, 5, recipe, &parent) == 0 &&
        actql_native_owned_transfer(parent, 5, recipe) == 0 && actql_native_owned_enter(parent) == 0 &&
        domain_view(parent, 8 * page, &first, &loan, &view) == 0 &&
        actql_native_owned_grow(parent, 16 * page, 32 * page, &controls) == 0 &&
        domain_view(parent, 24 * page, &extra, &extra_loan, &extra_view) == 0 && actql_native_owned_leave(parent) == 0);
    actql_read_context *context = NULL;
    CHECK("same original Read context enters original domain", actql_native_owned_acquire_extent_domain(&view, &domain) == 0 &&
        actql_native_owned_transfer_original_domain(domain) == 0 && actql_native_owned_enter(domain) == 0 &&
        actql_read_context_create(domain, &context) == 0 && actql_read_context_retain(context) == 0 &&
        actql_read_context_enter(context) == 0);
    void *old = actql_native_file_scoped_allocate(page);
    CHECK("old actual scoped object", old != NULL && actql_native_owned_contains_live_span(domain, old, page) == 0);
    ((unsigned char *)old)[0] = 37;
    controls = 0;
    CHECK("attachment preserves entered Read identity", actql_native_owned_attach_in_process_domain_segment(domain,
        &view, &extra_view, 8 * page, &controls) == 0 && read_current == context && context->lease == domain);
    void *newer = actql_native_file_scoped_allocate(12 * page);
    CHECK("actual scoped allocation uses new segment", newer != NULL &&
        actql_native_owned_contains_live_span(domain, newer, 12 * page) == 0 && ((unsigned char *)old)[0] == 37);
    ((unsigned char *)newer)[12 * page - 1] = 63;
    CHECK("leave with escaped scoped alias", actql_read_context_leave(context) == 0 && actql_native_owned_leave(domain) == 0 &&
        actql_read_context_release_after_owner_ack(context) == 0);
    CHECK("escaped Read blocks context and domain close", actql_read_context_try_close(&context) == ACTQL_OWNED_BUSY &&
        actql_native_owned_close_extent_domain(&view, &domain) == ACTQL_OWNED_BUSY && domain != NULL && !domain->closing &&
        extra_view.domain_live && ((unsigned char *)newer)[12 * page - 1] == 63);
    actql_native_file_scoped_free(old);
    CHECK("old free does not release new escaped alias", actql_read_context_try_close(&context) == ACTQL_OWNED_BUSY && extra_view.domain_live);
    actql_native_file_scoped_free(newer);
    CHECK("actual last alias enables same Read retirement", actql_read_context_try_close(&context) == 0 && context == NULL &&
        actql_native_owned_close_extent_domain(&view, &domain) == 0 && domain == NULL);
    CHECK("Read domain cleanup does not return parent loans", !loan.returned && !extra_loan.returned &&
        actql_native_owned_return_extent(&extra_loan) == ACTQL_OWNED_BUSY);
    CHECK("Read original physical custody closes in order", actql_native_owned_close_extent_view(&extra_view) == 0 &&
        actql_native_owned_return_extent(&extra_loan) == 0 && actql_native_owned_retire(parent, extra) == 0 &&
        actql_native_owned_close_extent_view(&view) == 0 && actql_native_owned_return_extent(&loan) == 0 &&
        actql_native_owned_retire(parent, first) == 0 && actql_native_owned_try_close(&parent) == 0 && parent == NULL);
    return 0;
}
#endif

int main(void) {
    if (physical_domain_growth() != 0) return 1;
#ifdef ACTQL_DOMAIN_GROWTH_READ
    if (escaped_read_growth() != 0) return 1;
#endif
    printf("{\"native_domain_growth_cases\":%d,\"passed\":%d}\n", discovered, passed);
    return discovered == passed ? 0 : 1;
}
