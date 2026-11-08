///|
// Only trusted assembly invokes this with its original one-time physical
// claim. No public API treats missing rows as permission to initialize.
fn initialize_native_local_client_custody(
  database : @sqlite.Database,
  crypto : @crypto.Library,
  adoption : Bytes,
  settings? : NativeLocalConfigurationSelection? = None,
  initial_signing? : NativeLocalInitialSigningCapture? = None,
  bootstrap? : NativeClientJournalBootstrapAccess? = None,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  let reads = bootstrap_journal_reads(bootstrap)
  if client_journal_transaction_fenced(database, reads) {
    return Err(Fenced)
  }
  match client_journal_transaction_operation(database, JournalBegin, reads) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  let result = initialize_native_local_client_rows(
    database, crypto, adoption, settings, initial_signing, bootstrap,
  )
  let result = match result {
    Ok(_) =>
      match initial_signing {
        None => Ok(())
        Some(original) => original.check_current(crypto, adoption)
      }
    Err(issue) => Err(issue)
  }
  match result {
    Ok(_) =>
      match
        client_journal_transaction_operation(database, JournalCommit, reads) {
        Ok(_) => Ok(())
        Err(_) => {
          fence_client_journal_transactions(database, reads)
          Err(TransactionUnknown)
        }
      }
    Err(issue) =>
      match
        client_journal_transaction_operation(database, JournalRollback, reads) {
        Ok(_) => Err(issue)
        Err(_) => {
          fence_client_journal_transactions(database, reads)
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
  settings : NativeLocalConfigurationSelection?,
  initial_signing : NativeLocalInitialSigningCapture?,
  bootstrap : NativeClientJournalBootstrapAccess?,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  // Refuse preexisting or partially lost custody before generating any key.
  for
    record_namespace in [
      "client_local_adoption", "client_local_settings", "client_submission_epoch",
      "client_run_custody", "client_runs", "client_submitted_intent_usage", "client_run_id_index",
      "client_run_id_index_coverage", "client_run_reference_index", "client_effect_custody",
      "client_effect_response_meta", "client_effect_response_bytes", "client_effect_row_receipt",
      "client_cancellations", "client_cancel_custody", "client_cancel_originals",
      "client_submitted_intent_custody", "client_submitted_intents", "client_submission_names",
      "client_submission_name_custody", "client_local_read_custody", "client_local_read_evidence",
      "client_local_grant_custody", "client_local_grant_originals", "client_local_preparation_target_originals",
      "client_local_signing_result_originals", "client_local_signing_candidate_originals",
      "client_local_installation_custody", "client_local_installation_originals",
      "client_worker_provisioning_custody", "client_worker_provisioning", "client_model_call_originals",
      "client_model_call_settlements",
    ] {
    match
      scan_client_journal_value(
        database,
        record_namespace,
        "",
        bootstrap_journal_reads(bootstrap),
      ) {
      Err(@sqlite.NotFound) => ()
      Ok(_) => return Err(CustodyLost)
      Err(issue) => return Err(Physical(issue))
    }
  }
  match install_bootstrap_run_definition_schema(database, 0L, bootstrap) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  match install_bootstrap_read_evidence_schema(database, 0L, bootstrap) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  match initialize_local_read_evidence(database, adoption, bootstrap~) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match initialize_local_grant_originals(database, adoption, bootstrap~) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let installation = match initial_signing {
    None =>
      initialize_local_installation_originals(database, adoption, bootstrap~)
    Some(_) => check_empty_local_installation_originals(database, bootstrap~)
  }
  match installation {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    initialize_native_client_epoch_in_transaction(database, crypto, bootstrap~) {
    Ok(_) => ()
    Err(issue) => return Err(Epoch(issue))
  }
  if initial_signing is Some(original) {
    let body = match
      original.control_body(
        database,
        crypto,
        adoption,
        reads=bootstrap_journal_reads(bootstrap),
      ) {
      Err(issue) => return Err(issue)
      Ok(value) => value
    }
    match insert_local_installation_control(database, body, bootstrap~) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  match
    initialize_local_worker_provisioning(database, adoption, crypto, bootstrap~) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match initialize_native_client_run_journal_rows(database, bootstrap~) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  match initialize_native_client_submitted_intents(database, bootstrap~) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  match initialize_native_client_submitted_names(database, bootstrap~) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  if settings is Some(settings) {
    match settings.persist(database, bootstrap~) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  insert_bootstrap_journal_value(
    database, "client_local_adoption", "adoption", adoption, bootstrap,
  )
  .map(_ => ())
  .map_err(issue => Physical(issue))
}
