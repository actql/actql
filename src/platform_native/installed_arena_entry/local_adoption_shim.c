#include "local_adoption_shim.h"
#include <string.h>
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
extern int32_t actql_bootstrap_control_scope_clear(void);
#endif

static struct {
    actql_adoption_prepare_fn prepare;
    actql_adoption_operate_fn operate;
    actql_adoption_journal_fn journal;
    actql_adoption_original_fn original;
    actql_adoption_host_fn host;
    actql_adoption_pair_fn pair;
    actql_adoption_read_fn read;
    actql_adoption_crypto_fn crypto;
    actql_adoption_session_fn session;
    actql_adoption_original_journal_fn original_journal;
    actql_adoption_ack_fn cleanup_ack;
    actql_adoption_tag_fn operation, issue;
} callbacks;
static int registered;

void actql_native_control_register_local_adoption_binding_roots(
    actql_adoption_prepare_fn prepare, actql_adoption_operate_fn operate,
    actql_adoption_journal_fn journal, actql_adoption_original_fn original,
    actql_adoption_host_fn host, actql_adoption_pair_fn pair,
    actql_adoption_read_fn read, actql_adoption_crypto_fn crypto,
    actql_adoption_session_fn session, actql_adoption_original_journal_fn original_journal,
    actql_adoption_ack_fn cleanup_ack, actql_adoption_tag_fn operation,
    actql_adoption_tag_fn issue) {
    if (registered) return;
    if (!prepare || !operate || !journal || !original || !host || !pair || !read ||
        !crypto || !session || !original_journal || !cleanup_ack || !operation || !issue) {
        registered = -1;
        return;
    }
    callbacks.prepare = prepare; callbacks.operate = operate; callbacks.journal = journal;
    callbacks.original = original; callbacks.host = host; callbacks.pair = pair;
    callbacks.read = read; callbacks.crypto = crypto; callbacks.session = session;
    callbacks.original_journal = original_journal; callbacks.cleanup_ack = cleanup_ack;
    callbacks.operation = operation; callbacks.issue = issue;
    registered = 1;
}

static int entry_available(void) {
    if (registered != 1) return 0;
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
    if (actql_bootstrap_control_scope_clear() != 1) return 0;
#endif
    return 1;
}

static int valid_utf16(const uint16_t *text, int32_t units, int32_t maximum, int empty) {
    if (units < (empty ? 0 : 1) || units > maximum || (units && !text)) return 0;
    for (int32_t i = 0; i < units; i++) {
        uint16_t c = text[i];
        if (c >= 0xD800 && c <= 0xDBFF) {
            if (++i == units || text[i] < 0xDC00 || text[i] > 0xDFFF) return 0;
        } else if (c >= 0xDC00 && c <= 0xDFFF) return 0;
    }
    return 1;
}

static moonbit_string_t exact_string(const uint16_t *text, int32_t units) {
    moonbit_string_t value = moonbit_make_string_raw(units);
    if (units) memcpy(value, text, (size_t)units * sizeof(uint16_t));
    return value;
}

