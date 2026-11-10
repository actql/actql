///|
#borrow(library, receiver)
extern "C" fn store_test_prepare_operation(
  library : Library,
  receiver : Ref[Int],
  route : FuncRef[(Ref[Int], Library, Int) -> Int],
) -> NativeStoreOperationOriginal = "actql_native_sqlite_prepare_store_operation"

///|
test "Store operation original refuses a legacy Library before invoking its receiver" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap()
  let library = load_library(path).unwrap()
  let callbacks = Ref(0)
  let original = store_test_prepare_operation(library, callbacks, fn(
    receiver,
    _library,
    _tag,
  ) {
    receiver.val += 1
    0
  })
  assert_eq(callbacks.val, 0)
  assert_true(original.activate() is Err(_))
  assert_eq(original.primary_code(), -3)
  assert_eq(callbacks.val, 0)
  assert_true(original.enter_store() is Err(_))
  assert_true(original.prepare_delivery_window(64) is Err(_))
  assert_true(original.enter_cleanup() is Err(_))
  assert_eq(callbacks.val, 0)
  // Only this unused routing metadata is detached. No Library ACK is issued.
  original.close_checked().unwrap()
  original.close_checked().unwrap()
  assert_eq(callbacks.val, 0)
  assert_true(!library.version().is_empty())
}
