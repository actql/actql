#include "live_channel_shim.h"

static struct {
    actql_live_prepare_fn prepare;
    actql_live_bind_fn bind;
    actql_live_operate_fn operate;
    actql_live_report_fn report;
    actql_live_host_fn host;
    actql_live_domain_fn domain;
    actql_live_channel_fn channel;
    actql_live_tag_fn operation, issue, state;
    actql_live_limit_fn limit;
    actql_live_description_fn description;
} callbacks;
static int registered;

void actql_native_control_register_live_channel_roots(
    actql_live_prepare_fn prepare, actql_live_bind_fn bind,
    actql_live_operate_fn operate, actql_live_report_fn report,
    actql_live_host_fn host, actql_live_domain_fn domain,
    actql_live_channel_fn channel, actql_live_tag_fn operation,
    actql_live_tag_fn issue, actql_live_tag_fn state,
    actql_live_limit_fn limit, actql_live_description_fn description) {
    if (registered) return;
    if (!prepare || !bind || !operate || !report || !host || !domain ||
        !channel || !operation || !issue || !state || !limit || !description) {
        registered = -1;
        return;
    }
    callbacks.prepare = prepare; callbacks.bind = bind;
    callbacks.operate = operate; callbacks.report = report;
    callbacks.host = host; callbacks.domain = domain; callbacks.channel = channel;
    callbacks.operation = operation; callbacks.issue = issue;
    callbacks.state = state; callbacks.limit = limit; callbacks.description = description;
    registered = 1;
}

