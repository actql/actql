#if defined(ACTQL_NATIVE_OWNED_LINUX_X64_PROCESS_DOMAIN)
/* Explicit process-only profile; the same POSIX implementation below owns
 * mappings, original loans, current scopes and child-first retirement. */
#include "owned_linux_x64_process_profile.h"
#elif defined(__linux__) && defined(__x86_64__) && \
      defined(ACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY)
/* Separate selected command entry; the default process-only exclusion above
 * remains unchanged. The same owned region and Read implementation follow. */
#include "owned_linux_x64_bundle_profile.h"
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

/* Each appended mapping belongs to the SAME capacity and lock. Its control
 * records live in the mapping they describe; neither a heap index nor another
 * capacity owner is introduced. Logical page indices never change. */
struct owned_segment {
    struct owned_segment *next;
    /* NULL for an owned root mapping. A child segment retains this exact
     * caller-funded view until domain retirement; its loan is not returned. */
    actql_owned_extent_view *borrowed_view;
    size_t first_page;
    size_t page_count;
    size_t control_pages;
    struct extent extents[];
};

struct owned_growth_receipt;
/* Fixed structural control, owned by the initial domain's actual header pages.
 * It is never a grant, another capacity or a replaceable transaction carrier. */
struct owned_domain_growth {
    actql_owned_capacity *parent;
    actql_owned_extent_view *original_view;
    struct owned_growth_receipt *receipts;
    struct owned_growth_receipt *pending;
    uint64_t serial;
    size_t expected_parent, expected_domain;
    size_t parent_bytes, parent_controls, domain_bytes, domain_controls;
    size_t ceiling_before;
    bool expand_read_bound;
    unsigned state, outcome;
};

