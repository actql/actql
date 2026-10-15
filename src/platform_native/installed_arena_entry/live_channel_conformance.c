/* Actual regular-C/private-shim reference and partial-custody checks. The
 * disposable 64-page FD is the existing fixture, not a product profile.
 * No process, channel-positive VM, Engine, external Provider or Run is started. */
#include "live_channel_shim.h"
#include <stdio.h>
#include <stdlib.h>
extern int actql_original_control_initialize(int, char **);
extern int64_t actql_bootstrap_page_bytes(void);
#define REQUIRE(c) do { if (!(c)) { fprintf(stderr, "assertion line %d: %s\n", __LINE__, #c); exit(1); } } while (0)
static actql_control_host *prepare(void) {
    moonbit_string_t source = moonbit_make_string_raw(40);
    moonbit_bytes_t recipe = moonbit_make_bytes(32, 17);
    const char *digits = "0123456789012345678901234567890123456789";
    for (int i = 0; i < 40; ++i) source[i] = (uint16_t)digits[i];
    int64_t bytes = 64 * actql_bootstrap_page_bytes();
    actql_control_reply *reply = actql_control_prepare(source, recipe, 1, bytes,
        20, 8, 4, 30, 0, bytes, 65536);
    moonbit_decref(source); moonbit_decref(recipe);
    REQUIRE(reply && actql_control_operation(reply) == 1 && actql_control_issue_family(reply) == 0);
    actql_control_host *host = actql_control_original(reply);
    REQUIRE(host && actql_control_drop_reply(&reply, host) == 0 && !reply);
    return host;
}
static void drop_domain(actql_domain_reply **reply, actql_control_host *host, actql_domain *domain) {
    REQUIRE(actql_domain_drop_reply(reply, host, domain) == 0 && !*reply);
}
static void drop_live(actql_live_channel_reply **reply, actql_control_host *host,
    actql_domain *domain, actql_live_channel *channel) {
    REQUIRE(actql_live_channel_drop_reply(reply, host, domain, channel) == 0 && !*reply);
}
static void step(unsigned *count, const char *name) {
    ++*count; printf("case:%u:%s\n", *count, name);
}
int main(int argc, char **argv) {
    unsigned count = 0;
    actql_live_channel_reply *reply = NULL;
    REQUIRE(actql_live_channel_prepare_into(NULL, NULL, 1, -1, -1, 7, &reply) == ACTQL_CONTROL_INVALID_SLOT);
    REQUIRE(actql_original_control_initialize(argc, argv) == 0);
    actql_control_host *host = prepare(), *foreign = prepare(), *backing_host = NULL, *domain_host = NULL;
    actql_control_reply *control_reply = NULL;
    REQUIRE(actql_control_acquire_fd_into(host, 0, &control_reply) == 0);
    REQUIRE(actql_control_issue_family(control_reply) == 0);
    REQUIRE(actql_control_drop_reply(&control_reply, host) == 0);
    actql_backing_reply *backing_reply = NULL;
    actql_backing_loan *loan = NULL;
    REQUIRE(actql_backing_borrow_into(host, &backing_reply) == 0);
    REQUIRE(actql_backing_issue_family(backing_reply) == 0);
    REQUIRE(actql_backing_originals_into(backing_reply, &backing_host, &loan) == 0 && backing_host == host && loan);
    REQUIRE(actql_backing_drop_reply(&backing_reply, backing_host, loan) == 0);
    REQUIRE(actql_backing_enter_scope_into(backing_host, loan, &backing_reply) == 0);
    REQUIRE(actql_backing_issue_family(backing_reply) == 0);
    REQUIRE(actql_backing_drop_reply(&backing_reply, backing_host, loan) == 0);
    actql_domain_reply *domain_reply = NULL;
    actql_domain *domain = NULL;
    int64_t bytes = 24 * actql_bootstrap_page_bytes();
    REQUIRE(actql_domain_prepare_into(host, loan, 0, bytes, 2, 1, 1, 3, 0, bytes, &domain_reply) == 0);
    REQUIRE(actql_domain_issue_family(domain_reply) == 0);
    REQUIRE(actql_domain_originals_into(domain_reply, &domain_host, &domain) == 0 && domain_host == host && domain);
    drop_domain(&domain_reply, domain_host, domain);

    actql_control_host *retained_host = NULL;
    actql_domain *retained_domain = NULL;
    actql_live_channel *channel = NULL;
    REQUIRE(actql_live_channel_prepare_into(host, domain, 1, -1, -1, 7, &reply) == 0);
    REQUIRE(actql_live_channel_operation(reply) == 1 && actql_live_channel_issue_family(reply) == 1);
    REQUIRE(actql_live_channel_originals_into(reply, &retained_host, &retained_domain, &channel) == 0);
    REQUIRE(retained_host == host && retained_domain == domain && !channel);
    REQUIRE(actql_live_channel_finish_refused_prepare(&retained_host, &retained_domain, &reply) == 0);
    REQUIRE(!retained_host && !retained_domain && !reply);
    step(&count, "untransferred original returns a typed no-channel refusal");

    REQUIRE(actql_domain_transfer_into(host, domain, &domain_reply) == 0 && actql_domain_issue_family(domain_reply) == 0);
    drop_domain(&domain_reply, host, domain);
    REQUIRE(actql_backing_leave_scope_into(backing_host, loan, &backing_reply) == 0 && actql_backing_issue_family(backing_reply) == 0);
    REQUIRE(actql_backing_drop_reply(&backing_reply, backing_host, loan) == 0);
    REQUIRE(actql_live_channel_prepare_into(foreign, domain, 1, -1, -1, 7, &reply) == 0);
    REQUIRE(actql_live_channel_issue_family(reply) == 2);
    REQUIRE(actql_live_channel_originals_into(reply, &retained_host, &retained_domain, &channel) == 0);
    REQUIRE(retained_host == host && retained_domain == domain && !channel);
    actql_live_channel_reply *unchanged_reply = reply;
    REQUIRE(actql_live_channel_drop_reply(&reply, foreign, domain, NULL) == ACTQL_CONTROL_INVALID_SLOT && reply == unchanged_reply);
    REQUIRE(actql_live_channel_finish_refused_prepare(&retained_host, &retained_domain, &reply) == 0);
    step(&count, "foreign target cannot replace original reply custody");

    REQUIRE(actql_live_channel_prepare_into(host, domain, 1, -1, -1, 7, &reply) == 0);
    REQUIRE(actql_live_channel_issue_family(reply) == 6);
    unchanged_reply = reply;
    REQUIRE(actql_live_channel_prepare_into(host, domain, 1, -1, -1, 7, &reply) == ACTQL_CONTROL_INVALID_SLOT && reply == unchanged_reply);
    REQUIRE(actql_live_channel_originals_into(reply, &retained_host, &retained_domain,
        (actql_live_channel **)&retained_domain) == ACTQL_CONTROL_INVALID_SLOT && !retained_host && !retained_domain);
    REQUIRE(actql_live_channel_originals_into(reply, &retained_host, &retained_domain, &channel) == 0);
    REQUIRE(retained_host == host && retained_domain == domain && channel);
    drop_live(&reply, retained_host, retained_domain, channel);
    step(&count, "partial channel survives persistent-slot overwrite and alias rejection");

    int32_t state = 71;
    int64_t limits[6] = {71, 72, 73, 74, 75, 76};
    REQUIRE(actql_live_channel_operate_into(host, domain, channel, 4, &reply) == 0);
    REQUIRE(actql_live_channel_issue_family(reply) == 1);
    REQUIRE(actql_live_channel_copy_state(reply, host, domain, channel, &state) == ACTQL_CONTROL_INVALID_SLOT && state == 71);
    REQUIRE(actql_live_channel_finish_retired_data(&retained_host, &retained_domain, &channel, &reply) == ACTQL_CONTROL_INVALID_SLOT);
    REQUIRE(retained_host == host && retained_domain == domain && channel && reply);
    drop_live(&reply, retained_host, retained_domain, channel);
    REQUIRE(actql_live_channel_operate_into(host, domain, channel, 5, &reply) == 0);
    REQUIRE(actql_live_channel_copy_limits(reply, host, domain, channel, limits) == ACTQL_CONTROL_INVALID_SLOT);
    for (int i = 0; i < 6; ++i) REQUIRE(limits[i] == 71 + i);
    drop_live(&reply, retained_host, retained_domain, channel);
    step(&count, "refused state and limits never become zero DATA or retirement evidence");

    REQUIRE(actql_live_channel_bind_into(host, domain, channel, 7, 0, 16777216, &reply) == 0);
    REQUIRE(actql_live_channel_operation(reply) == 2 && actql_live_channel_issue_family(reply) == 6);
    drop_live(&reply, retained_host, retained_domain, channel);
    REQUIRE(actql_live_channel_bind_into(host, domain, channel, 7, 0, 16777216, &reply) == 0);
    REQUIRE(actql_live_channel_issue_family(reply) == 3);
    drop_live(&reply, retained_host, retained_domain, channel);
    step(&count, "failed original binding cannot be reissued through the shim");

    REQUIRE(actql_live_channel_report_into(host, domain, channel, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, &reply) == 0);
    REQUIRE(actql_live_channel_operation(reply) == 6 && actql_live_channel_issue_family(reply) == 1);
    drop_live(&reply, retained_host, retained_domain, channel);
    REQUIRE(actql_live_channel_operate_into(host, domain, channel, 7, &reply) == 0 && actql_live_channel_issue_family(reply) == 1);
    drop_live(&reply, retained_host, retained_domain, channel);
    REQUIRE(actql_live_channel_operate_into(host, domain, channel, 6, &reply) == 0);
    REQUIRE(actql_live_channel_operation(reply) == -1 && actql_live_channel_issue_family(reply) == 1);
    drop_live(&reply, retained_host, retained_domain, channel);
    step(&count, "report stop and invalid command tags preserve typed refusals");

    REQUIRE(actql_domain_close_into(host, domain, &domain_reply) == 0 && actql_domain_issue_family(domain_reply) == 8);
    REQUIRE(actql_domain_finish_closed_data(&domain_host, &domain, &domain_reply) == ACTQL_CONTROL_INVALID_SLOT);
    drop_domain(&domain_reply, domain_host, domain);
    control_reply = actql_control_close(host);
    REQUIRE(control_reply && actql_control_issue_family(control_reply) == 5);
    REQUIRE(actql_control_drop_reply(&control_reply, host) == 0);
    step(&count, "pending channel retains domain and logical-closing Host responsibility");

    REQUIRE(actql_live_channel_operate_into(foreign, domain, channel, 8, &reply) == 0 && actql_live_channel_issue_family(reply) == 2);
    REQUIRE(actql_live_channel_finish_retired_data(&retained_host, &retained_domain, &channel, &reply) == ACTQL_CONTROL_INVALID_SLOT);
    drop_live(&reply, retained_host, retained_domain, channel);
    REQUIRE(actql_live_channel_operate_into(host, domain, channel, 8, &reply) == 0 && actql_live_channel_issue_family(reply) == 0);
    actql_control_host *unchanged_foreign = foreign;
    REQUIRE(actql_live_channel_finish_retired_data(&foreign, &retained_domain, &channel, &reply) == ACTQL_CONTROL_INVALID_SLOT && foreign == unchanged_foreign);
    REQUIRE(actql_live_channel_finish_retired_data(&retained_host, &retained_domain, &channel, &reply) == 0);
    REQUIRE(!retained_host && !retained_domain && !channel && !reply);
    step(&count, "only original Retire Ok retires extra managed channel aliases");

    REQUIRE(actql_domain_close_into(host, domain, &domain_reply) == 0 && actql_domain_issue_family(domain_reply) == 5);
    drop_domain(&domain_reply, domain_host, domain);
    REQUIRE(actql_backing_return_into(backing_host, loan, &backing_reply) == 0 && actql_backing_issue_family(backing_reply) == 0);
    REQUIRE(actql_backing_finish_returned_data(&backing_host, &loan, &backing_reply) == 0);
    REQUIRE(!backing_host && !loan && !backing_reply);
    REQUIRE(actql_domain_close_into(host, domain, &domain_reply) == 0 && actql_domain_issue_family(domain_reply) == 0);
    REQUIRE(actql_domain_finish_closed_data(&domain_host, &domain, &domain_reply) == 0);
    REQUIRE(!domain_host && !domain && !domain_reply);
    step(&count, "same backing borrow returns before independent domain allocation cleanup");

    REQUIRE(actql_live_channel_finish_retired_data(&retained_host, &retained_domain, &channel, &reply) == 0);
    REQUIRE(actql_live_channel_finish_retired_data(&retained_host, &retained_domain, &channel,
        (actql_live_channel_reply **)&channel) == ACTQL_CONTROL_INVALID_SLOT);
    REQUIRE(actql_control_try_close_and_drop(&host, &control_reply) == 0 && !host && !control_reply);
    REQUIRE(actql_control_try_close_and_drop(&foreign, &control_reply) == 0 && !foreign && !control_reply);
    step(&count, "idempotent data retirement supplies no duplicate physical close");
    printf("{\"success\":true,\"discovered\":10,\"executed\":%u,\"passed\":%u,\"failed\":0,\"initializer\":1,\"VM\":0,\"worker\":0,\"public_e2e\":0}\n", count, count);
    return count == 10 ? 0 : 1;
}
