#include <assert.h>
#include <sys/wait.h>
#include "../../src/cmd/native_client/stdout_stub.c"

extern actql_native_observed_component_member *fixture_member(int,int,int *);
extern void fixture_member_stop(actql_native_observed_component_member *);
extern int fixture_member_checks(void);

static void *foreign_stack_thread(void *raw) {
  const actql_bootstrap_command_stack *original = raw;
  assert(!actql_bootstrap_command_stack_current(original));
  actql_bootstrap_command_stack refused = {0};
  assert(!actql_bootstrap_capture_command_stack(&refused));
  assert(refused.attempted && !refused.captured);
  assert(!actql_bootstrap_capture_command_stack(&refused));
  return NULL;
}

static void *foreign_initial_thread(void *raw) {
  (void)raw;
  assert(actql_native_command_platform_initial_current() == NULL);
  return NULL;
}

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
  assert(!actql_command_initial_recipe_current(&actql_command_entry));
  assert(actql_command_entry.initial_managed == NULL);
  if (strcmp(argv[1], "initial-candidate") == 0) {
    assert(actql_native_command_platform_initial_current() == &actql_command_entry);
    size_t expected[4] = {0};
    size_t volume = actql_command_entry.initial_parser_allocation_volume;
    assert(actql_initial_managed_prepare_candidate(volume, expected));
    for (size_t index = 0; index < 4; ++index)
      assert(actql_command_entry.initial_managed_selection[index] == expected[index]);
    const size_t segment = ACTQL_INITIAL_MI_SEGMENT_BYTES;
    assert(expected[0] >= volume && expected[0] % segment == 0);
    assert(expected[0] - volume < segment);
    assert(expected[1] == 2 * segment && expected[2] == volume && expected[3] == 1);
    assert(actql_initial_managed_geometry(expected));
    size_t unchanged[4] = {11, 22, 33, 44};
    assert(!actql_initial_managed_prepare_candidate(0, unchanged));
    assert(!actql_initial_managed_prepare_candidate(SIZE_MAX, unchanged));
    for (size_t index = 0; index < 4; ++index) assert(unchanged[index] == 11 * (index + 1));
    assert(!actql_native_command_platform_managed_selection(&actql_command_entry, unchanged));
    for (size_t index = 0; index < 4; ++index) assert(unchanged[index] == 11 * (index + 1));
    pthread_t other;
    assert(pthread_create(&other, NULL, foreign_initial_thread, NULL) == 0);
    assert(pthread_join(other, NULL) == 0);
    pid_t child = fork(); assert(child >= 0);
    if (child == 0) { foreign_initial_thread(NULL); _exit(0); }
    int status = -1;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    char original = argv[1][0]; argv[1][0] = 'X';
    assert(actql_native_command_platform_initial_current() == NULL);
    argv[1][0] = original;
    assert(actql_native_client_measure_prearguments(256,4096,65536,8192) == 0);
    actql_native_client_capture_command_entry();
    assert(actql_native_command_platform_initial_current() == &actql_command_entry);
    assert(!actql_command_entry.initial_envelope_admitted);
    assert(!actql_command_initial_recipe_current(&actql_command_entry));
    assert(actql_native_command_platform_current() == NULL);
    assert(actql_command_entry.initial_managed == NULL);
    puts("original entry record passed");
    return 0;
  }
  if (strcmp(argv[1], "initial-stack") == 0) {
    actql_bootstrap_command_stack *original = &actql_command_entry.initial_stack;
    volatile unsigned char marker = 0;
    assert(original->attempted && original->captured);
    assert(original->process == getpid());
    assert(pthread_equal(original->thread, pthread_self()));
    assert(original->upper == (uintptr_t)pthread_get_stackaddr_np(pthread_self()));
    assert(original->bytes == pthread_get_stacksize_np(pthread_self()));
    assert(original->lower == original->upper - original->bytes);
    assert((uintptr_t)&marker >= original->lower && (uintptr_t)&marker < original->upper);
    assert(actql_bootstrap_command_stack_current(original));
    uintptr_t lower = original->lower, upper = original->upper;
    size_t bytes = original->bytes;
    assert(!actql_bootstrap_capture_command_stack(original));
    assert(original->lower == lower && original->upper == upper && original->bytes == bytes);
    pthread_t other;
    assert(pthread_create(&other, NULL, foreign_stack_thread, original) == 0);
    assert(pthread_join(other, NULL) == 0);
    assert(actql_bootstrap_command_stack_current(original));
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
      assert(!actql_bootstrap_command_stack_current(original));
      _exit(0);
    }
    int status = -1;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    original->lower += 1;
    assert(!actql_bootstrap_command_stack_current(original));
    original->lower = lower;
    assert(actql_bootstrap_command_stack_current(original));
    assert(!actql_command_initial_recipe_current(&actql_command_entry));
    assert(!actql_command_entry.initial_envelope_admitted);
    assert(actql_native_command_platform_current() == NULL);
    printf("original stack bytes=%zu entry bytes=%zu\n", original->bytes,
      sizeof(actql_command_entry));
    puts("original entry record passed");
    return 0;
  }
  if (strcmp(argv[1], "initial-volume") == 0) {
    size_t observed = 0, expected = 0;
    assert(actql_command_initial_parser_volume(
      actql_command_input.input.arguments, actql_command_input.input.storage_bytes,
      actql_command_argument_classes, &observed));
    assert(observed == actql_command_entry.initial_parser_allocation_volume);
    int64_t arithmetic_classes[4] = {16, 32, 48, 80};
    assert(actql_command_initial_parser_volume(4, 4096,
      arithmetic_classes, &expected));
    assert(expected == 68370633 + 16 + 32 + 48 + 80);
    assert(actql_command_initial_parser_volume(1048576, 1048576,
      arithmetic_classes, &expected));
    assert(expected == 1874331593ULL + 16 + 32 + 48 + 80);
    size_t unchanged = 123;
    assert(!actql_command_initial_parser_volume(0, 4096,
      arithmetic_classes, &unchanged) && unchanged == 123);
    assert(!actql_command_initial_parser_volume(1048577, 1048577,
      arithmetic_classes, &unchanged) && unchanged == 123);
    assert(!actql_command_initial_parser_volume(4, 3,
      arithmetic_classes, &unchanged) && unchanged == 123);
    arithmetic_classes[0] = -1;
    assert(!actql_command_initial_parser_volume(4, 4096,
      arithmetic_classes, &unchanged) && unchanged == 123);
    for (size_t i = 0; i < 4; i++) arithmetic_classes[i] = INT64_MAX;
    assert(!actql_command_initial_parser_volume(4, 4096,
      arithmetic_classes, &unchanged) && unchanged == 123);
    assert(!actql_command_initial_recipe_current(&actql_command_entry));
    assert(!actql_command_entry.initial_envelope_admitted);
    assert(actql_command_entry.initial_managed == NULL);
    assert(actql_native_command_platform_current() == NULL);
    puts("original entry record passed");
    return 0;
  }
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
