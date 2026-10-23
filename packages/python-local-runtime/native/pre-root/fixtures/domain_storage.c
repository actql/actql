/* Same original domain storage; no ordinary capacity or timing qualification. */
#include <stdio.h>
#include "../owned_capacity.c"
#define CHECK(name, predicate) do { discovered++; \
    if (!(predicate)) { fprintf(stderr, "Domain storage failed: %s\n", name); return 1; } \
    passed++; } while (0)
int main(void) {
    int discovered = 0, passed = 0;
    size_t page = (size_t)sysconf(_SC_PAGESIZE), bytes = 64 * page;
    unsigned char recipe[32] = {19};
    actql_owned_capacity *owner = NULL, *domain = NULL;
    void *old = NULL, *storage = NULL, *child = NULL;
    actql_owned_extent_loan loan = {0}, refused = {0};
    actql_owned_extent_view view = {0}, generic = {0};
    CHECK("same original parent", actql_native_owned_acquire(128 * page, 1, recipe, &owner) == 0 &&
        actql_native_owned_transfer(owner, 1, recipe) == 0);
    CHECK("unentered domain storage refuses", actql_native_owned_allocate_in_process_domain(owner, bytes, &storage) == ACTQL_OWNED_INVALID && storage == NULL);
    CHECK("parent entered", actql_native_owned_enter(owner) == 0);
    CHECK("generic full extent", actql_native_owned_allocate(owner, bytes, page, &old) == 0);
    memset(old, 0xa5, bytes);
    CHECK("old original retired", actql_native_owned_retire(owner, old) == 0);
    uint64_t before[5] = {0}, after[5] = {0};
    CHECK("initial work", actql_native_owned_extent_work(owner, before, 5) == 0);
    CHECK("registration reuses original pages", actql_native_owned_allocate_in_process_domain(owner, bytes, &storage) == 0 && storage == old);
    size_t controls = 0;
    CHECK("derived control prefix", round_pages(sizeof(*owner) + 64 * sizeof(struct extent), page, &controls) && controls < 64);
    CHECK("work counts acquired whole capacity and only actual prefix memset", actql_native_owned_extent_work(owner, after, 5) == 0 &&
        after[0] == before[0] + 1 && after[1] == before[1] + bytes && after[2] == before[2] + controls * page);
    /* Provider-local observation deliberately proves this path did not clear
     * capacity eagerly. No generic caller receives this uncleared payload. */
    for (size_t i = 0; i < controls * page; i++) if (((unsigned char *)storage)[i] != 0) return 2;
    for (size_t i = controls * page; i < bytes; i++) if (((unsigned char *)storage)[i] != 0xa5) return 3;
    CHECK("generic span refuses", actql_native_owned_contains_live_span(owner, storage, 1) == ACTQL_OWNED_INVALID &&
        actql_native_owned_contains_live_span(owner, (unsigned char *)storage + controls * page, page) == ACTQL_OWNED_INVALID);
    CHECK("generic protection and sealing refuse", actql_native_owned_protect(owner, storage, 0, page, PROT_READ) == ACTQL_OWNED_INVALID &&
        actql_native_owned_seal_readonly(owner, storage) == ACTQL_OWNED_INVALID);
    CHECK("generic loans refuse", actql_native_owned_lend_extent(owner, storage, true, &refused) == ACTQL_OWNED_INVALID &&
        actql_native_owned_lend_in_process_extent_range(owner, storage, 0, bytes, true, &refused) == ACTQL_OWNED_INVALID && refused.original == NULL);
    CHECK("partial domain loan refuses", actql_native_owned_lend_in_process_domain(owner, storage, bytes - page, &refused) == ACTQL_OWNED_INVALID);
    CHECK("same full domain loan", actql_native_owned_lend_in_process_domain(owner, storage, bytes, &loan) == 0);
    CHECK("parent retirement stays busy", actql_native_owned_retire(owner, storage) == ACTQL_OWNED_BUSY);
    CHECK("generic view refuses", actql_native_owned_view_in_process_extent(&loan, 0, bytes, &generic) == ACTQL_OWNED_INVALID && generic.original == NULL);
    actql_owned_extent_reference reference = {0};
    CHECK("domain loan is not FD transport", actql_native_owned_project_extent(&loan, &reference) == ACTQL_OWNED_INVALID);
    actql_owned_extent_loan copied_loan = loan;
    CHECK("copied loan refuses", actql_native_owned_view_in_process_domain(&copied_loan, &generic) == ACTQL_OWNED_INVALID);
    CHECK("same domain view", actql_native_owned_view_in_process_domain(&loan, &view) == 0);
    CHECK("loan return waits for view", actql_native_owned_return_extent(&loan) == ACTQL_OWNED_BUSY);
    actql_owned_extent_view copied_view = view;
    CHECK("copied view refuses", actql_native_owned_acquire_extent_domain(&copied_view, &domain) == ACTQL_OWNED_INVALID && domain == NULL);
    CHECK("same domain control", actql_native_owned_acquire_extent_domain(&view, &domain) == 0 && domain == storage);
    CHECK("view retirement waits for domain", actql_native_owned_close_extent_view(&view) == ACTQL_OWNED_BUSY);
    CHECK("same child entered", actql_native_owned_leave(owner) == 0 &&
        actql_native_owned_transfer_original_domain(domain) == 0 && actql_native_owned_enter(domain) == 0);
    CHECK("child allocates actual exposure", actql_native_owned_allocate(domain, page, page, &child) == 0);
    for (size_t i = 0; i < page; i++) if (((unsigned char *)child)[i] != 0) return 4;
    memset(child, 0x5a, page);
    CHECK("child return pending while live allocation", actql_native_owned_leave(domain) == 0 &&
        actql_native_owned_close_extent_domain(&view, &domain) == ACTQL_OWNED_BUSY && domain != NULL && view.domain_live);
    CHECK("same child physical retirement", actql_native_owned_retire(domain, child) == 0 &&
        actql_native_owned_close_extent_domain(&view, &domain) == 0 && domain == NULL);
    CHECK("separate view then loan ACK", actql_native_owned_close_extent_view(&view) == 0 && actql_native_owned_return_extent(&loan) == 0);
    actql_owned_extent_loan next_loan = {0};
    actql_owned_extent_view next_view = {0};
    CHECK("same parent entered again", actql_native_owned_enter(owner) == 0);
    CHECK("old initialized domain cannot be reissued", actql_native_owned_lend_in_process_domain(owner, storage, bytes, &next_loan) == 0 &&
        actql_native_owned_view_in_process_domain(&next_loan, &next_view) == 0 &&
        actql_native_owned_acquire_extent_domain(&next_view, &domain) == ACTQL_OWNED_IMAGE_MISMATCH && domain == NULL);
    CHECK("failed reissue cleanup", actql_native_owned_close_extent_view(&next_view) == 0 &&
        actql_native_owned_return_extent(&next_loan) == 0 && actql_native_owned_retire(owner, storage) == 0);
    void *reused = NULL;
    CHECK("generic reuse keeps full clearing", actql_native_owned_allocate(owner, bytes, page, &reused) == 0 && reused == old);
    for (size_t i = 0; i < bytes; i++) if (((unsigned char *)reused)[i] != 0) return 5;
    CHECK("separate original parent ACK", actql_native_owned_retire(owner, reused) == 0 &&
        actql_native_owned_leave(owner) == 0 && actql_native_owned_try_close(&owner) == 0 && owner == NULL);
    printf("{\"discovered\":%d,\"passed\":%d,\"domain_capacity\":%zu,\"initial_memset\":%zu,\"child_exposed_zero_bytes\":%zu}\n",
        discovered, passed, bytes, controls * page, page);
    return 0;
}
