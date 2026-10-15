/* Private physical caller preparation. No MoonBit/public factory currently
 * exposes this acquisition. A trusted installed Library supplier must verify
 * its owned staged component/source/recipe before loading it and keep the
 * original Host/current scope around the entire managed FFI operation. */

int32_t actql_native_sqlite_library_current(actql_native_sqlite_library *library) {
  return library != NULL && actql_library_current(library);
}
int32_t actql_native_sqlite_database_current(actql_native_sqlite_database *database) {
  return database != NULL && actql_library_current(database->library);
}

int32_t actql_native_sqlite_library_close_checked(actql_native_sqlite_library *library) {
  if (library == NULL) return 1;
  if (!library->selected_component || !actql_library_current(library) ||
      library->database_children != 0 || library->module_close_result < 0) return 0;
  /* No new operation may overtake partial cleanup. Released table, engine,
   * module and context each retain their own acknowledgement in this record. */
  library->closing = true;
  actql_adapter_free(library, library->error);
  library->error = NULL;
  if (library->selected_api != NULL) {
    if (library->component_release_api(library->selected_api) != 0) return 0;
    library->selected_api = NULL;
  }
  if (library->component_owned) {
    if (library->component_close() != 0) return 0;
    library->component_owned = false;
  }
  if (library->dynamic_library != NULL) {
    /* A consumed/unconfirmed loader reference is never passed to dlclose again.
     * Keep the same Library/context and original module-close Unknown. */
    library->module_close_result = -1;
    if (dlclose(library->dynamic_library) != 0) return 0;
    library->dynamic_library = NULL;
    library->module_close_result = 1;
  }
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  if (library->selected_context_user) {
    if (actql_read_context_release_after_owner_ack(library->selected_context) != 0)
      return 0;
    library->selected_context_user = false;
  }
#endif
  return 1;
}

#ifdef ACTQL_SCOPED_READ_ALLOCATOR
static bool actql_component_origin(const void *entry, void *base) {
  Dl_info original;
  return entry != NULL && dladdr(entry, &original) && original.dli_fbase == base;
}

static bool actql_component_api_original(const actql_sqlite_component_api *api,
                                         void *base) {
  if (api == NULL || api->abi != ACTQL_SQLITE_COMPONENT_ABI ||
      api->bytes != sizeof(*api) || api->instance != api ||
      !actql_component_origin(api, base)) return false;
  const void *entries[] = {
    (void *)api->allocate_memory, (void *)api->libversion, (void *)api->libversion_number,
    (void *)api->open_v2, (void *)api->close_v2, (void *)api->errmsg,
    (void *)api->exec, (void *)api->free_memory, (void *)api->prepare_v2,
    (void *)api->bind_text, (void *)api->bind_blob, (void *)api->bind_int64,
    (void *)api->step, (void *)api->column_int64, (void *)api->column_blob,
    (void *)api->column_bytes, (void *)api->finalize, (void *)api->changes64,
    (void *)api->busy_timeout, (void *)api->get_autocommit
  };
  for (size_t i = 0; i < sizeof(entries) / sizeof(entries[0]); i++)
    if (!actql_component_origin(entries[i], base)) return false;
  return true;
}
#endif

void *actql_native_sqlite_load_current_component(
  moonbit_bytes_t path, int32_t length, int32_t diagnostic_ceiling, int64_t heap_bytes
) {
#ifndef ACTQL_SCOPED_READ_ALLOCATOR
  (void)path; (void)length; (void)diagnostic_ceiling; (void)heap_bytes;
  return NULL; /* No stock fallback or pre-adoption instance. */
#else
  actql_read_context *context = actql_bootstrap_current_read_context();
  if (context == NULL || heap_bytes < 4096 || heap_bytes > INT_MAX || diagnostic_ceiling <= 0 || length <= 0 || length > 4096 || path[0] != '/' ||
      memchr(path, 0, (size_t)length) != NULL ||
      actql_read_context_retain(context) != 0) return NULL;
  actql_native_sqlite_library *library = moonbit_make_external_object(
    actql_native_sqlite_library_finalize, sizeof(actql_native_sqlite_library));
  memset(library, 0, sizeof(*library));
  library->diagnostic_ceiling = diagnostic_ceiling;
  library->selected_component = true;
  library->selected_context = context;
  library->selected_context_user = true;
  library->selected_process = getpid();
  char *text = actql_copy_text_for(library, path, length);
  if (text == NULL) return library;
  library->dynamic_library = dlopen(text, RTLD_NOW | RTLD_LOCAL);
  actql_adapter_free(library, text);
  if (library->dynamic_library == NULL) {
    actql_replace_error_for(library, &library->error, diagnostic_ceiling, dlerror());
    return library;
  }
  int (*bind)(actql_read_context *, size_t) = NULL;
  const char *(*source_id)(void) = NULL;
  const actql_sqlite_component_api *(*borrow_api)(void) = NULL;
  if (!actql_load_symbol(library, (void **)&bind, "actql_sqlite_component_bind") ||
      !ACTQL_LOAD(library, component_close, "actql_sqlite_component_close") ||
      !ACTQL_LOAD(library, component_release_api, "actql_sqlite_component_release_api") ||
      !actql_load_symbol(library, (void **)&source_id, "actql_sqlite_component_source_id") ||
      !actql_load_symbol(library, (void **)&borrow_api, "actql_sqlite_component_borrow_api"))
    return library;
  Dl_info origin;
  if (!dladdr((void *)bind, &origin) ||
      !actql_component_origin((void *)library->component_close, origin.dli_fbase) ||
      !actql_component_origin((void *)library->component_release_api, origin.dli_fbase) ||
      !actql_component_origin((void *)source_id, origin.dli_fbase) ||
      !actql_component_origin((void *)borrow_api, origin.dli_fbase)) return library;
  if (strcmp(source_id(), ACTQL_SQLITE_COMPONENT_SOURCE_ID) != 0) return library;
  int status = bind(context, (size_t)heap_bytes);
  if (status == ACTQL_SQLITE_COMPONENT_INVALID || status == ACTQL_SQLITE_COMPONENT_BUSY)
    return library; /* Another original binding/entry cannot be cleaned up here. */
  library->component_owned = true; /* Includes our SAME failed initialization. */
  if (status != ACTQL_SQLITE_COMPONENT_OK) return library;
  library->selected_api = borrow_api();
  if (!actql_component_api_original(library->selected_api, origin.dli_fbase)) return library;
  const actql_sqlite_component_api *api = library->selected_api;
  library->libversion = api->libversion;
  library->libversion_number = api->libversion_number;
  library->open_v2 = api->open_v2;
  library->close_v2 = api->close_v2;
  library->errmsg = api->errmsg;
  library->exec = api->exec;
  library->free_memory = api->free_memory;
  library->prepare_v2 = api->prepare_v2;
  library->bind_text = api->bind_text;
  library->bind_blob = api->bind_blob;
  library->bind_int64 = api->bind_int64;
  library->step = api->step;
  library->column_int64 = api->column_int64;
  library->column_blob = api->column_blob;
  library->column_bytes = api->column_bytes;
  library->finalize = api->finalize;
  library->changes64 = api->changes64;
  library->busy_timeout = api->busy_timeout;
  library->get_autocommit = api->get_autocommit;
  library->selected_ready = true;
  return library;
#endif
}
