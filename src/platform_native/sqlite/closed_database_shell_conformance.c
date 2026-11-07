/* Standalone selected-component lifetime conformance. Compile against the
 * selected provider's derived headers and fixture, using its original image.
 * Arguments: component image, fresh owned database path, closed or pending.
 * This checks Database shell retirement, not Host/Run or process-stop ACKs. */
#define main original_scoped_fixture_main
#include SCOPED_FIXTURE
#undef main
#include COMMAND_UNAVAILABLE
actql_read_context *actql_bootstrap_current_read_context(void) { return actql_read_context_current(); }
#include SQLITE_OWNER

int main(int argc, char **argv) {
  assert(argc == 4);
  setvbuf(stdout, NULL, _IONBF, 0);
  actql_owned_capacity *lease = lease_new();
  actql_read_context *read = context_new(lease);
  assert(actql_read_context_retain(read) == 0);
  context_enter(lease, read);
  moonbit_bytes_t path = moonbit_make_bytes((int32_t)strlen(argv[1]), 0);
  memcpy(path, argv[1], strlen(argv[1]));
  actql_native_sqlite_library *library = actql_native_sqlite_load_current_component(path, (int32_t)strlen(argv[1]), 2048, 524288);
  assert(library && actql_native_sqlite_library_ready(library));
  moonbit_decref(path);
  moonbit_bytes_t name_bytes = moonbit_make_bytes((int32_t)strlen(argv[2]), 0);
  memcpy(name_bytes, argv[2], strlen(argv[2]));
  actql_native_sqlite_database *database = actql_native_sqlite_open_local_store_database(library, name_bytes, (int32_t)strlen(argv[2]), 262144);
  moonbit_decref(name_bytes);
  assert(database && actql_native_sqlite_database_ready(database));
  assert(database->journal_descriptor_ack != NULL);
  if (strcmp(argv[3], "pending") == 0) {
    actql_native_sqlite_test_fail_close(database, 1);
    assert(!actql_native_sqlite_close_checked(database));
    assert(database->database != NULL && library->database_children == 1);
    assert(!actql_native_sqlite_library_close_checked(library));
    assert(library->selected_api != NULL && library->dynamic_library != NULL);
    // Refusal did not become an ACK. Keep the same actual Database until
    // checked cleanup succeeds; no replacement Library or handle is made.
    context_leave(lease, read);
    context_enter(lease, read);
  } else {
    assert(strcmp(argv[3], "closed") == 0);
  }
  assert(actql_native_sqlite_close_checked(database));
  assert(database->database == NULL && library->database_children == 1);
  // The physical close ACK was obtained while the same original was current.
  // Ending a managed alias later must not invoke that physical port again.
  context_leave(lease, read);
  moonbit_decref(database);
  context_enter(lease, read);
  printf("{\"phase\":\"already-closed-journal-shell\",\"remainingChildren\":%zu}\n", library->database_children);
  assert(library->database_children == 0);
  assert(actql_native_sqlite_library_close_checked(library));
  moonbit_decref(library);
  context_leave(lease, read);
  assert(actql_read_context_release_after_owner_ack(read) == 0);
  finish(&lease, &read);
  puts("{\"newPhysicalControls\":1,\"pass\":true,\"normalHost\":false}");
  return 0;
}
