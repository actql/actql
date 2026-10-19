#define _DARWIN_C_SOURCE
#define _XOPEN_SOURCE 700
#define main retained_read_fixture_main
#include "../../packages/python-local-runtime/native/pre-root/fixtures/scoped_read.c"
#undef main
#include "../../src/platform_native/remote_journal/inspection_stub.c"

int main(int argc, char **argv) {
  assert(argc == 2);
  moonbit_bytes_t path = moonbit_make_bytes_raw((int32_t)strlen(argv[1]));
  memcpy(path, argv[1], strlen(argv[1]));
  actql_owned_capacity *lease = lease_new();
  actql_read_context *context = context_new(lease);
  assert(actql_read_context_retain(context) == ACTQL_OWNED_OK);
  context_enter(lease, context);
  size_t stock_before = stock_file_allocations;
  actql_journal_inspection *owner = inspection_open_bounded(
    path, (int32_t)strlen(argv[1]), 1024);
  assert(owner->ready && !owner->absent);
  assert(actql_native_owned_contains_live_span(lease, owner, sizeof(*owner)) ==
    ACTQL_OWNED_OK);
  const char *paths[] = {
    owner->source, owner->wal, owner->journal, owner->directory, owner->copy,
  };
  for (size_t index = 0; index < sizeof(paths) / sizeof(paths[0]); index++) {
    assert(paths[index]);
    assert(actql_native_owned_contains_live_span(
      lease, paths[index], strlen(paths[index]) + 1) == ACTQL_OWNED_OK);
  }
  assert(actql_journal_inspection_prepare_private_index(owner));
  assert(actql_journal_inspection_private_index_ready(owner));
  assert(stock_file_allocations == stock_before);
  assert(actql_journal_inspection_validate(owner));
  assert(inspection_close(owner));
  moonbit_decref(owner);
  context_leave(lease, context);
  assert(actql_read_context_release_after_owner_ack(context) == ACTQL_OWNED_OK);
  finish(&lease, &context);
  moonbit_decref(path);
  puts("{\"case\":\"inspection-original-read-backing\",\"passed\":true,"
       "\"retainedNativePaths\":5,\"stockPathAllocations\":0,"
       "\"sqliteExecuted\":false,\"ordinaryCommand\":false}");
  return 0;
}
