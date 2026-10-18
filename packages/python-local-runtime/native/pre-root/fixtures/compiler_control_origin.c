/* Isolated C transport conformance; the emitted Core initializer is a counter,
 * not an actual Native component, allocator, Engine or process-retirement ACK. */
#include "runtime_initialization_shim.h"
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static actql_control_runtime_origin **published;
static int calls;
static const char *mode;
static int roots_state;

int actql_control_runtime_roots_state(void) { return roots_state; }

static void *foreign_thread(void *unused) {
    (void)unused;
    actql_control_runtime_origin *other = NULL;
    assert(actql_control_runtime_current(*published) == ACTQL_CONTROL_UNAVAILABLE);
    assert(actql_control_runtime_initialize_into(&other) == ACTQL_CONTROL_UNAVAILABLE);
    assert(other == NULL);
    return NULL;
}

int actql_original_control_initialize(int argc, char **argv) {
    assert(argc == 1 && argv != NULL && argv[0] != NULL && argv[1] == NULL);
    assert(strcmp(argv[0], "actql-private-compiler-control") == 0);
    /* The original out-slot is published before any initializer side effect. */
    assert(published != NULL && *published != NULL);
    calls++;
    if (strcmp(mode, "reentrant") == 0) {
        actql_control_runtime_origin *nested = NULL;
        assert(actql_control_runtime_initialize_into(&nested) == ACTQL_CONTROL_UNAVAILABLE);
        assert(nested == NULL);
        assert(actql_control_runtime_current(*published) == ACTQL_CONTROL_UNAVAILABLE);
        pthread_t thread;
        assert(pthread_create(&thread, NULL, foreign_thread, NULL) == 0);
        assert(pthread_join(thread, NULL) == 0);
    }
    roots_state = strcmp(mode, "failed") == 0 ? -1 : 1;
    return strcmp(mode, "failed") == 0 ? 7 : 0;
}

int main(int argc, char **argv) {
    assert(argc == 2);
    mode = argv[1];
    assert(strcmp(mode, "success") == 0 || strcmp(mode, "failed") == 0 ||
           strcmp(mode, "reentrant") == 0 || strcmp(mode, "preinitialized") == 0);
    actql_control_runtime_origin *original = NULL;
    published = &original;
    assert(actql_control_runtime_initialize_into(NULL) == ACTQL_CONTROL_INVALID_SLOT);
    actql_control_runtime_origin *occupied = (actql_control_runtime_origin *)1;
    assert(actql_control_runtime_initialize_into(&occupied) == ACTQL_CONTROL_INVALID_SLOT);
    assert(occupied == (actql_control_runtime_origin *)1 && calls == 0);
    assert(actql_control_runtime_current(NULL) == ACTQL_CONTROL_UNAVAILABLE);
    assert(actql_control_runtime_current(occupied) == ACTQL_CONTROL_UNAVAILABLE);
    if (strcmp(mode, "preinitialized") == 0) {
        for (int state = -1; state <= 1; state += 2) {
            roots_state = state;
            assert(actql_control_runtime_initialize_into(&original) == ACTQL_CONTROL_UNAVAILABLE);
            assert(original == NULL && calls == 0);
        }
        puts("{\"case\":\"preinitialized\",\"passed\":true,\"initializer_calls\":0,"
             "\"original_slot_retained\":false,\"actual_Core\":false,\"process_retirement_ACK\":false}");
        return 0;
    }
    int result = actql_control_runtime_initialize_into(&original);
    assert(original != NULL && calls == 1);
    actql_control_runtime_origin *same = original;
    assert(actql_control_runtime_initialize_into(&original) == ACTQL_CONTROL_INVALID_SLOT);
    assert(original == same);
    actql_control_runtime_origin *second = NULL;
    assert(actql_control_runtime_initialize_into(&second) == ACTQL_CONTROL_UNAVAILABLE);
    assert(second == NULL && calls == 1);
    if (strcmp(mode, "failed") == 0) {
        assert(result == ACTQL_CONTROL_CLEANUP_PENDING);
        assert(actql_control_runtime_current(original) == ACTQL_CONTROL_UNAVAILABLE);
    } else {
        assert(result == ACTQL_CONTROL_OK);
        assert(actql_control_runtime_current(original) == ACTQL_CONTROL_OK);
        pthread_t thread;
        assert(pthread_create(&thread, NULL, foreign_thread, NULL) == 0);
        assert(pthread_join(thread, NULL) == 0);
        pid_t child = fork();
        assert(child >= 0);
        if (child == 0) {
            assert(actql_control_runtime_current(original) == ACTQL_CONTROL_UNAVAILABLE);
            actql_control_runtime_origin *forked = NULL;
            assert(actql_control_runtime_initialize_into(&forked) == ACTQL_CONTROL_UNAVAILABLE);
            assert(forked == NULL);
            _exit(0);
        }
        int status = 0;
        assert(waitpid(child, &status, 0) == child);
        assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
        assert(actql_control_runtime_current(original) == ACTQL_CONTROL_OK);
    }
    printf("{\"case\":\"%s\",\"passed\":true,\"initializer_calls\":%d,"
           "\"original_slot_retained\":true,\"actual_Core\":false,"
           "\"process_retirement_ACK\":false}\n", mode, calls);
    return 0;
}
