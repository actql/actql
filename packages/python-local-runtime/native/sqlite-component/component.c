/* A dedicated translation unit: every upstream SQLite symbol has internal
 * linkage. No sqlite3_* symbol can resolve to the system/Python instance. */
#define _DARWIN_C_SOURCE
#define SQLITE_API static
#define SQLITE_EXTERN
#define SQLITE_OMIT_AUTOINIT 1
#define SQLITE_ZERO_MALLOC 1
#define SQLITE_OMIT_LOAD_EXTENSION 1
#define SQLITE_THREADSAFE 1
#include "sqlite3.c"
#include "component.h"
#include "api.h"
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

typedef union {
    max_align_t alignment;
    struct { int size; } value;
} actql_sqlite_allocation_header;

/* One Library binding per component lifetime, never per Run or on reopen.
 * A nonblocking physical entry fence rejects competing/reentrant operations;
 * it does not schedule calls, retry requests or issue a new Library authority.
 * These fields do not reconstruct Host, Store, current authorization or grants. */
static actql_read_context *component_context;
static _Atomic(pid_t) component_process;
static atomic_flag component_entry = ATOMIC_FLAG_INIT;
static size_t component_allocations;
static int component_attempted, component_ready, component_stopped;
static int component_retained;
static int component_api_borrowed;

static int component_current(void) {
    return component_context != NULL && component_process == getpid() &&
        actql_bootstrap_current_read_context() == component_context;
}

static int component_provider_origin(void) {
    Dl_info original, observed;
    if (!dladdr((void *)actql_bootstrap_current_read_context, &original)) return 0;
    void *entries[] = {(void *)actql_read_context_retain,
        (void *)actql_read_context_release_after_owner_ack,
        (void *)actql_native_file_scoped_allocate,
        (void *)actql_native_file_scoped_free};
    for (size_t i = 0; i < sizeof(entries) / sizeof(entries[0]); i++) {
        if (!dladdr(entries[i], &observed) ||
            observed.dli_fbase != original.dli_fbase) return 0;
    }
    return 1;
}

static int component_roundup(int bytes) {
    return bytes <= 0 || bytes > INT_MAX - 7 ? 0 : (bytes + 7) & ~7;
}

static void *component_malloc(int bytes) {
    if (!component_current() || bytes <= 0 || component_allocations == SIZE_MAX)
        return NULL;
    actql_sqlite_allocation_header *header = actql_native_file_scoped_allocate(
        sizeof(*header) + (size_t)bytes);
    if (header == NULL) return NULL;
    header->value.size = bytes;
    component_allocations++;
    return header + 1;
}

static void component_free(void *pointer) {
    if (pointer == NULL) return;
    /* Never inspect an inherited header, adopt its context or route it through
     * the child's ambient allocator. The public private wrapper refuses first. */
    if (component_process != getpid()) return;
    actql_sqlite_allocation_header *header = pointer;
    header--;
    actql_native_file_scoped_free(header);
    component_allocations--;
    /* A failed mprotect retirement stays released in the SAME provider extent
     * table. Logical free is not physical domain close or a capacity credit. */
}

static int component_size(void *pointer) {
    actql_sqlite_allocation_header *header = pointer;
    return pointer == NULL ? 0 : (header - 1)->value.size;
}

static void *component_realloc(void *pointer, int bytes) {
    if (!component_current()) return NULL;
    if (pointer == NULL) return component_malloc(bytes);
    if (bytes <= 0) { component_free(pointer); return NULL; }
    /* Both extents coexist in the original provider. On failure the old buffer
     * remains intact; neither a stock realloc nor a released credit is used. */
    void *next = component_malloc(bytes);
    if (next == NULL) return NULL;
    int previous = component_size(pointer);
    memcpy(next, pointer, (size_t)(previous < bytes ? previous : bytes));
    component_free(pointer);
    return next;
}

static int component_init(void *original) {
    return original == component_context && component_current()
        ? SQLITE_OK : SQLITE_MISUSE;
}
static void component_shutdown(void *original) { (void)original; }

static int component_bind_impl(actql_read_context *original) {
    if (component_attempted || original == NULL ||
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
    component_process = getpid();
    component_retained = 1;
    sqlite3_mem_methods methods = {component_malloc, component_free,
        component_realloc, component_size, component_roundup,
        component_init, component_shutdown, original};
    if (sqlite3_config(SQLITE_CONFIG_MALLOC, &methods) != SQLITE_OK ||
        sqlite3_initialize() != SQLITE_OK) return ACTQL_SQLITE_COMPONENT_FAILED;
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
    /* Engine initialization may itself hold allocations. SQLite shutdown frees
     * those, but only after all caller buffers are gone (memory_used includes
     * both). This slice exposes no DB/statement/VFS operations. */
    if (sqlite3_memory_used() != 0) return ACTQL_SQLITE_COMPONENT_BUSY;
    component_ready = 0;
    if (sqlite3_shutdown() != SQLITE_OK || component_allocations != 0)
        return ACTQL_SQLITE_COMPONENT_BUSY;
    if (actql_read_context_release_after_owner_ack(component_context) != 0)
        return ACTQL_SQLITE_COMPONENT_FAILED;
    component_retained = 0;
    component_stopped = 1;
    return ACTQL_SQLITE_COMPONENT_OK;
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
COMPONENT_INT_ENTRY(bind, (actql_read_context *original), (original))
COMPONENT_INT_ENTRY(free, (void *original), (original))
COMPONENT_INT_ENTRY(close, (void), ())
COMPONENT_VALUE_ENTRY(allocate, void *, (size_t bytes), (bytes), NULL)
COMPONENT_VALUE_ENTRY(resize, void *, (void *original, size_t bytes), (original, bytes), NULL)
COMPONENT_VALUE_ENTRY(size, size_t, (void *original), (original), 0)

/* close_v2 can leave a zombie connection whose statements still use the module.
 * The selected physical-close port instead uses SQLite's checked close: BUSY
 * retains the same original DB until its own statements actually finalize. */
static const actql_sqlite_component_api component_api = {
    ACTQL_SQLITE_COMPONENT_ABI, sizeof(actql_sqlite_component_api), &component_api,
    sqlite3_libversion, sqlite3_libversion_number, sqlite3_open_v2, sqlite3_close,
    sqlite3_errmsg, sqlite3_exec, sqlite3_free, sqlite3_prepare_v2,
    sqlite3_bind_text, sqlite3_bind_blob, sqlite3_bind_int64, sqlite3_step,
    sqlite3_column_int64, sqlite3_column_blob, sqlite3_column_bytes,
    sqlite3_finalize, sqlite3_changes64, sqlite3_busy_timeout, sqlite3_get_autocommit
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
