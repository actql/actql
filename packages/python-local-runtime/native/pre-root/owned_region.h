#ifndef ACTQL_OWNED_REGION_H
#define ACTQL_OWNED_REGION_H

#include "owned_capacity.h"
#include <stdbool.h>

/* Physical transport only. These values are not a grant or a custody token.
 * The trusted caller must retain the original Core child and SharedBorrow. */
typedef struct {
    uint64_t device;
    uint64_t inode;
    uint64_t generation;
    unsigned char recipe[32];
    size_t capacity;
    size_t offset;
    size_t length;
    bool writable;
} actql_owned_extent_reference;

/* Caller-funded, address-bound physical carriers. Never serialize or copy the
 * loan or view. Their storage and FD/VM overhead are outside arena coverage. */
typedef struct actql_owned_extent_loan {
    struct actql_owned_extent_loan *original;
    actql_owned_capacity *owner;
    size_t start;
    actql_owned_extent_reference extent;
    bool returned;
    /* In-process aliases are never projected as FD transport. The same
     * address-bound loan retains its parent mapping until view retirement. */
    int64_t local_process;
    bool local_view_attempted;
    bool local_view_live;
    bool domain_storage;
} actql_owned_extent_loan;

typedef struct actql_owned_extent_view {
    struct actql_owned_extent_view *original;
    void *mapping;
    size_t length;
    actql_owned_extent_reference extent;
    size_t payload_offset;
    size_t payload_length;
    bool map_confirmed;
    bool payload_bound;
    bool domain_attempted;
    bool domain_live;
    bool domain_borrowed;
    bool domain_storage;
    actql_owned_extent_loan *local_loan;
} actql_owned_extent_view;

/* Same original physical comparison used by the existing Native channel.
 * The view/material is not authority. These read-only observations do not lock
 * or reset a possibly borrowed child's allocator or issue another binding. */
int actql_native_owned_domain_matches_view(actql_owned_capacity *lease,
    const actql_owned_extent_view *view, int64_t original_process);
int actql_native_owned_domain_has_child(actql_owned_capacity *lease,
    int64_t original_process, int64_t child_process);
/* Read-only physical pre-start comparison; no launch or stop authority. */
int actql_native_owned_domain_unborrowed(actql_owned_capacity *lease,
    const actql_owned_extent_view *view);

/* Same-original sticky returned-header observation only. This is neither a
 * process-stop proof nor allocation-level cleanup or physical retirement ACK.
 * It does not enter, reset or lock a possibly borrowed child allocator. */
int actql_native_owned_domain_returned(actql_owned_capacity *lease,
    const actql_owned_extent_view *view);

/* Borrow a trusted, exclusively initialized, exact-sized private regular FD.
 * This does not create/duplicate/close an FD or charge its physical overhead.
 * A failed acquisition may leave *out for the same original cleanup. */
int actql_native_owned_acquire_fd(int fd, size_t capacity, uint64_t generation,
                                 const unsigned char recipe[32],
                                 actql_owned_capacity **out);
int actql_native_owned_lend_extent(actql_owned_capacity *owner, void *allocation,
                                  bool writable, actql_owned_extent_loan *loan);
/* The original Common extent must cover this exact page-aligned physical range.
 * Sub-page writer ranges are not rounded into an overlapping shared mapping. */
int actql_native_owned_lend_extent_range(actql_owned_capacity *owner, void *allocation,
                                        size_t offset, size_t length, bool writable,
                                        actql_owned_extent_loan *loan);
/* Same-process anonymous-parent ExclusiveWrite sibling. No mapping, FD or transport is
 * issued. Actual page exclusion remains in the original parent allocation. */
int actql_native_owned_lend_in_process_extent_range(actql_owned_capacity *owner,
    void *allocation, size_t offset, size_t length, bool writable,
    actql_owned_extent_loan *loan);
/* Private same-process domain registration only. The returned address is held
 * by the original Native carrier, never a generic span. Only domain controls
 * are cleared here; every child allocation clears its full exposed extent.
 * Whole capacity and the original loan/view/retirement duties are unchanged. */
int actql_native_owned_allocate_in_process_domain(actql_owned_capacity *owner,
    size_t bytes, void **out);
int actql_native_owned_lend_in_process_domain(actql_owned_capacity *owner,
    void *allocation, size_t bytes, actql_owned_extent_loan *loan);
int actql_native_owned_view_in_process_domain(actql_owned_extent_loan *loan,
    actql_owned_extent_view *view);
/* Bind the same original local loan once; payload bounds are Core-issued. */
int actql_native_owned_view_in_process_extent(actql_owned_extent_loan *loan,
    size_t payload_offset, size_t payload_length, actql_owned_extent_view *view);
int actql_native_owned_project_extent(actql_owned_extent_loan *loan,
                                     actql_owned_extent_reference *out);
/* The original trusted child supplier validates nominal child/borrow/current
 * before mapping. Equal FD or reference data is never that authorization. */
int actql_native_owned_map_extent(int fd, const actql_owned_extent_reference *extent,
                                 actql_owned_extent_view *view);
/* Trusted original supplier only: payload must be the Core-issued child
 * bounds. These scalar bounds do not authenticate installation or delegation.
 * Old mapping without that binding cannot acquire an allocator domain. */
int actql_native_owned_map_extent_payload(int fd,
    const actql_owned_extent_reference *extent, size_t payload_offset,
    size_t payload_length, actql_owned_extent_view *view);
