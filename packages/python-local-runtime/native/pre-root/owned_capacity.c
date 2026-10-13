#if !defined(__APPLE__) || !defined(__aarch64__)
#error "This unadopted candidate targets Darwin arm64 only"
#endif

#include "owned_capacity.h"
#include <stdatomic.h>
#include <stdbool.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

/* An extent is a physical allocator record, not a Run or capacity decision. */
struct extent {
    size_t pages;
    bool retired;
};

struct actql_owned_capacity {
    size_t length;
    size_t page_size;
    size_t page_count;
    size_t control_pages;
    uint64_t generation;
    unsigned char recipe[32];
    bool transferred;
    bool closing;
    size_t active_scopes;
    atomic_flag lock;
    struct extent extents[];
};

static _Thread_local actql_owned_capacity *current_capacity;
static _Thread_local size_t current_depth;

static void lock_capacity(actql_owned_capacity *lease) {
    while (atomic_flag_test_and_set_explicit(&lease->lock, memory_order_acquire)) {}
}

static void unlock_capacity(actql_owned_capacity *lease) {
    atomic_flag_clear_explicit(&lease->lock, memory_order_release);
}

static bool round_pages(size_t bytes, size_t page, size_t *pages) {
    if (bytes == 0 || bytes > SIZE_MAX - (page - 1)) return false;
    *pages = (bytes + page - 1) / page;
    return true;
}

int actql_native_owned_acquire(size_t capacity, uint64_t generation,
                        const unsigned char recipe[32],
                        actql_owned_capacity **out) {
    if (out == NULL || *out != NULL || recipe == NULL || generation == 0)
        return ACTQL_OWNED_INVALID;
    long selected_page = sysconf(_SC_PAGESIZE);
    if (selected_page <= 0) return ACTQL_OWNED_PHYSICAL_FAILURE;
    size_t page = (size_t)selected_page;
    if (capacity == 0 || capacity > PTRDIFF_MAX || capacity % page != 0)
        return ACTQL_OWNED_INVALID;
    size_t count = capacity / page;
    if (count > (SIZE_MAX - sizeof(actql_owned_capacity)) / sizeof(struct extent))
        return ACTQL_OWNED_INVALID;
    size_t control_bytes = sizeof(actql_owned_capacity) + count * sizeof(struct extent);
    size_t control_pages;
    if (!round_pages(control_bytes, page, &control_pages) || control_pages >= count)
        return ACTQL_OWNED_INVALID;
    void *mapping = mmap(NULL, capacity, PROT_READ | PROT_WRITE,
                         MAP_PRIVATE | MAP_ANON, -1, 0);
    if (mapping == MAP_FAILED) return ACTQL_OWNED_PHYSICAL_FAILURE;
    actql_owned_capacity *lease = mapping;
    lease->length = capacity;
    lease->page_size = page;
    lease->page_count = count;
    lease->control_pages = control_pages;
    lease->generation = generation;
    memcpy(lease->recipe, recipe, sizeof(lease->recipe));
    lease->transferred = false;
    lease->closing = false;
    lease->active_scopes = 0;
    lease->lock = (atomic_flag)ATOMIC_FLAG_INIT;
    /* Anonymous pages are zero initialized, including extent records. */
    *out = lease;
    return ACTQL_OWNED_OK;
}

int actql_native_owned_transfer(actql_owned_capacity *lease, uint64_t generation,
                         const unsigned char recipe[32]) {
    if (lease == NULL || recipe == NULL) return ACTQL_OWNED_INVALID;
    lock_capacity(lease);
    int status = ACTQL_OWNED_INVALID;
    if (!lease->transferred && !lease->closing && lease->generation == generation &&
        memcmp(lease->recipe, recipe, sizeof(lease->recipe)) == 0) {
        lease->transferred = true;
        status = ACTQL_OWNED_OK;
    }
    unlock_capacity(lease);
    return status;
}

int actql_native_owned_enter(actql_owned_capacity *lease) {
    if (lease == NULL || (current_capacity != NULL && current_capacity != lease))
        return ACTQL_OWNED_INVALID;
    lock_capacity(lease);
    if (lease->closing || lease->active_scopes == SIZE_MAX || current_depth == SIZE_MAX) {
        unlock_capacity(lease);
        return ACTQL_OWNED_BUSY;
    }
    lease->active_scopes++;
    current_capacity = lease;
    current_depth++;
    unlock_capacity(lease);
    return ACTQL_OWNED_OK;
}

