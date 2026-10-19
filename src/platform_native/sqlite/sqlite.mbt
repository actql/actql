///|
pub(all) enum NativeSqliteIssue {
  UnsupportedTarget
  InvalidName
  InvalidLimit
  LibraryLoad(String)
  DatabaseOpen(String)
  DatabaseClosed
  NotFound
  Collision
  Busy
  BodyTooLarge
  CapacityExceeded
  Physical(String)
  // Original SQL result is preserved if returning to Read subsequently fails.
  OperationRoutingBefore(Int)
  OperationRoutingAfter(NativeSqliteIssue?, Int)
}

///|
pub(all) struct NativeCapacityUsage {
  reserved_bytes : Int64
  reserved_objects : Int64
}

///|
/// Physical totals in this one database, across its record namespaces. These
/// values do not establish an admitted inventory, available credit, a COMMIT
/// acknowledgment or the completeness of any external Source namespace.
pub(all) struct NativeDatabaseUsage {
  record_count : Int64
  body_bytes : Int64
  reservation_count : Int64
}

///|
/// The existing bounded claim transaction distinguishes a newly committed
/// claim from its retained original. Neither variant proves Provider sending
/// or the presence of a separately saved use/outcome record.
pub(all) enum NativeOrdinalClaim {
  Fresh(Int64)
  Retained(Int64)
}

///|
pub(all) struct NativeJournalValue {
  revision : Int64
  body : Bytes
}

///|
pub(all) struct NativeJournalEntry {
  key : String
  revision : Int64
  body : Bytes
}

///|
/// Original row metadata only. No payload is copied; a header does not prove
/// body equality, inventory completeness, publication or a durable COMMIT.
pub(all) struct NativeJournalHeader {
  revision : Int64
  body_bytes : Int64
}

///|
/// Physical connection state only. Autocommit is not a particular COMMIT ACK,
/// durable content validation, Run outcome or permission to send another write.
pub(all) enum NativeSqliteTransactionState {
  NoActiveSqliteTransaction
  ActiveSqliteTransaction
} derive(Eq)

///|
/// The original failed open and its existing physical Database owner. This
/// opaque carrier cannot reopen a database, issue a request or settle capacity.
struct NativeSqliteOpenFailure {
  original_issue : NativeSqliteIssue
  mut database : Database?
}

///|
pub fn NativeSqliteOpenFailure::issue(
  self : NativeSqliteOpenFailure,
) -> NativeSqliteIssue {
  self.original_issue
}

///|
/// Keep the same failed-open handle until its own close is acknowledged. The
/// original open diagnosis survives cleanup; successful retries are idempotent.
pub fn NativeSqliteOpenFailure::retry_cleanup(
  self : NativeSqliteOpenFailure,
) -> Result[Unit, NativeSqliteIssue] {
  if self.database is Some(original) {
    match original.close_checked() {
      Ok(_) => self.database = None
      Err(issue) => return Err(issue)
    }
  }
  Ok(())
}

///|
/// Physical acquisition refused before a Library exists, or the SAME rejected
/// Library whose cleanup still belongs to its installed caller. Neither case
/// issues Host authority, a capacity grant or permission to acquire again.
pub(all) enum NativeSqliteLibraryLoadError {
  RefusedBeforeAcquisition(NativeSqliteIssue)
  CleanupRequired(NativeSqliteLibraryLoadFailure)
}

///|
// Only the Native implementation constructs physical acquisition failures.
// Other targets retain this opaque API type and refuse before acquisition.
#warnings("-struct_never_constructed")
struct NativeSqliteLibraryLoadFailure {
  original_issue : NativeSqliteIssue
  mut library : Library?
}

///|
pub fn NativeSqliteLibraryLoadFailure::issue(
  self : NativeSqliteLibraryLoadFailure,
) -> NativeSqliteIssue {
  self.original_issue
}

///|
/// Only retry original cleanup. Retain the same partial Library until its own
/// checked close ACK; this cannot load, configure, adopt or repair a runtime.
pub fn NativeSqliteLibraryLoadFailure::retry_cleanup(
  self : NativeSqliteLibraryLoadFailure,
) -> Result[Unit, NativeSqliteIssue] {
  if self.library is Some(original) {
    match original.close_checked() {
      Ok(_) => self.library = None
      Err(issue) => return Err(issue)
    }
  }
  Ok(())
}

///|
pub(all) enum NativeLookupReadAcquisition {
  ReadyLookupRead(NativeLookupRead)
  PendingLookupRead(NativeLookupRead, NativeSqliteIssue)
}
