#include "backing_shim.h"

/* Function roots only. Physical capacity/TLS remains the one existing provider;
 * this table cannot create or grant an original, loan, Root or Run. */
static struct {
    actql_backing_borrow_fn borrow;
    actql_backing_operation_fn current, return_loan;
    actql_backing_original_fn original;
    actql_backing_loan_fn loan;
    actql_backing_tag_fn operation, issue_family;
    actql_backing_description_fn description;
} backing_callbacks;
static int backing_registered;

void actql_native_control_register_backing_roots(
    actql_backing_borrow_fn borrow, actql_backing_operation_fn current,
    actql_backing_operation_fn return_loan, actql_backing_original_fn original,
    actql_backing_loan_fn loan, actql_backing_tag_fn operation,
    actql_backing_tag_fn issue_family, actql_backing_description_fn description) {
    if (backing_registered) return;
    if (!borrow || !current || !return_loan || !original || !loan ||
        !operation || !issue_family || !description) {
        backing_registered = -1;
        return;
    }
    backing_callbacks.borrow = borrow;
    backing_callbacks.current = current;
    backing_callbacks.return_loan = return_loan;
    backing_callbacks.original = original;
    backing_callbacks.loan = loan;
    backing_callbacks.operation = operation;
    backing_callbacks.issue_family = issue_family;
    backing_callbacks.description = description;
    backing_registered = 1;
}

int actql_backing_borrow_into(actql_control_host *host,
                            actql_backing_reply **reply_slot) {
    if (!host || !reply_slot || *reply_slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (backing_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *reply_slot = backing_callbacks.borrow(host);
    return *reply_slot ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

static int backing_operation_into(actql_backing_operation_fn operation,
                                  actql_control_host *host,
                                  actql_backing_loan *loan,
                                  actql_backing_reply **reply_slot) {
    if (!host || !loan || !reply_slot || *reply_slot)
        return ACTQL_CONTROL_INVALID_SLOT;
    if (backing_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *reply_slot = operation(host, loan);
    return *reply_slot ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}

int actql_backing_current_into(actql_control_host *host,
                             actql_backing_loan *loan,
                             actql_backing_reply **reply_slot) {
    return backing_operation_into(backing_callbacks.current, host, loan, reply_slot);
}

int actql_backing_return_into(actql_control_host *host,
                            actql_backing_loan *loan,
                            actql_backing_reply **reply_slot) {
    return backing_operation_into(backing_callbacks.return_loan, host, loan, reply_slot);
}

int actql_backing_originals_into(actql_backing_reply *reply,
                                actql_control_host **host_slot,
                                actql_backing_loan **loan_slot) {
    if (!reply || !host_slot || !loan_slot || (void *)host_slot == (void *)loan_slot ||
        *host_slot || *loan_slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (backing_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    /* Publish each owned accessor result immediately. A later lost response
     * keeps the same slots; None loan on refusal is never fabricated. */
    *host_slot = backing_callbacks.original(reply);
    if (!*host_slot) return ACTQL_CONTROL_UNAVAILABLE;
    *loan_slot = backing_callbacks.loan(reply);
    return ACTQL_CONTROL_OK;
}

int32_t actql_backing_operation(actql_backing_reply *reply) {
    if (backing_registered != 1 || !reply) return ACTQL_CONTROL_UNAVAILABLE;
    return backing_callbacks.operation(reply);
}

int32_t actql_backing_issue_family(actql_backing_reply *reply) {
    if (backing_registered != 1 || !reply) return ACTQL_CONTROL_UNAVAILABLE;
    return backing_callbacks.issue_family(reply);
}

moonbit_string_t actql_backing_description(actql_backing_reply *reply) {
    if (backing_registered != 1 || !reply) return NULL;
    return backing_callbacks.description(reply);
}

static int same_backing_reply(actql_backing_reply *reply,
                             actql_control_host *retained_host,
                             actql_backing_loan *retained_loan,
                             int require_loan) {
    actql_control_host *host = backing_callbacks.original(reply);
    actql_backing_loan *loan = backing_callbacks.loan(reply);
    int same = host && host == retained_host &&
               (loan ? loan == retained_loan : !require_loan);
    if (loan) moonbit_decref(loan);
    if (host) moonbit_decref(host);
    return same;
}

int actql_backing_drop_reply(actql_backing_reply **reply_slot,
                            actql_control_host *retained_host,
                            actql_backing_loan *retained_loan) {
    if (!reply_slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*reply_slot) return ACTQL_CONTROL_OK;
    if (backing_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    actql_backing_loan *observed = backing_callbacks.loan(*reply_slot);
    int returned = !retained_loan && observed &&
                   backing_callbacks.operation(*reply_slot) == 3 &&
                   backing_callbacks.issue_family(*reply_slot) == 0;
    int same = same_backing_reply(*reply_slot, retained_host,
                                 returned ? observed : retained_loan, 0);
    if (observed) moonbit_decref(observed);
    if (!same)
        return ACTQL_CONTROL_INVALID_SLOT;
    actql_backing_reply *owned = *reply_slot;
    *reply_slot = NULL;
    moonbit_decref(owned);
    return ACTQL_CONTROL_OK;
}

int actql_backing_drop_returned_loan(actql_backing_loan **loan_slot,
                                   actql_backing_reply *returned,
                                   actql_control_host *retained_host) {
    if (!loan_slot || !returned || !retained_host) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*loan_slot) return ACTQL_CONTROL_OK;
    if (backing_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (backing_callbacks.operation(returned) != 3 ||
        backing_callbacks.issue_family(returned) != 0 ||
        !same_backing_reply(returned, retained_host, *loan_slot, 1))
        return ACTQL_CONTROL_INVALID_SLOT;
    actql_backing_loan *owned = *loan_slot;
    *loan_slot = NULL;
    moonbit_decref(owned);
    return ACTQL_CONTROL_OK;
}
