#if defined(ACTQL_NATIVE_OWNED_LINUX_X64_PROCESS_DOMAIN)
/* Explicit process-only profile; the same POSIX implementation below owns
 * mappings, original loans, current scopes and child-first retirement. */
#include "owned_linux_x64_process_profile.h"
#elif defined(__APPLE__) && defined(__aarch64__)
/* Existing selected Darwin provider. */
#elif defined(__linux__) && defined(__aarch64__) && \
      defined(ACTQL_NATIVE_OWNED_LINUX_PROCESS_DOMAIN)
/* Only the selected local process-domain consumer enables this physical
 * backend. Its actual private FD/mapping is still required independently of
 * kernel process limits. This does not select image, Engine or Rust profiles. */
#if !defined(_GNU_SOURCE)
#error "The selected Linux provider requires _GNU_SOURCE before system headers"
#endif
#else
#error "Owned backing requires Darwin arm64 or explicitly selected Linux arm64"
#endif

#include "owned_capacity.h"
#include "owned_region.h"
#include <stdatomic.h>
#include <stdbool.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <pthread.h>

/* An extent is a physical allocator record, not a Run or capacity decision. */
struct extent {
    size_t pages;
    bool retired;
    bool sealed;
    /* Private domain registration storage is not a generic readable span. */
    bool domain_storage;
    size_t external_readers;
    bool external_writer;
    /* Private Rust storage is never a generic exportable span. */
    unsigned char rust_class;
    uint64_t rust_token;
};

struct actql_owned_capacity {
    size_t length;
    size_t page_size;
    size_t page_count;
    size_t control_pages;
    /* Search cache only: the lowest free page, or page_count when full.
     * It issues no capacity and stays inside this original control region. */
    size_t first_free_page;
    /* Observational occupancy only, including control and pending retirement.
     * Neither value issues capacity or acknowledges physical cleanup. */
    size_t occupied_pages;
    size_t peak_occupied_pages;
    /* Cumulative backing-extent work only. This is neither occupancy nor
     * capacity; child retirement and reuse never reset these observations. */
    uint64_t extent_work[5];
    bool extent_work_overflow;
    /* Optional one-shot physical ceiling, including original control pages.
     * It never changes mapping size, ownership, reservations or retirement. */
    size_t allocation_ceiling_pages;
    bool allocation_ceiling_attempted;
    size_t rust_available[8];
    uint64_t rust_serial;
    atomic_int rust_process;
    uint64_t backing_device;
    uint64_t backing_inode;
    bool fd_backed;
    bool extent_domain;
    pid_t domain_origin_pid;
    atomic_int domain_borrower_pid;
    bool domain_borrow_attempted;
    uint64_t generation;
    unsigned char recipe[32];
    bool transferred;
    bool closing;
    size_t active_scopes;
    atomic_flag lock;
    struct extent extents[];
};

struct owned_scope_state {
    actql_owned_capacity *capacity;
    size_t depth;
    size_t floor;
    pid_t process;
};
static _Thread_local struct owned_scope_state ordinary_scope;
/* One same-provider key, not another holding or a process thread registry.
 * Its value aliases the original live child controller through confirmed join.
 * Existing process/runtime custody must retain this provider while it is used. */
static pthread_key_t owned_scope_key;
static pthread_once_t owned_scope_key_once = PTHREAD_ONCE_INIT;
static atomic_bool owned_scope_key_ready;
static int owned_scope_key_status;
static struct owned_scope_state *owned_scope(void) {
    if (atomic_load_explicit(&owned_scope_key_ready, memory_order_acquire)) {
        struct owned_scope_state *scope = pthread_getspecific(owned_scope_key);
        if (scope != NULL) return scope;
    }
    /* An unbound thread remains unbound; never substitute another holding. */
    return &ordinary_scope;
}
#define current_capacity (owned_scope()->capacity)
#define current_depth (owned_scope()->depth)
#define current_floor (owned_scope()->floor)
#define current_process (owned_scope()->process)

/* This physical exclusion is not child authorization. A trusted bootstrap
 * validates the original Core loan before publishing the process borrow. */
