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
    ACTQL_OWNED_EXHAUSTED = -4
};

/* Capacity includes the allocator's control storage. No implicit heap growth. */
int actql_owned_acquire(size_t capacity, uint64_t generation,
                        const unsigned char recipe[32],
                        actql_owned_capacity **out);
/* One transfer to the original LocalCore; this does not issue a Core grant. */
int actql_owned_transfer(actql_owned_capacity *lease, uint64_t generation,
                         const unsigned char recipe[32]);
/* Scope surrounds a native call; foreign nested lease entry is refused. */
int actql_owned_enter(actql_owned_capacity *lease);
int actql_owned_leave(actql_owned_capacity *lease);
actql_owned_capacity *actql_owned_current(void);
int actql_owned_allocate(actql_owned_capacity *lease, size_t bytes,
                         size_t alignment, void **out);
int actql_owned_protect(actql_owned_capacity *lease, void *allocation,
                        size_t offset, size_t length, int protection);
/* Retirement keeps a failed physical cleanup in the same native lease. */
int actql_owned_retire(actql_owned_capacity *lease, void *allocation);
/* Requires all children retired. Failure preserves the original pointer. */
int actql_owned_try_close(actql_owned_capacity **lease);

#endif
