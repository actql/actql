/* A dedicated translation unit: every upstream SQLite symbol has internal
 * linkage. No sqlite3_* symbol can resolve to the system/Python instance. */
#define _DARWIN_C_SOURCE
#define SQLITE_API static
#define SQLITE_EXTERN
#define SQLITE_OMIT_AUTOINIT 1
#define SQLITE_ZERO_MALLOC 1
#define SQLITE_ENABLE_MEMSYS5 1
#define SQLITE_OMIT_LOAD_EXTENSION 1
#define SQLITE_THREADSAFE 1
#include "sqlite3.c"
#include "component.h"
#include <limits.h>
#include "api.h"
#include "owned_capacity.h"
#include <dlfcn.h>
#include <stdalign.h>
#include <stdatomic.h>
#include <unistd.h>

/* Import the one original provider. Do not compile owned_capacity.c, construct
 * another TLS index or accept a caller-defined allocator callback table here. */
extern actql_read_context *actql_bootstrap_current_read_context(void);
extern int actql_read_context_retain(actql_read_context *);
extern int actql_read_context_release_after_owner_ack(actql_read_context *);
extern void *actql_native_file_scoped_allocate(size_t);
extern void actql_native_file_scoped_free(void *);

/* One Library binding per component lifetime, never per Run or on reopen.
 * A nonblocking physical entry fence rejects competing/reentrant operations;
 * it does not schedule calls, retry requests or issue a new Library authority.
 * These fields do not reconstruct Host, Store, current authorization or grants. */
static actql_read_context *component_context;
static _Atomic(pid_t) component_process;
static atomic_flag component_entry = ATOMIC_FLAG_INIT;
static actql_owned_capacity *component_lease;
static void *component_heap;
static int component_shutdown_ack;
static int component_attempted, component_ready, component_stopped;
static int component_retained;
static int component_api_borrowed;


/* SQLite's unix VFS deliberately logs and drops close(2) errors. The original
 * component must nevertheless retain each unconfirmed descriptor and its heap
 * backing. Reserve its carrier BEFORE open, and never retry an uncertain close
 * (including EINTR). These are original physical children, not resource credit.
 * The private unix system-call table belongs to this translation unit alone. */
typedef struct component_descriptor {
    struct component_descriptor *next;
    int descriptor;
    int close_consumed;
    int close_error;
} component_descriptor;
static component_descriptor *component_descriptors;
static sqlite3_mutex *component_descriptor_mutex;
static int component_descriptor_unknown;

static int component_open_descriptor(const char *path, int flags, int mode) {
    component_descriptor *child = sqlite3_malloc(sizeof(*child));
    if (child == NULL) { errno = ENOMEM; return -1; }
    sqlite3_mutex_enter(component_descriptor_mutex);
    if (component_descriptor_unknown) {
        sqlite3_mutex_leave(component_descriptor_mutex);
        sqlite3_free(child); errno = EIO; return -1;
    }
    int fd = posixOpen(path, flags, mode);
    int error = errno;
    if (fd >= 0) {
        *child = (component_descriptor){component_descriptors, fd, 0, 0};
        component_descriptors = child;
    }
    sqlite3_mutex_leave(component_descriptor_mutex);
    if (fd < 0) sqlite3_free(child);
    errno = error;
    return fd;
}

static int component_close_descriptor(int fd) {
    sqlite3_mutex_enter(component_descriptor_mutex);
    component_descriptor **slot = &component_descriptors;
    while (*slot != NULL && (*slot)->descriptor != fd) slot = &(*slot)->next;
    component_descriptor *child = *slot;
    if (child == NULL || child->close_consumed) {
        component_descriptor_unknown = 1;
        sqlite3_mutex_leave(component_descriptor_mutex);
        errno = EIO; return -1;
    }
    child->close_consumed = 1;
    int result = close(fd);
    int error = errno;
    if (result == 0) *slot = child->next;
    else {
        child->close_error = error;
        component_descriptor_unknown = 1;
    }
    sqlite3_mutex_leave(component_descriptor_mutex);
    if (result == 0) sqlite3_free(child);
    errno = error;
    return result;
}

static int component_current(void) {
    return component_context != NULL && component_process == getpid() &&
        actql_bootstrap_current_read_context() == component_context &&
        actql_native_owned_current() == component_lease;
}

