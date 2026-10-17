// One borrowed original backing descriptor. The caller still owns its source;
// this carrier owns only its new close-on-exec duplicate and every uncertain
// close of that duplicate. None of these facts admits capacity or permission.
typedef struct {
  int source;
  int descriptor;
  int unknown_descriptor;
  dev_t device;
  ino_t inode;
  int access_mode;
  pthread_t owner_thread;
  bool captured;
  bool close_unknown;
  int32_t status;
} actql_executor_selected_child;

static bool actql_executor_selected_child_matches(
  actql_executor_selected_child *record, int descriptor
) {
  struct stat value;
  int flags = fcntl(descriptor, F_GETFL);
  return descriptor >= 0 && record->captured && flags >= 0 &&
    fstat(descriptor, &value) == 0 && S_ISREG(value.st_mode) &&
    value.st_dev == record->device && value.st_ino == record->inode &&
    (flags & O_ACCMODE) == record->access_mode;
}

static int32_t actql_executor_selected_child_close(
  actql_executor_selected_child *record
) {
  if (!pthread_equal(record->owner_thread, pthread_self())) return -1;
  if (record->descriptor < 0) return record->close_unknown ? -1 : 0;
  int original = record->descriptor;
  record->descriptor = -1;
  if (!actql_executor_selected_child_matches(record, original) ||
      actql_executor_slot_close(original) != 0) {
    record->unknown_descriptor = original;
    record->close_unknown = true;
    return -1;
  }
  return record->close_unknown ? -1 : 0;
}

static void actql_executor_selected_child_finalize(void *pointer) {
  // A best-effort finalizer is never an observed close/Stop acknowledgement.
  (void)actql_executor_selected_child_close(pointer);
}

void *actql_executor_slot_capture_selected_child(int32_t source) {
  actql_executor_selected_child *record = moonbit_make_external_object(
    actql_executor_selected_child_finalize, sizeof(*record));
  memset(record, 0, sizeof(*record));
  record->source = source;
  record->descriptor = -1;
  record->unknown_descriptor = -1;
  record->owner_thread = pthread_self();
  record->status = -3;
  struct stat original;
  int original_flags = fcntl(source, F_GETFL);
  int original_fd_flags = fcntl(source, F_GETFD);
  if (source < 0 || original_flags < 0 || original_fd_flags < 0 ||
      (original_fd_flags & FD_CLOEXEC) == 0 ||
      fstat(source, &original) != 0 || !S_ISREG(original.st_mode)) return record;
  int copied = fcntl(source, F_DUPFD_CLOEXEC,
    ACTQL_EXECUTOR_SLOT_FIRST_PRIVATE_FD);
  if (copied < 0) return record;
  // Retain the new owned alias before any inspection which can refuse.
  record->descriptor = copied;
  struct stat observed;
  int flags = fcntl(copied, F_GETFL);
  if (flags < 0 || fstat(copied, &observed) != 0 ||
      !S_ISREG(observed.st_mode)) {
    record->close_unknown = true;
    return record;
  }
  record->device = observed.st_dev;
  record->inode = observed.st_ino;
  record->access_mode = flags & O_ACCMODE;
  record->captured = true;
  if (observed.st_dev != original.st_dev || observed.st_ino != original.st_ino ||
      record->access_mode != (original_flags & O_ACCMODE)) return record;
  record->status = 0;
  return record;
}

int32_t actql_executor_slot_selected_child_current(
  actql_executor_selected_child *record
) {
  if (!pthread_equal(record->owner_thread, pthread_self())) return -1;
  if (record->close_unknown) return -4;
  if (record->status != 0) return -3;
  if (record->descriptor < 0) return -2;
  int source_flags = fcntl(record->source, F_GETFD);
  if (source_flags < 0 || (source_flags & FD_CLOEXEC) == 0 ||
      !actql_executor_selected_child_matches(record, record->source) ||
      !actql_executor_selected_child_matches(record, record->descriptor)) return -4;
  return 0;
}

int32_t actql_executor_slot_selected_child_close(
  actql_executor_selected_child *record
) {
  return actql_executor_selected_child_close(record);
}

int32_t actql_executor_slot_selected_child_closed(
  actql_executor_selected_child *record
) {
  if (!pthread_equal(record->owner_thread, pthread_self()) ||
      record->close_unknown) return -1;
  return record->descriptor < 0 ? 0 : 1;
}

enum {
  ACTQL_EXECUTOR_SELECTED_ENV_COUNT = 4,
  ACTQL_EXECUTOR_SELECTED_ENV_VALUE_BYTES = 4096,
  ACTQL_EXECUTOR_SELECTED_ENV_BYTES = 4 * (8 + 1 + 4096 + 1),
};

// The existing worker/compiler selection supplies these four OS fields only.
// No process environment is merged when the selected array is empty.
static int actql_executor_selected_environment_key(const char *text) {
  static const char *keys[] = {"LANG=", "LC_ALL=", "LC_CTYPE=", "TMPDIR="};
  for (int index = 0; index < ACTQL_EXECUTOR_SELECTED_ENV_COUNT; index++) {
    size_t length = strlen(keys[index]);
    if (strncmp(text, keys[index], length) == 0 &&
        strlen(text + length) <= ACTQL_EXECUTOR_SELECTED_ENV_VALUE_BYTES) return index;
  }
  return -1;
}

