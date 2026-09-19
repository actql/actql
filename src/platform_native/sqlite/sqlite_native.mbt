///|
type Library

///|
type Database

///|
#borrow(path)
extern "C" fn load_library_ffi(path : Bytes, length : Int) -> Library = "actql_native_sqlite_load_library"

///|
#borrow(library)
extern "C" fn library_ready_ffi(library : Library) -> Bool = "actql_native_sqlite_library_ready"

///|
#borrow(library)
extern "C" fn library_error_ffi(library : Library) -> Bytes = "actql_native_sqlite_library_error"

///|
#borrow(library)
extern "C" fn library_version_ffi(library : Library) -> Bytes = "actql_native_sqlite_library_version"

///|
#borrow(library, path)
extern "C" fn open_database_ffi(
  library : Library,
  path : Bytes,
  length : Int,
  max_body_bytes : Int64,
) -> Database = "actql_native_sqlite_open_database"

///|
#borrow(database)
extern "C" fn database_ready_ffi(database : Database) -> Bool = "actql_native_sqlite_database_ready"

///|
#borrow(database)
extern "C" fn database_error_ffi(database : Database) -> Bytes = "actql_native_sqlite_database_error"

///|
#borrow(database, scope, key)
extern "C" fn database_read_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
) -> Int = "actql_native_sqlite_database_read"

///|
#borrow(database, scope, after_key)
extern "C" fn database_scan_after_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  after_key : Bytes,
  after_key_length : Int,
) -> Int = "actql_native_sqlite_database_scan_after"

///|
#borrow(database, scope, key, body)
extern "C" fn database_insert_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
  body : Bytes,
  body_length : Int,
) -> Int = "actql_native_sqlite_database_insert"

///|
#borrow(database, scope, key, body)
extern "C" fn database_compare_exchange_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
  expected_revision : Int64,
  body : Bytes,
  body_length : Int,
) -> Int = "actql_native_sqlite_database_compare_exchange"

///|
#borrow(database)
extern "C" fn database_result_revision_ffi(database : Database) -> Int64 = "actql_native_sqlite_database_result_revision"

///|
#borrow(database)
extern "C" fn database_result_body_ffi(database : Database) -> Bytes = "actql_native_sqlite_database_result_body"

///|
#borrow(database)
extern "C" fn database_result_key_ffi(database : Database) -> Bytes = "actql_native_sqlite_database_result_key"

///|
#borrow(database)
extern "C" fn close_database_ffi(database : Database) -> Unit = "actql_native_sqlite_close_database"

///|
fn decode_message(bytes : Bytes) -> String {
  @utf8.decode_lossy(bytes)
}

///|
fn valid_name(bytes : Bytes) -> Bool {
  bytes.length() > 0 && bytes.length() <= 512
}

///|
fn operation_issue(database : Database, code : Int) -> NativeSqliteIssue {
  match code {
    1 => NotFound
    2 => Collision
    3 => Busy
    4 => BodyTooLarge
    5 => DatabaseClosed
    _ => Physical(decode_message(database_error_ffi(database)))
  }
}

///|
pub fn load_library(path : String) -> Result[Library, NativeSqliteIssue] {
  let encoded = @utf8.encode(path)
  let library = load_library_ffi(encoded, encoded.length())
  if library_ready_ffi(library) {
    Ok(library)
  } else {
    Err(LibraryLoad(decode_message(library_error_ffi(library))))
  }
}

///|
pub fn Library::version(self : Library) -> String {
  decode_message(library_version_ffi(self))
}

///|
pub fn Library::open_database(
  self : Library,
  path : String,
  max_body_bytes : Int64,
) -> Result[Database, NativeSqliteIssue] {
  if max_body_bytes < 0L {
    return Err(InvalidLimit)
  }
  let encoded = @utf8.encode(path)
  let database = open_database_ffi(
    self,
    encoded,
    encoded.length(),
    max_body_bytes,
  )
  if database_ready_ffi(database) {
    Ok(database)
  } else {
    Err(DatabaseOpen(decode_message(database_error_ffi(database))))
  }
}

///|
pub fn Database::read(
  self : Database,
  scope : String,
  key : String,
) -> Result[NativeJournalValue, NativeSqliteIssue] {
  let scope_bytes = @utf8.encode(scope)
  let key_bytes = @utf8.encode(key)
  if !valid_name(scope_bytes) || !valid_name(key_bytes) {
    return Err(InvalidName)
  }
  let code = database_read_ffi(
    self,
    scope_bytes,
    scope_bytes.length(),
    key_bytes,
    key_bytes.length(),
  )
  if code == 0 {
    Ok({
      revision: database_result_revision_ffi(self),
      body: database_result_body_ffi(self),
    })
  } else {
    Err(operation_issue(self, code))
  }
}

///|
/// Returns the next record in binary key order without materializing the
/// remaining namespace. An empty cursor starts at the first record.
pub fn Database::scan_after(
  self : Database,
  scope : String,
  after_key : String,
) -> Result[NativeJournalEntry, NativeSqliteIssue] {
  let scope_bytes = @utf8.encode(scope)
  let after_key_bytes = @utf8.encode(after_key)
  if !valid_name(scope_bytes) || after_key_bytes.length() > 512 {
    return Err(InvalidName)
  }
  let code = database_scan_after_ffi(
    self,
    scope_bytes,
    scope_bytes.length(),
    after_key_bytes,
    after_key_bytes.length(),
  )
  if code != 0 {
    return Err(operation_issue(self, code))
  }
  let key = @utf8.decode(database_result_key_ffi(self)) catch {
    _ => return Err(Physical("invalid stored journal key"))
  }
  Ok({
    key,
    revision: database_result_revision_ffi(self),
    body: database_result_body_ffi(self),
  })
}

///|
pub fn Database::insert(
  self : Database,
  scope : String,
  key : String,
  body : Bytes,
) -> Result[Int64, NativeSqliteIssue] {
  let scope_bytes = @utf8.encode(scope)
  let key_bytes = @utf8.encode(key)
  if !valid_name(scope_bytes) || !valid_name(key_bytes) {
    return Err(InvalidName)
  }
  let code = database_insert_ffi(
    self,
    scope_bytes,
    scope_bytes.length(),
    key_bytes,
    key_bytes.length(),
    body,
    body.length(),
  )
  if code == 0 {
    Ok(database_result_revision_ffi(self))
  } else {
    Err(operation_issue(self, code))
  }
}

///|
pub fn Database::compare_exchange(
  self : Database,
  scope : String,
  key : String,
  expected_revision : Int64,
  body : Bytes,
) -> Result[Int64, NativeSqliteIssue] {
  let scope_bytes = @utf8.encode(scope)
  let key_bytes = @utf8.encode(key)
  if !valid_name(scope_bytes) || !valid_name(key_bytes) {
    return Err(InvalidName)
  }
  if expected_revision < 0L {
    return Err(Collision)
  }
  let code = database_compare_exchange_ffi(
    self,
    scope_bytes,
    scope_bytes.length(),
    key_bytes,
    key_bytes.length(),
    expected_revision,
    body,
    body.length(),
  )
  if code == 0 {
    Ok(database_result_revision_ffi(self))
  } else {
    Err(operation_issue(self, code))
  }
}

///|
pub fn Database::close(self : Database) -> Unit {
  close_database_ffi(self)
}
