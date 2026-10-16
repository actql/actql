#include "worker_selection_shim.h"
static struct {
    actql_worker_select_fn select;
    actql_worker_current_fn current;
    actql_worker_host_fn host;
    actql_worker_original_fn selection;
    actql_worker_parent_fn parent;
    actql_worker_tag_fn operation, issue;
} callbacks;
static int registered;
void actql_native_control_register_worker_selection_roots(
    actql_worker_select_fn select, actql_worker_current_fn current,
    actql_worker_host_fn host, actql_worker_original_fn selection,
    actql_worker_parent_fn parent, actql_worker_tag_fn operation,
    actql_worker_tag_fn issue) {
    if (registered) return;
    if (!select || !current || !host || !selection || !parent || !operation || !issue) {
        registered = -1;
        return;
    }
    callbacks.select = select; callbacks.current = current;
    callbacks.host = host; callbacks.selection = selection;
    callbacks.parent = parent; callbacks.operation = operation; callbacks.issue = issue;
    registered = 1;
}
int actql_worker_select_into(actql_control_host *host, actql_worker_selection_reply **reply) {
    if (!host || !reply || *reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *reply = callbacks.select(host);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
int actql_worker_selection_current_into(actql_control_host *host,
    actql_worker_selection *selection, actql_worker_selection_reply **reply) {
    if (!host || !selection || !reply || *reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *reply = callbacks.current(host, selection);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
int actql_worker_selection_originals_into(actql_worker_selection_reply *reply,
    actql_control_host **host, actql_worker_selection **selection) {
    if (!reply || !host || !selection || (void *)host == (void *)selection || *host || *selection)
        return ACTQL_CONTROL_INVALID_SLOT;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *host = callbacks.host(reply);
    if (!*host) return ACTQL_CONTROL_UNAVAILABLE;
    *selection = callbacks.selection(reply);
    return ACTQL_CONTROL_OK;
}
int32_t actql_worker_selection_operation(actql_worker_selection_reply *reply) {
    return registered == 1 && reply ? callbacks.operation(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
int32_t actql_worker_selection_issue_family(actql_worker_selection_reply *reply) {
    return registered == 1 && reply ? callbacks.issue(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
static int same_reply(actql_worker_selection_reply *reply,
    actql_control_host *retained_host, actql_worker_selection *retained_selection) {
    actql_control_host *host = callbacks.host(reply);
    actql_worker_selection *selection = callbacks.selection(reply);
    int same = host && host == retained_host && (!selection || selection == retained_selection);
    if (selection) moonbit_decref(selection);
    if (host) moonbit_decref(host);
    return same;
}
int actql_worker_selection_drop_reply(actql_worker_selection_reply **reply,
    actql_control_host *host, actql_worker_selection *selection) {
    if (!reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*reply) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!same_reply(*reply, host, selection)) return ACTQL_CONTROL_INVALID_SLOT;
    actql_worker_selection_reply *owned = *reply;
    *reply = NULL;
    moonbit_decref(owned);
    return ACTQL_CONTROL_OK;
}
int actql_worker_selection_finish_data(actql_control_host **host,
    actql_worker_selection **selection, actql_worker_selection_reply **reply) {
    if (!host || !selection || !reply || (void *)host == (void *)selection ||
        (void *)host == (void *)reply || (void *)selection == (void *)reply)
        return ACTQL_CONTROL_INVALID_SLOT;
    if (!*host && !*selection && !*reply) return ACTQL_CONTROL_OK;
    if (registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!*host) return ACTQL_CONTROL_INVALID_SLOT;
    if (*selection) {
        actql_control_host *parent = callbacks.parent(*selection);
        int same = parent && parent == *host;
        if (parent) moonbit_decref(parent);
        if (!same) return ACTQL_CONTROL_INVALID_SLOT;
    }
    if (*reply && !same_reply(*reply, *host, *selection)) return ACTQL_CONTROL_INVALID_SLOT;
    /* Validate every alias before clearing any caller-owned persistent slot. */
    if (*reply) {
        actql_worker_selection_reply *owned = *reply;
        *reply = NULL;
        moonbit_decref(owned);
    }
    if (*selection) {
        actql_worker_selection *owned = *selection;
        *selection = NULL;
        moonbit_decref(owned);
    }
    actql_control_host *owned = *host;
    *host = NULL;
    moonbit_decref(owned);
    return ACTQL_CONTROL_OK;
}
