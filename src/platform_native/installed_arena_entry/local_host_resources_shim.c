#include "local_host_resources_shim.h"

extern int32_t actql_bootstrap_control_scope_clear(void);
static struct {
    actql_host_resources_bind_fn bind;
    actql_host_resources_operate_fn operate;
    actql_host_resources_host_fn host, sqlite_host;
    actql_host_resources_read_fn read;
    actql_host_resources_sqlite_fn sqlite;
    actql_host_resources_original_fn original;
    actql_host_resources_tag_fn operation, origin, family, closed;
    actql_host_resources_capacity_fn capacity;
} callbacks;
static int registered;

void actql_native_control_register_local_host_resource_roots(
    actql_host_resources_bind_fn bind, actql_host_resources_operate_fn operate,
    actql_host_resources_host_fn host, actql_host_resources_host_fn sqlite_host,
    actql_host_resources_read_fn read, actql_host_resources_sqlite_fn sqlite,
    actql_host_resources_original_fn original, actql_host_resources_tag_fn operation,
    actql_host_resources_tag_fn origin, actql_host_resources_tag_fn family,
    actql_host_resources_tag_fn closed, actql_host_resources_capacity_fn capacity) {
    if (registered) return;
    if (!bind || !operate || !host || !sqlite_host || !read || !sqlite ||
        !original || !operation || !origin || !family || !closed || !capacity) {
        registered = -1;
        return;
    }
    callbacks.bind = bind; callbacks.operate = operate;
    callbacks.host = host; callbacks.sqlite_host = sqlite_host;
    callbacks.read = read; callbacks.sqlite = sqlite; callbacks.original = original;
    callbacks.operation = operation; callbacks.origin = origin;
    callbacks.family = family; callbacks.closed = closed;
    callbacks.capacity = capacity;
    registered = 1;
}