int32_t actql_executor_slot_spawn_selected_duplex(
  moonbit_bytes_t executable, int32_t executable_length,
  moonbit_bytes_t arguments, int32_t arguments_length,
  int32_t descriptor, int32_t target_descriptor, int32_t input, int32_t output,
  actql_executor_selected_child *record,
  moonbit_bytes_t environment, int32_t environment_length
) {
  struct stat input_status;
  struct stat output_status;
  int input_flags = fcntl(input, F_GETFL);
  int output_flags = fcntl(output, F_GETFL);
  if (target_descriptor != 3 ||
      executable_length <= 0 || executable_length != Moonbit_array_length(executable) ||
      executable[0] != '/' ||
      arguments_length <= 0 || arguments_length != Moonbit_array_length(arguments) ||
      input < ACTQL_EXECUTOR_SLOT_FIRST_PRIVATE_FD ||
      output < ACTQL_EXECUTOR_SLOT_FIRST_PRIVATE_FD || input == output ||
      input_flags < 0 || (input_flags & O_ACCMODE) != O_RDONLY ||
      output_flags < 0 || (output_flags & O_ACCMODE) != O_WRONLY ||
      fstat(input, &input_status) != 0 || !S_ISFIFO(input_status.st_mode) ||
      fstat(output, &output_status) != 0 || !S_ISFIFO(output_status.st_mode) ||
      actql_executor_slot_selected_child_current(record) != 0 ||
      record->descriptor == descriptor || record->descriptor == input ||
      record->descriptor == output || environment_length < 0 ||
      environment_length > ACTQL_EXECUTOR_SELECTED_ENV_BYTES ||
      environment_length != Moonbit_array_length(environment) ||
      (environment_length > 0 && environment[environment_length - 1] != 0)) return -1;
  char *block = malloc((size_t)environment_length + 1);
  if (block == NULL) return -1;
  memcpy(block, environment, (size_t)environment_length);
  block[environment_length] = 0;
  char *selected[ACTQL_EXECUTOR_SELECTED_ENV_COUNT + 1];
  bool seen[ACTQL_EXECUTOR_SELECTED_ENV_COUNT] = {false};
  int count = 0;
  int32_t offset = 0;
  bool valid = true;
  while (offset < environment_length) {
    int key = actql_executor_selected_environment_key(block + offset);
    if (count == ACTQL_EXECUTOR_SELECTED_ENV_COUNT || key < 0 || seen[key]) {
      valid = false;
      break;
    }
    seen[key] = true;
    selected[count++] = block + offset;
    offset += (int32_t)strlen(block + offset) + 1;
  }
  selected[count] = NULL;
  int32_t result = valid ? actql_executor_slot_spawn_streams(
    executable, executable_length, arguments, arguments_length, descriptor,
    target_descriptor, input, output, record->descriptor, selected) : -1;
  free(block);
  return result;
}

// Finite fresh-file fixtures, outside any existing Run/Store namespace.
int32_t actql_executor_slot_test_selected_backing(
  moonbit_bytes_t path, int32_t path_length,
  moonbit_bytes_t contents, int32_t content_length
) {
  if (content_length < 0 || content_length > 4096) return -1;
  char *text = actql_executor_slot_text(path, path_length);
  if (text == NULL) return -1;
  int descriptor = open(text, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (descriptor < 0) { free(text); return -1; }
  // Removing the fixture's name proves later launch consumes the FD only.
  int removed = unlink(text);
  free(text);
  if (removed != 0 || write(descriptor, contents, (size_t)content_length) != content_length ||
      lseek(descriptor, 0, SEEK_SET) != 0) {
    close(descriptor);
    return -1;
  }
  return descriptor;
}

int32_t actql_executor_slot_test_selected_descriptor(
  actql_executor_selected_child *record
) {
  return record->descriptor;
}

int32_t actql_executor_slot_test_selected_without_cloexec(int32_t descriptor) {
  int flags = fcntl(descriptor, F_GETFD);
  return flags < 0 ? -1 : fcntl(descriptor, F_SETFD, flags & ~FD_CLOEXEC);
}

int32_t actql_executor_slot_test_selected_private_source(int32_t descriptor) {
  return fcntl(descriptor, F_DUPFD_CLOEXEC,
    ACTQL_EXECUTOR_SLOT_FIRST_PRIVATE_FD);
}

typedef struct { actql_executor_selected_child *record; int status; }
  actql_executor_selected_thread_probe;

static void *actql_executor_selected_foreign_thread(void *pointer) {
  actql_executor_selected_thread_probe *probe = pointer;
  probe->status = actql_executor_slot_selected_child_current(probe->record);
  return NULL;
}

int32_t actql_executor_slot_test_selected_foreign_thread(
  actql_executor_selected_child *record
) {
  actql_executor_selected_thread_probe probe = {record, 0};
  pthread_t thread;
  if (pthread_create(&thread, NULL, actql_executor_selected_foreign_thread,
      &probe) != 0) return -2;
  if (pthread_join(thread, NULL) != 0) return -2;
  return probe.status;
}
