int32_t actql_native_sqlite_library_acquired(actql_native_sqlite_library *library) {
  return library != NULL;
}

int32_t actql_native_sqlite_selected_current_scope(void) {
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  return actql_bootstrap_current_read_context() != NULL &&
    actql_native_owned_current() != NULL;
#else
  return 0;
#endif
}

/* The typed Native Library caller preserves failed acquisition custody. No
 * ordinary installed/public factory selects this candidate yet. A trusted installed Library supplier must verify
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
    void *module = library->dynamic_library;
    if (dlclose(module) != 0) return 0;
    library->dynamic_library = NULL;
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
    if (library->command_load &&
        !actql_native_command_platform_module_released(library->command_load, module)) return 0;
#endif
    library->module_close_result = 1;
  }
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  if (library->command_load && library->module_close_result == 0) {
    if (!actql_native_command_platform_module_released(library->command_load, NULL)) return 0;
    library->module_close_result = 1;
  }
  if (library->command_member) {
    moonbit_decref(library->command_member); library->command_member = NULL;
  }
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
      api->reset == NULL || api->clear_bindings == NULL ||
      !actql_component_origin(api, base)) return false;
  const void *entries[] = {
    (void *)api->allocate_memory, (void *)api->libversion, (void *)api->libversion_number,
    (void *)api->open_v2, (void *)api->close_v2, (void *)api->errmsg,
    (void *)api->exec, (void *)api->free_memory, (void *)api->prepare_v2,
    (void *)api->bind_text, (void *)api->bind_blob, (void *)api->bind_int64,
    (void *)api->step, (void *)api->column_int64, (void *)api->column_blob,
    (void *)api->column_bytes, (void *)api->finalize, (void *)api->changes64,
    (void *)api->busy_timeout, (void *)api->get_autocommit,
    (void *)api->reset, (void *)api->clear_bindings
  };
  for (size_t i = 0; i < sizeof(entries) / sizeof(entries[0]); i++)
    if (!actql_component_origin(entries[i], base)) return false;
  return true;
}
#endif

static void *actql_native_sqlite_load_component_original(
  moonbit_bytes_t path, int32_t length, int32_t diagnostic_ceiling, int64_t heap_bytes,
  actql_native_observed_component_member *member
) {
#ifndef ACTQL_SCOPED_READ_ALLOCATOR
  (void)path; (void)length; (void)diagnostic_ceiling; (void)heap_bytes; (void)member;
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
  if (member) {
    const char *expected = actql_native_observed_component_member_path(member);
    if (!expected || strcmp(expected, text)) { actql_adapter_free(library, text); return library; }
    library->command_member = member; moonbit_incref(member);
    library->command_load = actql_native_command_platform_begin_load(
      actql_native_command_platform_current(), ACTQL_NATIVE_COMMAND_SQLITE_COMPONENT, member);
    if (!library->command_load) { actql_adapter_free(library, text); return library; }
  }
  library->dynamic_library = dlopen(text, RTLD_NOW | RTLD_LOCAL);
  actql_adapter_free(library, text);
  if (library->command_load &&
      !actql_native_command_platform_observe_load(library->command_load, library->dynamic_library))
    return library;
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
  if (member &&
      (!actql_native_observed_component_member_image(member, origin.dli_fname) ||
       !actql_native_command_platform_load_current(library->command_load))) return library;
  if (strcmp(source_id(), ACTQL_SQLITE_COMPONENT_SOURCE_ID) != 0) return library;
  int status = bind(context, (size_t)heap_bytes);
  if (status == ACTQL_SQLITE_COMPONENT_INVALID || status == ACTQL_SQLITE_COMPONENT_BUSY)
    return library; /* Another original binding/entry cannot be cleaned up here. */
  library->component_owned = true; /* Includes our SAME failed initialization. */
  if (status != ACTQL_SQLITE_COMPONENT_OK) return library;
  library->selected_heap_bytes = heap_bytes;
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
  library->reset = api->reset;
  library->clear_bindings = api->clear_bindings;
  library->selected_ready = true;
  return library;
#endif
}

void *actql_native_sqlite_load_current_component(
  moonbit_bytes_t path, int32_t length, int32_t ceiling, int64_t heap_bytes) {
  return actql_native_sqlite_load_component_original(path, length, ceiling, heap_bytes, NULL);
}
void *actql_native_sqlite_load_command_component(
  moonbit_bytes_t path, int32_t length, int32_t ceiling, int64_t heap_bytes,
  actql_native_observed_component_member *member) {
  if (!member) return NULL;
  return actql_native_sqlite_load_component_original(path, length, ceiling, heap_bytes, member);
}
