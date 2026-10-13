///|
fn root_lock_custody_fixture() -> String {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(path) else {
    fail("selected Root/Lock custody cases require an owned isolated Root")
    return ""
  }
  path
}

///|
#borrow(lock)
extern "C" fn mark_lock_retirement_unknown(lock : Lock) -> Bool = "actql_native_filesystem_test_lock_consumed_unknown"

///|
test "failed Root constructor retains original refusal and acknowledges only its own retirement" {
  let path = root_lock_custody_fixture() + "/missing-root-" + @env.now().to_string()
  let failure = match open_root_with_custody(path, diagnostic_ceiling=Some(128)) {
    Err(original) => original
    Ok(_) => { fail("missing directory was admitted"); return }
  }
  assert_true(failure.issue() is RootOpen(_))
  assert_true(failure.root is Some(_))
  failure.retry_cleanup().unwrap()
  assert_true(failure.root is None)
  failure.retry_cleanup().unwrap()
  assert_true(failure.issue() is RootOpen(_))
}

///|
test "rejected competing Lock carries original constructor and does not release the current owner" {
  let root = open_root_with_custody(root_lock_custody_fixture(), diagnostic_ceiling=Some(128)).unwrap()
  let name = "lock-custody-" + @env.now().to_string()
  let owner = root.acquire_lock_with_custody(name).unwrap()
  let failure = match root.acquire_lock_with_custody(name) {
    Err(original) => original
    Ok(_) => { fail("competing Lock was admitted"); return }
  }
  assert_true(failure.issue() is Lock(_))
  assert_true(failure.lock is Some(_))
  failure.retry_cleanup().unwrap()
  failure.retry_cleanup().unwrap()
  assert_true(failure.issue() is Lock(_))
  // Cleaning the rejected descriptor never releases the genuine owner.
  assert_true(root.acquire_lock_with_custody(name) is Err(_))
  owner.close_checked().unwrap()
  owner.close_checked().unwrap()
  let successor = root.acquire_lock_with_custody(name).unwrap()
  successor.close_checked().unwrap()
  root.close().unwrap()
}

///|
test "consumed Lock close Unknown never reuses its raw descriptor" {
  let root = open_root_with_custody(root_lock_custody_fixture(), diagnostic_ceiling=Some(128)).unwrap()
  let token = @env.now().to_string()
  let lock = root.acquire_lock_with_custody("lock-unknown-" + token).unwrap()
  // Real close followed by whitebox loss of its observation. This is not a
  // claim that the kernel actually returned EIO/EINTR in this test.
  assert_true(mark_lock_retirement_unknown(lock))
  let failure : NativeLockOpenFailure = {
    original_issue: Lock("original rejected acquisition"),
    lock: Some(lock),
  }
  let writer = root.create_writer("lock-reuse-" + token, 3L).unwrap()
  assert_true(failure.retry_cleanup() is Err(Cleanup(_)))
  assert_true(failure.retry_cleanup() is Err(Cleanup(_)))
  assert_true(failure.lock is Some(_))
  assert_true(failure.issue() is Lock("original rejected acquisition"))
  writer.append(b"abc").unwrap()
  writer.cancel().unwrap()
  root.close().unwrap()
}
