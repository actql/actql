///|
/// Native DuckDB runtime library loaded from an explicitly selected path.
/// The loader is physical adapter code; query admission remains in the
/// portable Connector packages.
type Library

///|
/// Native DuckDB database and connection owned by one runtime library.
type Database

///|
#borrow(path)
extern "C" fn load_library_ffi(path : Bytes, length : Int) -> Library = "actql_native_duckdb_load_library"

///|
#borrow(library)
extern "C" fn library_ready_ffi(library : Library) -> Bool = "actql_native_duckdb_library_ready"

///|
#borrow(library)
extern "C" fn library_error_ffi(library : Library) -> Bytes = "actql_native_duckdb_library_error"

///|
#borrow(library)
extern "C" fn library_version_ffi(library : Library) -> Bytes = "actql_native_duckdb_library_version"

///|
#borrow(library, path)
extern "C" fn open_database_ffi(
  library : Library,
  path : Bytes,
  length : Int,
) -> Database = "actql_native_duckdb_open_database"

///|
#borrow(database)
extern "C" fn database_ready_ffi(database : Database) -> Bool = "actql_native_duckdb_database_ready"

///|
#borrow(database)
extern "C" fn database_error_ffi(database : Database) -> Bytes = "actql_native_duckdb_database_error"

///|
#borrow(database, sql)
extern "C" fn query_i64_ffi(
  database : Database,
  sql : Bytes,
  length : Int,
) -> Int64 = "actql_native_duckdb_query_i64"

///|
#borrow(database)
extern "C" fn query_ok_ffi(database : Database) -> Bool = "actql_native_duckdb_query_ok"

///|
#borrow(database)
extern "C" fn close_database_ffi(database : Database) -> Unit = "actql_native_duckdb_close_database"

///|
fn decode_message(bytes : Bytes) -> String {
  @utf8.decode_lossy(bytes)
}

///|
pub fn load_library(path : String) -> Result[Library, NativeDuckDBIssue] {
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
  path? : String = "",
) -> Result[Database, NativeDuckDBIssue] {
  let encoded = @utf8.encode(path)
  let database = open_database_ffi(self, encoded, encoded.length())
  if database_ready_ffi(database) {
    Ok(database)
  } else {
    Err(DatabaseOpen(decode_message(database_error_ffi(database))))
  }
}

///|
pub fn Database::query_i64(
  self : Database,
  sql : String,
) -> Result[Int64, NativeDuckDBIssue] {
  let encoded = @utf8.encode(sql)
  let value = query_i64_ffi(self, encoded, encoded.length())
  if query_ok_ffi(self) {
    Ok(value)
  } else {
    Err(Query(decode_message(database_error_ffi(self))))
  }
}

///|
pub fn Database::close(self : Database) -> Unit {
  close_database_ffi(self)
}