struct actql_owned_capacity {
    size_t length;
    size_t page_size;
    size_t page_count;
    size_t control_pages;
    size_t original_page_count;
    struct owned_segment *segments;
    actql_owned_capacity *pending_growth_domain;
    struct owned_domain_growth growth;
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
    size_t allocation_maximum_pages;
    bool allocation_ceiling_attempted;
    bool allocation_working_bound;
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

/* These helpers are called under the original lock, or while the original
 * owner already excludes mutation. A physical span never crosses mappings. */
static struct owned_segment *owned_segment_at(actql_owned_capacity *lease,
                                               size_t page) {
    for (struct owned_segment *segment = lease->segments; segment; segment = segment->next)
        if (page >= segment->first_page && page - segment->first_page < segment->page_count)
            return segment;
    return NULL;
}

static struct extent *owned_extent(actql_owned_capacity *lease, size_t page) {
    if (page < lease->original_page_count) return &lease->extents[page];
    struct owned_segment *segment = owned_segment_at(lease, page);
    return segment == NULL ? NULL : &segment->extents[page - segment->first_page];
}

static void *owned_page_address(actql_owned_capacity *lease, size_t page) {
    if (page < lease->original_page_count)
        return (unsigned char *)lease + page * lease->page_size;
    struct owned_segment *segment = owned_segment_at(lease, page);
    return segment == NULL ? NULL : (unsigned char *)segment +
        (page - segment->first_page) * lease->page_size;
}

static bool owned_pointer_offset(actql_owned_capacity *lease, const void *pointer,
                                   size_t *offset) {
    uintptr_t value = (uintptr_t)pointer, base = (uintptr_t)lease;
    size_t bytes = lease->original_page_count * lease->page_size;
    if (value >= base && value - base < bytes) {
        *offset = value - base;
        return true;
    }
    for (struct owned_segment *segment = lease->segments; segment; segment = segment->next) {
        base = (uintptr_t)segment;
        bytes = segment->page_count * lease->page_size;
        if (value >= base && value - base < bytes) {
            *offset = segment->first_page * lease->page_size + value - base;
            return true;
        }
    }
    return false;
}

static bool owned_control_page(actql_owned_capacity *lease, size_t page) {
    if (page < lease->original_page_count) return page < lease->control_pages;
    struct owned_segment *segment = owned_segment_at(lease, page);
    return segment == NULL || page - segment->first_page < segment->control_pages;
}

static size_t owned_control_pages(actql_owned_capacity *lease) {
    size_t pages = lease->control_pages;
    for (struct owned_segment *segment = lease->segments; segment; segment = segment->next)
        pages += segment->control_pages;
    return pages;
}

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
    lease->page_count = lease->original_page_count = count;
    lease->control_pages = control_pages;
    lease->first_free_page = control_pages;
    lease->occupied_pages = lease->peak_occupied_pages = control_pages;
    lease->allocation_ceiling_pages = count;
    lease->allocation_maximum_pages = count;
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

/* Layout data only, used to reserve the new segment's own controls before
 * acquisition. A quote neither acquires pages nor authorizes a constructor. */
static bool owned_growth_layout_extra(actql_owned_capacity *lease, size_t bytes,
    size_t extra, size_t *count, size_t *controls) {
    if (bytes == 0 || bytes % lease->page_size != 0 || bytes > PTRDIFF_MAX)
        return false;
    *count = bytes / lease->page_size;
    if (extra > SIZE_MAX - sizeof(struct owned_segment)) return false;
    size_t header = sizeof(struct owned_segment) + extra;
    return *count <= (SIZE_MAX - header) / sizeof(struct extent) &&
        round_pages(header + *count * sizeof(struct extent),
                     lease->page_size, controls) && *controls < *count;
}

static bool owned_growth_layout(actql_owned_capacity *lease, size_t bytes,
                                 size_t *count, size_t *controls) {
    return owned_growth_layout_extra(lease, bytes, 0, count, controls);
}

int actql_native_owned_growth_control_bytes(actql_owned_capacity *lease,
    size_t bytes, uint64_t *out) {
    if (lease == NULL || out == NULL || *out != 0) return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    size_t count, controls;
    int status = ACTQL_OWNED_INVALID;
    if (!foreign_domain_process(lease) && owned_growth_layout(lease, bytes, &count, &controls)) {
        *out = controls * lease->page_size;
        status = ACTQL_OWNED_OK;
    }
    unlock_capacity(lease);
    return status;
}

/* Explicit physical acquisition only. The trusted Resource owner must reserve
 * this exact addition on its existing ledger before calling. No allocator or
 * constructor calls this port implicitly, and no free-memory estimate is used.
 * expected_bytes fences a retry after a lost result without issuing a serial. */
static int grow_capacity_locked(actql_owned_capacity *lease, size_t expected_bytes,
    size_t additional_bytes, size_t extra_controls, uint64_t *control_bytes) {
    int status = ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease) || lease->closing) {
        status = ACTQL_OWNED_BUSY;
        goto done;
    }
    /* An FD mapping and a carved child have independently bounded original
     * loans/views. They cannot gain out-of-view backing through this root port. */
    if (!lease->transferred || lease->fd_backed || lease->extent_domain ||
        lease->allocation_ceiling_attempted || expected_bytes != lease->length ||
        additional_bytes == 0 || additional_bytes % lease->page_size != 0 ||
        additional_bytes > PTRDIFF_MAX - lease->length) goto done;
    size_t count, controls;
    if (!owned_growth_layout_extra(lease, additional_bytes, extra_controls, &count, &controls)) goto done;
    void *mapping = mmap(NULL, additional_bytes, PROT_READ | PROT_WRITE,
                         MAP_PRIVATE | MAP_ANON, -1, 0);
    if (mapping == MAP_FAILED) {
        status = ACTQL_OWNED_PHYSICAL_FAILURE;
        goto done;
    }
    /* No fallible operation follows acquisition. All new control records are
     * carried by these owned pages and publication is one locked transition. */
    struct owned_segment *segment = mapping;
    segment->next = lease->segments;
    segment->first_page = lease->page_count;
    segment->page_count = count;
    segment->control_pages = controls;
    for (size_t i = 0; i < controls; i++) segment->extents[i].pages = SIZE_MAX;
    lease->segments = segment;
    lease->page_count += count;
    lease->length += additional_bytes;
    lease->allocation_ceiling_pages += count;
    lease->allocation_maximum_pages += count;
    lease->occupied_pages += controls;
    if (lease->occupied_pages > lease->peak_occupied_pages)
        lease->peak_occupied_pages = lease->occupied_pages;
    *control_bytes = controls * lease->page_size;
    status = ACTQL_OWNED_OK;
