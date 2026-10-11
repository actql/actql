///|
// Only trusted assembly invokes this with its original one-time physical
// claim. No public API treats missing rows as permission to initialize.
fn initialize_native_local_client_custody(
  database : @sqlite.Database,
  crypto : @crypto.Library,
  adoption : Bytes,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if database.transaction_fenced() {
    return Err(Fenced)
  }
  match database.begin_immediate() {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  let result = initialize_native_local_client_rows(database, crypto, adoption)
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

///|
fn initialize_native_local_client_rows(
  database : @sqlite.Database,
  crypto : @crypto.Library,
  adoption : Bytes,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  // Refuse preexisting or partially lost custody before generating any key.
  for
    record_namespace in [
      "client_local_adoption", "client_submission_epoch", "client_run_custody", "client_runs",
      "client_effect_custody", "client_effect_response_meta", "client_effect_response_bytes",
      "client_effect_row_receipt", "client_cancellations", "client_cancel_custody",
      "client_cancel_originals", "client_submitted_intent_custody", "client_submitted_intents",
    ] {
    match database.scan_after(record_namespace, "") {
      Err(@sqlite.NotFound) => ()
      Ok(_) => return Err(CustodyLost)
      Err(issue) => return Err(Physical(issue))
    }
  }
  match initialize_native_client_epoch_in_transaction(database, crypto) {
    Ok(_) => ()
    Err(issue) => return Err(Epoch(issue))
  }
  match initialize_native_client_run_journal(database) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  match initialize_native_client_submitted_intents(database) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  database
  .insert("client_local_adoption", "adoption", adoption)
  .map(_ => ())
  .map_err(issue => Physical(issue))
}
