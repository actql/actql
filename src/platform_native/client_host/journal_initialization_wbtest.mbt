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
    match database.begin_immediate() {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
  }
  let result = match database.install_client_run_definition_schema(1024L) {
    Err(issue) => Err(Physical(issue))
    Ok(_) => initialize_native_client_run_journal_rows(database)
  }
  if !owned {
    return result
  }
  match result {
    Ok(_) =>
      match database.commit() {
        Ok(_) => Ok(())
        Err(_) => {
          database.fence_transactions()
          Err(TransactionUnknown)
        }
      }
    Err(issue) =>
      match database.rollback() {
        Ok(_) => Err(issue)
        Err(_) => {
          database.fence_transactions()
          Err(TransactionUnknown)
        }
      }
  }
}
