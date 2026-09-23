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
priv type VerifiedLibraryCandidate

///|
#borrow(root, name)
extern "C" fn open_candidate_ffi(
  root : Bytes,
  root_length : Int,
  name : Bytes,
  name_length : Int,
  device : UInt64,
  inode : UInt64,
  maximum : Int64,
) -> VerifiedLibraryCandidate = "actql_native_duckdb_open_candidate"

///|
#borrow(candidate)
extern "C" fn candidate_ready_ffi(candidate : VerifiedLibraryCandidate) -> Bool = "actql_native_duckdb_candidate_ready"

///|
#borrow(candidate)
extern "C" fn candidate_error_ffi(
  candidate : VerifiedLibraryCandidate,
) -> Bytes = "actql_native_duckdb_candidate_error"

///|
#borrow(candidate)
extern "C" fn candidate_next_ffi(candidate : VerifiedLibraryCandidate) -> Int = "actql_native_duckdb_candidate_next"

///|
#borrow(candidate)
extern "C" fn candidate_chunk_ffi(
  candidate : VerifiedLibraryCandidate,
) -> Bytes = "actql_native_duckdb_candidate_chunk"

///|
#borrow(candidate)
extern "C" fn candidate_total_ffi(
  candidate : VerifiedLibraryCandidate,
) -> Int64 = "actql_native_duckdb_candidate_total"

///|
#borrow(candidate)
extern "C" fn candidate_close_ffi(candidate : VerifiedLibraryCandidate) -> Int = "actql_native_duckdb_candidate_close"

///|
#borrow(candidate)
extern "C" fn candidate_load_ffi(
  candidate : VerifiedLibraryCandidate,
) -> Library = "actql_native_duckdb_candidate_load"

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
  memory_bytes : Int64,
  threads : Int,
  external_access : Bool,
  read_only : Bool,
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
extern "C" fn transaction_ffi(database : Database, action : Int) -> Bool = "actql_native_duckdb_transaction"

///|
#borrow(database, sql)
extern "C" fn prepare_stream_query_ffi(
  database : Database,
  sql : Bytes,
  length : Int,
  max_columns : Int,
  max_rows : Int64,
  max_chunk_rows : Int,
  max_chunk_bytes : Int,
) -> Query = "actql_native_duckdb_prepare_stream_query"

///|
#borrow(query)
extern "C" fn stream_query_parameter_count_ffi(query : Query) -> Int64 = "actql_native_duckdb_stream_query_parameter_count"

///|
#borrow(query)
extern "C" fn bind_null_ffi(query : Query, index : Int) -> Bool = "actql_native_duckdb_stream_query_bind_null"

///|
#borrow(query)
extern "C" fn bind_boolean_ffi(query : Query, index : Int, value : Int) -> Bool = "actql_native_duckdb_stream_query_bind_boolean"

///|
#borrow(query)
extern "C" fn bind_double_ffi(
  query : Query,
  index : Int,
  value : Double,
) -> Bool = "actql_native_duckdb_stream_query_bind_double"

///|
#borrow(query, value)
extern "C" fn bind_text_ffi(
  query : Query,
  index : Int,
  value : Bytes,
  length : Int,
) -> Bool = "actql_native_duckdb_stream_query_bind_text"

///|
#borrow(query)
extern "C" fn bind_date_ffi(query : Query, index : Int, days : Int) -> Bool = "actql_native_duckdb_stream_query_bind_date"

///|
#borrow(query)
extern "C" fn bind_timestamp_ffi(
  query : Query,
  index : Int,
  micros : Int64,
) -> Bool = "actql_native_duckdb_stream_query_bind_timestamp"

///|
#borrow(query, coefficient)
extern "C" fn bind_decimal_ffi(
  query : Query,
  index : Int,
  coefficient : Bytes,
  length : Int,
  width : Int,
  scale : Int,
) -> Bool = "actql_native_duckdb_stream_query_bind_decimal"

///|
#borrow(query)
extern "C" fn execute_stream_query_ffi(query : Query) -> Bool = "actql_native_duckdb_stream_query_execute"

///|
#borrow(query)
extern "C" fn stream_query_ready_ffi(query : Query) -> Bool = "actql_native_duckdb_stream_query_ready"

