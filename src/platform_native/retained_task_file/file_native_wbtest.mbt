///|
#borrow(root)
extern "C" fn test_fail_root_sync(
  root : @filesystem.Root,
  failures : Int,
) -> Unit = "actql_native_filesystem_test_fail_root_sync"

///|
test "native retained task seal and release retain cleanup on sync failure" {
  guard native_retained_test_root() is Some(root) else { return }
  let occurrence = "task-file-sync-" + @env.now().to_string()
  let file = begin_native_retained_task_file(root, occurrence, 3L).unwrap()
  file.append("abc").unwrap()
  test_fail_root_sync(file.root, 1)
  assert_true(file.seal("sha256:" + @sha256.hex(b"abc"), 3) is Err(_))
  assert_false(file.available())
  test_fail_root_sync(file.root, 1)
  assert_true(file.release() is Err(_))
  assert_false(file.release_confirmed())
  file.release().unwrap()
  assert_true(file.release_confirmed())
  assert_false(file.available())
}
