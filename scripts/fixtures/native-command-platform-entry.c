#include <assert.h>
#include <sys/wait.h>
#include "../../src/cmd/native_client/stdout_stub.c"

extern actql_native_observed_component_member *fixture_member(int,int,int *);
extern void fixture_member_stop(actql_native_observed_component_member *);
extern int fixture_member_checks(void);

static void *foreign_thread(void *raw) {
  actql_native_command_platform_load *load = raw;
  assert(actql_native_command_platform_current() == NULL);
  assert(!actql_native_command_platform_available());
  assert(actql_native_command_platform_scratch_directory(
    &actql_command_entry) == NULL);
  assert(!actql_native_command_platform_load_current(load));
  assert(!actql_native_command_platform_module_released(load, (void *)1));
  return NULL;
}

int main(int argc, char **argv) {
  assert(argc == 2);
  assert(atomic_load(&actql_command_entry_state) == 1);
  assert(actql_command_entry.process == getpid());
  assert(pthread_equal(actql_command_entry.thread, pthread_self()));
  assert(actql_native_command_platform_current() == NULL);
  assert(actql_native_command_platform_scratch_directory(
    &actql_command_entry) == NULL);
  assert(actql_command_early_input_attempted);
  assert(actql_command_early_input_status == ACTQL_COMMAND_INPUT_OK);
  assert(!actql_command_input_attempted);
  size_t refused_selection[4] = {11,22,33,44};
  assert(!actql_native_command_platform_managed_selection(
    &actql_command_entry, refused_selection));
  assert(refused_selection[0] == 11 && refused_selection[1] == 22 &&
    refused_selection[2] == 33 && refused_selection[3] == 44);
  assert(!actql_command_entry.initial_coverage_complete);
  assert(actql_command_entry.initial_managed == NULL);
  if (strcmp(argv[1], "early-input") == 0) {
    char original[ACTQL_COMMAND_ORIGINAL_CONTEXT_BYTES + 1];
    size_t length = actql_command_input.context_bytes;
    assert(length > 0 && length < sizeof(original));
    memcpy(original, actql_command_original_context, length + 1);
    assert(setenv("ACTQL_NATIVE_LOCAL_RUNTIME", "replacement", 1) == 0);
    assert(setenv("TMPDIR", "/replacement/scratch", 1) == 0);
    assert(actql_native_client_measure_prearguments(256,4096,65536,8192) == 0);
    assert(actql_native_client_preargument_selection() == ACTQL_COMMAND_INPUT_OK);
    unsigned char observed[ACTQL_COMMAND_ORIGINAL_CONTEXT_BYTES];
    assert(actql_native_client_copy_preargument_context(observed, (int32_t)length));
    assert(memcmp(observed, original, length) == 0);
    assert(strcmp(actql_command_input_scratch, "/original/command-scratch") == 0);
    actql_native_client_capture_command_entry();
    assert(atomic_load(&actql_command_entry_state) == 2);
    assert(!actql_command_entry.initial_envelope_admitted);
    assert(actql_native_command_platform_current() == NULL);
    puts("original entry record passed");
    return 0;
  }
  if (strcmp(argv[1], "early-argv-change") == 0) {
    argv[1][0] = 'X';
    assert(actql_native_client_measure_prearguments(256,4096,65536,8192)
      == ACTQL_COMMAND_INPUT_INVALID);
    assert(actql_native_client_preargument_selection() == ACTQL_COMMAND_INPUT_INVALID);
    actql_native_client_capture_command_entry();
    assert(atomic_load(&actql_command_entry_state) == -1);
    assert(actql_native_command_platform_current() == NULL);
    argv[1][0] = 'e';
    assert(actql_native_client_measure_prearguments(256,4096,65536,8192)
      == ACTQL_COMMAND_INPUT_INVALID);
    assert(!actql_command_entry.initial_envelope_admitted);
    puts("original entry record passed");
    return 0;
  }
  assert(actql_native_client_measure_prearguments(256,4096,65536,8192) == 0);
  actql_native_client_capture_command_entry();
  assert(atomic_load(&actql_command_entry_state) == 2);
  assert(actql_command_entry.image == (const void *)_dyld_get_image_header(0));
  assert(actql_native_command_platform_current() == NULL);
  if (strcmp(argv[1], "capture") == 0) {
    actql_native_client_capture_command_entry();
    assert(actql_native_command_platform_current() == NULL);
    puts("original entry record passed");
    return 0;
  }

  /* Exercise the private record's lifecycle after a controlled admission.
   * This fixture-only state write is NOT a product constructor, an installed
   * initial envelope, a filesystem original, dlopen or physical module ACK. */
  actql_command_entry.initial_envelope_admitted = true;
  actql_native_command_platform_original *entry =
    actql_native_command_platform_current();
  assert(entry == &actql_command_entry);
  assert(actql_native_command_platform_available());
  assert(actql_native_command_platform_scratch_directory((void *)1) == NULL);
  const char *scratch = actql_native_command_platform_scratch_directory(entry);
  assert(scratch && strcmp(scratch, getenv("TMPDIR")) == 0);
  /* Later environment replacement cannot change the selected original. */
  assert(setenv("TMPDIR", "/different-current-environment", 1) == 0);
  assert(actql_native_command_platform_scratch_directory(entry) == scratch);
  assert(strcmp(scratch, "/different-current-environment") != 0);
  int finalized = 0;
  actql_native_observed_component_member *member = fixture_member(1,0,&finalized);
  assert(!actql_native_command_platform_begin_load(
    (void *)1, ACTQL_NATIVE_COMMAND_SQLITE_COMPONENT, member));
  actql_native_command_platform_load *load =
    actql_native_command_platform_begin_load(entry,
      ACTQL_NATIVE_COMMAND_SQLITE_COMPONENT, member);
  assert(load != NULL && actql_native_command_platform_load_current(load));
  if (strcmp(argv[1], "one-shot") == 0) {
    assert(!actql_native_command_platform_begin_load(entry,
      ACTQL_NATIVE_COMMAND_SQLITE_COMPONENT, member));
    assert(actql_native_command_platform_observe_load(load, NULL));
    assert(!actql_native_command_platform_observe_load(load, (void *)1));
    assert(!actql_native_command_platform_module_released(load, (void *)1));
    assert(actql_native_command_platform_module_released(load, NULL));
    assert(!actql_native_command_platform_begin_load(entry,
      ACTQL_NATIVE_COMMAND_SQLITE_COMPONENT, member));
    assert(load->attempted && load->released);
  } else if (strcmp(argv[1], "partial-current") == 0) {
    fixture_member_stop(member);
    assert(!actql_native_command_platform_observe_load(load, (void *)1));
    assert(load->observed && load->module == (void *)1 && !load->released);
    assert(!actql_native_command_platform_module_released(load, NULL));
    assert(actql_native_command_platform_module_released(load, (void *)1));
  } else if (strcmp(argv[1], "thread-fork") == 0) {
    assert(actql_native_command_platform_observe_load(load, (void *)1));
    pthread_t thread;
    assert(pthread_create(&thread, NULL, foreign_thread, load) == 0);
    assert(pthread_join(thread, NULL) == 0);
    pid_t child = fork(); assert(child >= 0);
    if (child == 0) { foreign_thread(load); _exit(0); }
    int status; assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    assert(!load->released);
    assert(actql_native_command_platform_module_released(load, (void *)1));
  } else if (strcmp(argv[1], "runtime") == 0) {
    int other_finalized = 0;
    actql_native_observed_component_member *other =
      fixture_member(2,1,&other_finalized);
    assert(!actql_native_command_platform_begin_load(entry,
      ACTQL_NATIVE_COMMAND_CRYPTO_COMPONENT, other));
    assert(!entry->loads[1].attempted);
    moonbit_decref(other); assert(other_finalized == 1);
    assert(actql_native_command_platform_observe_load(load, NULL));
    assert(actql_native_command_platform_module_released(load, NULL));
  } else { assert(!"unknown fixture selection"); }

  assert(finalized == 0); /* Caller still owns its own member alias. */
  moonbit_decref(member); assert(finalized == 1);
  int checks = fixture_member_checks();
  assert(!actql_native_command_platform_load_current(load));
  assert(actql_native_command_platform_module_released(load, load->module));
  assert(fixture_member_checks() == checks);
  assert(entry->runtime != NULL && load->attempted);
  puts("original entry record passed");
  return 0;
}
