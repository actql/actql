#include "process_shim.h"
#include <string.h>

/* Code roots only; existing nominal process/domain Owners keep all authority. */
static struct {
    actql_process_prepare_fn prepare;
    actql_process_operate_fn operate;
    actql_process_child_fn child;
    actql_process_host_fn host;
    actql_process_domain_fn domain;
    actql_process_original_fn process;
    actql_process_channel_fn channel;
    actql_process_frame_fn frame;
    actql_process_tag_fn operation, issue, backing, stop;
    actql_process_descriptor_fn descriptor;
    actql_process_description_fn description;
} callbacks;
static int registered;
void actql_native_control_register_process_roots(
    actql_process_prepare_fn prepare, actql_process_operate_fn operate,
    actql_process_child_fn child, actql_process_host_fn host,
    actql_process_domain_fn domain, actql_process_original_fn process,
    actql_process_channel_fn channel, actql_process_frame_fn frame,
    actql_process_tag_fn operation, actql_process_tag_fn issue,
    actql_process_descriptor_fn descriptor, actql_process_tag_fn backing,
    actql_process_tag_fn stop, actql_process_description_fn description) {
    if (registered) return;
    if (!prepare || !operate || !child || !host || !domain || !process ||
        !channel || !frame || !operation || !issue || !descriptor || !backing ||
        !stop || !description) { registered = -1; return; }
    callbacks.prepare = prepare; callbacks.operate = operate; callbacks.child = child;
    callbacks.host = host; callbacks.domain = domain; callbacks.process = process;
    callbacks.channel = channel; callbacks.frame = frame; callbacks.operation = operation;
    callbacks.issue = issue; callbacks.descriptor = descriptor; callbacks.backing = backing;
    callbacks.stop = stop; callbacks.description = description;
    registered = 1;
}
int actql_process_prepare_utf16_into(actql_control_host *host, actql_domain *domain,
    const uint16_t *path, int32_t units, int32_t descriptor, int64_t nonce,
    int64_t retained, int64_t execution, actql_process_reply **slot) {
    if (!host || !domain || !path || units <= 0 || !slot || *slot)
        return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    moonbit_string_t text = moonbit_make_string_raw(units);
    memcpy(text, path, (size_t)units * sizeof(uint16_t));
    *slot = callbacks.prepare(host, domain, text, descriptor, nonce, retained, execution);
    moonbit_decref(text);
    return *slot ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
int actql_process_operate_into(actql_control_host *host, actql_domain *domain,
    actql_process *process, int32_t operation, actql_process_reply **slot) {
    if (!host || !domain || !process || !slot || *slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *slot = callbacks.operate(host, domain, process, operation);
    return *slot ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
int actql_process_child_utf16_into(actql_control_host *host, actql_domain *domain,
    actql_process *process, const uint16_t *executable, int32_t units,
    const uint8_t *arguments, int32_t arguments_bytes,
    const uint8_t *environment, int32_t environment_bytes, actql_process_reply **slot) {
    if (!host || !domain || !process || !executable || units <= 0 ||
        arguments_bytes < 0 || environment_bytes < 0 ||
        (arguments_bytes && !arguments) || (environment_bytes && !environment) ||
        !slot || *slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    moonbit_string_t text = moonbit_make_string_raw(units);
    moonbit_bytes_t args = moonbit_make_bytes_raw(arguments_bytes);
    moonbit_bytes_t env = moonbit_make_bytes_raw(environment_bytes);
    memcpy(text, executable, (size_t)units * sizeof(uint16_t));
    if (arguments_bytes) memcpy(args, arguments, (size_t)arguments_bytes);
    if (environment_bytes) memcpy(env, environment, (size_t)environment_bytes);
    *slot = callbacks.child(host, domain, process, text, args, env);
    moonbit_decref(env); moonbit_decref(args); moonbit_decref(text);
    return *slot ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
int actql_process_originals_into(actql_process_reply *reply, actql_control_host **host,
    actql_domain **domain, actql_process **process, actql_live_channel **channel,
    actql_original_child_frame **frame) {
    if (!reply || !host || !domain || !process || !channel || !frame ||
        *host || *domain || *process || *channel || *frame) return ACTQL_CONTROL_INVALID_SLOT;
    const void *slots[] = {host, domain, process, channel, frame};
    for (size_t i = 0; i < 5; i++)
        for (size_t j = 0; j < i; j++)
            if (slots[i] == slots[j]) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *host = callbacks.host(reply);
    if (!*host) return ACTQL_CONTROL_UNAVAILABLE;
    *domain = callbacks.domain(reply);
    if (!*domain) return ACTQL_CONTROL_UNAVAILABLE;
    *process = callbacks.process(reply);
    *channel = callbacks.channel(reply);
    *frame = callbacks.frame(reply);
    return ACTQL_CONTROL_OK;
}
int32_t actql_process_operation(actql_process_reply *reply) {
    return registered == 1 && reply ? callbacks.operation(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
int32_t actql_process_issue_family(actql_process_reply *reply) {
    return registered == 1 && reply ? callbacks.issue(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
static int same_process(actql_process_reply *reply, actql_control_host *host,
    actql_domain *domain, actql_process *process) {
    actql_control_host *h = callbacks.host(reply);
    actql_domain *d = callbacks.domain(reply);
    actql_process *p = callbacks.process(reply);
    int same = h && h == host && d && d == domain && p == process;
    if (p) moonbit_decref(p);
    if (d) moonbit_decref(d);
    if (h) moonbit_decref(h);
    return same;
}
int actql_process_copy_facts(actql_process_reply *reply, actql_control_host *host,
    actql_domain *domain, actql_process *process, int32_t facts[4]) {
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!reply || !host || !domain || !process || !facts ||
        callbacks.issue(reply) != 0 || !same_process(reply, host, domain, process))
        return ACTQL_CONTROL_INVALID_SLOT;
    int32_t operation = callbacks.operation(reply);
    if (operation != 3 && operation != 6 && operation != 9) return ACTQL_CONTROL_INVALID_SLOT;
    facts[0] = callbacks.descriptor(reply, 0); facts[1] = callbacks.descriptor(reply, 1);
    facts[2] = callbacks.backing(reply); facts[3] = callbacks.stop(reply);
    return ACTQL_CONTROL_OK;
}
int actql_process_drop_reply(actql_process_reply **slot, actql_control_host *host,
    actql_domain *domain, actql_process *process) {
    if (!slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*slot) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!host || !domain || !same_process(*slot, host, domain, process))
        return ACTQL_CONTROL_INVALID_SLOT;
    actql_process_reply *reply = *slot; *slot = NULL; moonbit_decref(reply);
    return ACTQL_CONTROL_OK;
}
int actql_process_finish_closed_data(actql_control_host **host, actql_domain **domain,
    actql_process **process, actql_live_channel **channel,
    actql_original_child_frame **frame, actql_process_reply **reply) {
    if (!host || !domain || !process || !channel || !frame || !reply ||
        !*host || !*domain || !*process || !*reply) return ACTQL_CONTROL_INVALID_SLOT;
    const void *slots[] = {host, domain, process, channel, frame, reply};
    for (size_t i = 0; i < 6; i++)
        for (size_t j = 0; j < i; j++)
            if (slots[i] == slots[j]) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    int32_t operation = callbacks.operation(*reply);
    if ((operation != 7 && operation != 8) || callbacks.issue(*reply) != 0 ||
        !same_process(*reply, *host, *domain, *process)) return ACTQL_CONTROL_INVALID_SLOT;
    actql_live_channel *c = callbacks.channel(*reply);
    actql_original_child_frame *f = callbacks.frame(*reply);
    int same = c == *channel && f == *frame;
    if (f) moonbit_decref(f);
    if (c) moonbit_decref(c);
    if (!same) return ACTQL_CONTROL_INVALID_SLOT;
    actql_process_reply *r = *reply; *reply = NULL;
    actql_original_child_frame *owned_frame = *frame; *frame = NULL;
    actql_live_channel *owned_channel = *channel; *channel = NULL;
    actql_process *p = *process; *process = NULL;
    actql_domain *d = *domain; *domain = NULL;
    actql_control_host *h = *host; *host = NULL;
    moonbit_decref(r);
    if (owned_frame) moonbit_decref(owned_frame);
    if (owned_channel) moonbit_decref(owned_channel);
    moonbit_decref(p); moonbit_decref(d); moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}
int actql_process_finish_refused_prepare(actql_control_host **host,
    actql_domain **domain, actql_process_reply **reply) {
    if (!host || !domain || !reply || !*host || !*domain || !*reply ||
        (void *)host == (void *)domain || (void *)host == (void *)reply ||
        (void *)domain == (void *)reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (callbacks.operation(*reply) != 1 || callbacks.issue(*reply) == 0 ||
        !same_process(*reply, *host, *domain, NULL)) return ACTQL_CONTROL_INVALID_SLOT;
    actql_process_reply *r = *reply; *reply = NULL;
    actql_domain *d = *domain; *domain = NULL;
    actql_control_host *h = *host; *host = NULL;
    moonbit_decref(r); moonbit_decref(d); moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}
