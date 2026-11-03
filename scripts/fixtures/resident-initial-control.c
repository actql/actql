/* Native command-capture component only: no MoonBit Runtime, Site or Store. */
#include "../../src/cmd/native_remote_resident_site/initial_control_capture.h"
#include <assert.h>
#include <stdio.h>
#include <sys/wait.h>

#if defined(ACTQL_RESIDENT_INITIAL_CONTROL_HEADER)
static void *foreign_thread(void *unused) {
    (void)unused;
    assert(!entry_current(&original_entry));
    return NULL;
}
#endif

int main(int argc, char **argv) {
#if !defined(ACTQL_RESIDENT_INITIAL_CONTROL_HEADER)
    (void)argc; (void)argv;
    assert(!selected_recipe());
    assert(!capture_entry(&original_entry));
    assert(!entry_current(&original_entry));
    puts("PASS unselected entry refuses without capture");
    return 0;
#else
    if (argc == 2 && strcmp(argv[1], "loader-refusal") == 0) {
#if defined(__linux__)
        const char *key = "LD_ACTQL_RESIDENT_COMPONENT";
#else
        const char *key = "DYLD_ACTQL_RESIDENT_COMPONENT";
#endif
        assert(setenv(key, "1", 1) == 0);
        assert(!capture_entry(&original_entry));
        assert(!entry_current(&original_entry));
        assert(unsetenv(key) == 0);
        assert(!capture_entry(&original_entry));
        puts("PASS unsupported loader selection stays refused");
        return 0;
    }
    if (argc == 2 && strlen(argv[1]) > ACTQL_RESIDENT_ARGUMENT_BYTES) {
        assert(!capture_entry(&original_entry));
        assert(!entry_current(&original_entry));
        puts("PASS argument bound checked before original copy");
        return 0;
    }
    assert(capture_entry(&original_entry));
    assert(entry_current(&original_entry));
    assert(!capture_entry(&original_entry));
    assert(entry_current(&original_entry));
    resident_entry copied = original_entry;
    assert(!entry_current(&copied));
    pthread_t thread;
    assert(pthread_create(&thread, NULL, foreign_thread, NULL) == 0);
    assert(pthread_join(thread, NULL) == 0);
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) _exit(entry_current(&original_entry) ? 1 : 0);
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    assert(entry_current(&original_entry));
    unsigned char saved = (unsigned char)argv[0][0];
    argv[0][0] = (char)(saved ^ 1);
    assert(!entry_current(&original_entry));
    argv[0][0] = (char)saved;
    assert(entry_current(&original_entry));
    original_entry.retired = true;
    assert(!entry_current(&original_entry));
    puts("PASS same original; copy, thread, fork, changed input and retired refusals");
    return 0;
#endif
}