static bool foreign_domain_process(actql_owned_capacity *lease) {
    int borrower = atomic_load_explicit(&lease->domain_borrower_pid, memory_order_acquire);
    return (!lease->fd_backed && lease->domain_origin_pid != getpid()) ||
        (lease->extent_domain && borrower != 0 && borrower != (int)getpid());
}

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
    lease->first_free_page = control_pages;
    lease->occupied_pages = lease->peak_occupied_pages = control_pages;
    lease->allocation_ceiling_pages = count;
    lease->backing_device = 0;
    lease->backing_inode = 0;
    lease->fd_backed = false;
    lease->extent_domain = false;
    lease->domain_origin_pid = getpid();
    atomic_init(&lease->domain_borrower_pid, 0);
    atomic_init(&lease->rust_process, 0);
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
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    int status = ACTQL_OWNED_INVALID;
    if (!foreign_domain_process(lease) && !lease->transferred && !lease->closing && lease->generation == generation &&
        memcmp(lease->recipe, recipe, sizeof(lease->recipe)) == 0) {
        lease->transferred = true;
        status = ACTQL_OWNED_OK;
    }
    unlock_capacity(lease);
    return status;
}

int actql_native_owned_transfer_original_domain(actql_owned_capacity *lease) {
    if (lease == NULL || !lease->extent_domain) return ACTQL_OWNED_INVALID;
    /* Immutable fields of this exact original. The Native caller already
     * validated its nominal domain/borrow/current through the existing Owner. */
    return actql_native_owned_transfer(lease, lease->generation, lease->recipe);
}

int actql_native_owned_enter(actql_owned_capacity *lease) {
    if (lease == NULL || (current_capacity != NULL &&
        (current_capacity != lease || current_process != getpid())))
        return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    if (foreign_domain_process(lease) || lease->closing || lease->active_scopes == SIZE_MAX || current_depth == SIZE_MAX) {
        unlock_capacity(lease);
        return ACTQL_OWNED_BUSY;
    }
    lease->active_scopes++;
    current_capacity = lease;
    current_depth++;
    current_process = getpid();
    unlock_capacity(lease);
    return ACTQL_OWNED_OK;
}

int actql_native_owned_leave(actql_owned_capacity *lease) {
    if (lease == NULL || current_capacity != lease || current_process != getpid() ||
        current_depth <= current_floor)
        return ACTQL_OWNED_INVALID;
    lock_capacity(lease);
    lease->active_scopes--;
    if (--current_depth == 0) {
        current_capacity = NULL;
        current_process = 0;
    }
    unlock_capacity(lease);
    return ACTQL_OWNED_OK;
}

actql_owned_capacity *actql_native_owned_current(void) {
    return current_capacity;
}

int actql_native_owned_control_scope_clear(void) {
    return current_capacity == NULL && current_depth == 0 ? 1 : 0;
}

int actql_native_owned_control_bytes(actql_owned_capacity *lease, uint64_t *out) {
    if (lease == NULL || out == NULL || *out != 0) return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    if (foreign_domain_process(lease)) {
        unlock_capacity(lease);
        return ACTQL_OWNED_BUSY;
    }
    *out = (uint64_t)(lease->control_pages * lease->page_size);
    unlock_capacity(lease);
    return ACTQL_OWNED_OK;
}

/* Trusted same-original supplier only, before the first payload allocation.
 * Failed selection is consumed too. Freeing an extent never changes this
 * ceiling or discharges the mapping, domain, loan or descriptor responsibility. */
int actql_native_owned_bound_allocations(actql_owned_capacity *lease,
                                        size_t bytes) {
    if (lease == NULL || current_capacity != lease || current_depth == 0 ||
        foreign_domain_process(lease)) return ACTQL_OWNED_INVALID;
    lock_capacity(lease);
    int status = ACTQL_OWNED_INVALID;
    if (!lease->allocation_ceiling_attempted && lease->extent_domain &&
        lease->domain_origin_pid == getpid() && lease->transferred &&
        !lease->closing && !foreign_domain_process(lease)) {
        lease->allocation_ceiling_attempted = true;
        lease->allocation_ceiling_pages = lease->control_pages;
        if (bytes != 0 && bytes % lease->page_size == 0 &&
            bytes <= lease->length && bytes / lease->page_size > lease->control_pages &&
            lease->occupied_pages == lease->control_pages &&
            lease->peak_occupied_pages == lease->control_pages) {
            lease->allocation_ceiling_pages = bytes / lease->page_size;
            status = ACTQL_OWNED_OK;
        }
    }
    unlock_capacity(lease);
    return status;
}

int actql_native_owned_rounded_bytes(actql_owned_capacity *lease, size_t bytes,
                                    uint64_t *out) {
    if (lease == NULL || out == NULL || *out != 0) return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    size_t pages = 0;
    int status = ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) {
        status = ACTQL_OWNED_BUSY;
    } else if (round_pages(bytes, lease->page_size, &pages) && pages <= lease->page_count) {
        *out = (uint64_t)(pages * lease->page_size);
        status = ACTQL_OWNED_OK;
    }
    unlock_capacity(lease);
    return status;
}

