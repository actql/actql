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
  /* Runtime initializers and ordinary stdio use already happened. Neither is
   * a prerequisite for binding the command in normal main. */
  assert(atomic_load(&actql_command_entry_state) == 0);
  assert(!actql_command_early_input_attempted);
  assert(actql_native_command_platform_current() == NULL);
  assert(fputs("", stdout) >= 0 && fflush(stdout) == 0);
  assert(fputs("", stderr) >= 0 && fflush(stderr) == 0);
  if (strcmp(argv[1], "used-streams") == 0) {
    FILE *saved = stdout;
    FILE *replacement = tmpfile();
    assert(replacement);
    assert(fputs("prior", replacement) >= 0 && fflush(replacement) == 0);
    stdout = replacement;
    assert(actql_native_client_measure_prearguments(256,4096,65536,8192) == 0);
    actql_native_client_capture_command_entry();
    assert(actql_native_command_platform_current());
    unsigned char body[] = "body";
    assert(actql_native_client_write_stdout(body, 4));
    rewind(replacement);
    char observed[10] = {0};
    assert(fread(observed, 1, 9, replacement) == 9);
    assert(strcmp(observed, "priorbody") == 0);
    stdout = saved;
    assert(fclose(replacement) == 0);
    FILE *readonly = fopen("/dev/null", "r");
    assert(readonly);
    stdout = readonly;
    assert(!actql_native_client_write_stdout(body, 4));
    stdout = saved;
    assert(fclose(readonly) == 0);
    puts("original entry record passed");
    return 0;
  }
  assert(actql_native_client_measure_prearguments(256,4096,65536,8192) == 0);
  if (strcmp(argv[1], "argument-currentness") == 0) {
    int original_argc = 0;
    const char *const *original_argv = NULL;
    assert(actql_command_raw_arguments(&original_argc, &original_argv));
    assert(original_argc == argc && original_argv == (const char *const *)argv);
    assert(actql_command_original_arguments_current());
    char original = argv[1][0];
    argv[1][0] = 'X';
    assert(!actql_command_original_arguments_current());
    argv[1][0] = original;
    char *retained = argv[1];
    argv[1] = NULL;
    assert(!actql_command_original_arguments_current());
    argv[1] = retained;
    assert(actql_command_original_arguments_current());
#if defined(__linux__) && defined(__x86_64__) && defined(__GLIBC__)
    assert(actql_native_client_compiled_platform() == 2);
    actql_command_capture_linux_arguments(1, NULL, NULL);
    assert(actql_command_raw_arguments(&original_argc, &original_argv));
    assert(original_argc == argc && original_argv == (const char *const *)argv);
#else
    assert(actql_native_client_compiled_platform() == 1);
#endif
    puts("original entry record passed");
    return 0;
  }
  actql_native_client_capture_command_entry();
  assert(atomic_load(&actql_command_entry_state) == 2);
  actql_native_command_platform_original *entry =
    actql_native_command_platform_current();
  assert(entry == &actql_command_entry);
  if (strcmp(argv[1], "capture") == 0) {
    actql_native_client_capture_command_entry();
    assert(actql_native_command_platform_current() == entry);
    size_t unchanged[4] = {11,22,33,44};
    assert(!actql_native_command_platform_managed_selection(entry, unchanged));
    for (size_t i = 0; i < 4; i++) assert(unchanged[i] == 11 * (i + 1));
    puts("original entry record passed");
    return 0;
  }
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
