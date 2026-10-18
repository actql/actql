#include "../../platform_native/installed_arena_entry/shim_abi.generated.h"

/* Real registered Moon callbacks, not a C double. Keep any unconfirmed test
 * originals reachable on failure; a failed assertion is not cleanup authority. */
static actql_local_journal_capture *pending_captures[8];
static actql_local_journal_reply *pending_replies[8];
static int pending_count;

int32_t actql_native_local_journal_transport_probe(
    actql_local_session *session, actql_local_session *other,
    actql_local_sqlite_library *library, actql_local_crypto_library *crypto,
    double ttl_ms, int32_t expected_issue) {
    if (pending_count > 6) return -100;
    actql_local_journal_capture *capture = NULL, *foreign = NULL;
    actql_local_journal_reply *reply = NULL, *foreign_reply = NULL;
    actql_local_session *returned_session = NULL;
    actql_local_host *host = NULL;
    actql_local_journal_failure *failure = NULL;
    int32_t failed = 0;
#define CHECK(expr) do { if (!(expr)) { failed = __LINE__; goto cleanup; } } while (0)
    CHECK(actql_local_journal_prepare_into(session, library, crypto, ttl_ms,
        8, 8388608, &capture) == 0 && capture);
    CHECK(actql_local_journal_prepare_into(other, library, crypto, 100.0,
        8, 8388608, &foreign) == 0 && foreign && foreign != capture);
    actql_local_journal_capture *original = capture;
    CHECK(actql_local_journal_prepare_into(session, library, crypto, ttl_ms,
        8, 8388608, &capture) == -1 && capture == original);
    CHECK(actql_local_journal_originals_into(capture, &returned_session,
        &host, &failure) == 0 && returned_session == session && !host && !failure);
    CHECK(actql_local_journal_drop_originals(foreign, &returned_session, &host, &failure) == -1);
    CHECK(returned_session == session && !host && !failure);
    CHECK(actql_local_journal_drop_originals(capture, &returned_session,
        (actql_local_host **)&returned_session, &failure) == -1 && returned_session == session);
    CHECK(actql_local_journal_drop_originals(capture, &returned_session, &host, &failure) == 0);
    CHECK(!returned_session && !host && !failure);
    CHECK(actql_local_journal_drop_originals(capture, &returned_session, &host, &failure) == 0);
    CHECK(actql_local_journal_current_into(capture, &reply) == 0);
    CHECK(actql_local_journal_issue_family(reply) == 1);
    CHECK(actql_local_journal_finish_closed_data(&capture, &reply) == -1);
    CHECK(actql_local_journal_drop_reply(&reply, foreign) == -1 && reply);
    CHECK(actql_local_journal_drop_reply(&reply, capture) == 0 && !reply);
    CHECK(actql_local_journal_open_into(capture, &reply) == 0);
    CHECK(actql_local_journal_operation(reply) == 1);
    CHECK(actql_local_journal_issue_family(reply) == expected_issue);
    actql_local_journal_reply *first = reply;
    CHECK(actql_local_journal_open_into(capture, &reply) == -1 && reply == first);
    CHECK(actql_local_journal_originals_into(capture, &returned_session,
        &host, &failure) == 0 && returned_session == session);
    CHECK(expected_issue ? (!host && failure) : (host && !failure));
    CHECK(actql_local_journal_drop_originals(foreign, &returned_session, &host, &failure) == -1);
    CHECK(returned_session == session && (expected_issue ? (!host && failure) : (host && !failure)));
    CHECK(actql_local_journal_drop_originals(capture, &returned_session, &host, &failure) == 0);
    CHECK(!returned_session && !host && !failure);
    CHECK(actql_local_journal_drop_reply(&reply, capture) == 0);
    CHECK(actql_local_journal_open_into(capture, &reply) == 0);
    CHECK(actql_local_journal_issue_family(reply) == expected_issue);
    CHECK(actql_local_journal_drop_reply(&reply, capture) == 0);
    CHECK(actql_local_journal_current_into(capture, &reply) == 0);
    CHECK(actql_local_journal_issue_family(reply) == expected_issue);
    CHECK(actql_local_journal_drop_reply(&reply, capture) == 0);
    CHECK(actql_local_journal_close_into(foreign, &foreign_reply) == 0);
    CHECK(actql_local_journal_issue_family(foreign_reply) == 0);
    CHECK(actql_local_journal_finish_closed_data(&capture, &foreign_reply) == -1);
    CHECK(actql_local_journal_close_into(capture, &reply) == 0);
    CHECK(actql_local_journal_operation(reply) == 3 && actql_local_journal_issue_family(reply) == 0);
    CHECK(actql_local_journal_original_issue_family(capture) == expected_issue);
    CHECK(actql_local_journal_drop_reply(&reply, capture) == 0);
    CHECK(actql_local_journal_current_into(capture, &reply) == 0);
    CHECK(actql_local_journal_issue_family(reply) == 3);
    CHECK(actql_local_journal_drop_reply(&reply, capture) == 0);
    CHECK(actql_local_journal_close_into(capture, &reply) == 0);
    CHECK(actql_local_journal_finish_closed_data(&capture, &reply) == 0 && !capture && !reply);
    CHECK(actql_local_journal_finish_closed_data(&capture, &reply) == 0);
    CHECK(actql_local_journal_finish_closed_data(&foreign, &foreign_reply) == 0 && !foreign && !foreign_reply);
cleanup:
    if (returned_session) moonbit_decref(returned_session);
    if (host) moonbit_decref(host);
    if (failure) moonbit_decref(failure);
    actql_local_journal_capture **captures[] = { &capture, &foreign };
    actql_local_journal_reply **replies[] = { &reply, &foreign_reply };
    for (int i = 0; i < 2; ++i) {
        if (!*captures[i]) continue;
        if (*replies[i]) actql_local_journal_drop_reply(replies[i], *captures[i]);
        if (actql_local_journal_close_into(*captures[i], replies[i]) == 0 &&
            actql_local_journal_finish_closed_data(captures[i], replies[i]) == 0) continue;
        if (pending_count < 8) {
            pending_captures[pending_count] = *captures[i];
            pending_replies[pending_count++] = *replies[i];
        }
    }
#undef CHECK
    return failed;
}
