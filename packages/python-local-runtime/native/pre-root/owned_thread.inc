/* Included once in the SAME capacity/TLS provider; never another allocator. */
#include "owned_thread.h"
#include <pthread.h>
#include <sched.h>
#include <stdalign.h>

struct actql_owned_thread_control {
    struct actql_owned_thread_control *original;
    actql_owned_capacity *owner;
    pid_t origin_pid;
    pthread_t thread;
    struct owned_scope_state scope;
    atomic_int attached;
    actql_owned_thread_entry entry;
    void *argument;
    atomic_int launch;
    bool join_attempted;
    bool joined;
    bool pinned;
};

size_t actql_native_owned_thread_control_bytes(void) {
    return sizeof(struct actql_owned_thread_control);
}

size_t actql_native_owned_thread_control_alignment(void) {
    return alignof(struct actql_owned_thread_control);
}

/* Physical range validation only. Unlike the Guest span port this does not
 * require Core transfer: the maintainer compiler also has an unbound original.
 * Read the control record ONLY after proving its allocation remains accessible.
 * The caller must exclude storage retirement while start/join is in progress. */
static bool thread_storage_locked(actql_owned_capacity *lease, void *storage) {
    size_t offset;
    if (!owned_pointer_offset(lease, storage, &offset) ||
        (uintptr_t)storage % alignof(struct actql_owned_thread_control) != 0) return false;
    size_t start = offset / lease->page_size;
    if (owned_control_page(lease, start)) return false;
    while (start > lease->control_pages && owned_extent(lease, start)->pages == SIZE_MAX) start--;
    size_t pages = owned_extent(lease, start)->pages;
    if (pages == 0 || pages == SIZE_MAX || owned_extent(lease, start)->retired ||
        pages > lease->page_count - start) return false;
    size_t begin = start * lease->page_size, length = pages * lease->page_size;
    return offset >= begin && offset - begin < length &&
        sizeof(struct actql_owned_thread_control) <= length - (offset - begin);
}

/* Darwin clears a key immediately before its destructor, including a NULL
 * destructor. Restore this same alias on every destructor pass so other Rust/C
 * TLS destructors continue to see the SAME original scope. No alias is freed or
 * pin released here; join is the only successful child-retirement observation.
 * This provider/key must outlive all such callbacks in process/runtime custody. */
static void restore_owned_scope(void *scope) {
    if (pthread_setspecific(owned_scope_key, scope) != 0) __builtin_trap();
}
static void initialize_owned_scope_key(void) {
    owned_scope_key_status = pthread_key_create(&owned_scope_key, restore_owned_scope);
    if (owned_scope_key_status == 0)
        atomic_store_explicit(&owned_scope_key_ready, true, memory_order_release);
}

static void *owned_thread_entry(void *argument) {
    struct actql_owned_thread_control *record = argument;
    /* Publish native thread identity before permitting callback/self-join.
     * The already retained original pin covers this pre-bootstrap interval. */
    while (atomic_load_explicit(&record->launch, memory_order_acquire) == 0) sched_yield();
    if (pthread_setspecific(owned_scope_key, &record->scope) != 0) {
        /* No callback/Rust bootstrap ran. The created child's original pin and
         * controller still require confirmed join; no parent-side unpin here. */
        atomic_store_explicit(&record->attached, 2, memory_order_release);
        return NULL;
    }
    atomic_store_explicit(&record->attached, 1, memory_order_release);
    record->entry(record->argument);
    /* Deliberately keep the SAME TLS through pthread_exit/TSD destructors.
     * Only the original joiner retires this pin AFTER pthread_join succeeds. */
    return NULL;
}

