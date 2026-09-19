///|
type Library

///|
type Database

///|
pub fn load_library(_path : String) -> Result[Library, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Library::version(_self : Library) -> String {
  ""
}

///|
pub fn Library::open_database(
  _self : Library,
  path : String,
  max_body_bytes : Int64,
) -> Result[Database, NativeSqliteIssue] {
  ignore(path)
  ignore(max_body_bytes)
  Err(UnsupportedTarget)
}

///|
pub fn Database::read(
  _self : Database,
  scope : String,
  key : String,
) -> Result[NativeJournalValue, NativeSqliteIssue] {
  ignore(scope)
  ignore(key)
  Err(UnsupportedTarget)
}

///|
pub fn Database::scan_after(
  _self : Database,
  scope : String,
  after_key : String,
) -> Result[NativeJournalEntry, NativeSqliteIssue] {
  ignore(scope)
  ignore(after_key)
  Err(UnsupportedTarget)
}

///|
pub fn Database::insert(
  _self : Database,
  scope : String,
  key : String,
  body : Bytes,
) -> Result[Int64, NativeSqliteIssue] {
  ignore(scope)
  ignore(key)
  ignore(body)
  Err(UnsupportedTarget)
}

///|
pub fn Database::compare_exchange(
  _self : Database,
  scope : String,
  key : String,
  expected_revision : Int64,
  body : Bytes,
) -> Result[Int64, NativeSqliteIssue] {
  ignore(scope)
  ignore(key)
  ignore(expected_revision)
  ignore(body)
  Err(UnsupportedTarget)
}

///|
pub fn Database::close(_self : Database) -> Unit {

}

///|
#warnings("-unused_value")
fn retain_native_import() -> Unit {
  ignore(@utf8.encode(""))
}