int actql_native_owned_domain_matches_view(actql_owned_capacity *lease,
    const actql_owned_extent_view *view, int64_t original_process) {
    if (lease == NULL || view == NULL || original_process != (int64_t)getpid() ||
        !view->domain_live || !view->map_confirmed || view->mapping == NULL ||
        lease != (void *)((unsigned char *)view->mapping + view->payload_offset) ||
        !lease->extent_domain ||
        (view->local_loan == NULL ? !lease->fd_backed :
            (lease->fd_backed || view->original != view ||
             view->local_loan->original != view->local_loan ||
             view->local_loan->returned || !view->local_loan->local_view_live ||
             view->local_loan->local_process != (int64_t)getpid() ||
             view->mapping != (unsigned char *)view->local_loan->owner +
                                  view->local_loan->extent.offset)) ||
        lease->domain_origin_pid != original_process ||
        lease->generation != view->extent.generation ||
        lease->backing_device != view->extent.device ||
        lease->backing_inode != view->extent.inode ||
        lease->length != view->payload_length ||
        memcmp(lease->recipe, view->extent.recipe, 32) != 0)
        return ACTQL_OWNED_INVALID;
    return ACTQL_OWNED_OK;
}

int actql_native_owned_domain_has_child(actql_owned_capacity *lease,
    int64_t original_process, int64_t child_process) {
    if (lease == NULL || original_process != (int64_t)getpid() ||
        child_process <= 0 || child_process > INT32_MAX ||
        !lease->extent_domain || !lease->transferred ||
        lease->domain_origin_pid != original_process ||
        atomic_load_explicit(&lease->domain_borrower_pid, memory_order_acquire) != (int)child_process)
        return ACTQL_OWNED_INVALID;
    /* Do not take a child's possibly abandoned allocator lock here. */
    return ACTQL_OWNED_OK;
}

int actql_native_owned_domain_returned(actql_owned_capacity *lease,
    const actql_owned_extent_view *view) {
    if (current_capacity != NULL || view == NULL || view->domain_borrowed ||
        actql_native_owned_domain_matches_view(lease, view,
            (int64_t)getpid()) != ACTQL_OWNED_OK)
        return ACTQL_OWNED_INVALID;
    return atomic_load_explicit(&lease->domain_borrower_pid, memory_order_acquire) == 0 &&
        lease->domain_borrow_attempted && lease->closing
        ? ACTQL_OWNED_OK : ACTQL_OWNED_BUSY;
}

/* Existing generic placement, called under the original capacity lock. */
static int allocate_storage_locked(actql_owned_capacity *lease, size_t bytes,
                           size_t alignment, void **out, bool domain_storage) {
    size_t pages;
    if (!round_pages(bytes, lease->page_size, &pages)) return ACTQL_OWNED_INVALID;
    size_t clear_pages = pages;
    if (domain_storage &&
        (pages > (SIZE_MAX - sizeof(*lease)) / sizeof(struct extent) ||
         !round_pages(sizeof(*lease) + pages * sizeof(struct extent),
                      lease->page_size, &clear_pages) || clear_pages >= pages))
        return ACTQL_OWNED_INVALID;
    if (lease->first_free_page < lease->control_pages ||
        lease->first_free_page > lease->page_count) {
        return ACTQL_OWNED_INVALID;
    }
    if (lease->occupied_pages > lease->allocation_ceiling_pages ||
        pages > lease->allocation_ceiling_pages - lease->occupied_pages)
        return ACTQL_OWNED_EXHAUSTED;
    int status = ACTQL_OWNED_EXHAUSTED;
    size_t start = lease->first_free_page;
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
        if (lease->occupied_pages > lease->page_count ||
            pages > lease->page_count - lease->occupied_pages)
            return ACTQL_OWNED_INVALID;
        void *base = (void *)address;
        size_t length = pages * lease->page_size;
        if (mprotect(base, length, PROT_READ | PROT_WRITE) != 0) {
            status = ACTQL_OWNED_PHYSICAL_FAILURE;
            break;
        }
        /* Only the private domain path withholds its payload from all generic
         * consumers. Every generic allocation still clears its full extent. */
        size_t cleared = clear_pages * lease->page_size;
        memset(base, 0, cleared);
        const uint64_t work[3] = {1, length, cleared};
        for (size_t i = 0; i < 3; i++) {
            if (lease->extent_work[i] > UINT64_MAX - work[i])
                lease->extent_work_overflow = true;
            else lease->extent_work[i] += work[i];
        }
        lease->extents[start].pages = pages;
        lease->extents[start].retired = false;
        lease->extents[start].domain_storage = domain_storage;
        lease->occupied_pages += pages;
        if (lease->occupied_pages > lease->peak_occupied_pages)
            lease->peak_occupied_pages = lease->occupied_pages;
        for (size_t i = 1; i < pages; i++) lease->extents[start + i].pages = SIZE_MAX;
        /* Preserve first-fit, including earlier holes skipped for alignment or
         * size. Only a consumed first free page advances this cached prefix. */
        if (start == lease->first_free_page) {
            size_t next = start + pages;
            while (next < lease->page_count && lease->extents[next].pages != 0)
                next++;
            lease->first_free_page = next;
        }
        *out = base;
        status = ACTQL_OWNED_OK;
        break;
    }
    return status;
}

