///|
// One closed Runtime binding operation uses one actual Journal snapshot.
// Scope, Account and selected-file getters consume the same admitted facts;
// the retained original port still checks physical Read lifetime on each use.
fn[T] NativeLocalJournalCapture::with_runtime_binding_access(
  self : NativeLocalJournalCapture,
  operation : (NativeLocalHostConnection, NativeLocalRuntimeBindingAccess) -> Result[
    T,
    NativeClientRunJournalIssue,
  ],
) -> Result[T, NativeLocalAdoptionIssue] {
  let result = self.with_current_adoption_material_in_original_read((
    host,
    material,
    operations,
  ) => {
    host.journal
    .transaction_with_reads(
      () => {
        let access : NativeLocalRuntimeBindingAccess = {
          runtime_current: runtime => {
            if self.read_callback_active && self.read_facts_valid {
              runtime.local_runtime_require_live() is Ok(_)
            } else {
              runtime.check_current() is Ok(_)
            }
          },
          scope: (principal, connection) => {
            self.operation_scope(host, material, principal, connection)
          },
          read_allowed: (principal, connection) => {
            self.operation_account(host, material, {
              principal,
              connection,
              resource: "run",
              operation: "read",
            })
            is Ok(@authorization.Allow(_))
          },
          selected: name => {
            // The current original above admitted this immutable settings
            // list in the same snapshot. No caller callback or mutation is
            // dispatched between that observation and this pure selection.
            match
              host.session.settings.files
              .iter()
              .find_first(file => file.name == name) {
              Some(file) => Ok(file)
              None => Err(CustodyLost)
            }
          },
        }
        with_local_runtime_binding_frame(
          access,
          () => {
            match self.check_original_read_lifetime() {
              Ok(_) => true
              Err(issue) => {
                if self.read_operation_issue is None {
                  self.read_operation_issue = Some(issue)
                }
                false
              }
            }
          },
          retained => operation(host, retained),
        )
      },
      reads=Some(operations.reads),
    )
    .map_err(issue => Journal(issue))
  })
  match result {
    Err(issue) => Err(issue)
    Ok(value) =>
      // Physical Runtime observation and binding return are the boundary for
      // external configuration/current changes. Never retain this snapshot
      // across the next operation, close or a failed original return.
      self.check_current_in_original_read().map(_ => value)
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
