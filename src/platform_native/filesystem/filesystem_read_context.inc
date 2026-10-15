/* Physical caller of the existing Native Domain read context. No loan issuer,
 * Ledger, permission or origin is created here. The installed supplier must
 * validate the original backed-read use before entering physical capacity.
 * All managed consumers must use the same derived header/free routes.
 *
 * Status is the ORIGINAL context result. An operation's physical result is a
 * separate out parameter. No unavailable scope becomes empty Bytes, successful
 * close, unperformed read or an acquisition retry. Constructors publish the
 * same original Root/Reader even on physical failure. The existing Native
 * failure carrier must retain it; this C port is not yet a MoonBit supplier.
 */
/* Borrowed getter from the same installed provider, never a pointer wire. */
extern actql_read_context *actql_bootstrap_current_read_context(void);

static int actql_filesystem_context_begin(actql_read_context *context) {
  if (context == NULL) return ACTQL_OWNED_INVALID;
  return actql_read_context_enter(context);
}
static int actql_filesystem_root_context_begin(
  actql_native_filesystem_root *root
) {
  if (root == NULL || !root->read_context_user)
    return ACTQL_OWNED_INVALID;
  return actql_filesystem_context_begin(root->read_context);
}
static int actql_filesystem_reader_context_begin(
  actql_native_filesystem_reader *reader
) {
  if (reader == NULL || !reader->read_context_user)
    return ACTQL_OWNED_INVALID;
  return actql_filesystem_context_begin(reader->read_context);
}

static int actql_native_filesystem_scoped_open_root(
  actql_read_context *context, moonbit_bytes_t path, int32_t length,
  int32_t diagnostic_ceiling, actql_native_filesystem_root **output
) {
  if (output == NULL || *output != NULL || diagnostic_ceiling <= 0)
    return ACTQL_OWNED_INVALID;
  int status = actql_read_context_retain(context);
  if (status != ACTQL_OWNED_OK) return status;
  status = actql_filesystem_context_begin(context);
  if (status != ACTQL_OWNED_OK) {
    // No Root, allocation or descriptor was acquired by this constructor.
    int released = actql_read_context_release_after_owner_ack(context);
    return released == ACTQL_OWNED_OK ? status : released;
  }
  actql_native_filesystem_root *root =
    actql_native_filesystem_open_root_with_diagnostics(
      path, length, diagnostic_ceiling);
  root->read_context = context;
  root->read_context_user = true;
  *output = root; // Publish original failure custody before leaving the scope.
  return actql_read_context_leave(context);
}

int actql_native_filesystem_scoped_open_reader(
  actql_native_filesystem_root *root, moonbit_bytes_t name, int32_t length,
  uint64_t device, uint64_t inode, int64_t size,
  actql_native_filesystem_reader **output
) {
  if (root == NULL || !root->read_context_user || output == NULL || *output != NULL)
    return ACTQL_OWNED_INVALID;
  actql_read_context *context = root->read_context;
  int status = actql_read_context_retain(context);
  if (status != ACTQL_OWNED_OK) return status;
  status = actql_filesystem_context_begin(context);
  if (status != ACTQL_OWNED_OK) {
    int released = actql_read_context_release_after_owner_ack(context);
    return released == ACTQL_OWNED_OK ? status : released;
  }
  actql_native_filesystem_reader *reader = actql_native_filesystem_open_reader(
    root, name, length, device, inode, size);
  reader->read_context = context;
  reader->read_context_user = true;
  *output = reader;
  return actql_read_context_leave(context);
}

// These hooks bracket the WHOLE original managed caller as well as C: UTF-8
// input encoding and output Bytes/String/typed-record construction must stay
// inside the same original current claim. The Core caller must perform its
// own original/current fences and leave on every ordinary Result branch.
int actql_native_filesystem_scoped_root_enter(actql_native_filesystem_root *root) {
  return actql_filesystem_root_context_begin(root);
}
int actql_native_filesystem_scoped_root_leave(actql_native_filesystem_root *root) {
  if (root == NULL) return ACTQL_OWNED_INVALID;
  return actql_read_context_leave(root->read_context);
}
int actql_native_filesystem_scoped_reader_enter(actql_native_filesystem_reader *reader) {
  return actql_filesystem_reader_context_begin(reader);
}
int actql_native_filesystem_scoped_reader_leave(actql_native_filesystem_reader *reader) {
  if (reader == NULL) return ACTQL_OWNED_INVALID;
  return actql_read_context_leave(reader->read_context);
}