static int allocate_locked(actql_owned_capacity *lease, size_t bytes,
                           size_t alignment, void **out) {
    return allocate_storage_locked(lease, bytes, alignment, out, false);
}

int actql_native_owned_allocate(actql_owned_capacity *lease, size_t bytes,
                         size_t alignment, void **out) {
    if (lease == NULL || out == NULL || *out != NULL || alignment == 0 ||
        (alignment & (alignment - 1)) != 0) return ACTQL_OWNED_INVALID;
    size_t pages;
    if (!round_pages(bytes, lease->page_size, &pages)) return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    if (foreign_domain_process(lease) || lease->closing) {
        unlock_capacity(lease);
        return ACTQL_OWNED_BUSY;
    }
    int status = allocate_locked(lease, bytes, alignment, out);
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
           lease->extents[*start].pages != SIZE_MAX && lease->extents[*start].rust_class == 0;
}

/* Parent-local physical guards cover every page in this original allocation.
 * Interior page records retain their own external use counts. */
static bool allocation_has_external_use(actql_owned_capacity *lease, size_t start,
                                         bool writers_only) {
    size_t pages = lease->extents[start].pages;
    for (size_t i = 0; i < pages; i++) {
        struct extent *page = &lease->extents[start + i];
        if (page->external_writer || (!writers_only && page->external_readers != 0))
            return true;
    }
    return false;
}

int actql_native_owned_capacity_bytes(actql_owned_capacity *lease, uint64_t *out) {
    if (lease == NULL || out == NULL || *out != 0) return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    /* Closing is not released. A failed final unmap still owns the full region. */
    if (foreign_domain_process(lease)) {
        unlock_capacity(lease);
        return ACTQL_OWNED_BUSY;
    }
    *out = (uint64_t)lease->length;
    unlock_capacity(lease);
    return ACTQL_OWNED_OK;
}

