#include "control_shim.h"

/* Code references only. This neither creates a physical provider/TLS nor
 * adopts a supplier, profile, authority, Root or Run. No DLL constructor. */
static struct {
    actql_control_prepare_fn prepare;
    actql_control_operation_fn acquire, current, close;
    actql_control_original_fn original;
    actql_control_tag_fn operation, issue_family;
    actql_control_description_fn description;
} callbacks;
static int registered;

void actql_native_control_register_original_roots(
    actql_control_prepare_fn prepare, actql_control_operation_fn acquire,
    actql_control_operation_fn current, actql_control_operation_fn close,
    actql_control_original_fn original, actql_control_tag_fn operation,
    actql_control_tag_fn issue_family, actql_control_description_fn description) {
    /* Initialization is serialized by the trusted control runtime. Reject a
     * second registration without invalidating existing cleanup callbacks. */
    if (registered) return;
    if (!prepare || !acquire || !current || !close || !original ||
        !operation || !issue_family || !description) {
        registered = -1;
        return;
    }
    callbacks.prepare = prepare;
    callbacks.acquire = acquire;
    callbacks.current = current;
    callbacks.close = close;
    callbacks.original = original;
    callbacks.operation = operation;
    callbacks.issue_family = issue_family;
    callbacks.description = description;
    registered = 1;
}

actql_control_reply *actql_control_prepare(
    moonbit_string_t source, moonbit_bytes_t recipe, int64_t generation,
    int64_t bytes, int32_t planning, int32_t attempts, int32_t holdings,
    int64_t transfer, int64_t retained, int64_t execution, int64_t envelope) {
    if (registered != 1 || !source || !recipe) return NULL;
    return callbacks.prepare(source, recipe, generation, bytes, planning,
                             attempts, holdings, transfer, retained, execution,
                             envelope);
}

actql_control_reply *actql_control_acquire(actql_control_host *original) {
    if (registered != 1 || !original) return NULL;
    return callbacks.acquire(original);
}

actql_control_reply *actql_control_current(actql_control_host *original) {
    if (registered != 1 || !original) return NULL;
    return callbacks.current(original);
}

actql_control_reply *actql_control_close(actql_control_host *original) {
    if (registered != 1 || !original) return NULL;
    return callbacks.close(original);
}

actql_control_host *actql_control_original(actql_control_reply *reply) {
    if (registered != 1 || !reply) return NULL;
    return callbacks.original(reply);
}

int32_t actql_control_operation(actql_control_reply *reply) {
    if (registered != 1 || !reply) return ACTQL_CONTROL_UNAVAILABLE;
    return callbacks.operation(reply);
}

int32_t actql_control_issue_family(actql_control_reply *reply) {
    if (registered != 1 || !reply) return ACTQL_CONTROL_UNAVAILABLE;
    return callbacks.issue_family(reply);
}

moonbit_string_t actql_control_description(actql_control_reply *reply) {
    if (registered != 1 || !reply) return NULL;
    return callbacks.description(reply);
}

int actql_control_originals_into(actql_control_reply *reply,
                                actql_control_host **original_slot,
                                actql_control_host **retained_slot) {
    if (!reply || !original_slot || !retained_slot ||
        original_slot == retained_slot || *original_slot || *retained_slot)
        return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    actql_control_host *original = callbacks.original(reply);
    if (!original) return ACTQL_CONTROL_UNAVAILABLE;
    *original_slot = original;
    moonbit_incref(original);
    *retained_slot = original;
    return ACTQL_CONTROL_OK;
}

int actql_control_current_into(actql_control_host *original,
                              actql_control_reply **reply_slot) {
    if (!original || !reply_slot || *reply_slot)
        return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *reply_slot = callbacks.current(original);
    return *reply_slot ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

int actql_control_drop_reply(actql_control_reply **slot,
                             actql_control_host *retained_original) {
    if (!slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*slot) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    /* The accessor lends no internals: Some carries an owned ref, None NULL. */
    actql_control_host *original = callbacks.original(*slot);
    int same = !original || original == retained_original;
    if (original) moonbit_decref(original);
    if (!same) return ACTQL_CONTROL_INVALID_SLOT;
    actql_control_reply *owned = *slot;
    *slot = NULL;
    moonbit_decref(owned);
    return ACTQL_CONTROL_OK;
}

int actql_control_try_close_and_drop(actql_control_host **original_slot,
                                   actql_control_reply **pending_slot) {
    if (!original_slot || !pending_slot || *pending_slot)
        return ACTQL_CONTROL_INVALID_SLOT;
    if (!*original_slot) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    actql_control_host *original = *original_slot;
    actql_control_reply *reply = callbacks.close(original);
    if (!reply) return ACTQL_CONTROL_UNAVAILABLE;
    if (callbacks.operation(reply) != 4 || callbacks.issue_family(reply) != 0) {
        *pending_slot = reply;
        return ACTQL_CONTROL_CLEANUP_PENDING;
    }
    /* No direct actql_owned_try_close. The typed Owner already acknowledged
     * full same-arena retirement and settlement; data drops are separate. */
    moonbit_decref(reply);
    *original_slot = NULL;
    moonbit_decref(original);
    return ACTQL_CONTROL_OK;
}
