/* Same component implementation, with controlled close-result uncertainty.
 * A simulated lost ACK is not a kernel close failure or a released original. */
#define _DARWIN_C_SOURCE
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
static int lost_close_ack, close_calls;
static int controlled_close(int descriptor) {
    close_calls++;
    int result = close(descriptor);
    if (lost_close_ack) {
        lost_close_ack = 0;
        assert(result == 0);
        errno = EINTR;
        return -1;
    }
    return result;
}
#define close controlled_close
#include "../component.c"
#undef close
/* The release amalgamation defines NDEBUG for its internal assertions. The
 * independent fixture must retain its own assertions and executed calls. */
#undef NDEBUG
#include <assert.h>
#include "scoped_read.h"

int main(int argc, char **argv) {
    assert(argc == 2);
    const char *name = argv[1];
    assert(!strcmp(name, "success") || !strcmp(name, "close-unknown") ||
        !strcmp(name, "heap-exhaustion"));
    static const unsigned char recipe[32] = {17};
    actql_owned_capacity *lease = NULL;
    actql_read_context *context = NULL;
    assert(actql_native_owned_acquire(64 * (size_t)sysconf(_SC_PAGESIZE),
        1, recipe, &lease) == 0);
    assert(actql_native_owned_transfer(lease, 1, recipe) == 0);
    assert(actql_native_owned_enter(lease) == 0);
    assert(actql_read_context_create(lease, &context) == 0);
    assert(actql_read_context_retain(context) == 0);
    assert(actql_read_context_enter(context) == 0);
    assert(actql_sqlite_component_bind(context, 32 * (size_t)sysconf(_SC_PAGESIZE)) == 0);
    if (!strcmp(name, "heap-exhaustion")) {
        void *buffers[128] = {0};
        size_t used = 0;
        while (used < 128 && (buffers[used] = component_allocate_impl(8192)) != NULL) used++;
        assert(used > 0 && used < 128);
        /* Consume remaining small blocks too: the FD carrier must be reserved
         * before any physical open, without an untracked fallback allocation. */
        void *small[2048] = {0}; size_t count = 0;
        while (count < 2048 && (small[count] = component_allocate_impl(16)) != NULL) count++;
        assert(count < 2048);
        errno = 0;
        assert(component_open_descriptor("/dev/null", O_RDONLY, 0) == -1 && errno == ENOMEM);
        assert(component_descriptors == NULL && !component_descriptor_unknown);
        while (count) assert(component_free_impl(small[--count]) == 0);
        while (used) assert(component_free_impl(buffers[--used]) == 0);
    } else {
        int descriptor = component_open_descriptor("/dev/null", O_RDONLY, 0);
        assert(descriptor >= 0 && component_descriptors->descriptor == descriptor);
        assert(actql_sqlite_component_close() == ACTQL_SQLITE_COMPONENT_BUSY);
        lost_close_ack = !strcmp(name, "close-unknown");
        int before = close_calls;
        int result = component_close_descriptor(descriptor);
        assert(close_calls == before + 1);
        if (!strcmp(name, "close-unknown")) {
            assert(result == -1 && errno == EINTR);
            assert(component_descriptors->descriptor == descriptor &&
                component_descriptors->close_consumed &&
                component_descriptors->close_error == EINTR);
            int other = open("/dev/null", O_RDONLY);
            assert(other == descriptor);
            assert(component_close_descriptor(descriptor) == -1);
            assert(close_calls == before + 1 && fcntl(other, F_GETFD) >= 0);
            assert(actql_sqlite_component_descriptor_ack(NULL) == ACTQL_SQLITE_COMPONENT_BUSY);
            assert(actql_sqlite_component_close() == ACTQL_SQLITE_COMPONENT_BUSY);
            assert(component_open_descriptor("/dev/null", O_RDONLY, 0) == -1);
            assert(close(other) == 0);
        } else assert(result == 0 && component_descriptors == NULL);
    }
    int pending = !strcmp(name, "close-unknown");
    if (!pending) assert(actql_sqlite_component_close() == 0);
    assert(actql_read_context_leave(context) == 0);
    assert(actql_native_owned_leave(lease) == 0);
    assert(actql_read_context_release_after_owner_ack(context) == 0);
    assert(actql_read_context_try_close(&context) == (pending ? ACTQL_OWNED_BUSY : 0));
    if (!pending) assert(actql_native_owned_try_close(&lease) == 0);
    printf("{\"case\":\"%s\",\"passed\":true,\"cleanupPending\":%s,"
        "\"kernelFaultObserved\":false}\n", name, pending ? "true" : "false");
    return 0;
}
