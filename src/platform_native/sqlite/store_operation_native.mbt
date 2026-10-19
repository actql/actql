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

///|
#borrow(database)
extern "C" fn database_enter_store_sql_ffi(database : Database, cleanup_allowed : Int) -> Int = "actql_native_sqlite_database_enter_store_sql"

///|
#borrow(database)
extern "C" fn database_leave_store_sql_ffi(database : Database) -> Int = "actql_native_sqlite_database_leave_store_sql"

///|
/// The actual result and any later routing failure remain distinct. Returned
/// values keep their SQL-domain aliases; scope leave is not their retirement.
fn[T] Database::with_original_store_sql(
  self : Database,
  cleanup_allowed : Bool,
  call : () -> Result[T, NativeSqliteIssue],
) -> Result[T, NativeSqliteIssue] {
  let before = database_enter_store_sql_ffi(self, if cleanup_allowed { 1 } else { 0 })
  if before != 0 { return Err(OperationRoutingBefore(before)) }
  let result = call()
  let after = database_leave_store_sql_ffi(self)
  if after != 0 {
    return Err(OperationRoutingAfter(match result { Ok(_) => None; Err(issue) => Some(issue) }, after))
  }
  result
}

///|
#borrow(library, original, path)
extern "C" fn open_original_store_database_ffi(
  library : Library, original : NativeStoreOperationOriginal,
  path : Bytes, length : Int, max_body_bytes : Int64, existing : Int,
) -> Database = "actql_native_sqlite_open_original_store_database"

///|
#borrow(original)
extern "C" fn store_operation_finish_open_ffi(original : NativeStoreOperationOriginal) -> Int = "actql_native_sqlite_store_operation_finish_open"

///|
#borrow(database)
extern "C" fn database_has_store_operation_ffi(database : Database) -> Bool = "actql_native_sqlite_database_has_store_operation"

///|
#borrow(database)
extern "C" fn database_fence_original_store_ffi(database : Database) -> Unit = "actql_native_sqlite_database_fence_original_store"

///|
/// Fixed coordinator original and one Database only. The failed-open carrier
/// retains the actual Database even if its return scope cannot be confirmed.
pub fn Library::open_original_local_store_database_with_custody(
  self : Library, original : NativeStoreOperationOriginal,
  path : String, max_body_bytes : Int64, existing? : Bool = false,
) -> Result[Database, NativeSqliteOpenFailure] {
  if max_body_bytes < 0L { return Err({original_issue: InvalidLimit, database: None}) }
  let encoded = @utf8.encode(path)
  let database = open_original_store_database_ffi(self, original, encoded, encoded.length(), max_body_bytes, if existing { 1 } else { 0 })
  let result = sqlite_open_result_with_custody(database)
  let after = store_operation_finish_open_ffi(original)
  if after != 0 {
    return match result {
      Ok(value) => Err({original_issue: OperationRoutingAfter(None, after), database: Some(value)})
      Err(failure) => Err({original_issue: OperationRoutingAfter(Some(failure.issue()), after), database: failure.database})
    }
  }
  result
}