int actql_native_filesystem_scoped_inspect_generation(
  actql_native_filesystem_root *root, moonbit_bytes_t name, int32_t length,
  int32_t *physical
) {
  if (physical == NULL) return ACTQL_OWNED_INVALID;
  int status = actql_filesystem_root_context_begin(root);
  if (status != ACTQL_OWNED_OK) return status;
  *physical = actql_native_filesystem_inspect_generation(root, name, length);
  return actql_read_context_leave(root->read_context);
}

int actql_native_filesystem_scoped_reader_next(
  actql_native_filesystem_reader *reader, int32_t max_bytes, int32_t *physical
) {
  if (physical == NULL) return ACTQL_OWNED_INVALID;
  int status = actql_filesystem_reader_context_begin(reader);
  if (status != ACTQL_OWNED_OK) return status;
  *physical = actql_native_filesystem_reader_next(reader, max_bytes);
  return actql_read_context_leave(reader->read_context);
}

int actql_native_filesystem_scoped_reader_chunk(
  actql_native_filesystem_reader *reader, moonbit_bytes_t *output
) {
  if (output == NULL) return ACTQL_OWNED_INVALID;
  int status = actql_filesystem_reader_context_begin(reader);
  if (status != ACTQL_OWNED_OK) return status;
  *output = actql_native_filesystem_reader_chunk(reader);
  return actql_read_context_leave(reader->read_context);
}

int actql_native_filesystem_scoped_root_error(
  actql_native_filesystem_root *root, moonbit_bytes_t *output
) {
  if (output == NULL) return ACTQL_OWNED_INVALID;
  int status = actql_filesystem_root_context_begin(root);
  if (status != ACTQL_OWNED_OK) return status;
  *output = actql_native_filesystem_root_error(root);
  return actql_read_context_leave(root->read_context);
}
int actql_native_filesystem_scoped_reader_error(
  actql_native_filesystem_reader *reader, bool opening, moonbit_bytes_t *output
) {
  if (output == NULL) return ACTQL_OWNED_INVALID;
  int status = actql_filesystem_reader_context_begin(reader);
  if (status != ACTQL_OWNED_OK) return status;
  *output = opening ? actql_native_filesystem_reader_open_error(reader) :
                      actql_native_filesystem_reader_error(reader);
  return actql_read_context_leave(reader->read_context);
}

int actql_native_filesystem_scoped_root_close(
  actql_native_filesystem_root *root, int32_t *physical
) {
  if (root == NULL || physical == NULL || root->read_context == NULL)
    return ACTQL_OWNED_INVALID;
  // Re-observation after this Owner's ACK makes no new allocation/FD call.
  if (!root->read_context_user) {
    // This selected port clears its user only after this same Root's ACK
    // and successful context-use return. It is not inferred from fd < 0.
    *physical = 0;
    return ACTQL_OWNED_OK;
  }
  int status = actql_filesystem_root_context_begin(root);
  if (status != ACTQL_OWNED_OK) return status;
  *physical = actql_native_filesystem_root_close(root);
  if (*physical == 0) {
    status = actql_read_context_release_after_owner_ack(root->read_context);
    if (status == ACTQL_OWNED_OK) root->read_context_user = false;
  }
  int left = actql_read_context_leave(root->read_context);
  return status == ACTQL_OWNED_OK ? left : status;
}
int actql_native_filesystem_scoped_reader_close(
  actql_native_filesystem_reader *reader, bool finish, int32_t *physical
) {
  if (reader == NULL || physical == NULL || reader->read_context == NULL)
    return ACTQL_OWNED_INVALID;
  if (!reader->read_context_user) {
    // Close ACK does not prove EOF/generation completion. Preserve the
    // original finish classification after an ordinary close or failed open.
    *physical = finish ? (reader->ready && reader->finished ? 0 : 3) : 0;
    return ACTQL_OWNED_OK;
  }
  int status = actql_filesystem_reader_context_begin(reader);
  if (status != ACTQL_OWNED_OK) return status;
  *physical = finish ? actql_native_filesystem_reader_finish(reader) :
                       actql_native_filesystem_reader_close(reader);
  if (*physical == 0) {
    status = actql_read_context_release_after_owner_ack(reader->read_context);
    if (status == ACTQL_OWNED_OK) reader->read_context_user = false;
  }
  int left = actql_read_context_leave(reader->read_context);
  return status == ACTQL_OWNED_OK ? left : status;
}

/* There is deliberately no finalizer release-after-ACK. The existing GC
 * finalizer is not an observable FD/child-retirement ACK. Losing an unclosed
 * Root/Reader therefore retains the original context use instead of permitting
 * loan/domain return. The upper typed custody carrier must prevent that loss.
 * Managed record/Bytes/String aliases keep their original allocator extent
 * after leave and even after FD close. try_close cannot acknowledge them. */