int actql_host_resources_bind_into(actql_control_host *host, actql_parent_read *read,
    actql_sqlite_original *sqlite, actql_local_host_resources_reply **reply) {
    if (!host || !read || !sqlite || !reply || *reply) return ACTQL_CONTROL_INVALID_SLOT;
    /* The persistent controller must not live in either child it retires. */
    if (registered != 1 || actql_bootstrap_control_scope_clear() != 1)
        return ACTQL_CONTROL_UNAVAILABLE;
    *reply = callbacks.bind(host, read, sqlite);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

int actql_host_resources_operate_into(actql_control_host *host,
    actql_local_host_resources *original, int32_t operation,
    actql_local_host_resources_reply **reply) {
    if (!host || !original || !reply || *reply || operation < 2 || operation > 8)
        return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *reply = callbacks.operate(host, original, operation);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

static int distinct_slots(const void *const *slots, size_t count) {
    for (size_t i = 0; i < count; i++) {
        if (!slots[i]) return 0;
        for (size_t j = 0; j < i; j++) if (slots[i] == slots[j]) return 0;
    }
    return 1;
}

int actql_host_resources_originals_into(actql_local_host_resources_reply *reply,
    actql_control_host **host, actql_control_host **sqlite_host,
    actql_parent_read **read, actql_sqlite_original **sqlite,
    actql_local_host_resources **original) {
    const void *slots[] = {host, sqlite_host, read, sqlite, original};
    if (!reply || !distinct_slots(slots, 5) || *host || *sqlite_host || *read ||
        *sqlite || *original) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    /* Partial getter output stays in the caller's persistent slots. */
    *host = callbacks.host(reply);
    if (!*host) return ACTQL_CONTROL_UNAVAILABLE;
    *sqlite_host = callbacks.sqlite_host(reply);
    if (!*sqlite_host) return ACTQL_CONTROL_UNAVAILABLE;
    *read = callbacks.read(reply);
    if (!*read) return ACTQL_CONTROL_UNAVAILABLE;
    *sqlite = callbacks.sqlite(reply);
    if (!*sqlite) return ACTQL_CONTROL_UNAVAILABLE;
    *original = callbacks.original(reply);
    return ACTQL_CONTROL_OK; /* Nullable only for a refused bind. */
}

int32_t actql_host_resources_operation(actql_local_host_resources_reply *reply) {
    return registered == 1 && reply ? callbacks.operation(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
int32_t actql_host_resources_issue_origin(actql_local_host_resources_reply *reply) {
    return registered == 1 && reply ? callbacks.origin(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
int32_t actql_host_resources_issue_family(actql_local_host_resources_reply *reply) {
    return registered == 1 && reply ? callbacks.family(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
int32_t actql_host_resources_close_confirmed(actql_local_host_resources_reply *reply) {
    return registered == 1 && reply ? callbacks.closed(reply) : ACTQL_CONTROL_UNAVAILABLE;
}

int64_t actql_host_resources_capacity_scalar(actql_control_host *host, int32_t index) {
    return registered == 1 && host ? callbacks.capacity(host, index) : -1;
}

static int same_originals(actql_local_host_resources_reply *reply,
    actql_control_host *host, actql_control_host *sqlite_host, actql_parent_read *read,
    actql_sqlite_original *sqlite, actql_local_host_resources *original) {
    actql_control_host *h = callbacks.host(reply);
    actql_control_host *s = callbacks.sqlite_host(reply);
    actql_parent_read *r = callbacks.read(reply);
    actql_sqlite_original *q = callbacks.sqlite(reply);
    actql_local_host_resources *o = callbacks.original(reply);
    int same = h && s && r && q && h == host && s == sqlite_host &&
        r == read && q == sqlite && o == original;
    if (o) moonbit_decref(o);
    if (q) moonbit_decref(q);
    if (r) moonbit_decref(r);
    if (s) moonbit_decref(s);
    if (h) moonbit_decref(h);
    return same;
}

int actql_host_resources_drop_reply(actql_local_host_resources_reply **reply,
    actql_control_host *host, actql_control_host *sqlite_host, actql_parent_read *read,
    actql_sqlite_original *sqlite, actql_local_host_resources *original) {
    if (!reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*reply) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!same_originals(*reply, host, sqlite_host, read, sqlite, original))
        return ACTQL_CONTROL_INVALID_SLOT;
    actql_local_host_resources_reply *value = *reply;
    *reply = NULL;
    moonbit_decref(value);
    return ACTQL_CONTROL_OK;
}

int actql_host_resources_finish_closed_data(actql_control_host **host,
    actql_control_host **sqlite_host, actql_parent_read **read,
    actql_sqlite_original **sqlite, actql_local_host_resources **original,
    actql_local_host_resources_reply **reply) {
    const void *slots[] = {host, sqlite_host, read, sqlite, original, reply};
    if (!distinct_slots(slots, 6)) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*host && !*sqlite_host && !*read && !*sqlite && !*original && !*reply)
        return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!*host || !*sqlite_host || !*read || !*sqlite || !*original || !*reply ||
        callbacks.operation(*reply) != 8 || callbacks.origin(*reply) != 0 ||
        callbacks.family(*reply) != 0 || callbacks.closed(*reply) != 1 ||
        !same_originals(*reply, *host, *sqlite_host, *read, *sqlite, *original))
        return ACTQL_CONTROL_INVALID_SLOT;
    actql_local_host_resources_reply *v = *reply; *reply = NULL; moonbit_decref(v);
    actql_local_host_resources *o = *original; *original = NULL; moonbit_decref(o);
    actql_sqlite_original *q = *sqlite; *sqlite = NULL; moonbit_decref(q);
    actql_parent_read *r = *read; *read = NULL; moonbit_decref(r);
    actql_control_host *s = *sqlite_host; *sqlite_host = NULL; moonbit_decref(s);
    actql_control_host *h = *host; *host = NULL; moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}

int actql_host_resources_finish_refused_bind_data(actql_control_host **host,
    actql_control_host **sqlite_host, actql_parent_read **read,
    actql_sqlite_original **sqlite, actql_local_host_resources **original,
    actql_local_host_resources_reply **reply) {
    const void *slots[] = {host, sqlite_host, read, sqlite, original, reply};
    if (!distinct_slots(slots, 6)) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*host && !*sqlite_host && !*read && !*sqlite && !*original && !*reply)
        return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!*host || !*sqlite_host || !*read || !*sqlite || *original || !*reply ||
        callbacks.operation(*reply) != 1 || callbacks.origin(*reply) == 0 ||
        callbacks.family(*reply) == 0 ||
        !same_originals(*reply, *host, *sqlite_host, *read, *sqlite, NULL))
        return ACTQL_CONTROL_INVALID_SLOT;
    actql_local_host_resources_reply *v = *reply; *reply = NULL; moonbit_decref(v);
    actql_sqlite_original *q = *sqlite; *sqlite = NULL; moonbit_decref(q);
    actql_parent_read *r = *read; *read = NULL; moonbit_decref(r);
    actql_control_host *s = *sqlite_host; *sqlite_host = NULL; moonbit_decref(s);
    actql_control_host *h = *host; *host = NULL; moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}
