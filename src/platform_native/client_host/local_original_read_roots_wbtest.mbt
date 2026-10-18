///|
test "legacy adoption roots are not a current original read even when Host custody is valid" {
  let host = local_journal_test_connection("legacy-root-is-not-read")
  host.check_binding().unwrap()
  assert_true(
    host.session.require_current_original_read_roots() is Err(Filesystem(Read(_))),
  )
  // Physical refusal does not invalidate the authentic old Host or replace it.
  host.check_binding().unwrap()
  host.close_owned_root_descriptors().unwrap()
  assert_true(host.session.require_current_original_read_roots() is Err(Closed))
}
