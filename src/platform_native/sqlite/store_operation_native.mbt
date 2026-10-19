///|
/// Minted only by the fixed private Native coordinator bridge. No public
/// constructor, callback factory, pointer or serialized identity admits it.
type NativeStoreOperationOriginal

///|
#borrow(original)
extern "C" fn store_operation_activate_ffi(original : NativeStoreOperationOriginal) -> Int = "actql_native_sqlite_store_operation_activate"

///|
#borrow(original)
extern "C" fn store_operation_enter_ffi(original : NativeStoreOperationOriginal, cleanup : Int) -> Int = "actql_native_sqlite_store_operation_enter"

///|
#borrow(original)
extern "C" fn store_operation_leave_ffi(original : NativeStoreOperationOriginal) -> Int = "actql_native_sqlite_store_operation_leave"

///|
#borrow(original)
extern "C" fn store_operation_close_ffi(original : NativeStoreOperationOriginal) -> Int = "actql_native_sqlite_store_operation_close"

///|
#borrow(original)
extern "C" fn store_operation_primary_ffi(original : NativeStoreOperationOriginal) -> Int = "actql_native_sqlite_store_operation_primary"

///|
#borrow(original)
extern "C" fn store_operation_cleanup_ffi(original : NativeStoreOperationOriginal) -> Int = "actql_native_sqlite_store_operation_cleanup"

///|
fn store_operation_result(code : Int) -> Result[Unit, NativeSqliteIssue] {
  if code == 0 { Ok(()) } else { Err(Physical("original Store operation routing unavailable (\{code})")) }
}

///|
/// The same receiver has already been registered before activation can fail.
pub fn NativeStoreOperationOriginal::activate(self : NativeStoreOperationOriginal) -> Result[Unit, NativeSqliteIssue] {
  store_operation_result(store_operation_activate_ffi(self))
}

///|
pub fn NativeStoreOperationOriginal::enter_store(self : NativeStoreOperationOriginal) -> Result[Unit, NativeSqliteIssue] {
  store_operation_result(store_operation_enter_ffi(self, 0))
}

///|
/// Existing cleanup only. This cannot clear the original routing failure or
/// restore normal dispatch; its coordinator never resumes business on leave.
pub fn NativeStoreOperationOriginal::enter_cleanup(self : NativeStoreOperationOriginal) -> Result[Unit, NativeSqliteIssue] {
  store_operation_result(store_operation_enter_ffi(self, 1))
}

///|
pub fn NativeStoreOperationOriginal::leave_store(self : NativeStoreOperationOriginal) -> Result[Unit, NativeSqliteIssue] {
  store_operation_result(store_operation_leave_ffi(self))
}

///|
/// Detach only routing metadata after the actual Database and scope ACKs.
pub fn NativeStoreOperationOriginal::close_checked(self : NativeStoreOperationOriginal) -> Result[Unit, NativeSqliteIssue] {
  store_operation_result(store_operation_close_ffi(self))
}

///|
/// Closed diagnostic observations, never current/permission or cleanup ACKs.
pub fn NativeStoreOperationOriginal::primary_code(self : NativeStoreOperationOriginal) -> Int {
  store_operation_primary_ffi(self)
}

///|
pub fn NativeStoreOperationOriginal::cleanup_code(self : NativeStoreOperationOriginal) -> Int {
  store_operation_cleanup_ffi(self)
}