static int component_provider_origin(void) {
    Dl_info original, observed;
    if (!dladdr((void *)actql_bootstrap_current_read_context, &original)) return 0;
    void *entries[] = {(void *)actql_read_context_retain,
        (void *)actql_read_context_release_after_owner_ack,
        (void *)actql_native_file_scoped_allocate,
        (void *)actql_native_file_scoped_free,
        (void *)actql_native_owned_current, (void *)actql_native_owned_retire};
    for (size_t i = 0; i < sizeof(entries) / sizeof(entries[0]); i++) {
        if (!dladdr(entries[i], &observed) ||
            observed.dli_fbase != original.dli_fbase) return 0;
    }
    return 1;
}

static int component_bind_impl(actql_read_context *original, size_t heap_bytes) {
    if (component_attempted || original == NULL || heap_bytes < 4096 ||
        heap_bytes > INT_MAX || actql_native_owned_current() == NULL ||
        actql_bootstrap_current_read_context() != original ||
        !component_provider_origin()) return ACTQL_SQLITE_COMPONENT_INVALID;
    component_attempted = 1;
    /* Exact-source private globals; no call to initialize/shutdown/config on
     * another library. A previously initialized candidate is never rebound. */
    if (sqlite3GlobalConfig.isInit || sqlite3GlobalConfig.inProgress ||
        sqlite3GlobalConfig.isMallocInit) return ACTQL_SQLITE_COMPONENT_FAILED;
    if (actql_read_context_retain(original) != 0)
        return ACTQL_SQLITE_COMPONENT_FAILED;
    component_context = original;
    component_lease = actql_native_owned_current();
    component_process = getpid();
    component_retained = 1;
    /* Exactly one original provider extent. The explicit private selection is
     * a partition of existing backing, never a capacity grant. Metadata,
     * minimum-block rounding and fragmentation all live inside this same heap.
     * A null heap MUST NOT reach CONFIG_HEAP: SQLite would restore defaults. */
    component_heap = actql_native_file_scoped_allocate(heap_bytes);
    if (component_heap == NULL) return ACTQL_SQLITE_COMPONENT_FAILED;
    if (sqlite3_config(SQLITE_CONFIG_HEAP, component_heap, (int)heap_bytes, 16) != SQLITE_OK ||
        sqlite3_initialize() != SQLITE_OK) return ACTQL_SQLITE_COMPONENT_FAILED;
    component_descriptor_mutex = sqlite3_mutex_alloc(SQLITE_MUTEX_STATIC_VFS3);
    if (component_descriptor_mutex == NULL ||
        unixSetSystemCall(NULL, "open", (sqlite3_syscall_ptr)component_open_descriptor) != SQLITE_OK ||
        unixSetSystemCall(NULL, "close", (sqlite3_syscall_ptr)component_close_descriptor) != SQLITE_OK)
        return ACTQL_SQLITE_COMPONENT_FAILED;
    component_ready = 1;
    return ACTQL_SQLITE_COMPONENT_OK;
}

static void *component_allocate_impl(size_t bytes) {
    if (!component_ready || !component_current() || bytes == 0 || bytes > INT_MAX)
        return NULL;
    return sqlite3_malloc((int)bytes);
}

static void *component_resize_impl(void *original, size_t bytes) {
    if (!component_ready || !component_current() || bytes > INT_MAX) return NULL;
    return sqlite3_realloc(original, (int)bytes);
}

static size_t component_size_impl(void *original) {
    if (!component_ready || component_process != getpid() || original == NULL)
        return 0;
    return (size_t)sqlite3_msize(original);
}

static int component_free_impl(void *original) {
    if (!component_retained || component_process != getpid())
        return ACTQL_SQLITE_COMPONENT_INVALID;
    sqlite3_free(original);
    return ACTQL_SQLITE_COMPONENT_OK;
}

