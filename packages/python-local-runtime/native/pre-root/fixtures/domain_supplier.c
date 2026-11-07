/* Actual same-parent acquisition while the original child scope stays entered.
 * Syscall faults retain the actual partial originals; no cleanup ACK is faked. */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
static int fail_map, fail_allocate, fail_retire, maps, unmaps, inject_attach_refusal;
static void *retirement_target, *activation_target;
static size_t activation_length, activated_length;
static void inject_stale_attach_cut(void);
static void *observed_map(void *address, size_t length, int protection, int flags, int fd, off_t offset) {
    if (fail_map) { fail_map--; errno = ENOMEM; return MAP_FAILED; }
    void *result = mmap(address, length, protection, flags, fd, offset);
    if (result != MAP_FAILED) maps++;
    return result;
}
static int observed_protect(void *address, size_t length, int protection) {
    if (protection == (PROT_READ | PROT_WRITE) && fail_allocate) {
        int mode = fail_allocate; fail_allocate = 0;
        activation_target = address; activation_length = length; activated_length = 0;
        if (mode > 1) {
            size_t selected = mode == 2 ? length : (size_t)sysconf(_SC_PAGESIZE);
            if (mprotect(address, selected, protection) != 0) return -1;
            activated_length = selected;
        }
        errno = EIO; return -1;
    }
    if (protection == PROT_NONE && fail_retire && address == retirement_target) {
        fail_retire--; errno = EIO; return -1;
    }
    int result = mprotect(address, length, protection);
    if (result == 0 && protection == (PROT_READ | PROT_WRITE) && inject_attach_refusal) {
        inject_attach_refusal--;
        inject_stale_attach_cut();
    }
    return result;
}
static int observed_unmap(void *address, size_t length) { unmaps++; return munmap(address, length); }
#define mmap observed_map
#define mprotect observed_protect
#define munmap observed_unmap
#ifndef OWNED_SOURCE
#define OWNED_SOURCE "../owned_capacity.c"
#endif
#include OWNED_SOURCE
#undef mmap
#undef mprotect
#undef munmap
#ifdef ACTQL_DOMAIN_GROWTH_READ
void moonbit_panic(void) { abort(); }
#endif
static actql_owned_capacity *fault_domain;
static int inject_original_closing;
/* White-box unexpected cut after actual parent allocation. The production port
 * has no callback here; this only forces its otherwise closed attach-refusal
 * path and proves it keeps real acquired mapping/loan/view custody. */
static void inject_stale_attach_cut(void) {
    if (inject_original_closing) fault_domain->closing = true;
    else fault_domain->growth.expected_domain++;
}
static int discovered, passed;
#define CHECK(name, condition) do { discovered++; if (!(condition)) { \
    fprintf(stderr, "domain supplier failed: %s\n", name); return 1; } passed++; } while (0)

