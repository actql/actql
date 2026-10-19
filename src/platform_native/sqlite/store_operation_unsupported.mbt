///|
type NativeStoreOperationOriginal

///|
pub fn NativeStoreOperationOriginal::activate(
  _self : NativeStoreOperationOriginal,
) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeStoreOperationOriginal::enter_store(
  _self : NativeStoreOperationOriginal,
) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeStoreOperationOriginal::enter_cleanup(
  _self : NativeStoreOperationOriginal,
) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeStoreOperationOriginal::leave_store(
  _self : NativeStoreOperationOriginal,
) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeStoreOperationOriginal::close_checked(
  _self : NativeStoreOperationOriginal,
) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeStoreOperationOriginal::primary_code(
  _self : NativeStoreOperationOriginal,
) -> Int {
  -1
}

///|
pub fn NativeStoreOperationOriginal::cleanup_code(
  _self : NativeStoreOperationOriginal,
) -> Int {
  -1
}