done:
    return status;
}

int actql_native_owned_grow(actql_owned_capacity *lease, size_t expected_bytes,
                            size_t additional_bytes, uint64_t *control_bytes) {
    if (lease == NULL || control_bytes == NULL || *control_bytes != 0 ||
        current_capacity != lease || current_process != getpid())
        return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    int status = lease->pending_growth_domain != NULL ? ACTQL_OWNED_BUSY :
        grow_capacity_locked(lease, expected_bytes, additional_bytes, 0, control_bytes);
    unlock_capacity(lease);
    return status;
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
    *out = (uint64_t)(owned_control_pages(lease) * lease->page_size);
    unlock_capacity(lease);
    return ACTQL_OWNED_OK;
}

/* Trusted same-original supplier only, before the first payload allocation.
 * Failed selection is consumed too. Freeing an extent never changes this
 * ceiling or discharges the mapping, domain, loan or descriptor responsibility. */
static int bound_allocations_original(actql_owned_capacity *lease,
    size_t initial_bytes, size_t maximum_bytes, bool working) {
    if (lease == NULL || current_capacity != lease || current_depth == 0 ||
        foreign_domain_process(lease)) return ACTQL_OWNED_INVALID;
    lock_capacity(lease);
    int status = ACTQL_OWNED_INVALID;
    if (!lease->allocation_ceiling_attempted && lease->extent_domain &&
        lease->domain_origin_pid == getpid() && lease->transferred &&
        !lease->closing && !foreign_domain_process(lease)) {
        lease->allocation_ceiling_attempted = true;
        lease->allocation_ceiling_pages = lease->control_pages;
        lease->allocation_maximum_pages = lease->control_pages;
        if (initial_bytes != 0 && initial_bytes % lease->page_size == 0 &&
            maximum_bytes >= initial_bytes && maximum_bytes <= PTRDIFF_MAX &&
            maximum_bytes % lease->page_size == 0 && initial_bytes <= lease->length &&
            initial_bytes / lease->page_size > lease->control_pages &&
            lease->occupied_pages == lease->control_pages &&
            lease->peak_occupied_pages == lease->control_pages) {
            lease->allocation_ceiling_pages = initial_bytes / lease->page_size;
            lease->allocation_maximum_pages = maximum_bytes / lease->page_size;
            lease->allocation_working_bound = working;
            status = ACTQL_OWNED_OK;
        }
    }
    unlock_capacity(lease);
    return status;
}

int actql_native_owned_bound_allocations(actql_owned_capacity *lease, size_t bytes) {
    return bound_allocations_original(lease, bytes, bytes, false);
}

/* Same immutable selected maximum, smaller actually backed initial prefix.
 * Selection creates no mapping or semantic allowance. Only checked acquisition
 * can extend the current bound, and never beyond this original maximum. */
int actql_native_owned_bound_working_allocations(actql_owned_capacity *lease,
    size_t initial_bytes, size_t maximum_bytes) {
    return bound_allocations_original(lease, initial_bytes, maximum_bytes, true);
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
             view->mapping != owned_page_address(view->local_loan->owner,
                                                view->local_loan->start))) ||
        lease->domain_origin_pid != original_process ||
        lease->generation != view->extent.generation ||
        lease->backing_device != view->extent.device ||
        lease->backing_inode != view->extent.inode ||
        lease->original_page_count * lease->page_size != view->payload_length ||
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

/* Publish exact placement in the existing extent table. Private growth must
 * retain its candidate even when page activation returns an uncertain result. */
static void publish_storage_locked(actql_owned_capacity *lease, size_t start,
    size_t pages, bool domain_storage) {
    owned_extent(lease, start)->pages = pages;
    owned_extent(lease, start)->retired = false;
    owned_extent(lease, start)->domain_storage = domain_storage;
    lease->occupied_pages += pages;
    if (lease->occupied_pages > lease->peak_occupied_pages)
        lease->peak_occupied_pages = lease->occupied_pages;
    for (size_t i = 1; i < pages; i++) owned_extent(lease, start + i)->pages = SIZE_MAX;
    /* Preserve first-fit, including earlier holes skipped for alignment or
     * size. Only a consumed first free page advances this cached prefix. */
    if (start == lease->first_free_page) {
        size_t next = start + pages;
        while (next < lease->page_count && owned_extent(lease, next)->pages != 0)
            next++;
        lease->first_free_page = next;
    }
}

