///|
pub fn Database::insert_with_body_extent(
  _self : Database,
  _scope : String,
  _key : String,
  _body : Bytes,
  _body_extent : Int64,
) -> Result[Int64, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::compare_exchange_with_body_extent(
  _self : Database,
  _scope : String,
  _key : String,
  _revision : Int64,
  _body : Bytes,
  _body_extent : Int64,
) -> Result[Int64, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::observe_body_extent(
  _self : Database,
  _scope : String,
  _key : String,
) -> Result[NativeJournalHeader, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::read_exact_body_extent(
  _self : Database,
  _scope : String,
  _key : String,
  _original : NativeJournalHeader,
) -> Result[NativeJournalValue, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::observe_scan_body_extent(
  _self : Database,
  _scope : String,
  _after_key : String,
) -> Result[(String, NativeJournalHeader), NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::scan_exact_body_extent(
  _self : Database,
  _scope : String,
  _after_key : String,
  _expected_key : String,
  _original : NativeJournalHeader,
) -> Result[NativeJournalEntry, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}
