#include "original_read_shim.h"
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
    actql_parent_read_prepare_fn prepare;
    actql_parent_read_operation_fn current, enter, leave, cleanup, close;
    actql_parent_read_host_fn host;
    actql_parent_read_domain_fn domain;
    actql_parent_read_original_fn original;
    actql_parent_read_tag_fn operation, issue;
} callbacks;
static int registered;
void actql_native_control_register_parent_read_roots(
    actql_parent_read_prepare_fn prepare, actql_parent_read_operation_fn current,
    actql_parent_read_operation_fn enter, actql_parent_read_operation_fn leave,
    actql_parent_read_operation_fn cleanup, actql_parent_read_operation_fn close,
    actql_parent_read_host_fn host, actql_parent_read_domain_fn domain,
    actql_parent_read_original_fn original, actql_parent_read_tag_fn operation,
    actql_parent_read_tag_fn issue) {
    if (registered) return;
    if (!prepare || !current || !enter || !leave || !cleanup || !close ||
        !host || !domain || !original || !operation || !issue) {
        registered = -1;
        return;
    }
    callbacks.prepare = prepare; callbacks.current = current;
    callbacks.enter = enter; callbacks.leave = leave;
    callbacks.cleanup = cleanup; callbacks.close = close;
    callbacks.host = host; callbacks.domain = domain; callbacks.original = original;
    callbacks.operation = operation; callbacks.issue = issue;
    registered = 1;
}
int actql_parent_read_prepare_into(actql_control_host *host, actql_domain *domain,
    int64_t bootstrap_retained, int64_t bootstrap_execution, int64_t workspace,
    int64_t read_retained, int64_t read_execution, actql_parent_read_reply **reply) {
    if (!host || !domain || !reply || *reply) return ACTQL_CONTROL_INVALID_SLOT;
    /* The outer control carrier must not acquire itself inside the context
     * whose last managed alias it will later retire. No scope switching here. */
    if (registered != 1 || inside_read_scope()) return ACTQL_CONTROL_UNAVAILABLE;
    *reply = callbacks.prepare(host, domain, bootstrap_retained, bootstrap_execution,
        workspace, read_retained, read_execution);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
static int operate(actql_parent_read_operation_fn call, actql_control_host *host,
    actql_parent_read *original, actql_parent_read_reply **reply) {
    if (!host || !original || !reply || *reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *reply = call(host, original);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
#define READ_OPERATION(NAME, FIELD) \
int NAME(actql_control_host *host, actql_parent_read *original, actql_parent_read_reply **reply) { \
    return operate(callbacks.FIELD, host, original, reply); \
}
READ_OPERATION(actql_parent_read_current_into, current)
READ_OPERATION(actql_parent_read_enter_into, enter)
READ_OPERATION(actql_parent_read_leave_into, leave)
READ_OPERATION(actql_parent_read_cleanup_into, cleanup)
READ_OPERATION(actql_parent_read_close_into, close)
#undef READ_OPERATION
int actql_parent_read_originals_into(actql_parent_read_reply *reply,
    actql_control_host **host, actql_domain **domain, actql_parent_read **original) {
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
int32_t actql_parent_read_operation(actql_parent_read_reply *reply) {
    return registered == 1 && reply ? callbacks.operation(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
int32_t actql_parent_read_issue_family(actql_parent_read_reply *reply) {
    return registered == 1 && reply ? callbacks.issue(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
static int same_reply(actql_parent_read_reply *reply, actql_control_host *host,
    actql_domain *domain, actql_parent_read *original) {
    actql_control_host *h = callbacks.host(reply);
    actql_domain *d = callbacks.domain(reply);
    actql_parent_read *o = callbacks.original(reply);
    int same = h && h == host && d && d == domain && o == original;
    if (o) moonbit_decref(o);
    if (d) moonbit_decref(d);
    if (h) moonbit_decref(h);
    return same;
}
int actql_parent_read_drop_reply(actql_parent_read_reply **reply, actql_control_host *host,
    actql_domain *domain, actql_parent_read *original) {
    if (!reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*reply) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!same_reply(*reply, host, domain, original)) return ACTQL_CONTROL_INVALID_SLOT;
    actql_parent_read_reply *r = *reply; *reply = NULL; moonbit_decref(r);
    return ACTQL_CONTROL_OK;
}
static int distinct(void *host, void *domain, void *original, void *reply) {
    return host && domain && original && reply && host != domain && host != original &&
        host != reply && domain != original && domain != reply && original != reply;
}
int actql_parent_read_finish_closed_data(actql_control_host **host, actql_domain **domain,
    actql_parent_read **original, actql_parent_read_reply **reply) {
    if (!distinct(host, domain, original, reply)) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*host && !*domain && !*original && !*reply) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!*host || !*domain || !*original || !*reply || callbacks.operation(*reply) != 6 ||
        callbacks.issue(*reply) != 0 || !same_reply(*reply, *host, *domain, *original))
        return ACTQL_CONTROL_INVALID_SLOT;
    actql_parent_read_reply *r = *reply; *reply = NULL; moonbit_decref(r);
    actql_parent_read *o = *original; *original = NULL; moonbit_decref(o);
    actql_domain *d = *domain; *domain = NULL; moonbit_decref(d);
    actql_control_host *h = *host; *host = NULL; moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}
int actql_parent_read_finish_refused_prepare(actql_control_host **host, actql_domain **domain,
    actql_parent_read_reply **reply) {
    if (!host || !domain || !reply || (void *)host == (void *)domain ||
        (void *)host == (void *)reply || (void *)domain == (void *)reply)
        return ACTQL_CONTROL_INVALID_SLOT;
    if (!*host && !*domain && !*reply) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!*host || !*domain || !*reply || callbacks.operation(*reply) != 1 ||
        callbacks.issue(*reply) <= 0 || !same_reply(*reply, *host, *domain, NULL))
        return ACTQL_CONTROL_INVALID_SLOT;
    actql_parent_read_reply *r = *reply; *reply = NULL; moonbit_decref(r);
    actql_domain *d = *domain; *domain = NULL; moonbit_decref(d);
    actql_control_host *h = *host; *host = NULL; moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}