/* Existing generic placement, called under the original capacity lock. */
static int allocate_storage_original_locked(actql_owned_capacity *lease, size_t bytes,
    size_t alignment, void **out, bool domain_storage, actql_owned_capacity *growth) {
    if (lease->pending_growth_domain != growth) return ACTQL_OWNED_BUSY;
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
        uintptr_t address = (uintptr_t)owned_page_address(lease, start);
        if (address % alignment != 0 || owned_extent(lease, start)->pages != 0) {
            start++;
            continue;
        }
        size_t used = 0;
        while (used < pages && owned_extent(lease, start + used)->pages == 0) used++;
        if (used != pages) {
            start += used + 1;
            continue;
        }
        if (lease->occupied_pages > lease->page_count ||
            pages > lease->page_count - lease->occupied_pages)
            return ACTQL_OWNED_INVALID;
        void *base = (void *)address;
        size_t length = pages * lease->page_size;
        if (growth != NULL) {
            /* This output is the same supplier receipt's cleanup custody, not
             * a successful payload grant. Its original fence excludes reuse. */
            publish_storage_locked(lease, start, pages, domain_storage);
            owned_extent(lease, start)->retired = true;
            *out = base;
        }
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
        if (growth == NULL) publish_storage_locked(lease, start, pages, domain_storage);
        else owned_extent(lease, start)->retired = false;
        *out = base;
        status = ACTQL_OWNED_OK;
        break;
    }
    return status;
}

static int allocate_storage_locked(actql_owned_capacity *lease, size_t bytes,
                           size_t alignment, void **out, bool domain_storage) {
    return allocate_storage_original_locked(lease, bytes, alignment, out, domain_storage, NULL);
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
    size_t offset;
    if (!owned_pointer_offset(lease, allocation, &offset) ||
        offset % lease->page_size != 0) return false;
    *start = offset / lease->page_size;
    return !owned_control_page(lease, *start) && owned_extent(lease, *start)->pages != 0 &&
           owned_extent(lease, *start)->pages != SIZE_MAX && owned_extent(lease, *start)->rust_class == 0;
}

/* Parent-local physical guards cover every page in this original allocation.
 * Interior page records retain their own external use counts. */
static bool allocation_has_external_use(actql_owned_capacity *lease, size_t start,
                                         bool writers_only) {
    size_t pages = owned_extent(lease, start)->pages;
    for (size_t i = 0; i < pages; i++) {
        struct extent *page = owned_extent(lease, start + i);
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
    size_t offset;
    if (foreign_domain_process(lease) || lease->closing || !lease->transferred) goto done;
    if (!owned_pointer_offset(lease, address, &offset)) goto done;
    if (bytes > lease->length - offset) goto done;
    size_t start = offset / lease->page_size;
    if (owned_control_page(lease, start)) goto done;
    /* Interior pages carry SIZE_MAX. Find this single backing extent, never
     * merge adjacent allocations or read beyond the original control table. */
    while (start > lease->control_pages && owned_extent(lease, start)->pages == SIZE_MAX)
        start--;
    size_t pages = owned_extent(lease, start)->pages;
    if (pages == 0 || pages == SIZE_MAX || owned_extent(lease, start)->rust_class != 0 ||
        owned_extent(lease, start)->domain_storage ||
        owned_extent(lease, start)->retired ||
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
        !owned_extent(lease, start)->domain_storage && !owned_extent(lease, start)->retired) {
        if (allocation_has_external_use(lease, start, false) ||
            (lease->fd_backed && owned_extent(lease, start)->sealed && protection != PROT_READ)) {
            unlock_capacity(lease);
            return ACTQL_OWNED_BUSY;
        }
        size_t bytes = owned_extent(lease, start)->pages * lease->page_size;
        if (offset <= bytes && length <= bytes - offset)
            status = mprotect((unsigned char *)allocation + offset, length, protection) == 0
                         ? ACTQL_OWNED_OK : ACTQL_OWNED_PHYSICAL_FAILURE;
    }
    unlock_capacity(lease);
    return status;
}

static int clean_retired(actql_owned_capacity *lease, size_t start) {
    size_t pages = owned_extent(lease, start)->pages;
    void *base = owned_page_address(lease, start);
    if (pages > lease->occupied_pages ||
        lease->occupied_pages - pages < owned_control_pages(lease))
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
    memset(owned_extent(lease, start), 0, pages * sizeof(struct extent));
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
        !owned_extent(lease, start)->domain_storage && !owned_extent(lease, start)->retired) {
        if (allocation_has_external_use(lease, start, true)) {
            unlock_capacity(lease);
            return ACTQL_OWNED_BUSY;
        }
        size_t bytes = owned_extent(lease, start)->pages * lease->page_size;
        status = mprotect(allocation, bytes, PROT_READ) == 0
                     ? ACTQL_OWNED_OK : ACTQL_OWNED_PHYSICAL_FAILURE;
        if (status == ACTQL_OWNED_OK) owned_extent(lease, start)->sealed = true;
    }
    unlock_capacity(lease);
    return status;
}