int actql_native_owned_contains_live_span(actql_owned_capacity *lease,
                                         const void *address, size_t bytes) {
    if (lease == NULL || address == NULL || bytes == 0 ||
        actql_native_owned_current() != lease) return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    int status = ACTQL_OWNED_INVALID;
    uintptr_t value = (uintptr_t)address;
    uintptr_t base = (uintptr_t)lease;
    if (foreign_domain_process(lease) || lease->closing || !lease->transferred) goto done;
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
    if (pages == 0 || pages == SIZE_MAX || lease->extents[start].rust_class != 0 ||
        lease->extents[start].domain_storage ||
        lease->extents[start].retired ||
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
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    size_t start;
    int status = ACTQL_OWNED_INVALID;
    if (!foreign_domain_process(lease) && allocation_start(lease, allocation, &start) &&
        !lease->extents[start].domain_storage && !lease->extents[start].retired) {
        if (allocation_has_external_use(lease, start, false) ||
            (lease->fd_backed && lease->extents[start].sealed && protection != PROT_READ)) {
            unlock_capacity(lease);
            return ACTQL_OWNED_BUSY;
        }
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
    if (pages > lease->occupied_pages ||
        lease->occupied_pages - pages < lease->control_pages)
        return ACTQL_OWNED_INVALID;
    if (mprotect(base, pages * lease->page_size, PROT_NONE) != 0)
        return ACTQL_OWNED_PHYSICAL_FAILURE;
    const uint64_t work[2] = {1, pages * lease->page_size};
    for (size_t i = 0; i < 2; i++) {
        if (lease->extent_work[i + 3] > UINT64_MAX - work[i])
            lease->extent_work_overflow = true;
        else lease->extent_work[i + 3] += work[i];
    }
    lease->occupied_pages -= pages;
    memset(&lease->extents[start], 0, pages * sizeof(struct extent));
    /* Failed retirement never publishes free storage. Only the same confirmed
     * physical cleanup makes this earlier hole eligible for first-fit reuse. */
    if (start < lease->first_free_page) lease->first_free_page = start;
    return ACTQL_OWNED_OK;
}

int actql_native_owned_extent_work(actql_owned_capacity *lease, uint64_t *out,
                                   size_t count) {
    if (lease == NULL || out == NULL || count != 5 ||
        current_capacity != lease || current_process != getpid())
        return ACTQL_OWNED_INVALID;
    for (size_t i = 0; i < count; i++)
        if (out[i] != 0) return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    int status = ACTQL_OWNED_INVALID;
    if (!foreign_domain_process(lease) && lease->transferred &&
        !lease->extent_work_overflow) {
        memcpy(out, lease->extent_work, sizeof(lease->extent_work));
        status = ACTQL_OWNED_OK;
    }
    unlock_capacity(lease);
    return status;
}

int actql_native_owned_seal_readonly(actql_owned_capacity *lease, void *allocation) {
    if (lease == NULL) return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    size_t start;
    int status = ACTQL_OWNED_INVALID;
    if (!foreign_domain_process(lease) && allocation_start(lease, allocation, &start) &&
        !lease->extents[start].domain_storage && !lease->extents[start].retired) {
        if (allocation_has_external_use(lease, start, true)) {
            unlock_capacity(lease);
            return ACTQL_OWNED_BUSY;
        }
        size_t bytes = lease->extents[start].pages * lease->page_size;
        status = mprotect(allocation, bytes, PROT_READ) == 0
                     ? ACTQL_OWNED_OK : ACTQL_OWNED_PHYSICAL_FAILURE;
        if (status == ACTQL_OWNED_OK) lease->extents[start].sealed = true;
    }
    unlock_capacity(lease);
    return status;
}

int actql_native_owned_retire(actql_owned_capacity *lease, void *allocation) {
    if (lease == NULL) return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    size_t start;
    int status = ACTQL_OWNED_INVALID;
    if (!foreign_domain_process(lease) && allocation_start(lease, allocation, &start)) {
        if (allocation_has_external_use(lease, start, false)) {
            unlock_capacity(lease);
            return ACTQL_OWNED_BUSY;
        }
        lease->extents[start].retired = true;
        status = clean_retired(lease, start);
    }
    unlock_capacity(lease);
    return status;
}

#if defined(__APPLE__)
#include "owned_rust_heap.inc"
#endif

static int prepare_capacity_close_locked(actql_owned_capacity *lease) {
    if (lease->active_scopes != 0) {
        return ACTQL_OWNED_BUSY;
    }
    lease->closing = true;
    for (size_t i = lease->control_pages; i < lease->page_count; i++) {
        if (lease->extents[i].pages == 0) continue;
        if (lease->extents[i].pages == SIZE_MAX || !lease->extents[i].retired) {
            return ACTQL_OWNED_BUSY;
        }
        int status = clean_retired(lease, i);
        if (status != ACTQL_OWNED_OK) {
            return status;
        }
    }
    return ACTQL_OWNED_OK;
}

int actql_native_owned_try_close(actql_owned_capacity **slot) {
    if (slot == NULL) return ACTQL_OWNED_INVALID;
    actql_owned_capacity *lease = *slot;
    if (lease == NULL) return ACTQL_OWNED_OK;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    /* An interior domain is retired through its original view, never munmap. */
    if (lease->extent_domain) return ACTQL_OWNED_INVALID;
    /* The original owner must exclude concurrent callers before final close. */
    lock_capacity(lease);
    int prepared = prepare_capacity_close_locked(lease);
    if (prepared != ACTQL_OWNED_OK) {
        unlock_capacity(lease);
        return prepared;
    }
    size_t length = lease->length;
    if (munmap(lease, length) != 0) {
        unlock_capacity(lease);
        return ACTQL_OWNED_PHYSICAL_FAILURE;
    }
    *slot = NULL;
    return ACTQL_OWNED_OK;
}

/* Included once. Child views exclude the parent's control table; an adopted
 * domain borrow uses only its original interior relative allocator records. */
#include "owned_region.inc"
#include "owned_domain_borrow.inc"

/* Child startup and join reuse this provider's original scope and backing. */
#include "owned_thread.inc"
