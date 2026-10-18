///|
// Uses the same selected provider as the original consuming-read properties.
// Actual context equality is observed inside the physical Filesystem Owner;
// matching path/inode metadata and another valid scope cannot substitute.
test "Root binding follows only its same current original consumer through physical scopes" {
  let first = original_read_consumer_fixture("root-binding-first")
  let second = original_read_consumer_fixture("root-binding-second")
  let root_path = @env.get_env_var("ACTQL_TEST_INSTALLED_PROCESS_ROOT").unwrap()
  let legacy = @filesystem.open_private_root(root_path).unwrap()
  let held : Ref[@filesystem.Root?] = Ref(None)
  let first_consumer = first.host
    .prepare_domain_original_read_consumer(first.read, 8192L, 16384L)
    .unwrap()
  let second_consumer = second.host
    .prepare_domain_original_read_consumer(second.read, 8192L, 16384L)
    .unwrap()
  first.host.enter_domain_original_read_consumer(first_consumer).unwrap()
  assert_true(legacy.require_current_original_read() is Err(_))
  held.val = Some(
    @filesystem.open_private_root_in_current_read_context_with_custody(
      root_path, 128,
    ).unwrap(),
  )
  held.val.unwrap().require_current_original_read().unwrap()
  first.host.leave_domain_original_read_consumer(first_consumer).unwrap()
  assert_true(held.val.unwrap().require_current_original_read() is Err(_))
  second.host.enter_domain_original_read_consumer(second_consumer).unwrap()
  assert_true(held.val.unwrap().require_current_original_read() is Err(_))
  second.host.leave_domain_original_read_consumer(second_consumer).unwrap()
  first.host.resume_domain_original_read_consumer_scope(first_consumer).unwrap()
  held.val.unwrap().require_current_original_read().unwrap()
  held.val.unwrap().close().unwrap()
  assert_true(held.val.unwrap().require_current_original_read() is Err(_))
  held.val = None
  first.host.leave_domain_original_read_consumer(first_consumer).unwrap()
  legacy.close().unwrap()
  original_read_consumer_finish(second)
  original_read_consumer_finish(first)
}
