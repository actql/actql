///|
/// Native DuckDB runtime library loaded from an explicitly selected path.
/// The loader is physical adapter code; query admission remains in the
/// portable Connector packages.
type Library

///|
/// Native DuckDB database and connection owned by one runtime library.
type Database

///|
/// One streaming query owned by its database connection. The query retains
/// the database until explicit close or finalization and never materializes
/// the complete result in the Host process.
type Query

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
#borrow(database, sql)
extern "C" fn stream_query_ffi(
  database : Database,
  sql : Bytes,
  length : Int,
  max_columns : Int,
  max_rows : Int64,
  max_chunk_rows : Int,
  max_chunk_bytes : Int,
) -> Query = "actql_native_duckdb_stream_query"

///|
#borrow(query)
extern "C" fn stream_query_ready_ffi(query : Query) -> Bool = "actql_native_duckdb_stream_query_ready"

///|
#borrow(query)
extern "C" fn stream_query_error_ffi(query : Query) -> Bytes = "actql_native_duckdb_stream_query_error"

///|
#borrow(query)
extern "C" fn stream_query_fields_ffi(query : Query) -> Bytes = "actql_native_duckdb_stream_query_fields"

///|
#borrow(query)
extern "C" fn stream_query_next_ffi(query : Query) -> Bytes = "actql_native_duckdb_stream_query_next"

///|
#borrow(query)
extern "C" fn stream_query_status_ffi(query : Query) -> Int = "actql_native_duckdb_stream_query_status"

///|
#borrow(query)
extern "C" fn stream_query_last_rows_ffi(query : Query) -> Int = "actql_native_duckdb_stream_query_last_rows"

///|
#borrow(query)
extern "C" fn close_stream_query_ffi(query : Query) -> Bool = "actql_native_duckdb_close_stream_query"

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
/// Begin a zero-parameter streaming query. SQL admission remains the owning
/// Connector's responsibility; this physical adapter only enforces hard
/// transport bounds before exposing metadata or a batch.
pub fn Database::stream_query(
  self : Database,
  sql : String,
  max_columns : Int,
  max_rows : Int64,
  max_chunk_rows : Int,
  max_chunk_bytes : Int,
) -> Result[Query, NativeDuckDBIssue] {
  if sql.is_empty() ||
    max_columns < 0 ||
    max_rows < 0L ||
    max_chunk_rows < 1 ||
    max_chunk_bytes < 1 {
    return Err(InvalidLimits)
  }
  let encoded = @utf8.encode(sql)
  let query = stream_query_ffi(
    self,
    encoded,
    encoded.length(),
    max_columns,
    max_rows,
    max_chunk_rows,
    max_chunk_bytes,
  )
  if stream_query_ready_ffi(query) {
    Ok(query)
  } else {
    let issue = match stream_query_status_ffi(query) {
      2 => Err(CapacityExceeded)
      3 => Err(Closed)
      _ => Err(Query(decode_message(stream_query_error_ffi(query))))
    }
    close_stream_query_ffi(query) |> ignore
    issue
  }
}

///|
pub fn Query::fields_json(self : Query) -> Result[String, NativeDuckDBIssue] {
  if !stream_query_ready_ffi(self) {
    return match stream_query_status_ffi(self) {
      2 => Err(CapacityExceeded)
      3 => Err(Closed)
      _ => Err(Query(decode_message(stream_query_error_ffi(self))))
    }
  }
  Ok(decode_message(stream_query_fields_ffi(self)))
}

///|
pub fn Query::next(
  self : Query,
) -> Result[NativeDuckDBChunk?, NativeDuckDBIssue] {
  let bytes = stream_query_next_ffi(self)
  match stream_query_status_ffi(self) {
    0 =>
      Ok(
        Some({
          row_count: stream_query_last_rows_ffi(self),
          columns_json: decode_message(bytes),
        }),
      )
    1 => Ok(None)
    2 => Err(CapacityExceeded)
    3 => Err(Closed)
    _ => Err(Query(decode_message(stream_query_error_ffi(self))))
  }
}

///|
pub fn Query::close(self : Query) -> Bool {
  close_stream_query_ffi(self)
}

///|
pub fn Database::close(self : Database) -> Unit {
  close_database_ffi(self)
}
