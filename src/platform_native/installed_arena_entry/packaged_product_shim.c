#include "packaged_product_shim.h"
#include <string.h>
extern int32_t actql_bootstrap_control_scope_clear(void);

static struct {
    actql_product_observe_fn observe;
    actql_product_identity_fn identity;
    actql_product_host_fn host;
    actql_product_read_fn read;
    actql_product_runtime_fn runtime;
    actql_product_tag_fn operation, issue, length;
    actql_product_unit_fn unit;
} callbacks;
static int registered;

void actql_native_control_register_packaged_product_roots(
    actql_product_observe_fn observe, actql_product_identity_fn identity,
    actql_product_host_fn host, actql_product_read_fn read,
    actql_product_runtime_fn runtime, actql_product_tag_fn operation,
    actql_product_tag_fn issue, actql_product_tag_fn length, actql_product_unit_fn unit) {
    if (registered) return;
    if (!observe || !identity || !host || !read || !runtime ||
        !operation || !issue || !length || !unit) {
        registered = -1;
        return;
    }
    callbacks.observe = observe; callbacks.identity = identity;
    callbacks.host = host; callbacks.read = read; callbacks.runtime = runtime;
    callbacks.operation = operation; callbacks.issue = issue;
    callbacks.length = length; callbacks.unit = unit;
    registered = 1;
}

static moonbit_string_t exact_string(const uint16_t *data, int32_t length) {
    moonbit_string_t value = moonbit_make_string_raw(length);
    memcpy(value, data, (size_t)length * sizeof(uint16_t));
    return value;
}

int actql_packaged_product_observe_utf16_into(actql_packaged_runtime *runtime,
    const uint16_t *root, int32_t root_units, const uint16_t *launcher, int32_t launcher_units,
    const uint16_t *platform, int32_t platform_units, int32_t ceiling,
    actql_packaged_product_reply **reply) {
    if (!runtime || !reply || *reply || !root || root_units < 1 || root_units > 4096 ||
        !launcher || launcher_units != 64 || !platform || platform_units != 64 || ceiling < 1)
        return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1 || actql_bootstrap_control_scope_clear() != 1)
        return ACTQL_CONTROL_UNAVAILABLE;
    moonbit_string_t a = exact_string(root, root_units);
    moonbit_string_t b = exact_string(launcher, launcher_units);
    moonbit_string_t c = exact_string(platform, platform_units);
    *reply = callbacks.observe(runtime, a, b, c, ceiling);
    moonbit_decref(c); moonbit_decref(b); moonbit_decref(a);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

int actql_packaged_product_identity_into(actql_packaged_runtime *runtime,
    actql_packaged_product_reply **reply) {
    if (!runtime || !reply || *reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1 || actql_bootstrap_control_scope_clear() != 1)
        return ACTQL_CONTROL_UNAVAILABLE;
    *reply = callbacks.identity(runtime);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

int actql_packaged_product_validate_originals(actql_packaged_product_reply *reply,
    actql_control_host *host, actql_parent_read *read, actql_packaged_runtime *runtime) {
    if (!reply || !host || !read || !runtime) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    actql_control_host *h = callbacks.host(reply);
    actql_parent_read *p = callbacks.read(reply);
    actql_packaged_runtime *r = callbacks.runtime(reply);
    int same = h && h == host && p && p == read && r == runtime;
    if (r) moonbit_decref(r);
    if (p) moonbit_decref(p);
    if (h) moonbit_decref(h);
    return same ? ACTQL_CONTROL_OK : ACTQL_CONTROL_INVALID_SLOT;
}

int32_t actql_packaged_product_operation(actql_packaged_product_reply *reply) {
    return registered == 1 && reply ? callbacks.operation(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
int32_t actql_packaged_product_issue_family(actql_packaged_product_reply *reply) {
    return registered == 1 && reply ? callbacks.issue(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
int32_t actql_packaged_product_metadata_units(actql_packaged_product_reply *reply) {
    return registered == 1 && reply ? callbacks.length(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
int32_t actql_packaged_product_metadata_unit_at(actql_packaged_product_reply *reply, int32_t index) {
    return registered == 1 && reply ? callbacks.unit(reply, index) : ACTQL_CONTROL_UNAVAILABLE;
}
int actql_packaged_product_drop_reply(actql_packaged_product_reply **reply,
    actql_control_host *host, actql_parent_read *read, actql_packaged_runtime *runtime) {
    if (!reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*reply) return ACTQL_CONTROL_OK;
    int status = actql_packaged_product_validate_originals(*reply, host, read, runtime);
    if (status != ACTQL_CONTROL_OK) return status;
    actql_packaged_product_reply *original = *reply;
    *reply = NULL;
    moonbit_decref(original);
    return ACTQL_CONTROL_OK;
}
