///|
test "child custody preserves unselected acquisition and original failure cleanup" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_PRIVATE_ROOT").unwrap()
  let parent = open_private_root(path).unwrap()
  let ownership = parent.create_directory("custody-child").unwrap()
  let child = parent.open_child_with_custody("custody-child").unwrap()
  assert_eq(child.private_ownership().unwrap(), ownership)
  child.close().unwrap()
  assert_true(parent.remove_directory("custody-child", ownership).unwrap())
  let failed = match parent.open_child_with_custody("absent-child") {
    Err(original) => original
    Ok(_) => {
      fail("absent child was acquired")
      return
    }
  }
  assert_true(failed.issue() is RootOpen(_))
  assert_true(failed.root is Some(_))
  failed.retry_cleanup().unwrap()
  failed.retry_cleanup().unwrap()
  assert_true(failed.root is None)
  assert_true(failed.issue() is RootOpen(_))
  parent.close().unwrap()
}

///|
test "invalid child custody refuses before acquisition" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_PRIVATE_ROOT").unwrap()
  let parent = open_private_root(path).unwrap()
  let failed = match parent.open_child_with_custody("../escape") {
    Err(original) => original
    Ok(_) => {
      fail("invalid child was acquired")
      return
    }
  }
  assert_true(failed.issue() is InvalidName)
  assert_true(failed.root is None)
  failed.retry_cleanup().unwrap()
  parent.close().unwrap()
}
