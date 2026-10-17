// Parent-owned transport holding. This is neither resource admission nor a
// child-stop acknowledgement. Every original endpoint is consumed at most once.
typedef struct {
  int descriptor;
  dev_t device;
  ino_t inode;
  int access_mode;
  bool captured;
  int unknown_descriptor;
  int moved_from_unknown_descriptor;
} actql_executor_duplex_endpoint;

typedef struct {
  // Child stdin, parent stdin writer, child stdout, parent stdout reader.
  actql_executor_duplex_endpoint ends[4];
  pthread_t owner_thread;
  int32_t status;
  bool close_unknown;
} actql_executor_duplex;

static bool actql_executor_duplex_same(actql_executor_duplex_endpoint *end) {
  if (end->descriptor < 0 || !end->captured) return false;
  struct stat observed;
  int flags = fcntl(end->descriptor, F_GETFL);
  return fstat(end->descriptor, &observed) == 0 && S_ISFIFO(observed.st_mode) &&
    observed.st_dev == end->device && observed.st_ino == end->inode &&
    flags >= 0 && (flags & O_ACCMODE) == end->access_mode;
}

static int32_t actql_executor_duplex_close_end(
  actql_executor_duplex *transport, int role
) {
  actql_executor_duplex_endpoint *end = &transport->ends[role];
  if (end->descriptor < 0) return transport->close_unknown ? -1 : 0;
  int original = end->descriptor;
  // A reused number must never be closed as replacement cleanup evidence.
  if (!actql_executor_duplex_same(end)) {
    end->descriptor = -1;
    end->unknown_descriptor = original;
    transport->close_unknown = true;
    return -1;
  }
  end->descriptor = -1;
  if (actql_executor_slot_close(original) != 0) {
    end->unknown_descriptor = original;
    transport->close_unknown = true;
    return -1;
  }
  return 0;
}

static void actql_executor_duplex_finalize(void *pointer) {
  actql_executor_duplex *transport = pointer;
  // Best effort does not issue an observed close or an opaque Stop.
  for (int role = 0; role < 4; role++) {
    (void)actql_executor_duplex_close_end(transport, role);
  }
}

static bool actql_executor_duplex_capture(
  actql_executor_duplex_endpoint *end, int descriptor
) {
  end->descriptor = descriptor;
  end->captured = false;
  struct stat observed;
  int flags = fcntl(descriptor, F_GETFL);
  if (fstat(descriptor, &observed) != 0 || !S_ISFIFO(observed.st_mode) ||
      flags < 0) return false;
  end->device = observed.st_dev;
  end->inode = observed.st_ino;
  end->access_mode = flags & O_ACCMODE;
  end->captured = true;
  return true;
}

static int32_t actql_executor_duplex_pipe(
  actql_executor_duplex *transport, int reader_role, int writer_role,
  int (*open_pipe)(int[2])
) {
  int ends[2];
  if (open_pipe(ends) != 0) return -1;
  // Retain both originals before any operation that can refuse.
  bool reader = actql_executor_duplex_capture(
    &transport->ends[reader_role], ends[0]);
  bool writer = actql_executor_duplex_capture(
    &transport->ends[writer_role], ends[1]);
  if (!reader || !writer) return -1;
  const int roles[2] = {reader_role, writer_role};
  for (int n = 0; n < 2; n++) {
    actql_executor_duplex_endpoint *end = &transport->ends[roles[n]];
    int original = end->descriptor;
    int moved = fcntl(original, F_DUPFD_CLOEXEC,
      ACTQL_EXECUTOR_SLOT_FIRST_PRIVATE_FD);
    if (moved < 0) return -1;
    // The moved original remains in this carrier if old-close observation fails.
    if (!actql_executor_duplex_capture(end, moved)) {
      transport->close_unknown = true;
      if (actql_executor_slot_close(original) != 0) {
        end->moved_from_unknown_descriptor = original;
      }
      return -1;
    }
    if (actql_executor_slot_close(original) != 0) {
      transport->close_unknown = true;
      end->moved_from_unknown_descriptor = original;
      return -1;
    }
  }
  return 0;
}

static void *actql_executor_duplex_prepare(int (*open_pipe)(int[2])) {
  actql_executor_duplex *transport = moonbit_make_external_object(
    actql_executor_duplex_finalize, sizeof(*transport));
  memset(transport, 0, sizeof(*transport));
  for (int role = 0; role < 4; role++) {
    transport->ends[role].descriptor = -1;
    transport->ends[role].unknown_descriptor = -1;
    transport->ends[role].moved_from_unknown_descriptor = -1;
  }
  transport->owner_thread = pthread_self();
  transport->status = -1;
  if (actql_executor_duplex_pipe(transport, 0, 1, open_pipe) != 0 ||
      actql_executor_duplex_pipe(transport, 3, 2, open_pipe) != 0) return transport;
  const int parent_roles[2] = {1, 3};
  for (int n = 0; n < 2; n++) {
    int fd = transport->ends[parent_roles[n]].descriptor;
    int flags = fcntl(fd, F_GETFL);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0) return transport;
  }
  transport->status = 0;
  return transport;
}

