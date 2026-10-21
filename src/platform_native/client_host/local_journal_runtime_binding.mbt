///|
// The access exists only during this synchronous original Read operation.
// Its current callback repeats the complete captured fence; each SQL read
// exchanges the original Read/SQLite phases rather than running in the heap
// selected for the other domain. Nothing is installed on the Host as a bypass.
fn[T] NativeLocalJournalCapture::with_runtime_binding_access(
  self : NativeLocalJournalCapture,
  operation : (NativeLocalHostConnection, NativeLocalRuntimeBindingAccess) -> Result[
    T,
    NativeClientRunJournalIssue,
  ],
) -> Result[T, NativeLocalAdoptionIssue] {
  match self.check_current_in_original_read() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard self.opening is JournalAcquired(host) &&
    self.original_resources is Some(original) else {
    return Err(OriginalResourceScopePending)
  }
  let queries : NativeLocalJournalReadQueries = {
    original,
    database: host.database,
    failure: None,
    invalidate_snapshot: () => host.journal.admitted_adoption = None,
  }
  let material = () => {
    @host.bind_client_local_adopted_host_material(host.database, () => {
      host.current_adoption_material_with_reads(
        () => self.check_current_in_original_read(),
        reads=Some(queries.access()),
      )
    }).map_err(local_current_material_issue)
  }
  let access : NativeLocalRuntimeBindingAccess = {
    scope: (principal, connection) => {
      match material() {
        Err(issue) => Err(issue)
        Ok(value) =>
          match
            @host.client_local_adopted_authority_scope_body(
              value,
              host.database,
              principal,
              connection,
            ) {
            Err(issue) => Err(local_current_material_issue(issue))
            Ok(body) => local_adoption_digest(host.epoch.crypto, body)
          }
      }
    },
    read_allowed: (principal, connection) => {
      match material() {
        Err(_) => false
        Ok(value) =>
          @host.client_local_adopted_account_outcome(value, host.database, {
            principal,
            connection,
            resource: "run",
            operation: "read",
          })
          is Ok(@authorization.Allow(_))
      }
    },
    selected: name => {
      match self.selected_configuration_in_original_read(name) {
        Err(_) => Err(CustodyLost)
        Ok(body) =>
          match
            host.session.settings.files
            .iter()
            .find_first(file => file.name == name && file.body == body) {
            Some(file) => Ok(file)
            None => Err(CustodyLost)
          }
      }
    },
  }
  let result = operation(host, access)
  match (queries.failure, self.read_operation_issue) {
    (Some(issue), _) => {
      self.read_operation_issue = Some(issue)
      Err(issue)
    }
    (None, Some(issue)) => Err(issue)
    (None, None) => result.map_err(issue => Journal(issue))
  }
}

///|
/// Bind the same captured Runtime using this acquired Journal's original
/// current material and Account read decision. This neither migrates an old
/// cohort nor prepares or dispatches a Run.
pub fn NativeLocalJournalCapture::bind_packaged_runtime_in_original_read(
  self : NativeLocalJournalCapture,
  current : NativeLocalPackagedRuntime,
  principal : String,
  connection : String,
  environment_file : String,
  run_file : String,
  runtime_file : String,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  self.with_runtime_binding_access((host, access) => {
    host.bind_packaged_runtime_with_access(
      current, principal, connection, environment_file, run_file, runtime_file, access,
    )
  })
}

///|
/// The unchanged cohort needs no migration. Historical operational witnesses
/// remain unavailable, just as at the original binding entrance; a scalar pair
/// or caller label cannot select an unsupported upgrade through this route.
pub fn NativeLocalJournalCapture::require_packaged_runtime_upgrade_in_original_read(
  self : NativeLocalJournalCapture,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  self.with_runtime_binding_access((host, access) => {
    match host.packaged_runtime {
      None => Ok(())
      Some(binding) => {
        if !local_runtime_binding_current_with_access(binding, access) {
          return Err(CustodyLost)
        }
        match binding.pair {
          None => Ok(())
          Some(_) => require_local_historical_runtime_implementation()
        }
      }
    }
  })
}

///|
/// The original selected cohort needs no historical replacement pair. Keep
/// the existing pure no-pair result after actual Runtime/current observation;
/// historical pair routes still require their unsupported original witness.
pub fn NativeLocalJournalCapture::runtime_submission_assets_in_original_read(
  self : NativeLocalJournalCapture,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  max_work : Int,
) -> Result[NativeLocalRuntimeSubmission, NativeLocalAdoptionIssue] {
  self.with_runtime_binding_access((host, access) => {
    guard host.packaged_runtime is Some(binding) &&
      local_runtime_binding_current_with_access(binding, access) else {
      return Err(CustodyLost)
    }
    if binding.pair is Some(_) {
      return Err(UnsupportedPreparation)
    }
    // This exact existing branch performs no SQL, epoch or Runtime acquisition.
    host.packaged_runtime_assets_for_submission(
      reference, preparation, max_work,
    )
  })
}