int actql_local_adoption_prepare_utf16_into(
    actql_control_host *host, actql_local_host_resources *resources,
    actql_parent_read *read, actql_adoption_crypto *crypto,
    const uint16_t *parent, int32_t parent_units,
    const uint16_t *state, int32_t state_units,
    const uint16_t *source, int32_t source_units,
    const uint16_t *source_name, int32_t source_name_units,
    const uint16_t *account, int32_t account_units,
    const uint16_t *configuration, int32_t configuration_units,
    const int32_t *configuration_lengths, int32_t configuration_count,
    const uint16_t *managed, int32_t managed_units, int32_t has_managed,
    int32_t ceiling, actql_adoption_binding **original) {
    if (!host || !resources || !read || !crypto || !original || *original || ceiling < 1 ||
        !valid_utf16(parent, parent_units, 4096, 0) ||
        !valid_utf16(state, state_units, 4096, 0) ||
        !valid_utf16(source, source_units, 4096, 0) ||
        !valid_utf16(source_name, source_name_units, 4096, 0) ||
        !valid_utf16(account, account_units, 4096, 0) ||
        (has_managed != 0 && has_managed != 1) || (!has_managed && managed_units != 0) ||
        !valid_utf16(managed, managed_units, 4096, !has_managed) ||
        configuration_count < 0 || configuration_count > 8 ||
        configuration_units < 0 || configuration_units > 8 * 4096 ||
        (configuration_count && (!configuration || !configuration_lengths))) return ACTQL_CONTROL_INVALID_SLOT;
    int32_t total = 0;
    for (int32_t i = 0; i < configuration_count; i++) {
        int32_t units = configuration_lengths[i];
        if (units < 1 || units > 4096 || units > configuration_units - total ||
            !valid_utf16(configuration + total, units, 4096, 0)) return ACTQL_CONTROL_INVALID_SLOT;
        total += units;
    }
    if (total != configuration_units) return ACTQL_CONTROL_INVALID_SLOT;
    if (!entry_available()) return ACTQL_CONTROL_UNAVAILABLE;
    moonbit_string_t p = exact_string(parent, parent_units), s = exact_string(state, state_units);
    moonbit_string_t r = exact_string(source, source_units), n = exact_string(source_name, source_name_units);
    moonbit_string_t a = exact_string(account, account_units), m = exact_string(managed, managed_units);
    moonbit_string_t *files = (moonbit_string_t *)moonbit_make_ref_array_raw(configuration_count);
    total = 0;
    for (int32_t i = 0; i < configuration_count; i++) {
        files[i] = exact_string(configuration + total, configuration_lengths[i]);
        total += configuration_lengths[i];
    }
    *original = callbacks.prepare(host, resources, read, crypto, p, s, r, n, a,
                                  files, m, has_managed, ceiling);
    moonbit_decref(files); moonbit_decref(m); moonbit_decref(a);
    moonbit_decref(n); moonbit_decref(r); moonbit_decref(s); moonbit_decref(p);
    return *original ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

int actql_local_adoption_operate_into(actql_adoption_binding *original, int32_t operation,
                                     actql_adoption_reply **reply) {
    if (!original || !reply || *reply || operation < 1 || operation > 3) return ACTQL_CONTROL_INVALID_SLOT;
    if (!entry_available()) return ACTQL_CONTROL_UNAVAILABLE;
    *reply = callbacks.operate(original, operation);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

int actql_local_adoption_capture_journal_into(actql_adoption_binding *original,
    double ttl_ms, int32_t max_records, int64_t max_snapshot_bytes, actql_adoption_reply **reply) {
    if (!original || !reply || *reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (!entry_available()) return ACTQL_CONTROL_UNAVAILABLE;
    *reply = callbacks.journal(original, ttl_ms, max_records, max_snapshot_bytes);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

static int distinct_slots(const void **slots, size_t length) {
    for (size_t i = 0; i < length; i++) {
        if (!slots[i]) return 0;
        for (size_t j = 0; j < i; j++) if (slots[i] == slots[j]) return 0;
    }
    return 1;
}

int actql_local_adoption_originals_into(actql_adoption_binding *original,
    actql_control_host **host, actql_local_host_resources **resources,
    actql_parent_read **read, actql_adoption_crypto **crypto,
    actql_adoption_session **session, actql_adoption_journal **journal) {
    const void *slots[] = {host, resources, read, crypto, session, journal};
    if (!original || !distinct_slots(slots, 6) || *host || *resources || *read ||
        *crypto || *session || *journal) return ACTQL_CONTROL_INVALID_SLOT;
    if (!entry_available()) return ACTQL_CONTROL_UNAVAILABLE;
    *host = callbacks.host(original); *resources = callbacks.pair(original);
    *read = callbacks.read(original); *crypto = callbacks.crypto(original);
    *session = callbacks.session(original); *journal = callbacks.original_journal(original);
    return *host && *resources && *read && *crypto ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

int actql_local_adoption_drop_originals(actql_adoption_binding *original,
    actql_control_host **host, actql_local_host_resources **resources,
    actql_parent_read **read, actql_adoption_crypto **crypto,
    actql_adoption_session **session, actql_adoption_journal **journal) {
    const void *slots[] = {host, resources, read, crypto, session, journal};
    if (!original || !distinct_slots(slots, 6)) return ACTQL_CONTROL_INVALID_SLOT;
    if (!entry_available()) return ACTQL_CONTROL_UNAVAILABLE;
    if (!*host && !*resources && !*read && !*crypto && !*session && !*journal) return ACTQL_CONTROL_OK;
    actql_control_host *h = callbacks.host(original);
    actql_local_host_resources *p = callbacks.pair(original);
    actql_parent_read *r = callbacks.read(original);
    actql_adoption_crypto *c = callbacks.crypto(original);
    actql_adoption_session *s = callbacks.session(original);
    actql_adoption_journal *j = callbacks.original_journal(original);
    int same = (!*host || *host == h) && (!*resources || *resources == p) &&
        (!*read || *read == r) && (!*crypto || *crypto == c) &&
        (!*session || *session == s) && (!*journal || *journal == j);
    if (h) moonbit_decref(h); if (p) moonbit_decref(p); if (r) moonbit_decref(r);
    if (c) moonbit_decref(c); if (s) moonbit_decref(s); if (j) moonbit_decref(j);
    if (!same) return ACTQL_CONTROL_INVALID_SLOT;
    h = *host; p = *resources; r = *read; c = *crypto; s = *session; j = *journal;
    *host = NULL; *resources = NULL; *read = NULL; *crypto = NULL; *session = NULL; *journal = NULL;
    if (h) moonbit_decref(h); if (p) moonbit_decref(p); if (r) moonbit_decref(r);
    if (c) moonbit_decref(c); if (s) moonbit_decref(s); if (j) moonbit_decref(j);
    return ACTQL_CONTROL_OK;
}

int32_t actql_local_adoption_operation(actql_adoption_reply *reply) {
    return registered == 1 && reply ? callbacks.operation(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
int32_t actql_local_adoption_issue_family(actql_adoption_reply *reply) {
    return registered == 1 && reply ? callbacks.issue(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
static int same_original(actql_adoption_reply *reply, actql_adoption_binding *original) {
    actql_adoption_binding *value = callbacks.original(reply);
    int same = value && value == original;
    if (value) moonbit_decref(value);
    return same;
}
int actql_local_adoption_drop_reply(actql_adoption_reply **reply, actql_adoption_binding *original) {
    if (!reply || !original || (void *)reply == (void *)original) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*reply) return ACTQL_CONTROL_OK;
    if (!entry_available()) return ACTQL_CONTROL_UNAVAILABLE;
    if (!same_original(*reply, original)) return ACTQL_CONTROL_INVALID_SLOT;
    actql_adoption_reply *value = *reply; *reply = NULL; moonbit_decref(value);
    return ACTQL_CONTROL_OK;
}
int actql_local_adoption_finish_closed_data(actql_adoption_binding **original, actql_adoption_reply **reply) {
    if (!original || !reply || (void *)original == (void *)reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*original && !*reply) return ACTQL_CONTROL_OK;
    if (!*original || !*reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (!entry_available()) return ACTQL_CONTROL_UNAVAILABLE;
    if (callbacks.operation(*reply) != 3 || callbacks.issue(*reply) != 0 ||
        !callbacks.cleanup_ack(*original) || !same_original(*reply, *original)) return ACTQL_CONTROL_INVALID_SLOT;
    actql_adoption_reply *r = *reply; actql_adoption_binding *o = *original;
    *reply = NULL; *original = NULL; moonbit_decref(r); moonbit_decref(o);
    return ACTQL_CONTROL_OK;
}
