#include "sqlite_database_shim.h"
#include <limits.h>
#include <string.h>
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
#include "scoped_read.h"
extern actql_read_context *actql_bootstrap_current_read_context(void);
#endif
static int inside_read_scope(void) {
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
    return actql_bootstrap_current_read_context() != NULL;
#else
    return 0;
#endif
}
static struct {
    actql_database_restore_fn restore;
    actql_database_initialize_fn initialize;
    actql_database_operation_fn observe, close, fence;
    actql_database_read_fn read;
    actql_database_insert_fn insert;
    actql_database_compare_fn compare;
    actql_database_transaction_fn transaction;
    actql_database_host_fn host;
    actql_database_library_fn library;
    actql_database_original_fn original;
    actql_database_tag_fn operation, stage, issue, after, has_row;
    actql_database_scalar_fn revision, bound;
    actql_database_body_fn body;
} callbacks;
static int registered;
void actql_native_control_register_sqlite_database_roots(
    actql_database_restore_fn restore, actql_database_initialize_fn initialize,
    actql_database_operation_fn observe, actql_database_read_fn read,
    actql_database_insert_fn insert, actql_database_compare_fn compare,
    actql_database_transaction_fn transaction, actql_database_operation_fn close,
    actql_database_operation_fn fence, actql_database_host_fn host,
    actql_database_library_fn library, actql_database_original_fn original,
    actql_database_tag_fn operation, actql_database_tag_fn stage,
    actql_database_tag_fn issue, actql_database_tag_fn after,
    actql_database_tag_fn has_row, actql_database_scalar_fn revision,
    actql_database_body_fn body, actql_database_scalar_fn bound) {
    if (registered) return;
    if (!restore || !initialize || !observe || !read || !insert || !compare ||
        !transaction || !close || !fence || !host || !library || !original ||
        !operation || !stage || !issue || !after || !has_row || !revision || !body || !bound) {
        registered = -1;
        return;
    }
    callbacks.restore = restore; callbacks.initialize = initialize;
    callbacks.observe = observe; callbacks.read = read; callbacks.insert = insert;
    callbacks.compare = compare; callbacks.transaction = transaction;
    callbacks.close = close; callbacks.fence = fence; callbacks.host = host;
    callbacks.library = library; callbacks.original = original;
    callbacks.operation = operation; callbacks.stage = stage; callbacks.issue = issue;
    callbacks.after = after; callbacks.has_row = has_row; callbacks.revision = revision;
    callbacks.body = body; callbacks.bound = bound;
    registered = 1;
}
static moonbit_string_t copy_text(const uint16_t *text, int32_t units) {
    moonbit_string_t result = moonbit_make_string_raw(units);
    if (units) memcpy(result, text, (size_t)units * sizeof(uint16_t));
    return result;
}
static int open_into(actql_control_host *host, actql_sqlite_original *library,
    const uint16_t *path, int32_t units, int64_t bound, uint64_t device,
    uint64_t inode, int initialize, actql_sqlite_database_reply **reply) {
    if (!host || !library || !path || units <= 0 || units > 4096 || bound <= 0 ||
        bound > INT32_MAX || !reply || *reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1 || inside_read_scope()) return ACTQL_CONTROL_UNAVAILABLE;
    moonbit_string_t managed = copy_text(path, units);
    *reply = initialize ? callbacks.initialize(host, library, managed, bound, device, inode)
                        : callbacks.restore(host, library, managed, bound);
    moonbit_decref(managed);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
int actql_sqlite_database_restore_utf16_into(actql_control_host *host, actql_sqlite_original *library,
    const uint16_t *path, int32_t units, int64_t bound, actql_sqlite_database_reply **reply) {
    return open_into(host, library, path, units, bound, 0, 0, 0, reply);
}
int actql_sqlite_database_initialize_utf16_into(actql_control_host *host, actql_sqlite_original *library,
    const uint16_t *path, int32_t units, int64_t bound, uint64_t device, uint64_t inode,
    actql_sqlite_database_reply **reply) {
    return open_into(host, library, path, units, bound, device, inode, 1, reply);
}
static int operate(actql_database_operation_fn operation, actql_control_host *host,
    actql_sqlite_database *original, actql_sqlite_database_reply **reply, int inside) {
    if (!host || !original || !reply || *reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1 || inside_read_scope() != inside) return ACTQL_CONTROL_UNAVAILABLE;
    *reply = operation(host, original);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
int actql_sqlite_database_observe_into(actql_control_host *host, actql_sqlite_database *original, actql_sqlite_database_reply **reply) {
    return operate(callbacks.observe, host, original, reply, 1);
}
int actql_sqlite_database_fence_into(actql_control_host *host, actql_sqlite_database *original, actql_sqlite_database_reply **reply) {
    return operate(callbacks.fence, host, original, reply, 1);
}
int actql_sqlite_database_close_into(actql_control_host *host, actql_sqlite_database *original, actql_sqlite_database_reply **reply) {
    return operate(callbacks.close, host, original, reply, 0);
}
/* Keep a refused original preflight in the caller's output slot. It is an
 * Observe reply with no row operation attempted, never an invented row ACK. */
static int preflight(actql_control_host *host, actql_sqlite_database *original,
    actql_sqlite_database_reply **reply) {
    int code = operate(callbacks.observe, host, original, reply, 1);
    if (code != ACTQL_CONTROL_OK) return code;
    if (callbacks.operation(*reply) != 3 || callbacks.stage(*reply) != 2 ||
        callbacks.issue(*reply) != 0 || callbacks.after(*reply) != 0) return 1;
    return ACTQL_CONTROL_OK;
}
static void release_preflight(actql_sqlite_database_reply **reply) {
    actql_sqlite_database_reply *owned = *reply; *reply = NULL;
    moonbit_decref(owned);
}
static int names_valid(const uint16_t *scope, int32_t scope_units, const uint16_t *key, int32_t key_units) {
    /* The existing SQLite Owner validates exact UTF-8 bounds and NUL rules.
     * This is only a pre-copy ABI bound, not normalization or truncation. */
    return scope && key && scope_units > 0 && scope_units <= 512 && key_units > 0 && key_units <= 512;
}
int actql_sqlite_database_read_utf16_into(actql_control_host *host, actql_sqlite_database *original,
    const uint16_t *scope, int32_t scope_units, const uint16_t *key, int32_t key_units,
    int64_t limit, actql_sqlite_database_reply **reply) {
    if (!names_valid(scope, scope_units, key, key_units) || limit <= 0 || limit > INT32_MAX)
        return ACTQL_CONTROL_INVALID_SLOT;
    int code = preflight(host, original, reply);
    if (code != ACTQL_CONTROL_OK) return code == 1 ? ACTQL_CONTROL_OK : code;
    release_preflight(reply);
    moonbit_string_t s = copy_text(scope, scope_units), k = copy_text(key, key_units);
    *reply = callbacks.read(host, original, s, k, limit);
    moonbit_decref(k); moonbit_decref(s);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
static int write_into(actql_control_host *host, actql_sqlite_database *original,
    const uint16_t *scope, int32_t scope_units, const uint16_t *key, int32_t key_units,
    int64_t expected, const unsigned char *body, int64_t length, int compare,
    actql_sqlite_database_reply **reply) {
    if (!names_valid(scope, scope_units, key, key_units) || length < 0 || length > INT32_MAX ||
        (length && !body) || (compare && expected < 0)) return ACTQL_CONTROL_INVALID_SLOT;
    int code = preflight(host, original, reply);
    if (code != ACTQL_CONTROL_OK) return code == 1 ? ACTQL_CONTROL_OK : code;
    /* Same original Core bound, after exact current/scope validation, before
     * allocating/copying the body. No caller supplied alternative quota. */
    if (length > callbacks.bound(*reply)) return ACTQL_CONTROL_OK;
    release_preflight(reply);
    moonbit_string_t s = copy_text(scope, scope_units), k = copy_text(key, key_units);
    moonbit_bytes_t b = moonbit_make_bytes_raw((int32_t)length);
    if (length) memcpy(b, body, (size_t)length);
    *reply = compare ? callbacks.compare(host, original, s, k, expected, b)
                     : callbacks.insert(host, original, s, k, b);
    moonbit_decref(b); moonbit_decref(k); moonbit_decref(s);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
int actql_sqlite_database_insert_utf16_into(actql_control_host *host, actql_sqlite_database *original,
    const uint16_t *scope, int32_t scope_units, const uint16_t *key, int32_t key_units,
    const unsigned char *body, int64_t length, actql_sqlite_database_reply **reply) {
    return write_into(host, original, scope, scope_units, key, key_units, 0, body, length, 0, reply);
}
int actql_sqlite_database_compare_utf16_into(actql_control_host *host, actql_sqlite_database *original,
    const uint16_t *scope, int32_t scope_units, const uint16_t *key, int32_t key_units,
    int64_t expected, const unsigned char *body, int64_t length, actql_sqlite_database_reply **reply) {
    return write_into(host, original, scope, scope_units, key, key_units, expected, body, length, 1, reply);
}
int actql_sqlite_database_transaction_into(actql_control_host *host, actql_sqlite_database *original,
    int32_t operation, actql_sqlite_database_reply **reply) {
    if (operation < 7 || operation > 9) return ACTQL_CONTROL_INVALID_SLOT;
    if (!host || !original || !reply || *reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1 || !inside_read_scope()) return ACTQL_CONTROL_UNAVAILABLE;
    *reply = callbacks.transaction(host, original, operation);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
int actql_sqlite_database_originals_into(actql_sqlite_database_reply *reply,
    actql_control_host **host, actql_sqlite_original **library, actql_sqlite_database **original) {
    if (!reply || !host || !library || !original || *host || *library || *original ||
        (void *)host == (void *)library || (void *)host == (void *)original ||
        (void *)library == (void *)original) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *host = callbacks.host(reply); if (!*host) return ACTQL_CONTROL_UNAVAILABLE;
    *library = callbacks.library(reply); if (!*library) return ACTQL_CONTROL_UNAVAILABLE;
    *original = callbacks.original(reply);
    return ACTQL_CONTROL_OK;
}
#define TAG(NAME, FIELD) \
int32_t NAME(actql_sqlite_database_reply *reply) { \
    return registered == 1 && reply ? callbacks.FIELD(reply) : ACTQL_CONTROL_UNAVAILABLE; \
}
TAG(actql_sqlite_database_operation, operation)
TAG(actql_sqlite_database_stage, stage)
TAG(actql_sqlite_database_issue_family, issue)
TAG(actql_sqlite_database_after_issue_family, after)
TAG(actql_sqlite_database_has_row, has_row)
#undef TAG
int64_t actql_sqlite_database_revision(actql_sqlite_database_reply *reply) {
    return registered == 1 && reply ? callbacks.revision(reply) : -1;
}
int64_t actql_sqlite_database_body_bound(actql_sqlite_database_reply *reply) {
    return registered == 1 && reply ? callbacks.bound(reply) : -1;
}
static int same_reply(actql_sqlite_database_reply *reply, actql_control_host *host,
    actql_sqlite_original *library, actql_sqlite_database *original) {
    actql_control_host *h = callbacks.host(reply);
    actql_sqlite_original *l = callbacks.library(reply);
    actql_sqlite_database *o = callbacks.original(reply);
    int same = h && h == host && l && l == library && o == original;
    if (o) moonbit_decref(o);
    if (l) moonbit_decref(l);
    if (h) moonbit_decref(h);
    return same;
}
int actql_sqlite_database_copy_row(actql_sqlite_database_reply *reply, actql_control_host *host,
    actql_sqlite_original *library, actql_sqlite_database *original,
    unsigned char *output, int64_t capacity, int64_t *length) {
    if (registered != 1 || !inside_read_scope()) return ACTQL_CONTROL_UNAVAILABLE;
    if (!reply || !host || !library || !original || !length || capacity < 0 ||
        (capacity && !output) || callbacks.operation(reply) != 4 || callbacks.stage(reply) != 2 ||
        callbacks.issue(reply) != 0 || callbacks.after(reply) != 0 || callbacks.has_row(reply) != 1 ||
        !same_reply(reply, host, library, original)) return ACTQL_CONTROL_INVALID_SLOT;
    moonbit_bytes_t body = callbacks.body(reply);
    if (!body) return ACTQL_CONTROL_UNAVAILABLE;
    int64_t size = Moonbit_array_length(body);
    int code = ACTQL_CONTROL_INVALID_SLOT;
    if (size >= 0 && size <= capacity && size <= callbacks.bound(reply)) {
        if (size) memcpy(output, body, (size_t)size);
        *length = size; code = ACTQL_CONTROL_OK;
    }
    moonbit_decref(body);
    return code;
}
int actql_sqlite_database_drop_reply(actql_sqlite_database_reply **reply, actql_control_host *host,
    actql_sqlite_original *library, actql_sqlite_database *original) {
    if (!reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*reply) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!same_reply(*reply, host, library, original)) return ACTQL_CONTROL_INVALID_SLOT;
    actql_sqlite_database_reply *owned = *reply; *reply = NULL; moonbit_decref(owned);
    return ACTQL_CONTROL_OK;
}
static int distinct(void *host, void *library, void *original, void *reply) {
    return host && library && original && reply && host != library && host != original && host != reply &&
        library != original && library != reply && original != reply;
}
int actql_sqlite_database_finish_closed_data(actql_control_host **host, actql_sqlite_original **library,
    actql_sqlite_database **original, actql_sqlite_database_reply **reply) {
    if (!distinct(host, library, original, reply)) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*host && !*library && !*original && !*reply) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!*host || !*library || !*original || !*reply || callbacks.operation(*reply) != 10 ||
        callbacks.stage(*reply) != 3 || callbacks.issue(*reply) != 0 || callbacks.after(*reply) != 0 ||
        !same_reply(*reply, *host, *library, *original)) return ACTQL_CONTROL_INVALID_SLOT;
    actql_sqlite_database_reply *r = *reply; *reply = NULL; moonbit_decref(r);
    actql_sqlite_database *o = *original; *original = NULL; moonbit_decref(o);
    actql_sqlite_original *l = *library; *library = NULL; moonbit_decref(l);
    actql_control_host *h = *host; *host = NULL; moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}
int actql_sqlite_database_finish_refused_open(actql_control_host **host, actql_sqlite_original **library,
    actql_sqlite_database_reply **reply) {
    if (!host || !library || !reply || (void *)host == (void *)library ||
        (void *)host == (void *)reply || (void *)library == (void *)reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*host && !*library && !*reply) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!*host || !*library || !*reply || (callbacks.operation(*reply) != 1 && callbacks.operation(*reply) != 2) ||
        callbacks.stage(*reply) != 0 || callbacks.issue(*reply) <= 0 ||
        !same_reply(*reply, *host, *library, NULL)) return ACTQL_CONTROL_INVALID_SLOT;
    actql_sqlite_database_reply *r = *reply; *reply = NULL; moonbit_decref(r);
    actql_sqlite_original *l = *library; *library = NULL; moonbit_decref(l);
    actql_control_host *h = *host; *host = NULL; moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}
