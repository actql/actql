#define _DARWIN_C_SOURCE
#include "component.h"
#include "owned_capacity.h"
#include "scoped_read.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct { actql_owned_capacity *lease; actql_read_context *context; } original;
static const unsigned char recipe[32] = {17};

static original fresh(void) {
    original value = {0};
    assert(actql_native_owned_acquire(64 * (size_t)sysconf(_SC_PAGESIZE),
                                     1, recipe, &value.lease) == 0);
    assert(actql_native_owned_transfer(value.lease, 1, recipe) == 0);
    assert(actql_native_owned_enter(value.lease) == 0);
    assert(actql_read_context_create(value.lease, &value.context) == 0);
    assert(actql_read_context_retain(value.context) == 0);
    assert(actql_native_owned_leave(value.lease) == 0);
    return value;
}
static void enter(original value) {
    assert(actql_native_owned_enter(value.lease) == 0);
    assert(actql_read_context_enter(value.context) == 0);
}
static void leave(original value) {
    assert(actql_read_context_leave(value.context) == 0);
    assert(actql_native_owned_leave(value.lease) == 0);
}
static void finish(original *value) {
    assert(actql_read_context_release_after_owner_ack(value->context) == 0);
    assert(actql_read_context_try_close(&value->context) == 0 && value->context == NULL);
    assert(actql_native_owned_try_close(&value->lease) == 0 && value->lease == NULL);
}

int main(int argc, char **argv) {
    assert(argc == 2);
    const char *name = argv[1];
    original value = fresh();
    if (!strcmp(name, "missing-current")) {
        assert(actql_sqlite_component_bind(value.context) == ACTQL_SQLITE_COMPONENT_INVALID);
        assert(actql_sqlite_component_allocate(8) == NULL);
    }
    enter(value);
    assert(actql_sqlite_component_bind(value.context) == 0);
    assert(strcmp(actql_sqlite_component_source_id(),
        "2025-11-04 19:38:17 fb2c931ae597f8d00a37574ff67aeed3eced4e5547f9120744ae4bfa8e74527b") == 0);

    if (!strcmp(name, "missing-current") || !strcmp(name, "one-binding")) {
        assert(actql_sqlite_component_bind(value.context) == ACTQL_SQLITE_COMPONENT_INVALID);
    } else if (!strcmp(name, "alias-close")) {
        void *bytes = actql_sqlite_component_allocate(9);
        assert(bytes != NULL); memcpy(bytes, "original!", 9);
        assert(actql_sqlite_component_size(bytes) >= 9);
        assert(actql_sqlite_component_close() == ACTQL_SQLITE_COMPONENT_BUSY);
        assert(actql_native_owned_try_close(&value.lease) == ACTQL_OWNED_BUSY);
        leave(value);
        assert(memcmp(bytes, "original!", 9) == 0);
        assert(actql_sqlite_component_free(bytes) == 0);
        enter(value);
    } else if (!strcmp(name, "resize-failure")) {
        void *bytes = actql_sqlite_component_allocate(41);
        assert(bytes != NULL); memset(bytes, 19, 41);
        assert(actql_sqlite_component_resize(bytes,
            64 * (size_t)sysconf(_SC_PAGESIZE)) == NULL);
        for (size_t i = 0; i < 41; i++) assert(((unsigned char *)bytes)[i] == 19);
        void *next = actql_sqlite_component_resize(bytes, 99);
        assert(next != NULL);
        for (size_t i = 0; i < 41; i++) assert(((unsigned char *)next)[i] == 19);
        assert(actql_sqlite_component_free(next) == 0);
    } else if (!strcmp(name, "exhaustion")) {
        void *held[64] = {0}; size_t count = 0;
        while (count < 64 && (held[count] = actql_sqlite_component_allocate(1)) != NULL)
            count++;
        assert(count > 0 && count < 64);
        assert(actql_sqlite_component_allocate(1) == NULL);
        assert(actql_sqlite_component_close() == ACTQL_SQLITE_COMPONENT_BUSY);
        for (size_t i = 0; i < count; i++) assert(actql_sqlite_component_free(held[i]) == 0);
    } else if (!strcmp(name, "foreign-current")) {
        void *bytes = actql_sqlite_component_allocate(23);
        assert(bytes != NULL); memset(bytes, 71, 23);
        leave(value);
        original foreign = fresh(); enter(foreign);
        assert(actql_sqlite_component_allocate(1) == NULL);
        assert(actql_sqlite_component_resize(bytes, 42) == NULL);
        assert(actql_sqlite_component_close() == ACTQL_SQLITE_COMPONENT_INVALID);
        /* Free routes through the ORIGINAL allocation provenance, not foreign TLS. */
        assert(actql_sqlite_component_free(bytes) == 0);
        leave(foreign); finish(&foreign); enter(value);
    } else if (!strcmp(name, "fork-refusal")) {
        void *bytes = actql_sqlite_component_allocate(23);
        assert(bytes != NULL); memset(bytes, 61, 23);
        pid_t child = fork(); assert(child >= 0);
        if (child == 0) {
            assert(actql_sqlite_component_allocate(1) == NULL);
            assert(actql_sqlite_component_free(bytes) == ACTQL_SQLITE_COMPONENT_INVALID);
            assert(actql_sqlite_component_close() == ACTQL_SQLITE_COMPONENT_INVALID);
            _exit(0);
        }
        int status = -1; assert(waitpid(child, &status, 0) == child);
        assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
        assert(((unsigned char *)bytes)[0] == 61);
        assert(actql_sqlite_component_free(bytes) == 0);
    } else if (!strcmp(name, "integer-boundaries")) {
        assert(actql_sqlite_component_allocate(0) == NULL);
        assert(actql_sqlite_component_allocate((size_t)INT_MAX + 1) == NULL);
        assert(actql_sqlite_component_allocate(INT_MAX) == NULL);
        assert(actql_sqlite_component_resize(NULL, (size_t)INT_MAX + 1) == NULL);
    } else { assert(!"Undiscovered conformance case"); }

    assert(actql_sqlite_component_close() == 0);
    assert(actql_sqlite_component_close() == 0);
    assert(actql_sqlite_component_bind(value.context) == ACTQL_SQLITE_COMPONENT_INVALID);
    assert(actql_sqlite_component_allocate(1) == NULL);
    leave(value); finish(&value);
    printf("{\"case\":\"%s\",\"pass\":true,\"host_pages\":64,\"database_operations\":0}\n", name);
    return 0;
}
