///|
type Library

///|
pub fn command_domain_necessary_bytes(
  _domain_bytes : Int64,
  _heap_bytes : Int64,
) -> Int64? {
  None
}

///|
struct Database {
  unsupported : Unit
}

///|
pub fn Database::client_run_definition_schema(
  _self : Database,
) -> Result[Int, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::install_client_run_definition_schema(
  _self : Database,
  _max_inspect_rows : Int64,
) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Library::open_inspection_database(
  _self : Library,
  _path : String,
  _max_body_bytes : Int64,
) -> Database {
  { unsupported: (), }
}

///|
pub fn Library::open_journal_inspection_database(
  _self : Library,
  _path : String,
  _max_body_bytes : Int64,
) -> Database {
  { unsupported: (), }
}

///|
pub fn Database::inspection_status(
  self : Database,
) -> Result[Unit, NativeSqliteIssue] {
  ignore(self.unsupported)
  Err(UnsupportedTarget)
}

///|
pub fn Database::close_checked(
  _self : Database,
) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn load_library(
  _path : String,
  diagnostic_ceiling? : Int? = None,
) -> Result[Library, NativeSqliteIssue] {
  if diagnostic_ceiling is Some(value) && value <= 0 {
    return Err(InvalidLimit)
  }
  Err(UnsupportedTarget)
}

///|
pub fn load_current_component_with_custody(
  _path : String,
  heap_bytes : Int64,
  diagnostic_ceiling : Int,
  command_member? : @filesystem.NativeObservedComponentMember? = None,
) -> Result[Library, NativeSqliteLibraryLoadError] {
  if heap_bytes < 4096L || heap_bytes > 2147483647L || diagnostic_ceiling <= 0 {
    return Err(RefusedBeforeAcquisition(InvalidLimit))
  }
  Err(RefusedBeforeAcquisition(UnsupportedTarget))
}

///|
pub fn Library::close_checked(
  _self : Library,
) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Library::version(_self : Library) -> String {
  ""
}

///|
pub fn Library::diagnostic_ceiling(_self : Library) -> Int? {
  None
}

///|
pub fn Database::diagnostic_ceiling(_self : Database) -> Int? {
  None
}

///|
pub fn Database::current_component_matches_heap(
  _self : Database,
  _expected_heap_bytes : Int64,
) -> Bool {
  false
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
pub fn Library::open_database_with_custody(
  _self : Library,
  _path : String,
  _max_body_bytes : Int64,
) -> Result[Database, NativeSqliteOpenFailure] {
  Err({ original_issue: UnsupportedTarget, database: None, })
}

///|
pub fn Library::open_existing_database(
  _self : Library,
  _path : String,
  _max_body_bytes : Int64,
) -> Result[Database, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Library::open_existing_database_with_custody(
  _self : Library,
  _path : String,
  _max_body_bytes : Int64,
) -> Result[Database, NativeSqliteOpenFailure] {
  Err({ original_issue: UnsupportedTarget, database: None, })
}

///|
pub fn Library::initialize_owned_database(
  _self : Library,
  _path : String,
  _ownership : @filesystem.NativeFileOwnership,
  _max_body_bytes : Int64,
) -> Result[Database, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Library::initialize_owned_database_with_custody(
  _self : Library,
  _path : String,
  _ownership : @filesystem.NativeFileOwnership,
  _max_body_bytes : Int64,
) -> Result[Database, NativeSqliteOpenFailure] {
  Err({ original_issue: UnsupportedTarget, database: None, })
}

///|
pub fn Library::open_existing_journal_database_with_custody(
  _self : Library,
  _path : String,
  _max_body_bytes : Int64,
) -> Result[Database, NativeSqliteOpenFailure] {
  Err({ original_issue: UnsupportedTarget, database: None, })
}

///|
pub fn Library::initialize_owned_journal_database_with_custody(
  _self : Library,
  _path : String,
  _ownership : @filesystem.NativeFileOwnership,
  _max_body_bytes : Int64,
) -> Result[Database, NativeSqliteOpenFailure] {
  Err({ original_issue: UnsupportedTarget, database: None, })
}

///|
pub fn Database::transaction_state(
  _self : Database,
) -> Result[NativeSqliteTransactionState, NativeSqliteIssue] {
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
pub fn Database::begin_immediate(
  _self : Database,
) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::commit(_self : Database) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::rollback(_self : Database) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::fence_transactions(_self : Database) -> Unit {
  ()
}

///|
pub fn Database::transaction_fenced(_self : Database) -> Bool {
  true
}

///|
pub fn Database::reserve_capacity(
  _self : Database,
  _scope : String,
  _key : String,
  _reserved_bytes : Int64,
  _reserved_objects : Int64,
  _max_bytes : Int64,
  _max_objects : Int64,
) -> Result[Bool, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::reserve_capacity_in_transaction(
  _self : Database,
  _scope : String,
  _key : String,
  _reserved_bytes : Int64,
  _reserved_objects : Int64,
  _max_bytes : Int64,
  _max_objects : Int64,
) -> Result[Bool, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::release_capacity(
  _self : Database,
  _scope : String,
  _key : String,
  _reserved_bytes : Int64,
  _reserved_objects : Int64,
) -> Result[Bool, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::release_capacity_in_transaction(
  _self : Database,
  _scope : String,
  _key : String,
  _reserved_bytes : Int64,
  _reserved_objects : Int64,
) -> Result[Bool, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::claim_ordinal(
  _self : Database,
  scope : String,
  key : String,
  max_claims : Int64,
) -> Result[Int64, NativeSqliteIssue] {
  ignore(scope)
  ignore(key)
  ignore(max_claims)
  Err(UnsupportedTarget)
}

///|
pub fn Database::claim_ordinal_action(
  _self : Database,
  _scope : String,
  _key : String,
  _max_claims : Int64,
) -> Result[NativeOrdinalClaim, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::claim_ordinal_action_in_transaction(
  _self : Database,
  _scope : String,
  _key : String,
  _max_claims : Int64,
) -> Result[NativeOrdinalClaim, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::lookup_claim_ordinal(
  _self : Database,
  _scope : String,
  _key : String,
) -> Result[Int64?, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::capacity_usage(
  _self : Database,
  _scope : String,
) -> Result[NativeCapacityUsage, NativeSqliteIssue] {
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

///|
pub fn Database::remove_exact(
  _self : Database,
  _scope : String,
  _key : String,
  _expected_revision : Int64,
  _expected_body : Bytes,
) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::read_with_body_limit(
  _self : Database,
  _scope : String,
  _key : String,
  _max_body_bytes : Int64,
) -> Result[NativeJournalValue, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::scan_after_with_body_limit(
  _self : Database,
  _scope : String,
  _after_key : String,
  _max_body_bytes : Int64,
) -> Result[NativeJournalEntry, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::read_capacity(
  _self : Database,
  _scope : String,
  _key : String,
) -> Result[NativeCapacityUsage, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::client_read_evidence_schema(
  _self : Database,
) -> Result[Int, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::install_client_read_evidence_schema(
  _self : Database,
  _max_inspect_rows : Int64,
) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::client_read_evidence_usage(
  _self : Database,
  _request_wire : String,
  _max_entries : Int64,
  _max_body_bytes : Int64,
) -> Result[(Int64, Int64), NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::database_usage(
  _self : Database,
) -> Result[NativeDatabaseUsage, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::read_header(
  _self : Database,
  _scope : String,
  _key : String,
) -> Result[NativeJournalHeader, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Database::begin_deferred(
  _self : Database,
) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Library::open_local_store_database_with_custody(
  _self : Library,
  _path : String,
  _max_body_bytes : Int64,
) -> Result[Database, NativeSqliteOpenFailure] {
  Err({ original_issue: UnsupportedTarget, database: None, })
}

///|
pub fn Library::open_existing_local_store_database_with_custody(
  _self : Library,
  _path : String,
  _max_body_bytes : Int64,
) -> Result[Database, NativeSqliteOpenFailure] {
  Err({ original_issue: UnsupportedTarget, database: None, })
}

///|
pub fn Database::retained_data_current(
  _self : Database,
) -> Result[Unit, NativeSqliteIssue] {
  Err(UnsupportedTarget)
}