static int owned_thread_start(actql_owned_capacity *lease, void *storage,
    size_t storage_bytes, const pthread_attr_t *attributes,
    actql_owned_thread_entry entry, void *argument) {
    if (lease == NULL || storage == NULL || entry == NULL ||
        storage_bytes != sizeof(struct actql_owned_thread_control) ||
        current_capacity != lease || current_depth == 0 || current_process != getpid())
        return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    if (lease->closing || lease->active_scopes == SIZE_MAX || foreign_domain_process(lease)) {
        unlock_capacity(lease);
        return ACTQL_OWNED_BUSY;
    }
    if (!thread_storage_locked(lease, storage)) {
        unlock_capacity(lease);
        return ACTQL_OWNED_INVALID;
    }
    struct actql_owned_thread_control *record = storage;
    const unsigned char *bytes = storage;
    for (size_t i = 0; i < sizeof(*record); i++) {
        if (bytes[i] != 0) {
            unlock_capacity(lease);
            return ACTQL_OWNED_INVALID;
        }
    }
    record->original = record;
    record->owner = lease;
    record->origin_pid = getpid();
    record->entry = entry;
    record->argument = argument;
    record->scope = (struct owned_scope_state){lease, 1, 1, getpid()};
    atomic_init(&record->launch, 0);
    atomic_init(&record->attached, 0);
    record->pinned = true;
    lease->active_scopes++;
    unlock_capacity(lease);
    int status = pthread_once(&owned_scope_key_once, initialize_owned_scope_key);
    if (status == 0) status = owned_scope_key_status;
    if (status == 0) status = pthread_create(&record->thread, attributes, owned_thread_entry, record);
    if (status != 0) {
        /* POSIX failure creates no thread. Keep a non-reusable refusal record;
         * return only this confirmed-not-started pin, never an uncertain child. */
        lock_capacity(lease);
        record->pinned = false;
        record->joined = true;
        lease->active_scopes--;
        atomic_store_explicit(&record->launch, 2, memory_order_release);
        unlock_capacity(lease);
        return ACTQL_OWNED_PHYSICAL_FAILURE;
    }
    atomic_store_explicit(&record->launch, 1, memory_order_release);
    int attached;
    while ((attached = atomic_load_explicit(&record->attached, memory_order_acquire)) == 0) sched_yield();
    return attached == 1 ? ACTQL_OWNED_OK : ACTQL_OWNED_PHYSICAL_FAILURE;
}

int actql_native_owned_thread_start(actql_owned_capacity *lease, void *storage,
    size_t storage_bytes, actql_owned_thread_entry entry, void *argument) {
    return owned_thread_start(lease, storage, storage_bytes, NULL, entry, argument);
}
int actql_native_owned_thread_start_configured(actql_owned_capacity *lease, void *storage,
    size_t storage_bytes, const void *attributes,
    actql_owned_thread_entry entry, void *argument) {
    if (attributes == NULL) return ACTQL_OWNED_INVALID;
    return owned_thread_start(lease, storage, storage_bytes, attributes, entry, argument);
}

int actql_native_owned_thread_join(actql_owned_capacity *lease, void *storage) {
    if (lease == NULL || storage == NULL ||
        (current_process != 0 && current_process != getpid())) return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    if (!thread_storage_locked(lease, storage)) {
        unlock_capacity(lease);
        return ACTQL_OWNED_INVALID;
    }
    struct actql_owned_thread_control *record = storage;
    if (record->original != record || record->owner != lease || record->origin_pid != getpid() ||
        atomic_load_explicit(&record->launch, memory_order_acquire) == 0) {
        unlock_capacity(lease);
        return ACTQL_OWNED_INVALID;
    }
    if (atomic_load_explicit(&record->launch, memory_order_acquire) == 2) {
        /* Confirmed no child was created; no pthread identity may be consumed. */
        unlock_capacity(lease);
        return ACTQL_OWNED_OK;
    }
    /* Reject self-join before observing another joiner's in-flight attempt. */
    if (pthread_equal(pthread_self(), record->thread)) {
        unlock_capacity(lease);
        return ACTQL_OWNED_INVALID;
    }
    if (record->joined) {
        unlock_capacity(lease);
        return ACTQL_OWNED_OK;
    }
    if (record->join_attempted) {
        unlock_capacity(lease);
        return ACTQL_OWNED_BUSY;
    }
    record->join_attempted = true;
    unlock_capacity(lease);
    if (pthread_join(record->thread, NULL) != 0) return ACTQL_OWNED_PHYSICAL_FAILURE;
    lock_capacity(lease);
    record->joined = true;
    if (record->pinned) {
        record->pinned = false;
        lease->active_scopes--;
    }
    unlock_capacity(lease);
    return ACTQL_OWNED_OK;
}