static int retire_allocation_locked(actql_owned_capacity *lease, void *allocation) {
    size_t start;
    if (!allocation_start(lease, allocation, &start)) return ACTQL_OWNED_INVALID;
    if (allocation_has_external_use(lease, start, false)) return ACTQL_OWNED_BUSY;
    owned_extent(lease, start)->retired = true;
    return clean_retired(lease, start);
}

int actql_native_owned_retire(actql_owned_capacity *lease, void *allocation) {
    if (lease == NULL) return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    int status = foreign_domain_process(lease) ? ACTQL_OWNED_BUSY :
        retire_allocation_locked(lease, allocation);
    unlock_capacity(lease);
    return status;
}

/* Generic, pending and heap census stays with the same physical provider. */
#include "owned_inventory.inc"

#if defined(__APPLE__)
#include "owned_rust_heap.inc"
#endif

static int prepare_capacity_close_locked(actql_owned_capacity *lease) {
    if (lease->active_scopes != 0) {
        return ACTQL_OWNED_BUSY;
    }
    lease->closing = true;
    /* First exclude every live original before reaping any failed retirement.
     * A child may still own the retry receipt for an earlier retired extent;
     * a parent close probe must not consume it then return BUSY on that child. */
    for (size_t i = lease->control_pages; i < lease->page_count; i++) {
        if (owned_control_page(lease, i) || owned_extent(lease, i)->pages == 0) continue;
        size_t pages = owned_extent(lease, i)->pages;
        if (pages == SIZE_MAX || !owned_extent(lease, i)->retired) return ACTQL_OWNED_BUSY;
        if (pages > lease->page_count - i) return ACTQL_OWNED_INVALID;
        i += pages - 1;
    }
    for (size_t i = lease->control_pages; i < lease->page_count; i++) {
        if (owned_control_page(lease, i) || owned_extent(lease, i)->pages == 0) continue;
        if (owned_extent(lease, i)->pages == SIZE_MAX || !owned_extent(lease, i)->retired) {
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
    if (lease->pending_growth_domain != NULL) return ACTQL_OWNED_BUSY;
    /* The original owner must exclude concurrent callers before final close. */
    lock_capacity(lease);
    int prepared = prepare_capacity_close_locked(lease);
    if (prepared != ACTQL_OWNED_OK) {
        unlock_capacity(lease);
        return prepared;
    }
    /* Newest segments are last in the logical page domain. Remove each only
     * after its actual unmap ACK. Failure keeps the same original and remaining
     * mappings for retry; cancellation alone never returns any backing. */
    while (lease->segments != NULL) {
        struct owned_segment *segment = lease->segments;
        struct owned_segment *next = segment->next;
        size_t pages = segment->page_count, controls = segment->control_pages;
        if (munmap(segment, pages * lease->page_size) != 0) {
            unlock_capacity(lease);
            return ACTQL_OWNED_PHYSICAL_FAILURE;
        }
        lease->segments = next;
        lease->page_count -= pages;
        lease->length -= pages * lease->page_size;
        lease->occupied_pages -= controls;
    }
    size_t length = lease->original_page_count * lease->page_size;
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
