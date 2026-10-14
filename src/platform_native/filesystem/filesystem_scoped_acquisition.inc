/* Original constructor result only, not a new Owner or permission. The
 * managed caller must hold the existing Native Domain scope around encoding,
 * construction and projection. No NULL opaque value crosses MoonBit FFI. */
typedef struct {
  void *original;
  int32_t status;
  bool reader;
} actql_filesystem_scoped_acquisition;

static void actql_filesystem_scoped_acquisition_finalize(void *value) {
  actql_filesystem_scoped_acquisition *result = value;
  // Dropping a reference is never a descriptor/context retirement ACK.
  if (result->original != NULL) moonbit_decref(result->original);
}

static actql_filesystem_scoped_acquisition *actql_filesystem_new_acquisition(bool reader) {
  actql_filesystem_scoped_acquisition *result = moonbit_make_external_object(
    actql_filesystem_scoped_acquisition_finalize, sizeof(*result));
  result->original = NULL;
  result->status = -1;
  result->reader = reader;
  return result;
}

MOONBIT_FFI_EXPORT int32_t actql_native_filesystem_current_read_available(void) {
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  return actql_bootstrap_current_read_context() != NULL;
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t actql_native_filesystem_root_is_scoped(actql_native_filesystem_root *root) {
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  return root->read_context != NULL;
#else
  (void)root;
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t actql_native_filesystem_root_read_available(actql_native_filesystem_root *root) {
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  if (root->read_context != NULL)
    return root->read_context_user &&
      actql_bootstrap_current_read_context() == root->read_context;
#else
  (void)root;
#endif
  return 1; // Original unselected Root behavior, never a funding assertion.
}

MOONBIT_FFI_EXPORT int32_t actql_native_filesystem_reader_read_available(actql_native_filesystem_reader *reader) {
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  if (reader->read_context != NULL)
    return reader->read_context_user &&
      actql_bootstrap_current_read_context() == reader->read_context;
#else
  (void)reader;
#endif
  return 1;
}

MOONBIT_FFI_EXPORT void *actql_native_filesystem_acquire_current_root(
  moonbit_bytes_t path, int32_t length, int32_t diagnostic_ceiling
) {
  actql_filesystem_scoped_acquisition *result = actql_filesystem_new_acquisition(false);
  actql_native_filesystem_root *root = NULL;
  result->status = actql_native_filesystem_scoped_open_current_root(
    path, length, diagnostic_ceiling, &root);
  result->original = root; // Includes a rejected original constructor.
  return result;
}

MOONBIT_FFI_EXPORT void *actql_native_filesystem_acquire_scoped_reader(
  actql_native_filesystem_root *root, moonbit_bytes_t name, int32_t length,
  uint64_t device, uint64_t inode, int64_t size
) {
  actql_filesystem_scoped_acquisition *result = actql_filesystem_new_acquisition(true);
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  if (root->read_context_user && actql_bootstrap_current_read_context() == root->read_context) {
    actql_native_filesystem_reader *reader = NULL;
    result->status = actql_native_filesystem_scoped_open_reader(root, name, length,
      device, inode, size, &reader);
    result->original = reader;
  }
#else
  (void)root; (void)name; (void)length; (void)device; (void)inode; (void)size;
#endif
  return result;
}

MOONBIT_FFI_EXPORT int32_t actql_native_filesystem_acquisition_status(actql_filesystem_scoped_acquisition *result) {
  return result->status;
}

MOONBIT_FFI_EXPORT int32_t actql_native_filesystem_acquisition_has_original(actql_filesystem_scoped_acquisition *result) {
  return result->original != NULL;
}

MOONBIT_FFI_EXPORT void *actql_native_filesystem_acquisition_original(actql_filesystem_scoped_acquisition *result) {
  // The private immutable result is checked by the typed caller before this
  // getter. No callback or await separates presence from the projection.
  if (result->original == NULL) abort();
  moonbit_incref(result->original);
  return result->original;
}

MOONBIT_FFI_EXPORT int32_t actql_native_filesystem_root_close_dispatch(actql_native_filesystem_root *root) {
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  if (root->read_context != NULL) {
    int32_t physical = -1;
    int status = actql_native_filesystem_scoped_root_close(root, &physical);
    return status == ACTQL_OWNED_OK ? physical : -1;
  }
#endif
  return actql_native_filesystem_root_close(root);
}

MOONBIT_FFI_EXPORT int32_t actql_native_filesystem_reader_close_dispatch(actql_native_filesystem_reader *reader) {
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  if (reader->read_context != NULL) {
    int32_t physical = -1;
    int status = actql_native_filesystem_scoped_reader_close(reader, false, &physical);
    return status == ACTQL_OWNED_OK ? physical : -1;
  }
#endif
  return actql_native_filesystem_reader_close(reader);
}

MOONBIT_FFI_EXPORT int32_t actql_native_filesystem_reader_finish_dispatch(actql_native_filesystem_reader *reader) {
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  if (reader->read_context != NULL) {
    int32_t physical = -1;
    int status = actql_native_filesystem_scoped_reader_close(reader, true, &physical);
    return status == ACTQL_OWNED_OK ? physical : -1;
  }
#endif
  return actql_native_filesystem_reader_finish(reader);
}
