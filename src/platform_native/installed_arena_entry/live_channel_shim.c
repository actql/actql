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
    int32_t reserved_attempts, int32_t live_reservations, int32_t live_delegations,
    actql_live_channel_reply **slot) {
    if (!host || !domain || !channel || !slot || *slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *slot = callbacks.report(host, domain, channel, planning, attempts, holdings,
        transferred, uncertain, reserved_transfer, held, reserved_retention,
        reserved_execution, peak_retention, reserved_attempts, live_reservations, live_delegations);
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
    if (!*host || !*domain || !*reply || (callbacks.operation(*reply) != 1 && callbacks.operation(*reply) != 10) ||
        callbacks.issue(*reply) <= 0 || !same_reply(*reply, *host, *domain, NULL))
        return ACTQL_CONTROL_INVALID_SLOT;
    actql_live_channel_reply *r = *reply;
    actql_domain *d = *domain;
    actql_control_host *h = *host;
    *reply = NULL; *domain = NULL; *host = NULL;
    moonbit_decref(r); moonbit_decref(d); moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}

/* Code roots, not another authority registry or allocator/provider. */
static struct {
    actql_live_before_fn before;
    actql_live_child_fn child;
    actql_ledger_prepare_fn prepare;
    actql_ledger_operate_fn operate;
    actql_ledger_host_fn host;
    actql_ledger_domain_fn domain;
    actql_ledger_channel_fn channel;
    actql_ledger_frame_fn frame;
    actql_ledger_tag_fn operation, issue;
    actql_ledger_limit_fn limit;
    actql_ledger_description_fn description;
} preparation;
static int preparation_registered;

void actql_native_control_register_live_preparation_roots(
    actql_live_before_fn before, actql_live_child_fn child,
    actql_ledger_prepare_fn prepare, actql_ledger_operate_fn operate,
    actql_ledger_host_fn host, actql_ledger_domain_fn domain,
    actql_ledger_channel_fn channel, actql_ledger_frame_fn frame,
    actql_ledger_tag_fn operation, actql_ledger_tag_fn issue,
    actql_ledger_limit_fn limit, actql_ledger_description_fn description) {
    if (preparation_registered) return;
    if (!before || !child || !prepare || !operate || !host || !domain ||
        !channel || !frame || !operation || !issue || !limit || !description) {
        preparation_registered = -1;
        return;
    }
    preparation.before = before; preparation.child = child;
    preparation.prepare = prepare; preparation.operate = operate;
    preparation.host = host; preparation.domain = domain;
    preparation.channel = channel; preparation.frame = frame;
    preparation.operation = operation; preparation.issue = issue;
    preparation.limit = limit; preparation.description = description;
    preparation_registered = 1;
}

int actql_live_channel_prepare_before_spawn_into(actql_control_host *host,
    actql_domain *domain, int32_t read_fd, int32_t write_fd, int64_t nonce,
    actql_live_channel_reply **slot) {
    if (!host || !domain || !slot || *slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (preparation_registered != 1 || registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *slot = preparation.before(host, domain, read_fd, write_fd, nonce);
    return *slot ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

int actql_live_channel_bind_child_into(actql_control_host *host, actql_domain *domain,
    actql_live_channel *channel, int32_t child, actql_live_channel_reply **slot) {
    if (!host || !domain || !channel || !slot || *slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (preparation_registered != 1 || registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *slot = preparation.child(host, domain, channel, child);
    return *slot ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

int actql_channel_ledger_prepare_into(actql_control_host *host, actql_domain *domain,
    actql_live_channel *channel, actql_channel_ledger_reply **slot) {
    if (!host || !domain || !channel || !slot || *slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (preparation_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *slot = preparation.prepare(host, domain, channel);
    return *slot ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

int actql_channel_ledger_operate_into(actql_control_host *host, actql_domain *domain,
    actql_live_channel *channel, actql_original_child_frame *frame,
    int32_t operation, int64_t retained, int64_t execution,
    actql_channel_ledger_reply **slot) {
    if (!host || !domain || !channel || !frame || !slot || *slot ||
        operation < 2 || operation > 10 ||
        (operation != 3 && (retained != 0 || execution != 0)))
        return ACTQL_CONTROL_INVALID_SLOT;
    if (preparation_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *slot = preparation.operate(host, domain, channel, frame, operation, retained, execution);
    return *slot ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

static int preparation_slots_distinct(const void *const *slots, size_t count) {
    for (size_t i = 0; i < count; i++)
        for (size_t j = i + 1; j < count; j++)
            if (slots[i] == slots[j]) return 0;
    return 1;
}

int actql_channel_ledger_originals_into(actql_channel_ledger_reply *reply,
    actql_control_host **host, actql_domain **domain, actql_live_channel **channel,
    actql_original_child_frame **frame) {
    const void *slots[] = {host, domain, channel, frame};
    if (!reply || !host || !domain || !channel || !frame || *host || *domain ||
        *channel || *frame || !preparation_slots_distinct(slots, 4))
        return ACTQL_CONTROL_INVALID_SLOT;
    if (preparation_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *host = preparation.host(reply);
    if (!*host) return ACTQL_CONTROL_UNAVAILABLE;
    *domain = preparation.domain(reply);
    if (!*domain) return ACTQL_CONTROL_UNAVAILABLE;
    *channel = preparation.channel(reply);
    if (!*channel) return ACTQL_CONTROL_UNAVAILABLE;
    *frame = preparation.frame(reply);
    return ACTQL_CONTROL_OK;
}

int32_t actql_channel_ledger_operation(actql_channel_ledger_reply *reply) {
    return preparation_registered == 1 && reply ? preparation.operation(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
int32_t actql_channel_ledger_issue_family(actql_channel_ledger_reply *reply) {
    return preparation_registered == 1 && reply ? preparation.issue(reply) : ACTQL_CONTROL_UNAVAILABLE;
}

static int same_ledger_reply(actql_channel_ledger_reply *reply, actql_control_host *host,
    actql_domain *domain, actql_live_channel *channel, actql_original_child_frame *frame) {
    actql_control_host *h = preparation.host(reply);
    actql_domain *d = preparation.domain(reply);
    actql_live_channel *c = preparation.channel(reply);
    actql_original_child_frame *f = preparation.frame(reply);
    int same = h && d && c && h == host && d == domain && c == channel && f == frame;
    if (f) moonbit_decref(f);
    if (c) moonbit_decref(c);
    if (d) moonbit_decref(d);
    if (h) moonbit_decref(h);
    return same;
}

int actql_channel_ledger_copy_limits(actql_channel_ledger_reply *reply,
    actql_control_host *host, actql_domain *domain, actql_live_channel *channel,
    actql_original_child_frame *frame, int64_t out[6]) {
    if (preparation_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!reply || !host || !domain || !channel || !frame || !out ||
        preparation.operation(reply) != 5 || preparation.issue(reply) != 0 ||
        !same_ledger_reply(reply, host, domain, channel, frame)) return ACTQL_CONTROL_INVALID_SLOT;
    int64_t values[6];
    for (int32_t i = 0; i < 6; i++) {
        values[i] = preparation.limit(reply, i);
        if (values[i] < 0) return ACTQL_CONTROL_INVALID_SLOT;
    }
    for (int32_t i = 0; i < 6; i++) out[i] = values[i];
    return ACTQL_CONTROL_OK;
}

int actql_channel_ledger_drop_reply(actql_channel_ledger_reply **slot,
    actql_control_host *host, actql_domain *domain, actql_live_channel *channel,
    actql_original_child_frame *frame) {
    if (!slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*slot) return ACTQL_CONTROL_OK;
    if (preparation_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!host || !domain || !channel ||
        !same_ledger_reply(*slot, host, domain, channel, frame)) return ACTQL_CONTROL_INVALID_SLOT;
    actql_channel_ledger_reply *owned = *slot;
    *slot = NULL;
    moonbit_decref(owned);
    return ACTQL_CONTROL_OK;
}

int actql_channel_ledger_finish_retired_data(actql_control_host **host,
    actql_domain **domain, actql_live_channel **channel, actql_original_child_frame **frame,
    actql_channel_ledger_reply **reply, actql_live_channel_reply *retired) {
    const void *slots[] = {host, domain, channel, frame, reply};
    if (!host || !domain || !channel || !frame || !reply ||
        !preparation_slots_distinct(slots, 5)) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*host && !*domain && !*channel && !*frame && !*reply) return ACTQL_CONTROL_OK;
    if (registered != 1 || preparation_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!*host || !*domain || !*channel || !*reply || !retired ||
        callbacks.operation(retired) != 8 || callbacks.issue(retired) != 0 ||
        !same_reply(retired, *host, *domain, *channel) ||
        !same_ledger_reply(*reply, *host, *domain, *channel, *frame))
        return ACTQL_CONTROL_INVALID_SLOT;
    if (*frame) {
        if (preparation.operation(*reply) != 8 || preparation.issue(*reply) != 0)
            return ACTQL_CONTROL_INVALID_SLOT;
    } else if (preparation.operation(*reply) != 1 || preparation.issue(*reply) <= 0) {
        return ACTQL_CONTROL_INVALID_SLOT;
    }
    actql_control_host *h = *host;
    actql_domain *d = *domain;
    actql_live_channel *c = *channel;
    actql_original_child_frame *f = *frame;
    actql_channel_ledger_reply *r = *reply;
    *host = NULL; *domain = NULL; *channel = NULL; *frame = NULL; *reply = NULL;
    if (r) moonbit_decref(r);
    if (f) moonbit_decref(f);
    moonbit_decref(c); moonbit_decref(d); moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}
