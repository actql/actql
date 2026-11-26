///|
// Private call routing inside the original Journal Owner. Each callback uses
// the same Database and its actual scope; these functions issue no authority,
// capacity, new transaction or original row. Legacy callers keep direct reads.
priv struct NativeClientJournalReadAccess {
  before_metadata_construction : ((Int64, Int64, Int64) -> Result[
    Unit,
    NativeClientRunJournalIssue,
  ])?
  database : @sqlite.Database
  before_submitted_decode : ((@host.ClientSubmittedJournalConstruction) -> Result[
    Unit,
    @host.ClientJournalDecodingIssue,
  ])?
  before_run_decode : ((@host.ClientRunJournalConstruction) -> Result[
    Unit,
    @host.ClientJournalDecodingIssue,
  ])?
  run_definition_schema : () -> Result[Int, @sqlite.NativeSqliteIssue]
  run_definition_key : (String) -> Result[String?, @sqlite.NativeSqliteIssue]
  read_evidence_schema : () -> Result[Int, @sqlite.NativeSqliteIssue]
  fenced : () -> Bool
  fence : () -> Unit
  schema : () -> Int
  // Retain the original scoped callback for whitebox same-Database routing checks.
  _observed_census : () -> Int64
  transaction : (NativeClientJournalTransactionOperation) -> Result[
    Unit,
    NativeClientJournalStepFailure,
  ]
  read : (String, String) -> Result[
    @sqlite.NativeJournalValue,
    @sqlite.NativeSqliteIssue,
  ]
  observe_scan_body_extent : (String, String) -> Result[
    (String, @sqlite.NativeJournalHeader),
    @sqlite.NativeSqliteIssue,
  ]
  scan : (String, String) -> Result[
    @sqlite.NativeJournalEntry,
    @sqlite.NativeSqliteIssue,
  ]
}

///|
fn client_journal_run_definition_schema(
  database : @sqlite.Database,
  reads : NativeClientJournalReadAccess?,
) -> Result[Int, @sqlite.NativeSqliteIssue] {
  match reads {
    None => database.client_run_definition_schema()
    Some(original) if physical_equal(database, original.database) =>
      (original.run_definition_schema)()
    _ => Err(@sqlite.Collision)
  }
}

///|
// Error-path classification through the already admitted physical uniqueness
// index. A key is only a locator; the Journal authenticates the selected row.
fn client_journal_run_definition_key(
  database : @sqlite.Database,
  definition_cid : String,
  reads : NativeClientJournalReadAccess?,
) -> Result[String?, @sqlite.NativeSqliteIssue] {
  match reads {
    None => database.client_run_definition_key(definition_cid)
    Some(original) if physical_equal(database, original.database) =>
      (original.run_definition_key)(definition_cid)
    _ => Err(@sqlite.Collision)
  }
}

///|
fn read_client_journal_value(
  database : @sqlite.Database,
  table_name : String,
  key : String,
  reads : NativeClientJournalReadAccess?,
) -> Result[@sqlite.NativeJournalValue, @sqlite.NativeSqliteIssue] {
  match reads {
    None => database.read(table_name, key)
    Some(original) => {
      if !physical_equal(database, original.database) {
        return Err(@sqlite.Collision)
      }
      (original.read)(table_name, key)
    }
  }
}

///|
fn scan_client_journal_value(
  database : @sqlite.Database,
  table_name : String,
  cursor : String,
  reads : NativeClientJournalReadAccess?,
) -> Result[@sqlite.NativeJournalEntry, @sqlite.NativeSqliteIssue] {
  match reads {
    None => database.scan_after(table_name, cursor)
    Some(original) => {
      if !physical_equal(database, original.database) {
        return Err(@sqlite.Collision)
      }
      (original.scan)(table_name, cursor)
    }
  }
}

///|
priv enum NativeClientJournalTransactionOperation {
  JournalBegin
  JournalCommit
  JournalRollback
}

///|
/// Evidence of a transaction refusal. These values carry no authority to enter or retry the original connection.
pub(all) enum NativeClientJournalStepFailure {
  ForeignDatabase(@sqlite.NativeSqliteTransactionStep)
  SqlStep(
    @sqlite.NativeSqliteTransactionStep,
    @sqlite.NativeSqliteTransactionObservation
  )
  ScopeStep(
    @sqlite.NativeSqliteTransactionStep,
    NativeLocalAdoptionIssue,
    @sqlite.NativeSqliteTransactionObservation?
  )
}

///|
fn NativeClientJournalTransactionOperation::sqlite_step(
  self : Self,
) -> @sqlite.NativeSqliteTransactionStep {
  match self {
    JournalBegin => BeginImmediate
    JournalCommit => Commit
    JournalRollback => Rollback
  }
}

///|
fn NativeClientJournalTransactionOperation::observe(
  self : Self,
  database : @sqlite.Database,
) -> Result[Unit, NativeClientJournalStepFailure] {
  self.check_observation(database.observe_transaction_step(self.sqlite_step()))
}

