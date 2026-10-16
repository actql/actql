/* Independent actual regular-C reference checks. No worker, arena acquisition,
 * Engine or product profile; the 64-page declaration is the existing fixture. */
#include "worker_selection_shim.h"
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
    actql_control_reply *reply = actql_control_prepare(source, recipe, 1, bytes, 20, 8, 4, 30, 0, bytes, 65536);
    moonbit_decref(source); moonbit_decref(recipe);
    REQUIRE(reply && actql_control_operation(reply) == 1 && actql_control_issue_family(reply) == 0);
    actql_control_host *host = actql_control_original(reply);
    REQUIRE(host && actql_control_drop_reply(&reply, host) == 0 && !reply);
    return host;
}
static void close_host(actql_control_host **host) {
    actql_control_reply *reply = NULL;
    REQUIRE(actql_control_try_close_and_drop(host, &reply) == 0 && !*host && !reply);
}
int main(int argc, char **argv) {
    unsigned executed = 0, passed = 0;
    actql_worker_selection_reply *reply = NULL;
    REQUIRE(actql_worker_select_into(NULL, &reply) == ACTQL_CONTROL_INVALID_SLOT && !reply);
    REQUIRE(actql_original_control_initialize(argc, argv) == 0);
    ++executed;
    actql_control_host *host = prepare(), *retained = NULL;
    actql_worker_selection *selection = NULL;
    REQUIRE(actql_worker_select_into(host, &reply) == 0);
    REQUIRE(actql_worker_selection_operation(reply) == 1 && actql_worker_selection_issue_family(reply) == 0);
    REQUIRE(actql_worker_selection_originals_into(reply, &retained, &selection) == 0 && retained == host && selection);
    REQUIRE(actql_worker_selection_drop_reply(&reply, retained, selection) == 0 && !reply);
    REQUIRE(actql_worker_selection_current_into(host, selection, &reply) == 0);
    REQUIRE(actql_worker_selection_operation(reply) == 2 && actql_worker_selection_issue_family(reply) == 0);
    actql_control_host *alias_host = NULL; actql_worker_selection *alias_selection = NULL;
    REQUIRE(actql_worker_selection_originals_into(reply, &alias_host, &alias_selection) == 0);
    REQUIRE(alias_host == host && alias_selection == selection);
    REQUIRE(actql_worker_selection_finish_data(&alias_host, &alias_selection, &reply) == 0);
    REQUIRE(!alias_host && !alias_selection && !reply);
    actql_control_reply *current = actql_control_current(host);
    REQUIRE(current && actql_control_issue_family(current) == 1);
    REQUIRE(actql_control_drop_reply(&current, host) == 0);
    ++passed;

    ++executed;
    actql_control_host *foreign = prepare();
    REQUIRE(foreign != host);
    REQUIRE(actql_worker_selection_current_into(foreign, selection, &reply) == 0);
    REQUIRE(actql_worker_selection_issue_family(reply) == 2);
    actql_worker_selection_reply *unchanged = reply;
    REQUIRE(actql_worker_selection_drop_reply(&reply, retained, selection) == ACTQL_CONTROL_INVALID_SLOT && reply == unchanged);
    REQUIRE(actql_worker_selection_drop_reply(&reply, foreign, selection) == 0 && !reply);
    actql_control_host *unchanged_foreign = foreign; actql_worker_selection *unchanged_selection = selection;
    REQUIRE(actql_worker_selection_finish_data(&foreign, &selection, &reply) == ACTQL_CONTROL_INVALID_SLOT);
    REQUIRE(foreign == unchanged_foreign && selection == unchanged_selection);
    close_host(&foreign);
    ++passed;

    ++executed;
    close_host(&host);
    REQUIRE(actql_worker_selection_current_into(retained, selection, &reply) == 0);
    REQUIRE(actql_worker_selection_issue_family(reply) == 4);
    REQUIRE(actql_worker_selection_finish_data(&retained, &selection, &reply) == 0);
    REQUIRE(!retained && !selection && !reply);
    REQUIRE(actql_worker_selection_finish_data(&retained, &selection, &reply) == 0);
    ++passed;

    ++executed;
    host = prepare();
    REQUIRE(actql_worker_select_into(host, &reply) == 0);
    unchanged = reply;
    REQUIRE(actql_worker_select_into(host, &reply) == ACTQL_CONTROL_INVALID_SLOT && reply == unchanged);
    REQUIRE(actql_worker_selection_originals_into(reply, &retained, (actql_worker_selection **)&retained) == ACTQL_CONTROL_INVALID_SLOT);
    REQUIRE(!retained && !selection);
    REQUIRE(actql_worker_selection_originals_into(reply, &retained, &selection) == 0);
    unchanged_selection = selection;
    REQUIRE(actql_worker_selection_finish_data(&retained, &selection, (actql_worker_selection_reply **)&selection) == ACTQL_CONTROL_INVALID_SLOT);
    REQUIRE(selection == unchanged_selection && retained == host && reply == unchanged);
    REQUIRE(actql_worker_selection_finish_data(&retained, &selection, &reply) == 0);
    close_host(&host);
    ++passed;
    printf("{\"discovered\":4,\"executed\":%u,\"passed\":%u,\"failed\":0,\"initializer\":1,\"arenaAcquisition\":0,\"worker\":0,\"Engine\":0,\"publicE2E\":0}\n", executed, passed);
    return executed == 4 && passed == 4 ? 0 : 1;
}
