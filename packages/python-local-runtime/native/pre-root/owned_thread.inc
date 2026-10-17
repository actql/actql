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
    uintptr_t base = (uintptr_t)lease, address = (uintptr_t)storage;
    if (address < base || address - base >= lease->length ||
        address % alignof(struct actql_owned_thread_control) != 0) return false;
    size_t offset = (size_t)(address - base), start = offset / lease->page_size;
    if (start < lease->control_pages) return false;
    while (start > lease->control_pages && lease->extents[start].pages == SIZE_MAX) start--;
    size_t pages = lease->extents[start].pages;
    if (pages == 0 || pages == SIZE_MAX || lease->extents[start].retired ||
        pages > lease->page_count - start) return false;
    size_t begin = start * lease->page_size, length = pages * lease->page_size;
    return offset >= begin && offset - begin < length &&
        sizeof(struct actql_owned_thread_control) <= length - (offset - begin);
}

static void *owned_thread_entry(void *argument) {
    struct actql_owned_thread_control *record = argument;
    /* Publish native thread identity before permitting callback/self-join.
     * The already retained original pin covers this pre-bootstrap interval. */
    while (atomic_load_explicit(&record->launch, memory_order_acquire) == 0) sched_yield();
    current_capacity = record->owner;
    current_depth = 1;
    current_process = getpid();
    current_floor = 1;
    record->entry(record->argument);
    /* Deliberately keep the SAME TLS through pthread_exit/TSD destructors.
     * Only the original joiner retires this pin AFTER pthread_join succeeds. */
    return NULL;
}

int actql_native_owned_thread_start(actql_owned_capacity *lease, void *storage,
    size_t storage_bytes, actql_owned_thread_entry entry, void *argument) {
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
    atomic_init(&record->launch, 0);
    record->pinned = true;
    lease->active_scopes++;
    unlock_capacity(lease);
    int status = pthread_create(&record->thread, NULL, owned_thread_entry, record);
    if (status != 0) {
        /* POSIX failure creates no thread. Keep a non-reusable refusal record;
         * return only this confirmed-not-started pin, never an uncertain child. */
        lock_capacity(lease);
        record->pinned = false;
        lease->active_scopes--;
        atomic_store_explicit(&record->launch, 2, memory_order_release);
        unlock_capacity(lease);
        return ACTQL_OWNED_PHYSICAL_FAILURE;
    }
    atomic_store_explicit(&record->launch, 1, memory_order_release);
    return ACTQL_OWNED_OK;
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
        atomic_load_explicit(&record->launch, memory_order_acquire) != 1) {
        unlock_capacity(lease);
        return ACTQL_OWNED_INVALID;
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
