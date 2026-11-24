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
/// Fixed physical operations on the original connection. The owning Journal
/// still decides durability, connection reuse, and whether it may continue.
pub(all) enum NativeSqliteTransactionStep {
  BeginDeferred
  BeginImmediate
  Commit
  Rollback
} derive(Eq)

///|
pub(all) struct NativeSqliteResultCode {
  primary : Int
  extended : Int
} derive(Eq)

///|
/// The response to this physical step, before subsequent routing. A lost
/// reply supplies no SQLite code or proof of the durable outcome.
pub(all) enum NativeSqliteTransactionReply {
  SqlNotIssued
  SqlRejected(NativeSqliteResultCode)
  SqlReplyLost
  SqlConfirmed
} derive(Eq)

///|
/// The reported issue can be a routing failure even when SQLite confirmed
/// the operation. Cleanup reports its own result without replacing this one.
pub struct NativeSqliteTransactionFailure {
  step : NativeSqliteTransactionStep
  reply : NativeSqliteTransactionReply
  issue : NativeSqliteIssue
}

///|
/// The physical stop attempt belongs to the same transaction and connection.
/// A missing rollback means no rollback statement was issued.
pub struct NativeSqliteTransactionStopFailure {
  rollback : Result[Unit, NativeSqliteTransactionFailure]?
  state : Result[NativeSqliteTransactionState, NativeSqliteIssue]
}

///|
/// The selected write's durable outcome. Independent of its physical cleanup
/// and whether a caller is allowed to continue or redispatch.
pub(all) enum NativeSqliteCommitOutcome {
  CommitConfirmed
  CommitNotApplied
  CommitUnknown
} derive(Eq)

///|
pub struct NativeSqliteJournalCommitFailure {
  primary : NativeSqliteTransactionFailure
  outcome : NativeSqliteCommitOutcome
  cleanup_failure : NativeSqliteTransactionStopFailure?
}

///|
fn NativeSqliteIssue::routing_failed(self : NativeSqliteIssue) -> Bool {
  match self {
    OperationRoutingBefore(_) | OperationRoutingAfter(_, _) => true
    _ => false
  }
}

///|
/// Start one journal write. A failed BEGIN cannot authorize rolling back a
/// transaction the caller did not acquire, even on a shared Database.
pub fn Database::begin_journal_write(
  self : Database,
) -> Result[Unit, NativeSqliteTransactionFailure] {
  match self.transaction_step(BeginImmediate) {
    Ok(_) => Ok(())
    Err(failure) => {
      if failure.reply is SqlConfirmed ||
        failure.issue.routing_failed() ||
        !(self.transaction_state() is Ok(NoActiveSqliteTransaction)) {
        self.fence_transactions()
      }
      Err(failure)
    }
  }
}

///|
/// Stop the caller's original write after a body or COMMIT refusal. Preserve
/// the first refused stop observation and fence before returning it.
pub fn Database::rollback_journal_write(
  self : Database,
) -> Result[Unit, NativeSqliteTransactionStopFailure] {
  let initial = self.transaction_state()
  let rollback = match initial {
    Ok(ActiveSqliteTransaction) => Some(self.transaction_step(Rollback))
    _ => None
  }
  let state = match rollback {
    Some(_) => self.transaction_state()
    None => initial
  }
  match (rollback, state) {
    (None | Some(Ok(_)), Ok(NoActiveSqliteTransaction)) => Ok(())
    _ => {
      self.fence_transactions()
      Err({ rollback, state, })
    }
  }
}

///|
/// Commit once. A lost reply always requires owner reconciliation. A confirmed
/// SQL success with a failed route still preserves its physical outcome.
pub fn Database::commit_journal_write(
  self : Database,
) -> Result[Unit, NativeSqliteJournalCommitFailure] {
  guard self.transaction_step(Commit) is Err(primary) else { return Ok(()) }
  if primary.reply is SqlConfirmed {
    self.fence_transactions()
    return Err({ primary, outcome: CommitConfirmed, cleanup_failure: None, })
  }
  let cleanup_failure = match self.rollback_journal_write() {
    Ok(_) => None
    Err(failure) => Some(failure)
  }
  let definitely_not_applied = match primary.reply {
    SqlNotIssued => true
    SqlRejected(code) => code.primary == 5 || code.primary == 6
    _ => false
  }
  let outcome = if definitely_not_applied && cleanup_failure is None {
    CommitNotApplied
  } else {
    CommitUnknown
  }
  if outcome == CommitUnknown || primary.issue.routing_failed() {
    self.fence_transactions()
  }
  Err({ primary, outcome, cleanup_failure, })
}

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