void *actql_executor_slot_duplex_open(void) {
  return actql_executor_duplex_prepare(pipe);
}

int32_t actql_executor_slot_duplex_current(actql_executor_duplex *transport) {
  if (!pthread_equal(transport->owner_thread, pthread_self())) return -1;
  if (transport->close_unknown) return -4;
  if (transport->status != 0) return -3;
  for (int role = 0; role < 4; role++) {
    actql_executor_duplex_endpoint *end = &transport->ends[role];
    if (end->descriptor >= 0 && !actql_executor_duplex_same(end)) {
      end->unknown_descriptor = end->descriptor;
      end->descriptor = -1;
      transport->close_unknown = true;
      return -4;
    }
  }
  return 0;
}

int32_t actql_executor_slot_duplex_descriptor(
  actql_executor_duplex *transport, int32_t role
) {
  if (role < 0 || role > 3 ||
      actql_executor_slot_duplex_current(transport) != 0) return -1;
  return transport->ends[role].descriptor;
}

int32_t actql_executor_slot_duplex_close_child(actql_executor_duplex *transport) {
  if (!pthread_equal(transport->owner_thread, pthread_self())) return -1;
  int first = actql_executor_duplex_close_end(transport, 0);
  int second = actql_executor_duplex_close_end(transport, 2);
  return first == 0 && second == 0 && !transport->close_unknown ? 0 : -1;
}

int32_t actql_executor_slot_duplex_close(actql_executor_duplex *transport) {
  if (!pthread_equal(transport->owner_thread, pthread_self())) return -1;
  for (int role = 0; role < 4; role++) {
    (void)actql_executor_duplex_close_end(transport, role);
  }
  return transport->close_unknown ? -1 : 0;
}

int32_t actql_executor_slot_duplex_closed(actql_executor_duplex *transport) {
  if (!pthread_equal(transport->owner_thread, pthread_self()) ||
      transport->close_unknown) return -1;
  for (int role = 0; role < 4; role++) {
    if (transport->ends[role].descriptor >= 0) return 1;
  }
  return 0;
}

// Finite original-allocation fault fixture; no process-global fault setter and
// no public constructor from descriptor numbers or serialized evidence.
static _Thread_local int actql_executor_duplex_test_pipe_count = 0;
static int actql_executor_duplex_test_partial_pipe(int ends[2]) {
  if (actql_executor_duplex_test_pipe_count++ != 0) { errno = EMFILE; return -1; }
  return pipe(ends);
}

void *actql_executor_slot_test_duplex_partial(void) {
  actql_executor_duplex_test_pipe_count = 0;
  return actql_executor_duplex_prepare(actql_executor_duplex_test_partial_pipe);
}

int32_t actql_executor_slot_test_duplex_write(
  int32_t descriptor, moonbit_bytes_t bytes, int32_t length
) {
  if (length < 0 || length > 4096) return -1;
  ssize_t count = write(descriptor, bytes, (size_t)length);
  if (count < 0 && (errno == EAGAIN || errno == EINTR)) return -2;
  return count >= 0 && count <= INT32_MAX ? (int32_t)count : -1;
}

moonbit_bytes_t actql_executor_slot_test_duplex_read(int32_t descriptor) {
  uint8_t buffer[4096];
  ssize_t count = read(descriptor, buffer, sizeof(buffer));
  if (count < 0) count = 0;
  moonbit_bytes_t bytes = moonbit_make_bytes_raw((int32_t)count);
  if (count > 0) memcpy(bytes, buffer, (size_t)count);
  return bytes;
}

int32_t actql_executor_slot_test_duplex_open_descriptor(int32_t descriptor) {
  return fcntl(descriptor, F_GETFD) >= 0 ? 1 : 0;
}

typedef struct { actql_executor_duplex *original; int status; }
  actql_executor_duplex_test_thread;

static void *actql_executor_duplex_test_foreign_run(void *pointer) {
  actql_executor_duplex_test_thread *probe = pointer;
  probe->status = actql_executor_slot_duplex_current(probe->original);
  return NULL;
}

int32_t actql_executor_slot_test_duplex_foreign_thread(
  actql_executor_duplex *original
) {
  actql_executor_duplex_test_thread probe = {original, 0};
  pthread_t thread;
  if (pthread_create(&thread, NULL,
      actql_executor_duplex_test_foreign_run, &probe) != 0) return -2;
  if (pthread_join(thread, NULL) != 0) return -2;
  return probe.status;
}