static int supplier_case(int attachment_failure) {
    int map_before = maps, unmap_before = unmaps;
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char recipe[32] = {31};
    actql_owned_capacity *parent = NULL, *domain = NULL;
    actql_owned_extent_loan loan = {0};
    actql_owned_extent_view view = {0};
    void *storage = NULL;
    CHECK("actual original graph", actql_native_owned_acquire(12 * page, 7, recipe, &parent) == 0 &&
        actql_native_owned_transfer(parent, 7, recipe) == 0 && actql_native_owned_enter(parent) == 0 &&
        actql_native_owned_allocate_in_process_domain(parent, 8 * page, &storage) == 0 &&
        actql_native_owned_lend_in_process_domain(parent, storage, 8 * page, &loan) == 0 &&
        actql_native_owned_view_in_process_domain(&loan, &view) == 0 &&
        actql_native_owned_acquire_extent_domain(&view, &domain) == 0 &&
        actql_native_owned_transfer_original_domain(domain) == 0);
    CHECK("prepare cannot substitute entered parent TLS", actql_native_owned_prepare_domain_growth(domain, &view) == ACTQL_OWNED_INVALID &&
        actql_native_owned_leave(parent) == 0);
    actql_owned_extent_view copied = view;
    CHECK("copied original cannot bind", actql_native_owned_prepare_domain_growth(domain, &copied) == ACTQL_OWNED_INVALID);
    CHECK("fixed slot bound once before child entry", actql_native_owned_prepare_domain_growth(domain, &view) == 0 &&
        actql_native_owned_prepare_domain_growth(domain, &view) == ACTQL_OWNED_INVALID && maps == map_before + 1);
    uint64_t serial = 0;
    CHECK("quote requires original child scope", actql_native_owned_quote_domain_growth(domain, 16 * page + 13, &serial) == ACTQL_OWNED_INVALID &&
        actql_native_owned_enter(domain) == 0);
#ifdef ACTQL_DOMAIN_GROWTH_READ
    actql_read_context *context = NULL;
    CHECK("actual original Read enters", actql_read_context_create(domain, &context) == 0 &&
        actql_read_context_retain(context) == 0 && actql_read_context_enter(context) == 0);
    void *old = actql_native_file_scoped_allocate(page);
#else
    void *old = NULL;
    CHECK("original payload allocated", actql_native_owned_allocate(domain, page, page, &old) == 0);
#endif
    CHECK("old payload is live", old != NULL && actql_native_owned_contains_live_span(domain, old, page) == 0);
    ((unsigned char *)old)[0] = 79;
    CHECK("overflow quote leaves slot unused", actql_native_owned_quote_domain_growth(domain, SIZE_MAX, &serial) == ACTQL_OWNED_INVALID && serial == 0);
    CHECK("quote is not acquisition", actql_native_owned_quote_domain_growth(domain, 16 * page + 13, &serial) == 0 &&
        serial == 1 && parent->length == 12 * page && domain->length == 8 * page && maps == map_before + 1);
    uint64_t root_bytes = 0, root_controls = 0, child_bytes = 0, child_controls = 0;
    CHECK("actual whole-span geometry", actql_native_owned_domain_growth_scalar(domain, serial, 3, &root_bytes) == 0 &&
        actql_native_owned_domain_growth_scalar(domain, serial, 4, &root_controls) == 0 &&
        actql_native_owned_domain_growth_scalar(domain, serial, 5, &child_bytes) == 0 &&
        actql_native_owned_domain_growth_scalar(domain, serial, 6, &child_controls) == 0 &&
        child_bytes == 17 * page + child_controls && root_bytes == child_bytes + root_controls);
    CHECK("cancel only the unacquired quote", actql_native_owned_cancel_domain_growth_quote(domain, serial) == 0 &&
        actql_native_owned_acquire_domain_growth(domain, serial) == ACTQL_OWNED_INVALID);
    uint64_t first_serial = serial; serial = 0;
    CHECK("same slot advances nonrecycled serial", actql_native_owned_quote_domain_growth(domain, 16 * page + 13, &serial) == 0 && serial > first_serial);
    fail_map = 1;
    CHECK("actual mmap refusal unchanged custody", actql_native_owned_acquire_domain_growth(domain, serial) == ACTQL_OWNED_PHYSICAL_FAILURE &&
        parent->length == 12 * page && domain->length == 8 * page && parent->pending_growth_domain == NULL &&
        domain->growth.receipts == NULL && ((unsigned char *)old)[0] == 79);
    CHECK("refused quote cannot replay acquisition", actql_native_owned_acquire_domain_growth(domain, serial) == ACTQL_OWNED_INVALID &&
        actql_native_owned_cancel_domain_growth_quote(domain, serial) == 0);
    serial = 0;
    CHECK("next exact quote", actql_native_owned_quote_domain_growth(domain, 16 * page + 13, &serial) == 0);
    CHECK("stale serial cannot acquire or finish", actql_native_owned_acquire_domain_growth(domain, first_serial) == ACTQL_OWNED_INVALID &&
        actql_native_owned_finish_domain_growth(domain, first_serial) == ACTQL_OWNED_INVALID);
    CHECK("actual growth keeps original child current", actql_native_owned_acquire_domain_growth(domain, serial) == 0 &&
        actql_native_owned_current() == domain && parent->length == 12 * page + root_bytes &&
        domain->length == 8 * page + child_bytes && domain->growth.pending->view.domain_live &&
        parent->pending_growth_domain == domain && maps == map_before + 2);
#ifdef ACTQL_DOMAIN_GROWTH_READ
    CHECK("same Read still selected", read_current == context && context->lease == domain);
#endif
    CHECK("unknown acquisition result cannot replay or cancel", actql_native_owned_acquire_domain_growth(domain, serial) == ACTQL_OWNED_INVALID &&
        actql_native_owned_cancel_domain_growth_quote(domain, serial) == ACTQL_OWNED_INVALID);
    void *forbidden = NULL;
    CHECK("pending original parent cannot allocate or close", actql_native_owned_allocate(parent, page, page, &forbidden) == ACTQL_OWNED_BUSY &&
        forbidden == NULL && actql_native_owned_try_close(&parent) == ACTQL_OWNED_BUSY && !parent->closing);
    CHECK("original physical finish", actql_native_owned_finish_domain_growth(domain, serial) == 0 && parent->pending_growth_domain == NULL);
#ifdef ACTQL_DOMAIN_GROWTH_READ
    void *newer = actql_native_file_scoped_allocate(16 * page + 13);
#else
    void *newer = NULL;
    CHECK("new payload allocation", actql_native_owned_allocate(domain, 16 * page + 13, page, &newer) == 0);
#endif
    CHECK("actual allocation exceeds original total", newer != NULL && actql_native_owned_contains_live_span(domain, newer, 16 * page + 13) == 0 &&
        ((unsigned char *)old)[0] == 79 && view.payload_length == 8 * page && loan.extent.length == 8 * page);
    ((unsigned char *)newer)[16 * page + 12] = 83;
    uint64_t successful = serial; serial = 0;
    CHECK("reuse fixed slot for next actual demand", actql_native_owned_quote_domain_growth(domain, 3 * page, &serial) == 0 && serial > successful);
    CHECK("old completion cannot clear new quote", actql_native_owned_finish_domain_growth(domain, successful) == ACTQL_OWNED_INVALID &&
        domain->growth.state == OWNED_GROWTH_QUOTED);
    size_t old_parent_bytes = parent->length, old_domain_bytes = domain->length;
    fault_domain = domain;
    if (attachment_failure) inject_attach_refusal = 1; else fail_allocate = 1;
    CHECK("post-map failure retains acquired original mapping", actql_native_owned_acquire_domain_growth(domain, serial) != 0 &&
        parent->length > old_parent_bytes && domain->length == old_domain_bytes &&
        domain->growth.state == OWNED_GROWTH_PARTIAL && parent->pending_growth_domain == domain && maps == map_before + 3);
    CHECK("partial outcome cannot be cancelled or completed", actql_native_owned_cancel_domain_growth_quote(domain, serial) == ACTQL_OWNED_INVALID &&
        actql_native_owned_finish_domain_growth(domain, serial) == ACTQL_OWNED_INVALID &&
        actql_native_owned_acquire_domain_growth(domain, serial) == ACTQL_OWNED_INVALID);
    CHECK("partial phase retains correct acquired stages", attachment_failure
        ? domain->growth.pending->allocation != NULL && domain->growth.pending->loan.original != NULL &&
          domain->growth.pending->view.original != NULL && !domain->growth.pending->view.domain_live
        : domain->growth.pending->allocation != NULL && domain->growth.pending->loan.original == NULL);
    CHECK("cancellation cannot retire active aliases", actql_native_owned_close_extent_domain(&view, &domain) == ACTQL_OWNED_BUSY &&
        domain != NULL && !domain->closing && ((unsigned char *)newer)[16 * page + 12] == 83);
#ifdef ACTQL_DOMAIN_GROWTH_READ
    CHECK("leave actual Read", actql_read_context_leave(context) == 0 && actql_native_owned_leave(domain) == 0 &&
        actql_read_context_release_after_owner_ack(context) == 0);
    CHECK("escaped Read still fences all receipt cleanup", actql_read_context_try_close(&context) == ACTQL_OWNED_BUSY &&
        actql_native_owned_close_extent_domain(&view, &domain) == ACTQL_OWNED_BUSY && !domain->closing);
    actql_native_file_scoped_free(old); actql_native_file_scoped_free(newer);
    CHECK("same original Read physically retires", actql_read_context_try_close(&context) == 0 && context == NULL);
#else
    CHECK("old and new physical retire before leave", actql_native_owned_retire(domain, old) == 0 &&
        actql_native_owned_retire(domain, newer) == 0 && actql_native_owned_leave(domain) == 0);
#endif
    retirement_target = domain->growth.receipts->next->allocation;
    fail_retire = 1;
    CHECK("parent allocation cleanup failure keeps original slot", actql_native_owned_close_extent_domain(&view, &domain) == ACTQL_OWNED_PHYSICAL_FAILURE &&
        domain != NULL && view.domain_live && domain->growth.receipts != NULL && parent->pending_growth_domain == domain && unmaps == unmap_before);
    CHECK("same cleanup retry drains actual receipt stages", actql_native_owned_close_extent_domain(&view, &domain) == 0 && domain == NULL &&
        parent->pending_growth_domain == NULL && !loan.returned && parent->length > old_parent_bytes && unmaps == unmap_before);
    CHECK("original view and parent cleanup stay separate", actql_native_owned_return_extent(&loan) == ACTQL_OWNED_BUSY &&
        actql_native_owned_close_extent_view(&view) == 0 && actql_native_owned_return_extent(&loan) == 0 &&
        actql_native_owned_retire(parent, storage) == 0 && actql_native_owned_try_close(&parent) == 0 && parent == NULL && unmaps == unmap_before + 3);
    actql_owned_extent_view spent = {0};
    CHECK("returned loan refuses before touching closed parent", actql_native_owned_return_extent(&loan) == ACTQL_OWNED_INVALID &&
        actql_native_owned_view_in_process_domain(&loan, &spent) == ACTQL_OWNED_INVALID);
    return 0;
}
static int receipt_reap_interleaving(void) {
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char recipe[32] = {47};
    actql_owned_capacity *parent = NULL, *domain = NULL;
    actql_owned_extent_loan loan = {0};
    actql_owned_extent_view view = {0};
    void *hole = NULL, *storage = NULL;
    CHECK("earlier root hole before original child", actql_native_owned_acquire(32 * page, 11, recipe, &parent) == 0 &&
        actql_native_owned_transfer(parent, 11, recipe) == 0 && actql_native_owned_enter(parent) == 0 &&
        actql_native_owned_allocate_in_process_domain(parent, 4 * page, &hole) == 0 &&
        actql_native_owned_allocate_in_process_domain(parent, 8 * page, &storage) == 0 &&
        actql_native_owned_retire(parent, hole) == 0 &&
        actql_native_owned_lend_in_process_domain(parent, storage, 8 * page, &loan) == 0 &&
        actql_native_owned_view_in_process_domain(&loan, &view) == 0 &&
        actql_native_owned_acquire_extent_domain(&view, &domain) == 0 &&
        actql_native_owned_transfer_original_domain(domain) == 0 && actql_native_owned_leave(parent) == 0);
    CHECK("original supplier prepared before entry", actql_native_owned_prepare_domain_growth(domain, &view) == 0 &&
        actql_native_owned_enter(domain) == 0);
    uint64_t serial = 0;
    CHECK("actual growth uses reusable earlier parent extent", actql_native_owned_quote_domain_growth(domain, page, &serial) == 0 &&
        actql_native_owned_acquire_domain_growth(domain, serial) == 0 &&
        domain->growth.pending->allocation == hole && actql_native_owned_finish_domain_growth(domain, serial) == 0 &&
        actql_native_owned_leave(domain) == 0);
    retirement_target = hole; fail_retire = 1;
    CHECK("receipt retains failed physical retirement", actql_native_owned_close_extent_domain(&view, &domain) == ACTQL_OWNED_PHYSICAL_FAILURE &&
        domain != NULL && domain->growth.receipts != NULL && !domain->growth.receipts->allocation_retired);
    size_t start;
    CHECK("parent probe cannot reap receipt before live original", actql_native_owned_try_close(&parent) == ACTQL_OWNED_BUSY && parent != NULL &&
        allocation_start(parent, hole, &start) && owned_extent(parent, start)->retired);
    CHECK("original receipt remains retryable after parent probe", actql_native_owned_close_extent_domain(&view, &domain) == 0 && domain == NULL);
    CHECK("separate original view loan and parent retire", actql_native_owned_close_extent_view(&view) == 0 &&
        actql_native_owned_return_extent(&loan) == 0 && actql_native_owned_retire(parent, storage) == 0 &&
        actql_native_owned_try_close(&parent) == 0 && parent == NULL);
    return 0;
}

