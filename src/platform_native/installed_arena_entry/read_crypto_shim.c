#include "read_crypto_shim.h"
#include <limits.h>
#include <string.h>
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
extern void *actql_bootstrap_current_read_context(void);
extern int32_t actql_bootstrap_control_scope_clear(void);
#endif
static struct {
    actql_read_crypto_prepare_fn prepare;
    actql_read_crypto_load_fn load;
    actql_read_crypto_operation_fn open_library, close_component;
    actql_read_crypto_library_operation_fn close_library;
    actql_read_crypto_hmac_fn hmac;
    actql_read_crypto_verify_fn verify;
    actql_read_crypto_host_fn host;
    actql_read_crypto_pair_fn pair;
    actql_read_crypto_read_fn read;
    actql_read_crypto_component_fn component;
    actql_read_crypto_library_fn library;
    actql_read_crypto_tag_fn operation, origin, family, closed, length, verified;
    actql_read_crypto_byte_fn byte;
    actql_read_crypto_current_fn current;
} callbacks;
static int registered;
void actql_native_control_register_read_crypto_roots(
    actql_read_crypto_prepare_fn prepare, actql_read_crypto_load_fn load,
    actql_read_crypto_operation_fn open_library, actql_read_crypto_library_operation_fn close_library,
    actql_read_crypto_operation_fn close_component, actql_read_crypto_hmac_fn hmac,
    actql_read_crypto_verify_fn verify, actql_read_crypto_host_fn host,
    actql_read_crypto_pair_fn pair, actql_read_crypto_read_fn read,
    actql_read_crypto_component_fn component, actql_read_crypto_library_fn library,
    actql_read_crypto_tag_fn operation, actql_read_crypto_tag_fn origin,
    actql_read_crypto_tag_fn family, actql_read_crypto_tag_fn closed,
    actql_read_crypto_tag_fn length, actql_read_crypto_tag_fn verified,
    actql_read_crypto_byte_fn byte, actql_read_crypto_current_fn current) {
    if (registered) return;
    if (!prepare || !load || !open_library || !close_library || !close_component ||
        !hmac || !verify || !host || !pair || !read || !component || !library ||
        !operation || !origin || !family || !closed || !length || !verified || !byte || !current) {
        registered = -1; return;
    }
    callbacks.prepare = prepare; callbacks.load = load; callbacks.open_library = open_library;
    callbacks.close_library = close_library; callbacks.close_component = close_component;
    callbacks.hmac = hmac; callbacks.verify = verify; callbacks.host = host;
    callbacks.pair = pair; callbacks.read = read; callbacks.component = component;
    callbacks.library = library; callbacks.operation = operation; callbacks.origin = origin;
    callbacks.family = family; callbacks.closed = closed; callbacks.length = length;
    callbacks.verified = verified; callbacks.byte = byte; callbacks.current = current;
    registered = 1;
}
static int same_current(actql_control_host *host, actql_local_host_resources *pair,
    actql_parent_read *read, actql_read_crypto_component *component) {
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
    return registered == 1 && host && pair && read && component &&
        actql_bootstrap_current_read_context() != NULL && callbacks.current(host, pair, read, component) == 1;
#else
    (void)host; (void)pair; (void)read; (void)component; return 0;
#endif
}
int actql_read_crypto_prepare_into(actql_control_host *host, actql_local_host_resources *pair,
    actql_parent_read *read, actql_read_crypto_reply **reply) {
    if (!host || !pair || !read || !reply || *reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
    if (actql_bootstrap_control_scope_clear() != 1) return ACTQL_CONTROL_UNAVAILABLE;
#else
    return ACTQL_CONTROL_UNAVAILABLE;
#endif
    *reply = callbacks.prepare(host, pair, read);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
int actql_read_crypto_load_utf16_into(actql_control_host *host, actql_local_host_resources *pair,
    actql_parent_read *read, actql_read_crypto_component *component, const uint16_t *path,
    int32_t units, int64_t heap, int32_t diagnostic, actql_read_crypto_reply **reply) {
    if (!path || units <= 0 || units > 4096 || !reply || *reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (!same_current(host, pair, read, component)) return ACTQL_CONTROL_UNAVAILABLE;
    moonbit_string_t value = moonbit_make_string_raw(units);
    memcpy(value, path, (size_t)units * sizeof(uint16_t));
    *reply = callbacks.load(host, pair, read, component, value, heap, diagnostic);
    moonbit_decref(value);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
int actql_read_crypto_operate_into(actql_control_host *host, actql_local_host_resources *pair,
    actql_parent_read *read, actql_read_crypto_component *component, actql_local_crypto_library *library,
    int32_t operation, actql_read_crypto_reply **reply) {
    if (!reply || *reply || operation < 3 || operation > 5 || (operation == 4) != (library != NULL))
        return ACTQL_CONTROL_INVALID_SLOT;
    if (!same_current(host, pair, read, component)) return ACTQL_CONTROL_UNAVAILABLE;
    *reply = operation == 3 ? callbacks.open_library(host, pair, read, component) :
        operation == 4 ? callbacks.close_library(host, pair, read, component, library) :
        callbacks.close_component(host, pair, read, component);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
static int byte_input(const unsigned char *bytes, int64_t length) {
    return length >= 0 && length <= INT32_MAX && (length == 0 || bytes);
}
static moonbit_bytes_t copy_bytes(const unsigned char *bytes, int64_t length) {
    moonbit_bytes_t value = moonbit_make_bytes_raw((int32_t)length);
    if (length) memcpy(value, bytes, (size_t)length);
    return value;
}
int actql_read_crypto_hmac_into(actql_control_host *host, actql_local_host_resources *pair,
    actql_parent_read *read, actql_read_crypto_component *component, actql_local_crypto_library *library,
    const unsigned char *key, int64_t key_length, const unsigned char *data, int64_t data_length,
    actql_read_crypto_reply **reply) {
    if (!library || !reply || *reply || !byte_input(key, key_length) || !byte_input(data, data_length))
        return ACTQL_CONTROL_INVALID_SLOT;
    if (!same_current(host, pair, read, component)) return ACTQL_CONTROL_UNAVAILABLE;
    moonbit_bytes_t k = copy_bytes(key, key_length), d = copy_bytes(data, data_length);
    *reply = callbacks.hmac(host, pair, read, component, library, k, d);
    moonbit_decref(d); moonbit_decref(k);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
int actql_read_crypto_verify_into(actql_control_host *host, actql_local_host_resources *pair,
    actql_parent_read *read, actql_read_crypto_component *component, actql_local_crypto_library *library,
    const unsigned char *key, int64_t key_length, const unsigned char *data, int64_t data_length,
    const unsigned char *signature, int64_t signature_length, actql_read_crypto_reply **reply) {
    if (!library || !reply || *reply || !byte_input(key, key_length) ||
        !byte_input(data, data_length) || !byte_input(signature, signature_length)) return ACTQL_CONTROL_INVALID_SLOT;
    if (!same_current(host, pair, read, component)) return ACTQL_CONTROL_UNAVAILABLE;
    moonbit_bytes_t k = copy_bytes(key, key_length), d = copy_bytes(data, data_length), s = copy_bytes(signature, signature_length);
    *reply = callbacks.verify(host, pair, read, component, library, k, d, s);
    moonbit_decref(s); moonbit_decref(d); moonbit_decref(k);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
static int distinct_slots(void **slots, size_t count) {
    for (size_t i = 0; i < count; ++i) {
        if (!slots[i]) return 0;
        for (size_t j = 0; j < i; ++j) if (slots[i] == slots[j]) return 0;
    }
    return 1;
}
int actql_read_crypto_originals_into(actql_read_crypto_reply *reply, actql_control_host **host,
    actql_local_host_resources **pair, actql_parent_read **read,
    actql_read_crypto_component **component, actql_local_crypto_library **library) {
    void *slots[] = {host, pair, read, component, library};
    if (!reply || !distinct_slots(slots, 5) || *host || *pair || *read || *component || *library)
        return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *host = callbacks.host(reply); if (!*host) return ACTQL_CONTROL_UNAVAILABLE;
    *pair = callbacks.pair(reply); if (!*pair) return ACTQL_CONTROL_UNAVAILABLE;
    *read = callbacks.read(reply); if (!*read) return ACTQL_CONTROL_UNAVAILABLE;
    *component = callbacks.component(reply); *library = callbacks.library(reply);
    return ACTQL_CONTROL_OK;
}
int32_t actql_read_crypto_operation(actql_read_crypto_reply *reply) { return registered == 1 && reply ? callbacks.operation(reply) : -1; }
int32_t actql_read_crypto_issue_origin(actql_read_crypto_reply *reply) { return registered == 1 && reply ? callbacks.origin(reply) : -1; }
int32_t actql_read_crypto_issue_family(actql_read_crypto_reply *reply) { return registered == 1 && reply ? callbacks.family(reply) : -1; }
int32_t actql_read_crypto_close_confirmed(actql_read_crypto_reply *reply) { return registered == 1 && reply ? callbacks.closed(reply) : -1; }
int32_t actql_read_crypto_verification(actql_read_crypto_reply *reply) { return registered == 1 && reply ? callbacks.verified(reply) : -1; }
static int same_reply(actql_read_crypto_reply *reply, actql_control_host *host,
    actql_local_host_resources *pair, actql_parent_read *read,
    actql_read_crypto_component *component, actql_local_crypto_library *library) {
    actql_control_host *h = callbacks.host(reply);
    actql_local_host_resources *p = callbacks.pair(reply);
    actql_parent_read *r = callbacks.read(reply);
    actql_read_crypto_component *c = callbacks.component(reply);
    actql_local_crypto_library *l = callbacks.library(reply);
    int same = h && h == host && p && p == pair && r && r == read && c == component && l == library;
    if (l) moonbit_decref(l); if (c) moonbit_decref(c); if (r) moonbit_decref(r);
    if (p) moonbit_decref(p); if (h) moonbit_decref(h);
    return same;
}
int actql_read_crypto_copy_output(actql_read_crypto_reply *reply, actql_control_host *host,
    actql_local_host_resources *pair, actql_parent_read *read, actql_read_crypto_component *component,
    actql_local_crypto_library *library, unsigned char *output, int64_t capacity, int64_t *length) {
    if (!reply || !output || capacity < 0 || !length || !same_current(host, pair, read, component))
        return ACTQL_CONTROL_INVALID_SLOT;
    if (!same_reply(reply, host, pair, read, component, library) || callbacks.operation(reply) != 6 || callbacks.origin(reply) != 0)
        return ACTQL_CONTROL_INVALID_SLOT;
    int32_t count = callbacks.length(reply);
    if (count < 0 || count > capacity) return ACTQL_CONTROL_INVALID_SLOT;
    for (int32_t i = 0; i < count; ++i) { int32_t byte = callbacks.byte(reply, i); if (byte < 0 || byte > 255) return ACTQL_CONTROL_UNAVAILABLE; output[i] = (unsigned char)byte; }
    *length = count;
    return ACTQL_CONTROL_OK;
}
int actql_read_crypto_drop_reply(actql_read_crypto_reply **reply, actql_control_host *host,
    actql_local_host_resources *pair, actql_parent_read *read, actql_read_crypto_component *component,
    actql_local_crypto_library *library) {
    if (!reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*reply) return ACTQL_CONTROL_OK;
    if (registered != 1 || !same_reply(*reply, host, pair, read, component, library)) return ACTQL_CONTROL_INVALID_SLOT;
    /* Read-created replies are released in their same physical frame. The
     * initial registration reply was allocated in outer control instead. */
    if (callbacks.operation(*reply) != 1 && !same_current(host, pair, read, component)) return ACTQL_CONTROL_UNAVAILABLE;
    actql_read_crypto_reply *owned = *reply; *reply = NULL; moonbit_decref(owned);
    return ACTQL_CONTROL_OK;
}
int actql_read_crypto_finish_closed_data(actql_control_host **host, actql_local_host_resources **pair,
    actql_parent_read **read, actql_read_crypto_component **component,
    actql_local_crypto_library **library, actql_read_crypto_reply **reply) {
    void *slots[] = {host, pair, read, component, library, reply};
    if (!distinct_slots(slots, 6)) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*host && !*pair && !*read && !*component && !*library && !*reply) return ACTQL_CONTROL_OK;
    if (registered != 1 || !*host || !*pair || !*read || !*component || !*reply ||
        !same_current(*host, *pair, *read, *component) || !same_reply(*reply, *host, *pair, *read, *component, *library))
        return ACTQL_CONTROL_INVALID_SLOT;
    int32_t operation = callbacks.operation(*reply);
    if (callbacks.origin(*reply) != 0 || callbacks.closed(*reply) != 1 ||
        !((operation == 4 && *library) || (operation == 5 && !*library))) return ACTQL_CONTROL_INVALID_SLOT;
    actql_read_crypto_reply *r = *reply; *reply = NULL; moonbit_decref(r);
    actql_local_crypto_library *l = *library; *library = NULL; if (l) moonbit_decref(l);
    actql_read_crypto_component *c = *component; *component = NULL; moonbit_decref(c);
    actql_parent_read *rd = *read; *read = NULL; moonbit_decref(rd);
    actql_local_host_resources *p = *pair; *pair = NULL; moonbit_decref(p);
    actql_control_host *h = *host; *host = NULL; moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}
int actql_read_crypto_finish_refused_prepare(actql_control_host **host, actql_local_host_resources **pair,
    actql_parent_read **read, actql_read_crypto_reply **reply) {
    void *slots[] = {host, pair, read, reply};
    if (!distinct_slots(slots, 4)) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*host && !*pair && !*read && !*reply) return ACTQL_CONTROL_OK;
    if (registered != 1 || !*host || !*pair || !*read || !*reply || callbacks.operation(*reply) != 1 ||
        callbacks.origin(*reply) <= 0 || !same_reply(*reply, *host, *pair, *read, NULL, NULL)) return ACTQL_CONTROL_INVALID_SLOT;
    actql_read_crypto_reply *r = *reply; *reply = NULL; moonbit_decref(r);
    actql_parent_read *rd = *read; *read = NULL; moonbit_decref(rd);
    actql_local_host_resources *p = *pair; *pair = NULL; moonbit_decref(p);
    actql_control_host *h = *host; *host = NULL; moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}

int actql_read_crypto_finish_refused_library(actql_control_host **host, actql_local_host_resources **pair,
    actql_parent_read **read, actql_read_crypto_component **component,
    actql_local_crypto_library **library, actql_read_crypto_reply **reply) {
    void *slots[] = {host, pair, read, component, library, reply};
    if (!distinct_slots(slots, 6)) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*host && !*pair && !*read && !*component && !*library && !*reply) return ACTQL_CONTROL_OK;
    if (registered != 1 || !*host || !*pair || !*read || !*component || *library || !*reply ||
        !same_current(*host, *pair, *read, *component) ||
        callbacks.operation(*reply) != 3 || callbacks.origin(*reply) <= 0 ||
        !same_reply(*reply, *host, *pair, *read, *component, NULL)) return ACTQL_CONTROL_INVALID_SLOT;
    /* No Library was issued. Retire only this refused call's owned DATA refs,
     * without closing the component or borrowing another acquisition's ACK. */
    actql_read_crypto_reply *r = *reply; *reply = NULL; moonbit_decref(r);
    actql_read_crypto_component *c = *component; *component = NULL; moonbit_decref(c);
    actql_parent_read *rd = *read; *read = NULL; moonbit_decref(rd);
    actql_local_host_resources *p = *pair; *pair = NULL; moonbit_decref(p);
    actql_control_host *h = *host; *host = NULL; moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}
