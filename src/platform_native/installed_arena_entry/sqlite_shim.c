#include "sqlite_shim.h"
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
    actql_sqlite_prepare_fn prepare;
    actql_sqlite_operation_fn current, close;
    actql_sqlite_host_fn host;
    actql_sqlite_domain_fn domain;
    actql_sqlite_original_fn original;
    actql_sqlite_tag_fn operation, issue;
} callbacks;
static int registered;
void actql_native_control_register_sqlite_roots(actql_sqlite_prepare_fn prepare,
    actql_sqlite_operation_fn current, actql_sqlite_operation_fn close,
    actql_sqlite_host_fn host, actql_sqlite_domain_fn domain,
    actql_sqlite_original_fn original, actql_sqlite_tag_fn operation, actql_sqlite_tag_fn issue) {
    if (registered) return;
    if (!prepare || !current || !close || !host || !domain || !original || !operation || !issue) {
        registered = -1;
        return;
    }
    callbacks.prepare = prepare; callbacks.current = current; callbacks.close = close;
    callbacks.host = host; callbacks.domain = domain; callbacks.original = original;
    callbacks.operation = operation; callbacks.issue = issue;
    registered = 1;
}
int actql_sqlite_prepare_utf16_into(actql_control_host *host, actql_domain *domain,
    const uint16_t *path, int32_t units, int64_t heap, int32_t diagnostic, actql_sqlite_reply **reply) {
    if (!host || !domain || !path || units <= 0 || units > 4096 || !reply || *reply)
        return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1 || inside_read_scope())
        return ACTQL_CONTROL_UNAVAILABLE;
    moonbit_string_t managed_path = moonbit_make_string_raw(units);
    memcpy(managed_path, path, (size_t)units * sizeof(uint16_t));
    /* Publish the original reply before releasing the temporary path. A lost
     * foreign response cannot discard the newly returned partial custody. */
    *reply = callbacks.prepare(host, domain, managed_path, heap, diagnostic);
    moonbit_decref(managed_path);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
static int operate(actql_sqlite_operation_fn operation, actql_control_host *host,
    actql_sqlite_original *original, actql_sqlite_reply **reply) {
    if (!host || !original || !reply || *reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1 || inside_read_scope()) return ACTQL_CONTROL_UNAVAILABLE;
    *reply = operation(host, original);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
int actql_sqlite_current_into(actql_control_host *host, actql_sqlite_original *original, actql_sqlite_reply **reply) {
    return operate(callbacks.current, host, original, reply);
}
int actql_sqlite_close_into(actql_control_host *host, actql_sqlite_original *original, actql_sqlite_reply **reply) {
    return operate(callbacks.close, host, original, reply);
}
int actql_sqlite_originals_into(actql_sqlite_reply *reply, actql_control_host **host,
    actql_domain **domain, actql_sqlite_original **original) {
    if (!reply || !host || !domain || !original || *host || *domain || *original ||
        (void *)host == (void *)domain || (void *)host == (void *)original ||
        (void *)domain == (void *)original) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *host = callbacks.host(reply);
    if (!*host) return ACTQL_CONTROL_UNAVAILABLE;
    *domain = callbacks.domain(reply);
    if (!*domain) return ACTQL_CONTROL_UNAVAILABLE;
    *original = callbacks.original(reply);
    return ACTQL_CONTROL_OK;
}
int32_t actql_sqlite_operation(actql_sqlite_reply *reply) {
    return registered == 1 && reply ? callbacks.operation(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
int32_t actql_sqlite_issue_family(actql_sqlite_reply *reply) {
    return registered == 1 && reply ? callbacks.issue(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
static int same_reply(actql_sqlite_reply *reply, actql_control_host *host,
    actql_domain *domain, actql_sqlite_original *original) {
    actql_control_host *h = callbacks.host(reply);
    actql_domain *d = callbacks.domain(reply);
    actql_sqlite_original *o = callbacks.original(reply);
    int same = h && h == host && d && d == domain && o == original;
    if (o) moonbit_decref(o);
    if (d) moonbit_decref(d);
    if (h) moonbit_decref(h);
    return same;
}
int actql_sqlite_drop_reply(actql_sqlite_reply **reply, actql_control_host *host,
    actql_domain *domain, actql_sqlite_original *original) {
    if (!reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*reply) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!same_reply(*reply, host, domain, original)) return ACTQL_CONTROL_INVALID_SLOT;
    actql_sqlite_reply *owned = *reply;
    *reply = NULL;
    moonbit_decref(owned);
    return ACTQL_CONTROL_OK;
}
static int distinct(void *host, void *domain, void *original, void *reply) {
    return host && domain && original && reply && host != domain && host != original &&
        host != reply && domain != original && domain != reply && original != reply;
}
int actql_sqlite_finish_closed_data(actql_control_host **host, actql_domain **domain,
    actql_sqlite_original **original, actql_sqlite_reply **reply) {
    if (!distinct(host, domain, original, reply)) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*host && !*domain && !*original && !*reply) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!*host || !*domain || !*original || !*reply || callbacks.operation(*reply) != 3 ||
        callbacks.issue(*reply) != 0 || !same_reply(*reply, *host, *domain, *original))
        return ACTQL_CONTROL_INVALID_SLOT;
    actql_sqlite_reply *r = *reply; *reply = NULL; moonbit_decref(r);
    actql_sqlite_original *o = *original; *original = NULL; moonbit_decref(o);
    actql_domain *d = *domain; *domain = NULL; moonbit_decref(d);
    actql_control_host *h = *host; *host = NULL; moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}
int actql_sqlite_finish_refused_prepare(actql_control_host **host, actql_domain **domain,
    actql_sqlite_reply **reply) {
    if (!host || !domain || !reply || (void *)host == (void *)domain ||
        (void *)host == (void *)reply || (void *)domain == (void *)reply)
        return ACTQL_CONTROL_INVALID_SLOT;
    if (!*host && !*domain && !*reply) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!*host || !*domain || !*reply || callbacks.operation(*reply) != 1 ||
        callbacks.issue(*reply) <= 0 || !same_reply(*reply, *host, *domain, NULL))
        return ACTQL_CONTROL_INVALID_SLOT;
    actql_sqlite_reply *r = *reply; *reply = NULL; moonbit_decref(r);
    actql_domain *d = *domain; *domain = NULL; moonbit_decref(d);
    actql_control_host *h = *host; *host = NULL; moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}