int actql_native_owned_leave(actql_owned_capacity *lease) {
    if (lease == NULL || current_capacity != lease || current_depth == 0)
        return ACTQL_OWNED_INVALID;
    lock_capacity(lease);
    lease->active_scopes--;
    if (--current_depth == 0) current_capacity = NULL;
    unlock_capacity(lease);
    return ACTQL_OWNED_OK;
}

actql_owned_capacity *actql_native_owned_current(void) {
    return current_capacity;
}

int actql_native_owned_allocate(actql_owned_capacity *lease, size_t bytes,
                         size_t alignment, void **out) {
    if (lease == NULL || out == NULL || *out != NULL || alignment == 0 ||
        (alignment & (alignment - 1)) != 0) return ACTQL_OWNED_INVALID;
    size_t pages;
    if (!round_pages(bytes, lease->page_size, &pages)) return ACTQL_OWNED_INVALID;
    lock_capacity(lease);
    if (lease->closing) {
        unlock_capacity(lease);
        return ACTQL_OWNED_BUSY;
    }
    int status = ACTQL_OWNED_EXHAUSTED;
    size_t start = lease->control_pages;
    while (start < lease->page_count && pages <= lease->page_count - start) {
        uintptr_t address = (uintptr_t)lease + start * lease->page_size;
        if (address % alignment != 0 || lease->extents[start].pages != 0) {
            start++;
            continue;
        }
        size_t used = 0;
        while (used < pages && lease->extents[start + used].pages == 0) used++;
        if (used != pages) {
            start += used + 1;
            continue;
        }
        void *base = (void *)address;
        size_t length = pages * lease->page_size;
        if (mprotect(base, length, PROT_READ | PROT_WRITE) != 0) {
            status = ACTQL_OWNED_PHYSICAL_FAILURE;
            break;
        }
        memset(base, 0, length);
        lease->extents[start].pages = pages;
        lease->extents[start].retired = false;
        for (size_t i = 1; i < pages; i++) lease->extents[start + i].pages = SIZE_MAX;
        *out = base;
        status = ACTQL_OWNED_OK;
        break;
    }
    unlock_capacity(lease);
    return status;
}

/* Called while locked. Only exact allocation starts are accepted. */
static bool allocation_start(actql_owned_capacity *lease, void *allocation,
                              size_t *start) {
    uintptr_t address = (uintptr_t)allocation;
    uintptr_t base = (uintptr_t)lease;
    if (address < base || address - base >= lease->length ||
        (address - base) % lease->page_size != 0) return false;
    *start = (address - base) / lease->page_size;
    return *start >= lease->control_pages && lease->extents[*start].pages != 0 &&
           lease->extents[*start].pages != SIZE_MAX;
}

int actql_native_owned_capacity_bytes(actql_owned_capacity *lease, uint64_t *out) {
    if (lease == NULL || out == NULL || *out != 0) return ACTQL_OWNED_INVALID;
    lock_capacity(lease);
    /* Closing is not released. A failed final unmap still owns the full region. */
    *out = (uint64_t)lease->length;
    unlock_capacity(lease);
    return ACTQL_OWNED_OK;
}

int actql_native_owned_contains_live_span(actql_owned_capacity *lease,
                                         const void *address, size_t bytes) {
    if (lease == NULL || address == NULL || bytes == 0 ||
        actql_native_owned_current() != lease) return ACTQL_OWNED_INVALID;
    lock_capacity(lease);
    int status = ACTQL_OWNED_INVALID;
    uintptr_t value = (uintptr_t)address;
    uintptr_t base = (uintptr_t)lease;
    if (lease->closing || !lease->transferred) goto done;
    if (value < base || value - base >= lease->length) goto done;
    size_t offset = (size_t)(value - base);
    if (bytes > lease->length - offset) goto done;
    size_t start = offset / lease->page_size;
    if (start < lease->control_pages) goto done;
    /* Interior pages carry SIZE_MAX. Find this single backing extent, never
     * merge adjacent allocations or read beyond the original control table. */
    while (start > lease->control_pages && lease->extents[start].pages == SIZE_MAX)
        start--;
    size_t pages = lease->extents[start].pages;
    if (pages == 0 || pages == SIZE_MAX || lease->extents[start].retired ||
        pages > lease->page_count - start) goto done;
    size_t begin = start * lease->page_size;
    size_t length = pages * lease->page_size;
    if (offset >= begin && offset - begin < length && bytes <= length - (offset - begin))
        status = ACTQL_OWNED_OK;
done:
    unlock_capacity(lease);
    return status;
}