///|
#borrow(query)
extern "C" fn stream_query_executed_ffi(query : Query) -> Bool = "actql_native_duckdb_stream_query_executed"

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
/// Hash the exact Store-owned component on a held descriptor before dlopen.
/// The signed component identity is supplied by the admitted bundle Store,
/// not by a caller-selected path or digest.
pub fn load_verified_component(
  source : @bundle.NativeRuntimeBundleComponentSource,
  crypto : @signature.Library,
) -> Result[Library, NativeDuckDBIssue] {
  let (_, role, expected_cid, expected_bytes, name, generation, offset) = @bundle.native_bundle_component_source_projection(
    source,
  )
  let root = @bundle.native_bundle_component_source_root(source)
  if expected_bytes <= 0L ||
    generation.size != expected_bytes ||
    offset != 0L ||
    role != "duckdb_library" ||
    expected_cid.length() != 71 ||
    !expected_cid.has_prefix("sha256:") {
    return Err(LibraryLoad("invalid DuckDB library component"))
  }
  let encoded_root = @utf8.encode(root)
  let encoded_name = @utf8.encode(name)
  let candidate = open_candidate_ffi(
    encoded_root,
    encoded_root.length(),
    encoded_name,
    encoded_name.length(),
    generation.device,
    generation.inode,
    expected_bytes,
  )
  if !candidate_ready_ffi(candidate) {
    return Err(LibraryLoad(decode_message(candidate_error_ffi(candidate))))
  }
  let hash = match crypto.sha256_hasher() {
    Ok(value) => value
    Err(_) => {
      ignore(candidate_close_ffi(candidate))
      return Err(LibraryLoad("DuckDB library hash initialization failed"))
    }
  }
  let mut issue : String? = None
  let mut finished = false
  while !finished && issue is None {
    match candidate_next_ffi(candidate) {
      0 => {
        let chunk = candidate_chunk_ffi(candidate)
        if chunk.is_empty() || chunk.length() > 65536 {
          issue = Some("invalid DuckDB library chunk")
        } else {
          match hash.update(chunk) {
            Ok(_) => ()
            Err(_) => issue = Some("DuckDB library hash failed")
          }
        }
      }
      1 => finished = true
      _ => issue = Some(decode_message(candidate_error_ffi(candidate)))
    }
  }
  if issue is Some(message) {
    ignore(candidate_close_ffi(candidate))
    return Err(LibraryLoad(message))
  }
  let matched = match hash.finish_hex() {
    Ok(value) => "sha256:" + value == expected_cid
    Err(_) => {
      ignore(candidate_close_ffi(candidate))
      return Err(LibraryLoad("DuckDB library hash failed"))
    }
  }
  if candidate_total_ffi(candidate) != expected_bytes || !matched {
    ignore(candidate_close_ffi(candidate))
    return Err(LibraryLoad("DuckDB library component mismatch"))
  }
  let library = candidate_load_ffi(candidate)
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
  limits : NativeDuckDBOpenLimits,
  path? : String = "",
) -> Result[Database, NativeDuckDBIssue] {
  if limits.memory_bytes <= 0L ||
    limits.threads <= 0 ||
    (limits.read_only && path == "") {
    return Err(InvalidLimits)
  }
  let encoded = @utf8.encode(path)
  let database = open_database_ffi(
    self,
    encoded,
    encoded.length(),
    limits.memory_bytes,
    limits.threads,
    limits.external_access,
    limits.read_only,
  )
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
fn Database::transaction(
  self : Database,
  action : Int,
) -> Result[Unit, NativeDuckDBIssue] {
  if transaction_ffi(self, action) {
    Ok(())
  } else {
    Err(Query(decode_message(database_error_ffi(self))))
  }
}

///|
pub fn Database::begin_transaction(
  self : Database,
) -> Result[Unit, NativeDuckDBIssue] {
  self.transaction(0)
}

///|
pub fn Database::commit_transaction(
  self : Database,
) -> Result[Unit, NativeDuckDBIssue] {
  self.transaction(1)
}

///|
pub fn Database::rollback_transaction(
  self : Database,
) -> Result[Unit, NativeDuckDBIssue] {
  self.transaction(2)
}

///|
/// Prepare a bounded streaming query. SQL and parameter admission remain the
/// owning Connector's responsibility. The physical adapter requires exact,
/// ordered binding before execution and exposes no result before then.
pub fn Database::prepare_stream_query(
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
  let query = prepare_stream_query_ffi(
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
/// Begin a zero-parameter streaming query.
pub fn Database::stream_query(
  self : Database,
  sql : String,
  max_columns : Int,
  max_rows : Int64,
  max_chunk_rows : Int,
  max_chunk_bytes : Int,
) -> Result[Query, NativeDuckDBIssue] {
  let query = match
    self.prepare_stream_query(
      sql, max_columns, max_rows, max_chunk_rows, max_chunk_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if query.parameter_count() != 0 {
    query.close() |> ignore
    return Err(Query("DuckDB stream query requires parameters"))
  }
  match query.execute() {
    Ok(_) => Ok(query)
    Err(issue) => {
      query.close() |> ignore
      Err(issue)
    }
  }
}

///|
pub fn Query::parameter_count(self : Query) -> Int {
  stream_query_parameter_count_ffi(self).to_int()
}

///|
pub fn Query::bind_parameter(
  self : Query,
  index : Int,
  parameter : NativeDuckDBParameter,
) -> Result[Unit, NativeDuckDBIssue] {
  let bound = match parameter {
    NullValue => bind_null_ffi(self, index)
    BooleanValue(value) =>
      bind_boolean_ffi(self, index, if value { 1 } else { 0 })
    DoubleValue(value) => bind_double_ffi(self, index, value)
    TextValue(value) => {
      let encoded = @utf8.encode(value)
      bind_text_ffi(self, index, encoded, encoded.length())
    }
    DecimalValue(coefficient, width, scale) => {
      let encoded = @utf8.encode(coefficient)
      bind_decimal_ffi(self, index, encoded, encoded.length(), width, scale)
    }
    DateValue(days) => bind_date_ffi(self, index, days)
    TimestampValue(micros) => bind_timestamp_ffi(self, index, micros)
  }
  if bound {
    Ok(())
  } else {
    match stream_query_status_ffi(self) {
      2 => Err(CapacityExceeded)
      3 => Err(Closed)
      _ => Err(Query(decode_message(stream_query_error_ffi(self))))
    }
  }
}

///|
pub fn Query::execute(self : Query) -> Result[Unit, NativeDuckDBIssue] {
  if execute_stream_query_ffi(self) {
    Ok(())
  } else {
    match stream_query_status_ffi(self) {
      2 => Err(CapacityExceeded)
      3 => Err(Closed)
      _ => Err(Query(decode_message(stream_query_error_ffi(self))))
    }
  }
}

///|
pub fn Query::fields_json(self : Query) -> Result[String, NativeDuckDBIssue] {
  if !stream_query_executed_ffi(self) {
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
  if !stream_query_executed_ffi(self) {
    return match stream_query_status_ffi(self) {
      2 => Err(CapacityExceeded)
      3 => Err(Closed)
      _ => Err(Query(decode_message(stream_query_error_ffi(self))))
    }
  }
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
