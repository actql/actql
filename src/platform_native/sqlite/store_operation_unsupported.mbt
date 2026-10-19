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

///|
pub fn Library::open_original_local_store_database_with_custody(
  _self : Library,
  _original : NativeStoreOperationOriginal,
  _path : String,
  _max_body_bytes : Int64,
  existing? : Bool = false,
) -> Result[Database, NativeSqliteOpenFailure] {
  ignore(existing)
  Err({ original_issue: UnsupportedTarget, database: None, })
}

///|
pub fn NativeStoreOperationOriginal::enter_cleanup_work(
  _self : NativeStoreOperationOriginal,
) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::insert_original_store_cleanup(
  _self : Database,
  _original : NativeStoreOperationOriginal,
  _scope : String,
  _key : String,
  _body : Bytes,
) -> Result[Int64, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}
