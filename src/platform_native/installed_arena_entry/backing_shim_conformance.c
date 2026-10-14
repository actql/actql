/* Prepared actual-Core consumer, not a substitute for Native/Python execution.
 * Link the unchanged 64-page fixture against one matching control provider. */
#include "backing_shim.h"
#include <assert.h>
#include <stdio.h>

extern int actql_original_control_initialize(int, char **);
extern int actql_fixture_acquisition_reply_into(int, actql_control_reply **,
                                               actql_control_host **);

static actql_control_host *acquired(void) {
    actql_control_reply *reply = NULL;
    actql_control_host *guard = NULL;
    assert(actql_fixture_acquisition_reply_into(0, &reply, &guard) == 0);
    assert(reply && !guard);
    assert(actql_control_operation(reply) == 2);
    assert(actql_control_issue_family(reply) == 0);
    actql_control_host *host = actql_control_original(reply);
    assert(host);
    assert(actql_control_drop_reply(&reply, host) == 0 && !reply);
    return host;
}

static actql_backing_loan *borrowed(actql_control_host *host) {
    actql_backing_reply *reply = NULL;
    actql_control_host *retained = NULL;
    actql_backing_loan *loan = NULL;
    assert(actql_backing_borrow_into(host, &reply) == 0 && reply);
    assert(actql_backing_operation(reply) == 1);
    assert(actql_backing_issue_family(reply) == 0);
    assert(actql_backing_originals_into(reply, &retained, &loan) == 0);
    assert(retained == host && loan);
    assert(actql_backing_drop_reply(&reply, retained, loan) == 0 && !reply);
    moonbit_decref(retained);
    return loan;
}

static void return_and_drop(actql_control_host *host, actql_backing_loan **loan) {
    actql_backing_reply *reply = NULL;
    assert(actql_backing_return_into(host, *loan, &reply) == 0 && reply);
    assert(actql_backing_operation(reply) == 3);
    assert(actql_backing_issue_family(reply) == 0);
    assert(actql_backing_drop_returned_loan(loan, reply, host) == 0 && !*loan);
    assert(actql_backing_drop_reply(&reply, host, NULL) == 0 && !reply);
}

static void close_and_drop(actql_control_host **host) {
    actql_control_reply *pending = NULL;
    assert(actql_control_try_close_and_drop(host, &pending) == 0);
    assert(!*host && !pending);
}

int main(int argc, char **argv) {
    assert(actql_original_control_initialize(argc, argv) == 0);
    actql_control_host *host = acquired();
    actql_backing_loan *loan = borrowed(host);
    actql_control_reply *pending = NULL;
    assert(actql_control_try_close_and_drop(&host, &pending) == -3);
    assert(host && pending && actql_control_issue_family(pending) == 5);
    assert(actql_control_drop_reply(&pending, host) == 0);
    actql_backing_reply *reply = NULL;
    assert(actql_backing_current_into(host, loan, &reply) == 0);
    assert(actql_backing_issue_family(reply) == 4);
    assert(actql_backing_drop_reply(&reply, host, loan) == 0);
    return_and_drop(host, &loan);
    close_and_drop(&host);
    puts("case: pending original close retains same loan until cleanup return");

    host = acquired();
    actql_control_host *foreign = acquired();
    loan = borrowed(host);
    assert(actql_backing_return_into(foreign, loan, &reply) == 0);
    assert(actql_backing_issue_family(reply) == 2);
    actql_control_host *retained = NULL;
    actql_backing_loan *alias = NULL;
    assert(actql_backing_originals_into(reply, &retained, &alias) == 0);
    assert(retained == host && alias == loan);
    assert(actql_backing_drop_reply(&reply, foreign, alias) == -2 && reply);
    assert(actql_backing_drop_reply(&reply, retained, alias) == 0);
    moonbit_decref(alias);
    moonbit_decref(retained);
    assert(actql_backing_current_into(host, loan, &reply) == 0);
    assert(actql_backing_issue_family(reply) == 0);
    assert(actql_backing_drop_reply(&reply, host, loan) == 0);
    return_and_drop(host, &loan);
    close_and_drop(&host);
    close_and_drop(&foreign);
    puts("case: foreign refusal preserves true original loan and host");

    host = acquired();
    loan = borrowed(host);
    assert(actql_backing_current_into(host, loan, &reply) == 0);
    retained = NULL;
    alias = NULL;
    assert(actql_backing_originals_into(reply, &retained, &alias) == 0);
    assert(alias == loan && retained == host);
    assert(actql_backing_drop_returned_loan(&loan, reply, host) == -2 && loan);
    assert(actql_backing_drop_reply(&reply, host, loan) == 0);
    actql_backing_reply *returned = NULL;
    assert(actql_backing_return_into(host, loan, &returned) == 0);
    assert(actql_backing_issue_family(returned) == 0);
    assert(actql_backing_drop_returned_loan(&loan, returned, host) == 0);
    assert(actql_backing_return_into(host, alias, &reply) == 0);
    assert(actql_backing_issue_family(reply) == 3);
    assert(actql_backing_drop_reply(&reply, host, alias) == 0);
    assert(actql_backing_drop_returned_loan(&alias, returned, host) == 0);
    assert(actql_backing_drop_reply(&returned, host, NULL) == 0);
    moonbit_decref(retained);
    close_and_drop(&host);
    puts("case: returned alias cannot return twice or mint a new loan");

    host = acquired();
    assert(actql_backing_borrow_into(host, &reply) == 0);
    actql_backing_reply *original_reply = reply;
    assert(actql_backing_borrow_into(host, &reply) == -2);
    assert(reply == original_reply);
    retained = NULL;
    loan = NULL;
    assert(actql_backing_originals_into(reply, &retained, &loan) == 0);
    assert(actql_backing_drop_reply(&reply, retained, NULL) == -2 && reply);
    assert(actql_backing_originals_into(reply, &retained, &loan) == -2);
    assert(actql_backing_drop_reply(&reply, retained, loan) == 0);
    return_and_drop(host, &loan);
    moonbit_decref(retained);
    close_and_drop(&host);
    puts("case: occupied slots and live loan custody cannot be discarded");
    puts("{\"discovered\":4,\"executed\":4,\"passed\":4,\"failed\":0,\"initializer\":1,\"scope\":\"private-backing-shim\"}");
    return 0;
}
