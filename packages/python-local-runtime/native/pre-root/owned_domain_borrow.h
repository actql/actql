#ifndef ACTQL_OWNED_DOMAIN_BORROW_H
#define ACTQL_OWNED_DOMAIN_BORROW_H
#include "owned_capacity.h"

/* Physical transport only, called by the trusted child bootstrap AFTER original
 * Core child/loan/current/durable validation and independent startup funding.
 * Equal FD/reference/recipe DATA do not perform those checks or issue a grant.
 * The caller funds zero-initialized, stable, aligned storage and owns its FD.
 * The same provider publishes partial map/borrow state there before failure. */
size_t actql_native_domain_borrow_storage_bytes(void);
size_t actql_native_domain_borrow_storage_alignment(void);
int actql_native_domain_borrow_open(void *storage, size_t bytes, int fd,
    const unsigned char recipe[32], const int64_t material[15]);
int actql_native_domain_borrow_status(void *storage);
int actql_native_domain_borrow_enter(void *storage);
int actql_native_domain_borrow_leave(void *storage);
/* Borrowed physical pointer, not an owning slot or wire identity. Its lifetime
 * stays with this record; generic capacity try_close cannot retire a domain. */
int actql_native_domain_borrow_pointer(void *storage, actql_owned_capacity **out);
/* One original retirement pass, no FD close or Core/process/Run/Store ACK.
 * Retry retains its same record and skips already acknowledged borrow return.
 * Unknown response requires retaining the original, not calling close again. */
int actql_native_domain_borrow_close(void *storage);
/* Move local holding custody once. The parent already transferred this same
 * physical domain; this does not reset its header or issue capacity/Run grant.
 * The stable slot survives a partial close, and clears only after final unmap. */
int actql_native_domain_borrow_claim_holding(void *storage, actql_owned_capacity **slot);
int actql_native_domain_borrow_transfer_holding(void *storage, actql_owned_capacity *holding,
    uint64_t generation, const unsigned char recipe[32]);
int actql_native_domain_borrow_close_holding(void *storage, actql_owned_capacity **slot);
int actql_native_domain_borrow_capacity(void *storage, uint64_t *out);
int actql_native_domain_borrow_contains_live_span(void *storage, const void *address, size_t bytes);
#endif