int actql_native_owned_protect(actql_owned_capacity *lease, void *allocation,
                        size_t offset, size_t length, int protection) {
    if (lease == NULL || length == 0 || offset % lease->page_size != 0 ||
        length % lease->page_size != 0 ||
        (protection != PROT_NONE && protection != PROT_READ &&
         protection != (PROT_READ | PROT_WRITE) &&
         protection != (PROT_READ | PROT_EXEC))) return ACTQL_OWNED_INVALID;
    lock_capacity(lease);
    size_t start;
    int status = ACTQL_OWNED_INVALID;
    if (allocation_start(lease, allocation, &start) && !lease->extents[start].retired) {
        size_t bytes = lease->extents[start].pages * lease->page_size;
        if (offset <= bytes && length <= bytes - offset)
            status = mprotect((unsigned char *)allocation + offset, length, protection) == 0
                         ? ACTQL_OWNED_OK : ACTQL_OWNED_PHYSICAL_FAILURE;
    }
    unlock_capacity(lease);
    return status;
}

static int clean_retired(actql_owned_capacity *lease, size_t start) {
    size_t pages = lease->extents[start].pages;
    void *base = (unsigned char *)lease + start * lease->page_size;
    if (mprotect(base, pages * lease->page_size, PROT_NONE) != 0)
        return ACTQL_OWNED_PHYSICAL_FAILURE;
    memset(&lease->extents[start], 0, pages * sizeof(struct extent));
    return ACTQL_OWNED_OK;
}

int actql_native_owned_seal_readonly(actql_owned_capacity *lease, void *allocation) {
    if (lease == NULL) return ACTQL_OWNED_INVALID;
    lock_capacity(lease);
    size_t start;
    int status = ACTQL_OWNED_INVALID;
    if (allocation_start(lease, allocation, &start) && !lease->extents[start].retired) {
        size_t bytes = lease->extents[start].pages * lease->page_size;
        status = mprotect(allocation, bytes, PROT_READ) == 0
                     ? ACTQL_OWNED_OK : ACTQL_OWNED_PHYSICAL_FAILURE;
    }
    unlock_capacity(lease);
    return status;
}

int actql_native_owned_retire(actql_owned_capacity *lease, void *allocation) {
    if (lease == NULL) return ACTQL_OWNED_INVALID;
    lock_capacity(lease);
    size_t start;
    int status = ACTQL_OWNED_INVALID;
    if (allocation_start(lease, allocation, &start)) {
        lease->extents[start].retired = true;
        status = clean_retired(lease, start);
    }
    unlock_capacity(lease);
    return status;
}

int actql_native_owned_try_close(actql_owned_capacity **slot) {
    if (slot == NULL) return ACTQL_OWNED_INVALID;
    actql_owned_capacity *lease = *slot;
    if (lease == NULL) return ACTQL_OWNED_OK;
    /* The original owner must exclude concurrent callers before final close. */
    lock_capacity(lease);
    if (lease->active_scopes != 0) {
        unlock_capacity(lease);
        return ACTQL_OWNED_BUSY;
    }
    lease->closing = true;
    for (size_t i = lease->control_pages; i < lease->page_count; i++) {
        if (lease->extents[i].pages == 0) continue;
        if (lease->extents[i].pages == SIZE_MAX || !lease->extents[i].retired) {
            unlock_capacity(lease);
            return ACTQL_OWNED_BUSY;
        }
        int status = clean_retired(lease, i);
        if (status != ACTQL_OWNED_OK) {
            unlock_capacity(lease);
            return status;
        }
    }
    size_t length = lease->length;
    if (munmap(lease, length) != 0) {
        unlock_capacity(lease);
        return ACTQL_OWNED_PHYSICAL_FAILURE;
    }
    *slot = NULL;
    return ACTQL_OWNED_OK;
}
