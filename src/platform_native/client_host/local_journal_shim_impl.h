#ifndef ACTQL_PRIVATE_LOCAL_JOURNAL_SHIM_IMPL_H
#define ACTQL_PRIVATE_LOCAL_JOURNAL_SHIM_IMPL_H
#include "../installed_arena_entry/local_journal_shim.h"

/* Callback ABI/RC requires matching actual regular C qualification. These
 * scalars describe transport results only, not Host or resource admission. */
enum { ACTQL_LOCAL_JOURNAL_OK = 0, ACTQL_LOCAL_JOURNAL_INVALID_SLOT = -1,
       ACTQL_LOCAL_JOURNAL_UNAVAILABLE = -2 };
static struct {
    actql_local_journal_prepare_fn prepare;
    actql_local_journal_operation_fn open, current, close;
    actql_local_journal_capture_fn capture;
    actql_local_journal_session_fn session;
    actql_local_journal_host_fn host;
    actql_local_journal_failure_fn failure;
    actql_local_journal_capture_tag_fn cleanup_ack, original_issue;
    actql_local_journal_reply_tag_fn operation, issue;
} actql_local_journal_callbacks;
static int actql_local_journal_registered;

void actql_native_control_register_local_journal_roots(
    actql_local_journal_prepare_fn prepare,
    actql_local_journal_operation_fn open,
    actql_local_journal_operation_fn current,
    actql_local_journal_operation_fn close,
    actql_local_journal_capture_fn capture,
    actql_local_journal_session_fn session,
    actql_local_journal_host_fn host,
    actql_local_journal_failure_fn failure,
    actql_local_journal_capture_tag_fn cleanup_ack,
    actql_local_journal_reply_tag_fn operation,
    actql_local_journal_reply_tag_fn issue,
    actql_local_journal_capture_tag_fn original_issue
) {
    if (actql_local_journal_registered) return;
    if (!prepare || !open || !current || !close || !capture || !session ||
        !host || !failure || !cleanup_ack || !operation || !issue || !original_issue) {
        actql_local_journal_registered = -1;
        return;
    }
    actql_local_journal_callbacks.prepare = prepare;
    actql_local_journal_callbacks.open = open;
    actql_local_journal_callbacks.current = current;
    actql_local_journal_callbacks.close = close;
    actql_local_journal_callbacks.capture = capture;
    actql_local_journal_callbacks.session = session;
    actql_local_journal_callbacks.host = host;
    actql_local_journal_callbacks.failure = failure;
    actql_local_journal_callbacks.cleanup_ack = cleanup_ack;
    actql_local_journal_callbacks.operation = operation;
    actql_local_journal_callbacks.issue = issue;
    actql_local_journal_callbacks.original_issue = original_issue;
    actql_local_journal_registered = 1;
}

/* All managed inputs are borrowed; each published managed output is owned.
 * The caller validates the same runtime/provider, thread and original scope
 * before entry and keeps original aliases. No public path/key/data constructor
 * or physical read/Library fallback is provided by this transport. */
int actql_local_journal_prepare_into(
    actql_local_session *session, actql_local_sqlite_library *library,
    actql_local_crypto_library *crypto, double ttl_ms, int32_t max_records,
    int64_t max_snapshot_bytes, actql_local_journal_capture **capture
) {
    if (!session || !library || !crypto || !capture || *capture)
        return ACTQL_LOCAL_JOURNAL_INVALID_SLOT;
    if (actql_local_journal_registered != 1) return ACTQL_LOCAL_JOURNAL_UNAVAILABLE;
    *capture = actql_local_journal_callbacks.prepare(
        session, library, crypto, ttl_ms, max_records, max_snapshot_bytes);
    return *capture ? ACTQL_LOCAL_JOURNAL_OK : ACTQL_LOCAL_JOURNAL_UNAVAILABLE;
}

int actql_local_journal_open_into(
    actql_local_journal_capture *capture, actql_local_journal_reply **reply
) {
    if (!capture || !reply || *reply) return ACTQL_LOCAL_JOURNAL_INVALID_SLOT;
    if (actql_local_journal_registered != 1) return ACTQL_LOCAL_JOURNAL_UNAVAILABLE;
    *reply = actql_local_journal_callbacks.open(capture);
    return *reply ? ACTQL_LOCAL_JOURNAL_OK : ACTQL_LOCAL_JOURNAL_UNAVAILABLE;
}

int actql_local_journal_current_into(
    actql_local_journal_capture *capture, actql_local_journal_reply **reply
) {
    if (!capture || !reply || *reply) return ACTQL_LOCAL_JOURNAL_INVALID_SLOT;
    if (actql_local_journal_registered != 1) return ACTQL_LOCAL_JOURNAL_UNAVAILABLE;
    *reply = actql_local_journal_callbacks.current(capture);
    return *reply ? ACTQL_LOCAL_JOURNAL_OK : ACTQL_LOCAL_JOURNAL_UNAVAILABLE;
}

