///|
/// Non-native targets expose the same capability surface but cannot construct
/// native resource handles.
type Library

///|
type Database

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
  path? : String = "",
) -> Result[Database, NativeDuckDBIssue] {
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
