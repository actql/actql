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
} actql_owned_extent_view;

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
/* An unmap ACK is not a confirmed process stop or Common borrow return. */
int actql_native_owned_close_extent_view(actql_owned_extent_view *view);
/* Only the existing Owner's confirmed-stop/retirement path calls this port;
 * cancellation, parent death or lost response are not acknowledgements. */
int actql_native_owned_return_extent(actql_owned_extent_loan *loan);

#endif