int actql_local_journal_close_into(
    actql_local_journal_capture *capture, actql_local_journal_reply **reply
) {
    if (!capture || !reply || *reply) return ACTQL_LOCAL_JOURNAL_INVALID_SLOT;
    if (actql_local_journal_registered != 1) return ACTQL_LOCAL_JOURNAL_UNAVAILABLE;
    *reply = actql_local_journal_callbacks.close(capture);
    return *reply ? ACTQL_LOCAL_JOURNAL_OK : ACTQL_LOCAL_JOURNAL_UNAVAILABLE;
}

int actql_local_journal_originals_into(
    actql_local_journal_capture *capture, actql_local_session **session,
    actql_local_host **host, actql_local_journal_failure **failure
) {
    if (!capture || !session || !host || !failure || *session || *host || *failure ||
        (void *)session == (void *)host || (void *)session == (void *)failure ||
        (void *)host == (void *)failure) return ACTQL_LOCAL_JOURNAL_INVALID_SLOT;
    if (actql_local_journal_registered != 1) return ACTQL_LOCAL_JOURNAL_UNAVAILABLE;
    *session = actql_local_journal_callbacks.session(capture);
    if (!*session) return ACTQL_LOCAL_JOURNAL_UNAVAILABLE;
    *host = actql_local_journal_callbacks.host(capture);
    *failure = actql_local_journal_callbacks.failure(capture);
    return ACTQL_LOCAL_JOURNAL_OK;
}

int32_t actql_local_journal_operation(actql_local_journal_reply *reply) {
    return actql_local_journal_registered == 1 && reply
        ? actql_local_journal_callbacks.operation(reply) : ACTQL_LOCAL_JOURNAL_UNAVAILABLE;
}

int32_t actql_local_journal_issue_family(actql_local_journal_reply *reply) {
    return actql_local_journal_registered == 1 && reply
        ? actql_local_journal_callbacks.issue(reply) : ACTQL_LOCAL_JOURNAL_UNAVAILABLE;
}

int32_t actql_local_journal_original_issue_family(actql_local_journal_capture *capture) {
    return actql_local_journal_registered == 1 && capture
        ? actql_local_journal_callbacks.original_issue(capture) : ACTQL_LOCAL_JOURNAL_UNAVAILABLE;
}

static int actql_local_journal_same_capture(
    actql_local_journal_reply *reply, actql_local_journal_capture *capture
) {
    actql_local_journal_capture *original = actql_local_journal_callbacks.capture(reply);
    int same = original && original == capture;
    if (original) moonbit_decref(original);
    return same;
}

int actql_local_journal_drop_reply(
    actql_local_journal_reply **reply, actql_local_journal_capture *capture
) {
    if (!reply || !capture || (void *)reply == (void *)capture)
        return ACTQL_LOCAL_JOURNAL_INVALID_SLOT;
    if (!*reply) return ACTQL_LOCAL_JOURNAL_OK;
    if (actql_local_journal_registered != 1) return ACTQL_LOCAL_JOURNAL_UNAVAILABLE;
    if (!actql_local_journal_same_capture(*reply, capture))
        return ACTQL_LOCAL_JOURNAL_INVALID_SLOT;
    actql_local_journal_reply *original = *reply;
    *reply = NULL;
    moonbit_decref(original);
    return ACTQL_LOCAL_JOURNAL_OK;
}

/* This is managed DATA retirement after the actual INNER descriptor ACK.
 * It does not stop/close an escaped alias, parent Domain/read or WorkspaceLoan. */
int actql_local_journal_finish_closed_data(
    actql_local_journal_capture **capture, actql_local_journal_reply **reply
) {
    if (!capture || !reply || (void *)capture == (void *)reply)
        return ACTQL_LOCAL_JOURNAL_INVALID_SLOT;
    if (!*capture && !*reply) return ACTQL_LOCAL_JOURNAL_OK;
    if (!*capture || !*reply) return ACTQL_LOCAL_JOURNAL_INVALID_SLOT;
    if (actql_local_journal_registered != 1) return ACTQL_LOCAL_JOURNAL_UNAVAILABLE;
    if (actql_local_journal_callbacks.operation(*reply) != 3 ||
        actql_local_journal_callbacks.issue(*reply) != 0 ||
        !actql_local_journal_callbacks.cleanup_ack(*capture) ||
        !actql_local_journal_same_capture(*reply, *capture))
        return ACTQL_LOCAL_JOURNAL_INVALID_SLOT;
    actql_local_journal_reply *r = *reply;
    actql_local_journal_capture *c = *capture;
    *reply = NULL; *capture = NULL;
    moonbit_decref(r); moonbit_decref(c);
    return ACTQL_LOCAL_JOURNAL_OK;
}
#endif
