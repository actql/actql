/* Prepared private conformance consumer, not an installed entry or Moon test
 * driver. Link only the actual matching regular C and one original provider.
 * The 64-page selection is the existing Native fixture, not a VM profile. */
#include "control_shim.h"
#include <stdio.h>
#include <stdlib.h>

extern int actql_original_control_initialize(int, char **);
extern int64_t actql_bootstrap_page_bytes(void);

static unsigned discovered, executed, passed;

#define REQUIRE(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "assertion failed at line %d: %s\n", __LINE__, #condition); \
        exit(1); \
    } \
} while (0)

static void begin_case(const char *name) {
    ++executed;
    printf("case: %s\n", name);
    fflush(stdout);
}

static actql_control_reply *prepare(int64_t bytes, int64_t generation) {
    moonbit_string_t source = moonbit_make_string_raw(40);
    moonbit_bytes_t recipe = moonbit_make_bytes(32, 17);
    const char *digits = "0123456789012345678901234567890123456789";
    for (int i = 0; i < 40; ++i) source[i] = (uint16_t)digits[i];
    actql_control_reply *reply = actql_control_prepare(
        source, recipe, generation, bytes, 20, 8, 4, 30, 0, bytes, 65536);
    REQUIRE(reply != NULL);
    /* Borrowed call inputs remain owned here; Host retains its own copies. */
    moonbit_decref(recipe);
    moonbit_decref(source);
    return reply;
}

static void expect_reply(actql_control_reply **slot, actql_control_host *host,
                         int operation, int family) {
    REQUIRE(*slot != NULL);
    REQUIRE(actql_control_operation(*slot) == operation);
    REQUIRE(actql_control_issue_family(*slot) == family);
    REQUIRE(actql_control_drop_reply(slot, host) == ACTQL_CONTROL_OK);
    REQUIRE(*slot == NULL);
}

static void close_host(actql_control_host **host) {
    actql_control_reply *pending = NULL;
    REQUIRE(actql_control_try_close_and_drop(host, &pending) == ACTQL_CONTROL_OK);
    REQUIRE(*host == NULL && pending == NULL);
}

int main(int argc, char **argv) {
    discovered = 8;
    begin_case("uninitialized callback transport is unavailable");
    REQUIRE(actql_control_acquire(NULL) == NULL);
    REQUIRE(actql_control_operation(NULL) == ACTQL_CONTROL_UNAVAILABLE);
    ++passed;
    REQUIRE(actql_original_control_initialize(argc, argv) == 0);
    const int64_t bytes = 64 * actql_bootstrap_page_bytes();
    REQUIRE(bytes > 0);

    begin_case("prepare retains borrowed inputs without granting acquisition");
    actql_control_reply *reply = prepare(bytes, 1);
    actql_control_host *first = actql_control_original(reply);
    REQUIRE(first != NULL);
    expect_reply(&reply, first, 1, 0);
    reply = actql_control_current(first);
    expect_reply(&reply, first, 3, 1);
    ++passed;

    begin_case("original acquisition is single use and its reply retains identity");
    reply = actql_control_acquire(first);
    actql_control_host *alias = actql_control_original(reply);
    REQUIRE(alias == first);
    expect_reply(&reply, first, 2, 0);
    reply = actql_control_acquire(alias);
    expect_reply(&reply, alias, 2, 3);
    reply = actql_control_current(first);
    expect_reply(&reply, first, 3, 0);
    moonbit_decref(alias);
    ++passed;

    begin_case("foreign original cannot discard a retained reply");
    reply = prepare(bytes, 1);
    actql_control_host *second = actql_control_original(reply);
    REQUIRE(second != NULL && second != first);
    actql_control_reply *unchanged = reply;
    REQUIRE(actql_control_drop_reply(&reply, first) == ACTQL_CONTROL_INVALID_SLOT);
    REQUIRE(reply == unchanged);
    expect_reply(&reply, second, 1, 0);
    close_host(&second);
    ++passed;

    begin_case("nonempty cleanup out-slot preserves the original and reply");
    reply = actql_control_current(first);
    unchanged = reply;
    alias = first;
    REQUIRE(actql_control_try_close_and_drop(&first, &reply) == ACTQL_CONTROL_INVALID_SLOT);
    REQUIRE(first == alias && reply == unchanged);
    expect_reply(&reply, first, 3, 0);
    ++passed;

    begin_case("typed close retires original before dropping owned references");
    alias = first;
    moonbit_incref(alias);
    close_host(&first);
    reply = actql_control_current(alias);
    expect_reply(&reply, alias, 3, 4);
    close_host(&alias);
    REQUIRE(actql_control_drop_reply(&reply, NULL) == ACTQL_CONTROL_OK);
    ++passed;

    begin_case("partial physical acquisition retains primary issue and same cleanup carrier");
    reply = prepare(bytes + 1, 1);
    first = actql_control_original(reply);
    REQUIRE(first != NULL);
    expect_reply(&reply, first, 1, 0);
    reply = actql_control_acquire(first);
    expect_reply(&reply, first, 2, 6);
    reply = actql_control_current(first);
    expect_reply(&reply, first, 3, 6);
    reply = actql_control_acquire(first);
    expect_reply(&reply, first, 2, 3);
    close_host(&first);
    ++passed;

    begin_case("invalid preparation exposes no original to drop or reacquire");
    reply = prepare(bytes, 0);
    REQUIRE(actql_control_operation(reply) == 1);
    REQUIRE(actql_control_issue_family(reply) != 0);
    REQUIRE(actql_control_original(reply) == NULL);
    REQUIRE(actql_control_drop_reply(&reply, NULL) == ACTQL_CONTROL_OK);
    REQUIRE(reply == NULL);
    ++passed;

    REQUIRE(discovered == 8 && executed == discovered && passed == executed);
    printf("{\"discovered\":%u,\"executed\":%u,\"passed\":%u,\"failed\":0,\"scope\":\"private-original-control-shim\"}\n",
           discovered, executed, passed);
    return 0;
}
