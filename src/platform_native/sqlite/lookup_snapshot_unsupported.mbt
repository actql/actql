///|
type NativeLookupRead

///|
pub fn Database::prepare_lookup_read(
  _self : Database,
) -> Result[NativeLookupReadAcquisition, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::owns_lookup_read(
  _self : Database,
  _child : NativeLookupRead,
) -> Bool {
  false
}

///|
pub fn NativeLookupRead::require_current(
  _self : NativeLookupRead,
) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeLookupRead::finish(
  _self : NativeLookupRead,
) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeLookupRead::retry_cleanup(
  _self : NativeLookupRead,
) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeLookupRead::read_with_body_limit(
  _self : NativeLookupRead,
  _scope : String,
  _key : String,
  _max_body_bytes : Int64,
) -> Result[NativeJournalValue, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeLookupRead::scan_after_with_body_limit(
  _self : NativeLookupRead,
  _scope : String,
  _after_key : String,
  _max_body_bytes : Int64,
) -> Result[NativeJournalEntry, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeLookupRead::read_header(
  _self : NativeLookupRead,
  _scope : String,
  _key : String,
) -> Result[NativeJournalHeader, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeLookupRead::read_capacity(
  _self : NativeLookupRead,
  _scope : String,
  _key : String,
) -> Result[NativeCapacityUsage, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeLookupRead::capacity_usage(
  _self : NativeLookupRead,
  _scope : String,
) -> Result[NativeCapacityUsage, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeLookupRead::database_usage(
  _self : NativeLookupRead,
) -> Result[NativeDatabaseUsage, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}
