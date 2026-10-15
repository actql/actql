#include "packaged_runtime_shim.h"
#include <string.h>
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
#include "scoped_read.h"
extern actql_read_context *actql_bootstrap_current_read_context(void);
#endif
static struct {
    actql_runtime_capture_fn capture;
    actql_runtime_operation_fn current, close;
    actql_runtime_host_fn host;
    actql_runtime_read_fn read;
    actql_runtime_original_fn runtime;
    actql_runtime_tag_fn operation, issue;
} callbacks;
static int registered;
void actql_native_control_register_packaged_runtime_roots(
    actql_runtime_capture_fn capture, actql_runtime_operation_fn current,
    actql_runtime_operation_fn close, actql_runtime_host_fn host,
    actql_runtime_read_fn read, actql_runtime_original_fn runtime,
    actql_runtime_tag_fn operation, actql_runtime_tag_fn issue) {
    if (registered) return;
    if (!capture || !current || !close || !host || !read || !runtime || !operation || !issue) {
        registered = -1;
        return;
    }
    callbacks.capture = capture; callbacks.current = current; callbacks.close = close;
    callbacks.host = host; callbacks.read = read; callbacks.runtime = runtime;
    callbacks.operation = operation; callbacks.issue = issue;
    registered = 1;
}
static moonbit_string_t exact_string(const uint16_t *data, int32_t length) {
    moonbit_string_t result = moonbit_make_string_raw(length);
    memcpy(result, data, (size_t)length * sizeof(uint16_t));
    return result;
}
int actql_packaged_runtime_capture_utf16_into(actql_control_host *host, actql_parent_read *read,
    const uint16_t *root, int32_t root_units, const uint16_t *source, int32_t source_units,
    const uint16_t *platform, int32_t platform_units, const uint16_t *manifest, int32_t manifest_units,
    int32_t ceiling, actql_packaged_runtime_reply **reply) {
    if (!host || !read || !reply || *reply || !root || root_units < 1 || root_units > 4096 ||
        !source || source_units != 40 || !platform || platform_units < 1 || platform_units > 32 ||
        !manifest || manifest_units != 64 || ceiling < 1) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
    if (actql_bootstrap_current_read_context()) return ACTQL_CONTROL_UNAVAILABLE;
#endif
    moonbit_string_t r = exact_string(root, root_units);
    moonbit_string_t s = exact_string(source, source_units);
    moonbit_string_t p = exact_string(platform, platform_units);
    moonbit_string_t m = exact_string(manifest, manifest_units);
    *reply = callbacks.capture(host, read, r, s, p, m, ceiling);
    moonbit_decref(m); moonbit_decref(p); moonbit_decref(s); moonbit_decref(r);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
int actql_packaged_runtime_current_into(actql_packaged_runtime *runtime, actql_packaged_runtime_reply **reply) {
    if (!runtime || !reply || *reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *reply = callbacks.current(runtime);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
int actql_packaged_runtime_close_into(actql_packaged_runtime *runtime, actql_packaged_runtime_reply **reply) {
    if (!runtime || !reply || *reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *reply = callbacks.close(runtime);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
int actql_packaged_runtime_originals_into(actql_packaged_runtime_reply *reply,
    actql_control_host **host, actql_parent_read **read, actql_packaged_runtime **runtime) {
    if (!reply || !host || !read || !runtime || *host || *read || *runtime ||
        (void *)host == (void *)read || (void *)host == (void *)runtime ||
        (void *)read == (void *)runtime) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *host = callbacks.host(reply);
    if (!*host) return ACTQL_CONTROL_UNAVAILABLE;
    *read = callbacks.read(reply);
    if (!*read) return ACTQL_CONTROL_UNAVAILABLE;
    *runtime = callbacks.runtime(reply);
    return ACTQL_CONTROL_OK;
}
int32_t actql_packaged_runtime_operation(actql_packaged_runtime_reply *reply) {
    return registered == 1 && reply ? callbacks.operation(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
int32_t actql_packaged_runtime_issue_family(actql_packaged_runtime_reply *reply) {
    return registered == 1 && reply ? callbacks.issue(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
static int same_reply(actql_packaged_runtime_reply *reply, actql_control_host *host,
    actql_parent_read *read, actql_packaged_runtime *runtime) {
    actql_control_host *h = callbacks.host(reply);
    actql_parent_read *p = callbacks.read(reply);
    actql_packaged_runtime *r = callbacks.runtime(reply);
    int same = h && h == host && p && p == read && r == runtime;
    if (r) moonbit_decref(r);
    if (p) moonbit_decref(p);
    if (h) moonbit_decref(h);
    return same;
}
int actql_packaged_runtime_drop_reply(actql_packaged_runtime_reply **reply,
    actql_control_host *host, actql_parent_read *read, actql_packaged_runtime *runtime) {
    if (!reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*reply) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!same_reply(*reply, host, read, runtime)) return ACTQL_CONTROL_INVALID_SLOT;
    actql_packaged_runtime_reply *r = *reply; *reply = NULL; moonbit_decref(r);
    return ACTQL_CONTROL_OK;
}
static int distinct(void *host, void *read, void *runtime, void *reply) {
    return host && read && runtime && reply && host != read && host != runtime &&
        host != reply && read != runtime && read != reply && runtime != reply;
}
int actql_packaged_runtime_finish_closed_data(actql_control_host **host,
    actql_parent_read **read, actql_packaged_runtime **runtime, actql_packaged_runtime_reply **reply) {
    if (!distinct(host, read, runtime, reply)) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*host && !*read && !*runtime && !*reply) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!*host || !*read || !*runtime || !*reply || callbacks.operation(*reply) != 3 ||
        callbacks.issue(*reply) != 0 || !same_reply(*reply, *host, *read, *runtime))
        return ACTQL_CONTROL_INVALID_SLOT;
    actql_packaged_runtime_reply *q = *reply; *reply = NULL; moonbit_decref(q);
    actql_packaged_runtime *r = *runtime; *runtime = NULL; moonbit_decref(r);
    actql_parent_read *p = *read; *read = NULL; moonbit_decref(p);
    actql_control_host *h = *host; *host = NULL; moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}
int actql_packaged_runtime_finish_refused_capture(actql_control_host **host,
    actql_parent_read **read, actql_packaged_runtime_reply **reply) {
    if (!host || !read || !reply || (void *)host == (void *)read ||
        (void *)host == (void *)reply || (void *)read == (void *)reply)
        return ACTQL_CONTROL_INVALID_SLOT;
    if (!*host && !*read && !*reply) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!*host || !*read || !*reply || callbacks.operation(*reply) != 1 ||
        callbacks.issue(*reply) < 1 || !same_reply(*reply, *host, *read, NULL))
        return ACTQL_CONTROL_INVALID_SLOT;
    actql_packaged_runtime_reply *q = *reply; *reply = NULL; moonbit_decref(q);
    actql_parent_read *p = *read; *read = NULL; moonbit_decref(p);
    actql_control_host *h = *host; *host = NULL; moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}