static int component_close_impl(void) {
    if (component_stopped) return component_process == getpid()
        ? ACTQL_SQLITE_COMPONENT_OK : ACTQL_SQLITE_COMPONENT_INVALID;
    if (!component_retained || !component_current())
        return ACTQL_SQLITE_COMPONENT_INVALID;
    if (component_api_borrowed) return ACTQL_SQLITE_COMPONENT_BUSY;
    if (component_descriptors != NULL || component_descriptor_unknown)
        return ACTQL_SQLITE_COMPONENT_BUSY;
    /* Engine initialization may itself hold allocations. SQLite shutdown frees
     * those, but only after all caller buffers are gone (memory_used includes
     * both). The API-table borrow separately retains DB/statement custody. */
    if (sqlite3_memory_used() != 0) return ACTQL_SQLITE_COMPONENT_BUSY;
    component_ready = 0;
    if (!component_shutdown_ack) {
        if (sqlite3_shutdown() != SQLITE_OK) return ACTQL_SQLITE_COMPONENT_BUSY;
        component_shutdown_ack = 1;
    }
    if (component_heap != NULL) {
        /* Direct ACK from the SAME provider and original lease. Failed retire
         * keeps the original pointer/user; retry only this cleanup, never bind,
         * shutdown, allocate a replacement or claim an internal free credit. */
        if (actql_native_owned_retire(component_lease, component_heap) != ACTQL_OWNED_OK)
            return ACTQL_SQLITE_COMPONENT_FAILED;
        component_heap = NULL;
    }
    if (actql_read_context_release_after_owner_ack(component_context) != 0)
        return ACTQL_SQLITE_COMPONENT_FAILED;
    component_retained = 0;
    component_stopped = 1;
    return ACTQL_SQLITE_COMPONENT_OK;
}

static int component_descriptor_ack_impl(void *unused) {
    (void)unused;
    if (!component_retained || !component_current())
        return ACTQL_SQLITE_COMPONENT_INVALID;
    sqlite3_mutex_enter(component_descriptor_mutex);
    int confirmed = !component_descriptor_unknown;
    sqlite3_mutex_leave(component_descriptor_mutex);
    return confirmed ? ACTQL_SQLITE_COMPONENT_OK : ACTQL_SQLITE_COMPONENT_BUSY;
}

static int component_heap_wal_impl(void *original) {
    if (!component_ready || !component_current() || original == NULL)
        return ACTQL_SQLITE_COMPONENT_INVALID;
    /* The existing adapter supplies the DB returned by this same API table.
     * Serialize the observation with SQLite's own original connection mutex;
     * an effective PRAGMA alone is not an acquired heap-backed WAL index. */
    sqlite3 *database = original;
    sqlite3_mutex *mutex = sqlite3_db_mutex(database);
    sqlite3_mutex_enter(mutex);
    Btree *tree = sqlite3DbNameToBtree(database, "main");
    Pager *pager = tree == NULL ? NULL : sqlite3BtreePager(tree);
    int ready = pager != NULL && pager->exclusiveMode && pager->pWal != NULL &&
        sqlite3WalHeapMemory(pager->pWal);
    sqlite3_mutex_leave(mutex);
    return ready ? ACTQL_SQLITE_COMPONENT_OK : ACTQL_SQLITE_COMPONENT_BUSY;
}

static int component_readonly_heap_wal_impl(void *original) {
    if (!component_ready || !component_current() || original == NULL)
        return ACTQL_SQLITE_COMPONENT_INVALID;
    sqlite3 *database = original;
    sqlite3_mutex *mutex = sqlite3_db_mutex(database);
    sqlite3_mutex_enter(mutex);
    Btree *tree = sqlite3DbNameToBtree(database, "main");
    Pager *pager = tree == NULL ? NULL : sqlite3BtreePager(tree);
    int ready = sqlite3_db_readonly(database, "main") == 1 && pager != NULL;
    if (ready && pager->pWal != NULL) {
        /* readonly_shm on an empty exclusively owned copy yields CANTINIT,
         * and the pinned WAL reader reconstructs its index in SQLite heap.
         * Successful reads reset exclusiveMode; bShmUnreliable retains that
         * actual route. Do not mistake NORMAL shared mappings for this path. */
        Wal *wal = pager->pWal;
        ready = wal->bShmUnreliable && (wal->readOnly & WAL_SHM_RDONLY) &&
            pager->fd->pMethods->xShmMap == unixShmMap;
        if (ready) {
            unixFile *file = (unixFile *)pager->fd;
            ready = file->pShm != NULL && file->pShm->pShmNode != NULL &&
                file->pShm->pShmNode->isReadonly &&
                file->pShm->pShmNode->isUnlocked &&
                file->pShm->pShmNode->nRegion == 0;
        }
    }
    sqlite3_mutex_leave(mutex);
    return ready ? ACTQL_SQLITE_COMPONENT_OK : ACTQL_SQLITE_COMPONENT_BUSY;
}

