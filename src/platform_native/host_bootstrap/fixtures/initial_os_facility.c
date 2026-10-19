/* Controlled parent-port protocol fixture. The actual process/thread calls
 * are real; this fixture does not supply the production entry/recipe proof. */
#include "../initial_os_facility.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>

static unsigned char parent_storage[2];
static actql_native_command_platform_original *parent =
  (actql_native_command_platform_original *)&parent_storage[0];
actql_native_command_platform_original *
actql_native_command_platform_initial_current(void) { return parent; }

static void *foreign_thread(void *pointer) {
  assert(!actql_native_initial_os_facility_current(pointer));
  return NULL;
}

int main(int argc, char **argv) {
  assert(argc == 2);
  if (!strcmp(argv[1], "unselected")) {
    assert(actql_native_initial_os_facility_capture() == NULL);
    assert(!actql_native_initial_os_facility_current(NULL));
  } else if (!strcmp(argv[1], "one-shot")) {
    actql_native_initial_os_facility *original = actql_native_initial_os_facility_capture();
    assert(original && actql_native_initial_os_facility_current(original));
    assert(actql_native_initial_os_facility_capture() == NULL);
    actql_native_initial_os_facility copy = *original;
    assert(!actql_native_initial_os_facility_current(&copy));
    assert(!actql_native_initial_os_facility_current((void *)&parent_storage[1]));
    assert(!actql_native_initial_os_facility_current(NULL));
    assert(actql_native_initial_os_facility_current(original));
    parent = (actql_native_command_platform_original *)&parent_storage[1];
    assert(!actql_native_initial_os_facility_current(original));
    parent = (actql_native_command_platform_original *)&parent_storage[0];
    assert(!actql_native_initial_os_facility_current(original));
  } else if (!strcmp(argv[1], "foreign")) {
    actql_native_initial_os_facility *original = actql_native_initial_os_facility_capture();
    assert(original && actql_native_initial_os_facility_current(original));
    pthread_t thread;
    assert(pthread_create(&thread, NULL, foreign_thread, original) == 0);
    assert(pthread_join(thread, NULL) == 0);
    assert(actql_native_initial_os_facility_current(original));
    pid_t child = fork(); assert(child >= 0);
    if (child == 0) {
      assert(!actql_native_initial_os_facility_current(original));
      _exit(0);
    }
    int status;
    assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    assert(actql_native_initial_os_facility_current(original));
  } else if (!strcmp(argv[1], "missing")) {
    parent = NULL;
    assert(actql_native_initial_os_facility_capture() == NULL);
    parent = (actql_native_command_platform_original *)&parent_storage[0];
    assert(actql_native_initial_os_facility_capture() == NULL);
  } else if (!strcmp(argv[1], "partial")) {
    assert(setenv("DYLD_PRINT_LIBRARIES", "0", 1) == 0);
    actql_native_initial_os_facility *original = actql_native_initial_os_facility_capture();
    assert(original && !actql_native_initial_os_facility_current(original));
    assert(unsetenv("DYLD_PRINT_LIBRARIES") == 0);
    assert(!actql_native_initial_os_facility_current(original));
    assert(actql_native_initial_os_facility_capture() == NULL);
  } else {
    assert(!"unknown case");
  }
  puts("initial OS facility protocol passed; production entry admission unexecuted");
  return 0;
}
