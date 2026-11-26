///|
// Existing legacy diagnostics construct a fresh generic database, sometimes
// after the epoch row. Install the real constraint in an actual transaction;
// this bounded fixture adapter is not an operational supplier or authority.
fn initialize_native_client_run_journal(
  database : @sqlite.Database,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let owned = match database.transaction_state() {
    Ok(@sqlite.NoActiveSqliteTransaction) => true
    Ok(@sqlite.ActiveSqliteTransaction) => false
    Err(issue) => return Err(Physical(issue))
  }
  if owned {
    match client_journal_transaction_operation(database, JournalBegin, None) {
      Ok(_) => ()
      Err(failure) => return Err(JournalStepFailed(failure, None))
    }
  }
  let result : Result[Unit, NativeClientRunJournalIssue] = match
    database.install_client_run_definition_schema(1024L) {
    Err(issue) => Err(Physical(issue))
    Ok(_) => initialize_native_client_run_journal_rows(database)
  }
  if !owned {
    return result
  }
  match result {
    Ok(_) =>
      match
        client_journal_transaction_operation(database, JournalCommit, None) {
        Ok(_) => Ok(())
        Err(failure) => {
          database.fence_transactions()
          Err(JournalStepFailed(failure, None))
        }
      }
    Err(issue) =>
      match
        client_journal_transaction_operation(database, JournalRollback, None) {
        Ok(_) => Err(issue)
        Err(failure) => {
          database.fence_transactions()
          Err(JournalStepFailed(failure, Some(issue)))
        }
      }
  }
}