int actql_live_channel_prepare_into(actql_control_host *host, actql_domain *domain,
    int32_t pid, int32_t read_fd, int32_t write_fd, int64_t nonce,
    actql_live_channel_reply **slot) {
    if (!host || !domain || !slot || *slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *slot = callbacks.prepare(host, domain, pid, read_fd, write_fd, nonce);
    return *slot ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

int actql_live_channel_bind_into(actql_control_host *host, actql_domain *domain,
    actql_live_channel *channel, int64_t nonce, int64_t offset, int64_t bytes,
    actql_live_channel_reply **slot) {
    if (!host || !domain || !channel || !slot || *slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *slot = callbacks.bind(host, domain, channel, nonce, offset, bytes);
    return *slot ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

int actql_live_channel_operate_into(actql_control_host *host, actql_domain *domain,
    actql_live_channel *channel, int32_t operation, actql_live_channel_reply **slot) {
    if (!host || !domain || !channel || !slot || *slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *slot = callbacks.operate(host, domain, channel, operation);
    return *slot ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

int actql_live_channel_report_into(actql_control_host *host, actql_domain *domain,
    actql_live_channel *channel, int32_t planning, int32_t attempts, int32_t holdings,
    int64_t transferred, int64_t uncertain, int64_t reserved_transfer, int64_t held,
    int64_t reserved_retention, int64_t reserved_execution, int64_t peak_retention,
    actql_live_channel_reply **slot) {
    if (!host || !domain || !channel || !slot || *slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *slot = callbacks.report(host, domain, channel, planning, attempts, holdings,
        transferred, uncertain, reserved_transfer, held, reserved_retention,
        reserved_execution, peak_retention);
    return *slot ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

static int distinct(const void *a, const void *b, const void *c, const void *d) {
    return a != b && a != c && a != d && b != c && b != d && c != d;
}

int actql_live_channel_originals_into(actql_live_channel_reply *reply,
    actql_control_host **host, actql_domain **domain, actql_live_channel **channel) {
    if (!reply || !host || !domain || !channel || *host || *domain || *channel ||
        (void *)host == (void *)domain || (void *)host == (void *)channel ||
        (void *)domain == (void *)channel) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *host = callbacks.host(reply);
    if (!*host) return ACTQL_CONTROL_UNAVAILABLE;
    *domain = callbacks.domain(reply);
    if (!*domain) return ACTQL_CONTROL_UNAVAILABLE;
    *channel = callbacks.channel(reply);
    return ACTQL_CONTROL_OK;
}

int32_t actql_live_channel_operation(actql_live_channel_reply *reply) {
    return registered == 1 && reply ? callbacks.operation(reply) : ACTQL_CONTROL_UNAVAILABLE;
}

int32_t actql_live_channel_issue_family(actql_live_channel_reply *reply) {
    return registered == 1 && reply ? callbacks.issue(reply) : ACTQL_CONTROL_UNAVAILABLE;
}

static int same_reply(actql_live_channel_reply *reply, actql_control_host *host,
    actql_domain *domain, actql_live_channel *channel) {
    actql_control_host *h = callbacks.host(reply);
    actql_domain *d = callbacks.domain(reply);
    actql_live_channel *c = callbacks.channel(reply);
    int same = h && d && h == host && d == domain && c == channel;
    if (c) moonbit_decref(c);
    if (d) moonbit_decref(d);
    if (h) moonbit_decref(h);
    return same;
}

int actql_live_channel_copy_state(actql_live_channel_reply *reply,
    actql_control_host *host, actql_domain *domain, actql_live_channel *channel,
    int32_t *out) {
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!reply || !host || !domain || !channel || !out ||
        callbacks.operation(reply) != 4 || callbacks.issue(reply) != 0 ||
        !same_reply(reply, host, domain, channel)) return ACTQL_CONTROL_INVALID_SLOT;
    int32_t state = callbacks.state(reply);
    if (state != 0 && state != 1) return ACTQL_CONTROL_INVALID_SLOT;
    *out = state;
    return ACTQL_CONTROL_OK;
}

int actql_live_channel_copy_limits(actql_live_channel_reply *reply,
    actql_control_host *host, actql_domain *domain, actql_live_channel *channel,
    int64_t out[6]) {
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!reply || !host || !domain || !channel || !out ||
        callbacks.operation(reply) != 5 || callbacks.issue(reply) != 0 ||
        !same_reply(reply, host, domain, channel)) return ACTQL_CONTROL_INVALID_SLOT;
    int64_t values[6];
    for (int32_t i = 0; i < 6; ++i) {
        values[i] = callbacks.limit(reply, i);
        if (values[i] < 0) return ACTQL_CONTROL_INVALID_SLOT;
    }
    for (int32_t i = 0; i < 6; ++i) out[i] = values[i];
    return ACTQL_CONTROL_OK;
}

int actql_live_channel_copy_capacities(actql_live_channel_reply *reply,
    actql_control_host *host, actql_domain *domain, actql_live_channel *channel,
    int64_t out[2]) {
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!reply || !host || !domain || !channel || !out ||
        callbacks.operation(reply) != 9 || callbacks.issue(reply) != 0 ||
        !same_reply(reply, host, domain, channel)) return ACTQL_CONTROL_INVALID_SLOT;
    int64_t vm = callbacks.limit(reply, 6);
    int64_t baseline = callbacks.limit(reply, 7);
    if (vm != 16777216 || baseline <= 0 || baseline > INT64_MAX - vm)
        return ACTQL_CONTROL_INVALID_SLOT;
    out[0] = vm;
    out[1] = baseline;
    return ACTQL_CONTROL_OK;
}

int actql_live_channel_drop_reply(actql_live_channel_reply **slot,
    actql_control_host *host, actql_domain *domain, actql_live_channel *channel) {
    if (!slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*slot) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!host || !domain || !same_reply(*slot, host, domain, channel))
        return ACTQL_CONTROL_INVALID_SLOT;
    actql_live_channel_reply *owned = *slot;
    *slot = NULL;
    moonbit_decref(owned);
    return ACTQL_CONTROL_OK;
}

int actql_live_channel_finish_retired_data(actql_control_host **host,
    actql_domain **domain, actql_live_channel **channel, actql_live_channel_reply **reply) {
    if (!host || !domain || !channel || !reply || !distinct(host, domain, channel, reply))
        return ACTQL_CONTROL_INVALID_SLOT;
    if (!*host && !*domain && !*channel && !*reply) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!*host || !*domain || !*channel || !*reply ||
        callbacks.operation(*reply) != 8 || callbacks.issue(*reply) != 0 ||
        !same_reply(*reply, *host, *domain, *channel)) return ACTQL_CONTROL_INVALID_SLOT;
    actql_live_channel_reply *r = *reply;
    actql_live_channel *c = *channel;
    actql_domain *d = *domain;
    actql_control_host *h = *host;
    /* All validation and slot clearing precedes any refcount/finalizer action. */
    *reply = NULL; *channel = NULL; *domain = NULL; *host = NULL;
    moonbit_decref(r); moonbit_decref(c); moonbit_decref(d); moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}

int actql_live_channel_finish_refused_prepare(actql_control_host **host,
    actql_domain **domain, actql_live_channel_reply **reply) {
    if (!host || !domain || !reply || (void *)host == (void *)domain ||
        (void *)host == (void *)reply || (void *)domain == (void *)reply)
        return ACTQL_CONTROL_INVALID_SLOT;
    if (!*host && !*domain && !*reply) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!*host || !*domain || !*reply || callbacks.operation(*reply) != 1 ||
        callbacks.issue(*reply) <= 0 || !same_reply(*reply, *host, *domain, NULL))
        return ACTQL_CONTROL_INVALID_SLOT;
    actql_live_channel_reply *r = *reply;
    actql_domain *d = *domain;
    actql_control_host *h = *host;
    *reply = NULL; *domain = NULL; *host = NULL;
    moonbit_decref(r); moonbit_decref(d); moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}