/* A missing activation ACK still owns the exact earlier first-fit candidate.
 * The newly mapped segment alone cannot identify or retire this old hole. */
static int activation_custody(int mode) {
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char recipe[32] = {59};
    actql_owned_capacity *parent = NULL, *domain = NULL;
    actql_owned_extent_loan loan = {0};
    actql_owned_extent_view view = {0};
    void *hole = NULL, *storage = NULL, *old = NULL;
    CHECK("activation original graph", actql_native_owned_acquire(32 * page, 13, recipe, &parent) == 0 &&
        actql_native_owned_transfer(parent, 13, recipe) == 0 && actql_native_owned_enter(parent) == 0 &&
        actql_native_owned_allocate_in_process_domain(parent, 4 * page, &hole) == 0 &&
        actql_native_owned_allocate_in_process_domain(parent, 8 * page, &storage) == 0 &&
        actql_native_owned_retire(parent, hole) == 0 &&
        actql_native_owned_lend_in_process_domain(parent, storage, 8 * page, &loan) == 0 &&
        actql_native_owned_view_in_process_domain(&loan, &view) == 0 &&
        actql_native_owned_acquire_extent_domain(&view, &domain) == 0 &&
        actql_native_owned_transfer_original_domain(domain) == 0 && actql_native_owned_leave(parent) == 0);
    CHECK("prepare activation supplier", actql_native_owned_prepare_domain_growth(domain, &view) == 0 &&
        actql_native_owned_enter(domain) == 0 && actql_native_owned_allocate(domain, page, page, &old) == 0);
    ((unsigned char *)old)[0] = 97;
    uint64_t serial = 0, root_controls = 0, child_bytes = 0;
    CHECK("exact activation quote", actql_native_owned_quote_domain_growth(domain, page, &serial) == 0 &&
        actql_native_owned_domain_growth_scalar(domain, serial, 4, &root_controls) == 0 &&
        actql_native_owned_domain_growth_scalar(domain, serial, 5, &child_bytes) == 0 && child_bytes > page);
    size_t occupied = parent->occupied_pages, mapped = parent->length;
    fail_allocate = mode;
    CHECK("real activation failure", actql_native_owned_acquire_domain_growth(domain, serial) == ACTQL_OWNED_PHYSICAL_FAILURE &&
        activation_target == hole && activation_length == child_bytes &&
        activated_length == (mode == 1 ? 0 : mode == 2 ? child_bytes : page));
    struct owned_growth_receipt *receipt = domain->growth.pending;
    size_t start;
    CHECK("pending exact candidate published before activation", receipt != NULL && receipt->allocation == hole &&
        allocation_start(parent, hole, &start) && owned_extent(parent, start)->retired &&
        owned_extent(parent, start)->domain_storage && owned_extent(parent, start)->pages == child_bytes / page &&
        parent->occupied_pages == occupied + root_controls / page + child_bytes / page);
    CHECK("no successful loan or view invented", receipt->loan.original == NULL && receipt->view.original == NULL &&
        !receipt->allocation_retired && parent->pending_growth_domain == domain && domain->length == 8 * page);
    CHECK("lost activation cannot replay", actql_native_owned_acquire_domain_growth(domain, serial) == ACTQL_OWNED_INVALID &&
        actql_native_owned_cancel_domain_growth_quote(domain, serial) == ACTQL_OWNED_INVALID);
    void *reused = NULL;
    CHECK("pending activation excludes reuse", actql_native_owned_allocate(parent, child_bytes, page, &reused) == ACTQL_OWNED_BUSY && reused == NULL);
    CHECK("old child alias survives partial activation", actql_native_owned_close_extent_domain(&view, &domain) == ACTQL_OWNED_BUSY &&
        ((unsigned char *)old)[0] == 97 && actql_native_owned_retire(domain, old) == 0 && actql_native_owned_leave(domain) == 0);
    retirement_target = hole; fail_retire = 1;
    CHECK("actual retirement refusal retains exact receipt", actql_native_owned_close_extent_domain(&view, &domain) == ACTQL_OWNED_PHYSICAL_FAILURE &&
        domain != NULL && domain->growth.pending == receipt && receipt->allocation == hole && !receipt->allocation_retired &&
        parent->pending_growth_domain == domain && parent->occupied_pages == occupied + root_controls / page + child_bytes / page);
    CHECK("failed retirement cannot return original loan", actql_native_owned_return_extent(&loan) == ACTQL_OWNED_BUSY &&
        actql_native_owned_try_close(&parent) == ACTQL_OWNED_BUSY &&
        actql_native_owned_allocate(parent, child_bytes, page, &reused) == ACTQL_OWNED_BUSY && reused == NULL);
    CHECK("only real retirement ACK releases candidate", actql_native_owned_close_extent_domain(&view, &domain) == 0 && domain == NULL &&
        parent->pending_growth_domain == NULL && receipt->allocation_retired &&
        parent->occupied_pages == occupied + root_controls / page && parent->length > mapped);
    CHECK("same earlier hole reusable only after ACK", actql_native_owned_enter(parent) == 0 &&
        actql_native_owned_allocate(parent, child_bytes, page, &reused) == 0 && reused == hole &&
        actql_native_owned_retire(parent, reused) == 0 && actql_native_owned_leave(parent) == 0);
    CHECK("separate original physical cleanup", actql_native_owned_close_extent_view(&view) == 0 &&
        actql_native_owned_return_extent(&loan) == 0 && actql_native_owned_retire(parent, storage) == 0 &&
        actql_native_owned_try_close(&parent) == 0 && parent == NULL);
    return 0;
}

int main(void) {
    if (supplier_case(0) || supplier_case(1) || receipt_reap_interleaving() ||
        activation_custody(1) || activation_custody(2) || activation_custody(3)) return 1;
    printf("{\"native_domain_supplier_cases\":%d,\"passed\":%d}\n", discovered, passed);
    return discovered == passed ? 0 : 1;
}
