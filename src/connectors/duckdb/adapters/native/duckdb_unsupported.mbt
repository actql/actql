///|
/// Non-native targets expose the same capability surface but cannot construct
/// native resource handles.
type Library

///|
type Database

///|
type Query

///|
pub fn load_library(_path : String) -> Result[Library, NativeDuckDBIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Library::version(_self : Library) -> String {
  ""
}

///|
pub fn Library::open_database(
  _self : Library,
  limits : NativeDuckDBOpenLimits,
  path? : String = "",
) -> Result[Database, NativeDuckDBIssue] {
  ignore(limits)
  ignore(path)
  Err(UnsupportedTarget)
}

///|
pub fn Database::query_i64(
  _self : Database,
  sql : String,
) -> Result[Int64, NativeDuckDBIssue] {
  ignore(sql)
  Err(UnsupportedTarget)
}

///|
pub fn Database::begin_transaction(
  _self : Database,
) -> Result[Unit, NativeDuckDBIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::commit_transaction(
  _self : Database,
) -> Result[Unit, NativeDuckDBIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::rollback_transaction(
  _self : Database,
) -> Result[Unit, NativeDuckDBIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::stream_query(
  _self : Database,
  sql : String,
  max_columns : Int,
  max_rows : Int64,
  max_chunk_rows : Int,
  max_chunk_bytes : Int,
) -> Result[Query, NativeDuckDBIssue] {
  ignore(sql)
  ignore(max_columns)
  ignore(max_rows)
  ignore(max_chunk_rows)
  ignore(max_chunk_bytes)
  Err(UnsupportedTarget)
}

///|
pub fn Database::prepare_stream_query(
  _self : Database,
  sql : String,
  max_columns : Int,
  max_rows : Int64,
  max_chunk_rows : Int,
  max_chunk_bytes : Int,
) -> Result[Query, NativeDuckDBIssue] {
  ignore(sql)
  ignore(max_columns)
  ignore(max_rows)
  ignore(max_chunk_rows)
  ignore(max_chunk_bytes)
  Err(UnsupportedTarget)
}

///|
pub fn Query::parameter_count(_self : Query) -> Int {
  0
}

///|
pub fn Query::bind_parameter(
  _self : Query,
  index : Int,
  parameter : NativeDuckDBParameter,
) -> Result[Unit, NativeDuckDBIssue] {
  ignore(index)
  ignore(parameter)
  Err(UnsupportedTarget)
}

///|
pub fn Query::execute(_self : Query) -> Result[Unit, NativeDuckDBIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Query::fields_json(_self : Query) -> Result[String, NativeDuckDBIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Query::next(
  _self : Query,
) -> Result[NativeDuckDBChunk?, NativeDuckDBIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Query::close(_self : Query) -> Bool {
  false
}

///|
pub fn Database::close(_self : Database) -> Unit {
  ()
}

///|
// MoonBit does not support target-conditional imports. Keep the common package
// interface identical without hiding that the UTF-8 conversion is native-only.
#warnings("-unused_value")
fn retain_native_import() -> Unit {
  ignore(@utf8.encode(""))
}