__attribute__((visibility("default")))
const char *actql_sqlite_component_source_id(void) { return SQLITE_SOURCE_ID; }

/* The existing Library Owner still supplies authority and lifetime. This fence
 * merely prevents two physical configure/close/allocator calls racing through
 * that port. Busy leaves the original buffer and cleanup responsibility intact. */
static int component_enter_call(void) {
    if (component_process != 0 && component_process != getpid())
        return ACTQL_SQLITE_COMPONENT_INVALID;
    return atomic_flag_test_and_set_explicit(&component_entry, memory_order_acquire)
        ? ACTQL_SQLITE_COMPONENT_BUSY : ACTQL_SQLITE_COMPONENT_OK;
}
static void component_leave_call(void) {
    atomic_flag_clear_explicit(&component_entry, memory_order_release);
}

#define COMPONENT_INT_ENTRY(name, params, args) \
    __attribute__((visibility("default"))) \
    int actql_sqlite_component_##name params { \
        int entered = component_enter_call(); \
        if (entered != 0) return entered; \
        int result = component_##name##_impl args; \
        component_leave_call(); \
        return result; \
    }
#define COMPONENT_VALUE_ENTRY(name, type, params, args, missing) \
    __attribute__((visibility("default"))) \
    type actql_sqlite_component_##name params { \
        if (component_enter_call() != 0) return missing; \
        type result = component_##name##_impl args; \
        component_leave_call(); \
        return result; \
    }
COMPONENT_INT_ENTRY(bind, (actql_read_context *original, size_t heap_bytes), (original, heap_bytes))
COMPONENT_INT_ENTRY(free, (void *original), (original))
COMPONENT_INT_ENTRY(close, (void), ())
COMPONENT_INT_ENTRY(descriptor_ack, (void *unused), (unused))
COMPONENT_INT_ENTRY(heap_wal, (void *database), (database))
COMPONENT_INT_ENTRY(readonly_heap_wal, (void *database), (database))
COMPONENT_VALUE_ENTRY(allocate, void *, (size_t bytes), (bytes), NULL)
COMPONENT_VALUE_ENTRY(resize, void *, (void *original, size_t bytes), (original, bytes), NULL)
COMPONENT_VALUE_ENTRY(size, size_t, (void *original), (original), 0)

/* close_v2 can leave a zombie connection whose statements still use the module.
 * The selected physical-close port instead uses SQLite's checked close: BUSY
 * retains the same original DB until its own statements actually finalize. */
static const actql_sqlite_component_api component_api = {
    ACTQL_SQLITE_COMPONENT_ABI, sizeof(actql_sqlite_component_api), &component_api,
    component_allocate_impl,
    sqlite3_libversion, sqlite3_libversion_number, sqlite3_open_v2, sqlite3_close,
    sqlite3_errmsg, sqlite3_exec, sqlite3_free, sqlite3_prepare_v2,
    sqlite3_bind_text, sqlite3_bind_blob, sqlite3_bind_int64, sqlite3_step,
    sqlite3_column_int64, sqlite3_column_blob, sqlite3_column_bytes,
    sqlite3_finalize, sqlite3_changes64, sqlite3_busy_timeout, sqlite3_get_autocommit,
    sqlite3_reset, sqlite3_clear_bindings
};

__attribute__((visibility("default")))
const actql_sqlite_component_api *actql_sqlite_component_borrow_api(void) {
    if (component_enter_call() != 0) return NULL;
    const actql_sqlite_component_api *result = NULL;
    if (component_ready && component_current() && !component_api_borrowed) {
        component_api_borrowed = 1;
        result = &component_api;
    }
    component_leave_call();
    return result;
}

__attribute__((visibility("default")))
int actql_sqlite_component_release_api(const actql_sqlite_component_api *original) {
    int entered = component_enter_call();
    if (entered != 0) return entered;
    int result = ACTQL_SQLITE_COMPONENT_INVALID;
    if (original == &component_api && component_api_borrowed && component_current()) {
        component_api_borrowed = 0;
        result = ACTQL_SQLITE_COMPONENT_OK;
    }
    component_leave_call();
    return result;
}