///|
fn NativeClientJournalTransactionOperation::check_observation(
  self : Self,
  observation : @sqlite.NativeSqliteTransactionObservation,
) -> Result[Unit, NativeClientJournalStepFailure] {
  let expected = match self {
    JournalBegin => @sqlite.ActiveSqliteTransaction
    JournalCommit | JournalRollback => @sqlite.NoActiveSqliteTransaction
  }
  match (observation.result, observation.state) {
    (Ok(_), Some(Ok(state))) if state == expected => Ok(())
    _ => Err(SqlStep(self.sqlite_step(), observation))
  }
}

///|
// The ordinary writer-contention refusal has not acquired a transaction.
// A missing sample, lost reply or failed scope exchange cannot prove that.
pub fn NativeClientJournalStepFailure::requires_reconciliation(
  self : Self,
) -> Bool {
  match self {
    ForeignDatabase(_) => false
    SqlStep(@sqlite.BeginImmediate, observation) =>
      match (observation.result, observation.state) {
        (Err(failure), Some(Ok(@sqlite.NoActiveSqliteTransaction))) =>
          failure.issue is @sqlite.OperationRoutingBefore(_) ||
          failure.issue is @sqlite.OperationRoutingAfter(_, _) ||
          !(failure.reply is @sqlite.SqlNotIssued ||
          failure.reply is @sqlite.SqlRejected(_))
        _ => true
      }
    _ => true
  }
}

///|
fn read_client_submission_name_schema(
  database : @sqlite.Database,
  reads : NativeClientJournalReadAccess?,
) -> Int {
  match reads {
    None => submission_name_schema_ffi(database)
    Some(original) =>
      if physical_equal(database, original.database) {
        (original.schema)()
      } else {
        -1
      }
  }
}

///|
fn client_journal_transaction_operation(
  database : @sqlite.Database,
  operation : NativeClientJournalTransactionOperation,
  reads : NativeClientJournalReadAccess?,
) -> Result[Unit, NativeClientJournalStepFailure] {
  match reads {
    Some(original) => {
      if !physical_equal(database, original.database) {
        return Err(ForeignDatabase(operation.sqlite_step()))
      }
      (original.transaction)(operation)
    }
    None => operation.observe(database)
  }
}

///|
// This scalar observes the same physical Database under its actual SQL scope.
// An unavailable or foreign original stays fenced; it is never cached as proof.
fn client_journal_transaction_fenced(
  database : @sqlite.Database,
  reads : NativeClientJournalReadAccess?,
) -> Bool {
  match reads {
    None => database.transaction_fenced()
    Some(original) =>
      !physical_equal(database, original.database) || (original.fenced)()
  }
}

///|
// Keep the original sticky fence on a failed transaction. The routing layer
// retains a failed scope transition separately; it cannot ACK physical fencing.
fn fence_client_journal_transactions(
  database : @sqlite.Database,
  reads : NativeClientJournalReadAccess?,
) -> Unit {
  match reads {
    None => database.fence_transactions()
    Some(original) =>
      if physical_equal(database, original.database) {
        (original.fence)()
      }
  }
}

///|
fn client_journal_read_evidence_schema(
  database : @sqlite.Database,
  reads : NativeClientJournalReadAccess?,
) -> Result[Int, @sqlite.NativeSqliteIssue] {
  match reads {
    None => database.client_read_evidence_schema()
    Some(original) if physical_equal(database, original.database) =>
      (original.read_evidence_schema)()
    _ => Err(@sqlite.Collision)
  }
}

///|
fn submitted_decode_construction(
  database : @sqlite.Database,
  reads : NativeClientJournalReadAccess?,
) -> ((@host.ClientSubmittedJournalConstruction) -> Result[
  Unit,
  @host.ClientJournalDecodingIssue,
])? {
  match reads {
    Some(original) if physical_equal(database, original.database) =>
      original.before_submitted_decode
    _ => None
  }
}

///|
fn run_decode_construction(
  database : @sqlite.Database,
  reads : NativeClientJournalReadAccess?,
) -> ((@host.ClientRunJournalConstruction) -> Result[
  Unit,
  @host.ClientJournalDecodingIssue,
])? {
  match reads {
    Some(original) if physical_equal(database, original.database) =>
      original.before_run_decode
    Some(_) => Some(_ => Err(@host.ClientJournalDecodingIssue::CustodyLost))
    None => None
  }
}

///|
fn run_metadata_construction(
  database : @sqlite.Database,
  reads : NativeClientJournalReadAccess?,
) -> ((Int64, Int64, Int64) -> Result[Unit, NativeClientRunJournalIssue])? {
  match reads {
    Some(original) if physical_equal(database, original.database) =>
      original.before_metadata_construction
    Some(_) => Some((_, _, _) => Err(CustodyLost))
    None => None
  }
}
