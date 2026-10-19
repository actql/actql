#include "../initial_loader_environment.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
  assert(argc == 2);
  if (!strcmp(argv[1], "vectors")) {
    char *empty[] = {NULL};
    char *ordinary[] = {"", "D", "DY", "DYL", "DYLD", "DYLDX=x",
      "dyld_print_libraries=1", "OTHER=DYLD_INSERT_LIBRARIES=x", NULL};
    assert(!actql_native_loader_environment_vector_supported(NULL));
    assert(actql_native_loader_environment_vector_supported(empty));
    assert(actql_native_loader_environment_vector_supported(ordinary));
    const char *names[] = {"DYLD_", "DYLD_INSERT_LIBRARIES=x", "DYLD_LIBRARY_PATH=",
      "DYLD_PRINT_LIBRARIES=0", "DYLD_FUTURE_OPTION=1"};
    for (size_t i = 0; i < sizeof(names)/sizeof(names[0]); ++i) {
      char *v[] = {"OTHER=value", (char *)names[i], NULL};
      assert(!actql_native_loader_environment_vector_supported(v));
    }
    puts("bounded environment vectors passed");
  } else if (!strcmp(argv[1], "boundary")) {
    static char *v[ACTQL_NATIVE_LOADER_ENVIRONMENT_SLOTS];
    for (size_t i = 0; i < ACTQL_NATIVE_LOADER_ENVIRONMENT_SLOTS; ++i) v[i] = "X=x";
    assert(!actql_native_loader_environment_vector_supported(v));
    v[ACTQL_NATIVE_LOADER_ENVIRONMENT_SLOTS-1] = NULL;
    assert(actql_native_loader_environment_vector_supported(v));
    v[ACTQL_NATIVE_LOADER_ENVIRONMENT_SLOTS-2] = "DYLD_PRINT_LIBRARIES=1";
    assert(!actql_native_loader_environment_vector_supported(v));
    puts("bounded environment termination passed");
  } else if (!strcmp(argv[1], "actual-change")) {
    actql_native_loader_environment observation = {0};
    assert(actql_native_loader_environment_capture(&observation));
    assert(actql_native_loader_environment_current(&observation));
    assert(!actql_native_loader_environment_capture(&observation));
    assert(setenv("DYLD_PRINT_LIBRARIES", "0", 1) == 0);
    assert(!actql_native_loader_environment_current(&observation));
    assert(unsetenv("DYLD_PRINT_LIBRARIES") == 0);
    assert(!actql_native_loader_environment_current(&observation));
    assert(!actql_native_loader_environment_capture(&observation));
    assert(observation.state == ACTQL_LOADER_ENVIRONMENT_REFUSED);
    puts("actual environment change remains refused");
  } else if (!strcmp(argv[1], "actual-refusal")) {
    assert(setenv("DYLD_INSERT_LIBRARIES", "unsupported", 1) == 0);
    actql_native_loader_environment observation = {0};
    assert(!actql_native_loader_environment_capture(&observation));
    assert(unsetenv("DYLD_INSERT_LIBRARIES") == 0);
    assert(!actql_native_loader_environment_current(&observation));
    assert(!actql_native_loader_environment_capture(&observation));
    puts("actual initial refusal remains refused");
  } else {
    assert(!"unknown case");
  }
  return 0;
}