/* Suballocate the SAME bound ExclusiveWrite view. Its control table consumes
 * the original payload, with no mmap/FD/heap fallback or second capacity claim.
 * Domain retirement precedes view retirement, which precedes parent return. */
int actql_native_owned_acquire_extent_domain(actql_owned_extent_view *view,
                                            actql_owned_capacity **out);
/* Attach an already acquired whole private same-parent local loan/view to this
 * SAME entered domain. The trusted Common owner must admit the precise added
 * backing and controls first. Neither this port nor its quote grants capacity.
 * It performs no mapping, parent allocation, TLS switch or fallback. Original
 * and added views stay address-bound and caller-retained until domain close;
 * that ACK does not close views, return loans or retire parent allocations.
 * FD/process domains and a previously selected allocation ceiling refuse.
 * Expected current bytes fence replay; an unknown outcome retains all custody.
 * Each allocation must still fit wholly within one segment, so aggregate free
 * bytes alone do not prove a constructor's contiguous-space requirement. */
int actql_native_owned_attach_in_process_domain_segment(
    actql_owned_capacity *domain, actql_owned_extent_view *original_view,
    actql_owned_extent_view *addition_view, size_t expected_domain_bytes,
    uint64_t *control_bytes);
/* Fixed physical supplier state is included in this domain's original header
 * quote. Prepare once before entry; caller retains the original view graph.
 * These ports accept no callback, never replace TLS and issue no Common grant.
 * Quote serials only fence the same original operation; they are not handles
 * or funding. The trusted owner must reserve the complete quoted root addition
 * before acquire. Partial/unknown outcome stays charged until actual cleanup.
 * Scalars: 0 state (idle/quoted/acquiring/attached/refused/partial/closed),
 * 1 expected root bytes, 2 expected child bytes, 3 added root bytes,
 * 4 added root controls, 5 added child bytes, 6 added child controls,
 * 7 exact serial outcome (pending/no acquisition/attached/root retained).
 * Quote payload is a complete contiguous constructor coexistence requirement,
 * not merely aggregate free-byte shortage. Existing policy ceilings still apply.
 * Parent receipts are stored in acquired root control pages. Domain close
 * retires them in view/loan/allocation order; root maps close separately. */
enum actql_owned_growth_outcome {
    ACTQL_OWNED_GROWTH_PENDING = 0,
    ACTQL_OWNED_GROWTH_NO_ACQUISITION = 1,
    ACTQL_OWNED_GROWTH_ATTACHED_COMMITTED = 2,
    ACTQL_OWNED_GROWTH_CHILD_RETIRED_ROOT_RETAINED = 3
};

int actql_native_owned_prepare_domain_growth(actql_owned_capacity *domain,
    actql_owned_extent_view *original_view);
int actql_native_owned_quote_domain_growth(actql_owned_capacity *domain,
    size_t contiguous_payload_bytes, uint64_t *serial);
int actql_native_owned_domain_growth_scalar(actql_owned_capacity *domain,
    uint64_t serial, unsigned field, uint64_t *out);
int actql_native_owned_acquire_domain_growth(actql_owned_capacity *domain,
    uint64_t serial);
int actql_native_owned_finish_domain_growth(actql_owned_capacity *domain,
    uint64_t serial);
int actql_native_owned_cancel_domain_growth_quote(actql_owned_capacity *domain,
    uint64_t serial);
/* Observe or settle only this serial's existing receipt while outside owned
 * scopes. Retains mapped root bytes; does not grant backing or refund claims. */
int actql_native_owned_reconcile_domain_growth(actql_owned_capacity *domain,
    actql_owned_extent_view *original_view, uint64_t serial, unsigned *outcome);

int actql_native_owned_close_extent_domain(actql_owned_extent_view *view,
                                          actql_owned_capacity **slot);
/* Trusted original worker bootstrap only, AFTER nominal Core child/loan/current
 * validation and independent process overhead funding. Bind the already
 * initialized payload once; never reset it or issue a replacement capacity.
 * This PID is physical exclusion, not a grant or durable process identity. */
int actql_native_owned_borrow_extent_domain(actql_owned_extent_view *view,
                                           actql_owned_capacity **out);
/* Child-local retirement only. It requires scopes and allocations to retire,
 * preserves the same slot on failure and never closes the parent domain/FD.
 * Success still requires separate view unmap and Owner-confirmed stop before
 * parent loan settlement. Unknown child death leaves the borrow outstanding. */
int actql_native_owned_return_extent_domain_borrow(actql_owned_extent_view *view,
                                                  actql_owned_capacity **slot);
/* Physical leaf for the existing process Owner only, AFTER its original typed
 * child/IPC stop observation. This function does not observe or authorize stop.
 * It unmaps the parent's original exclusive child view without touching a dead
 * child's allocator lock or pretending that retained allocations were freed.
 * The original descriptor/loan and quota still require separate cleanup ACKs.
 * Failure preserves this same view and slot. Never call from PID absence. */
int actql_native_owned_unmap_stopped_child_domain(actql_owned_extent_view *view,
                                                 actql_owned_capacity **slot);
/* An unmap ACK is not a confirmed process stop or Common borrow return. */
int actql_native_owned_close_extent_view(actql_owned_extent_view *view);
/* Only the existing Owner's confirmed-stop/retirement path calls this port;
 * cancellation, parent death or lost response are not acknowledgements. */
int actql_native_owned_return_extent(actql_owned_extent_loan *loan);

#endif
