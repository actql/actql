#ifndef ACTQL_OWNED_CAPACITY_H
#define ACTQL_OWNED_CAPACITY_H

#include <stddef.h>
#include <stdint.h>

/* Review-only native preparation. This is not an installed runtime API. */
typedef struct actql_owned_capacity actql_owned_capacity;

enum actql_owned_status {
    ACTQL_OWNED_OK = 0,
    ACTQL_OWNED_INVALID = -1,
    ACTQL_OWNED_PHYSICAL_FAILURE = -2,
    ACTQL_OWNED_BUSY = -3,
    ACTQL_OWNED_EXHAUSTED = -4,
    ACTQL_OWNED_IMAGE_MISMATCH = -5
};

/* Capacity includes the allocator's control storage. No implicit heap growth. */
int actql_native_owned_acquire(size_t capacity, uint64_t generation,
                        const unsigned char recipe[32],
                        actql_owned_capacity **out);
/* Explicit non-moving addition to the same anonymous root after its original
 * Resource reservation has grown. Current transferred original required.
 * expected_bytes must equal the current physical amount; stale/lost-result
 * retries refuse unchanged. Additional bytes include their own controls, whose
 * actual amount is returned in an initially empty slot. No growth of FD-backed
 * or carved domains, implicit allocation retry, ledger grant or new generation.
 * Failure leaves physical capacity and output unchanged. */
int actql_native_owned_grow(actql_owned_capacity *lease, size_t expected_bytes,
                            size_t additional_bytes, uint64_t *control_bytes);
/* Actual new-segment control layout only; neither acquisition nor authority.
 * The output slot must be empty and the original capacity remains unchanged. */
int actql_native_owned_growth_control_bytes(actql_owned_capacity *lease,
    size_t bytes, uint64_t *out);
/* Read-only additional segment layout for an actual original allocation. */
int actql_native_owned_growth_for_payload_bytes(actql_owned_capacity *lease,
    size_t payload_bytes, uint64_t *out);
/* One transfer to the original LocalCore; this does not issue a Core grant. */
int actql_native_owned_transfer(actql_owned_capacity *lease, uint64_t generation,
                         const unsigned char recipe[32]);
/* Scope surrounds a native call; foreign nested lease entry is refused. */
int actql_native_owned_enter(actql_owned_capacity *lease);
int actql_native_owned_leave(actql_owned_capacity *lease);
actql_owned_capacity *actql_native_owned_current(void);
/* Physical observations only, never a Core capacity grant. The full original
 * region remains owned even after its child extents retire. */
int actql_native_owned_capacity_bytes(actql_owned_capacity *lease, uint64_t *out);
/* Opaque observations of the same provider, not capacity grants. Output slots
 * must be empty. Rounding cannot exceed the original region's finite bounds. */
int actql_native_owned_control_bytes(actql_owned_capacity *lease, uint64_t *out);
/* Read-only current-original census. Exactly16 initially-zero uint64 slots:
 * capacity/page/control/occupied/peak bytes; generic/slab/large bytes;
 * slab metadata/live-slot/free-slot bytes; pending-retirement bytes;
 * generic/large/slab extent counts and live slab-slot count.
 * Slab details are contained in slab bytes, never additional charges. Pending
 * extents stay occupied; their payload is not read. Values issue no grant,
 * availability, exportable alias or cleanup acknowledgement. */
int actql_native_owned_inventory(actql_owned_capacity *lease, uint64_t *out,
                                  size_t count);
/* Five initially-zero uint64 slots: successful backing-extent allocations,
 * page-rounded allocated bytes, explicit payload memset bytes, confirmed
 * extent retirements and their bytes. Cumulative within this actual holding;
 * excludes anonymous-map zero supply, this holding's control writes and nested
 * allocators. A private child-domain control prefix is payload of this holding
 * and its actual initial memset is included; untouched child capacity is not.
 * Same entered original required. Overflow refuses observation, never changes
 * allocation/cleanup behavior. No capacity, physical ACK or reusable credit. */
int actql_native_owned_extent_work(actql_owned_capacity *lease, uint64_t *out,
                                    size_t count);
/* Reduce the same original's allocation ceiling once, before payload use.
 * Includes allocator controls and pending extents; never a capacity issuer.
 * Requires the entered original scope. Invalid first selections are consumed. */
int actql_native_owned_bound_allocations(actql_owned_capacity *lease, size_t bytes);
int actql_native_owned_rounded_bytes(actql_owned_capacity *lease, size_t bytes,
                                    uint64_t *out);
/* Exact existing domain transfer, with its original immutable material kept
 * inside this provider. Never applies to an anonymous parent or issues a loan. */
int actql_native_owned_transfer_original_domain(actql_owned_capacity *lease);
/* Raw same-origin TLS observation only; no admission, stop or cleanup ACK. */
int actql_native_owned_control_scope_clear(void);

/* Requires original current/transferred lease and one live backing extent.
 * It does not establish Guest VM identity or execution permission. */
int actql_native_owned_contains_live_span(actql_owned_capacity *lease,
                                         const void *address, size_t bytes);
int actql_native_owned_allocate(actql_owned_capacity *lease, size_t bytes,
                         size_t alignment, void **out);
int actql_native_owned_protect(actql_owned_capacity *lease, void *allocation,
                        size_t offset, size_t length, int protection);
int actql_native_owned_seal_readonly(actql_owned_capacity *lease, void *allocation);
/* The caller lends its original readonly, nofollow FD. Failure after allocation
 * leaves *out in the original lease for cleanup; it is not an accepted image. */
int actql_native_owned_capture_image_fd(actql_owned_capacity *lease, int fd,
                                        size_t expected_bytes, size_t maximum_bytes,
                                        const unsigned char digest[32], void **out);
/* Retirement keeps a failed physical cleanup in the same native lease. */
int actql_native_owned_retire(actql_owned_capacity *lease, void *allocation);
/* Rust-only internal storage. A token identifies the original live slot and is
 * consumed once; it is not a grant. Storage/metadata stay in this same holding.
 * Allocate requires the original current scope. Retirement retains its original
 * lease after scope exit, but never re-adopts an inherited/foreign process. */
int actql_native_owned_rust_allocate(actql_owned_capacity *lease, size_t bytes,
    size_t alignment, void **out, uint64_t *token);
int actql_native_owned_rust_retire(actql_owned_capacity *lease, void *allocation,
                                   uint64_t token);
/* Read-only physical containment inside one live Rust allocation. The trusted
 * native caller must retain its original owning buffer/handle for the entire
 * read. This does not identify a stale pointer after reuse, issue a borrow or
 * authority, or make a heap page a generic/protectable/exportable span. */
int actql_native_owned_contains_live_rust_span(actql_owned_capacity *lease,
                                               const void *address, size_t bytes);
/* Requires all children retired. Failure preserves the original pointer. */
int actql_native_owned_try_close(actql_owned_capacity **lease);

#endif
