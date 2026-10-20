///|
/// Authenticated saved compiler metadata, not current permission, a restored
/// compilation, execution measurements or an operation that can start a Run.
struct NativeClientSavedRunPlan {
  original : NativeClientOriginalRunSelection
  view : String
}

///|
pub fn NativeClientSavedRunPlan::original(
  self : NativeClientSavedRunPlan,
) -> NativeClientOriginalRunSelection {
  self.original
}

///|
pub fn NativeClientSavedRunPlan::wire(
  self : NativeClientSavedRunPlan,
) -> String {
  self.view
}

///|
fn NativeLocalHostConnection::lookup_submitted_run_plan_by_id_with_operations(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  run_id : String,
  operations? : NativeClientJournalOperationAccess? = None,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[NativeClientSavedRunPlan, NativeClientSavedRunStateIssue] {
  let selected = match
    self.select_original_run_id(
      crypto,
      principal,
      connection,
      run_id,
      operations~,
      capture~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let current = () => {
    saved_run_selection_current(
      self,
      crypto,
      principal,
      connection,
      selected.scope,
      capture~,
    )
  }
  let reads = operations.map(value => value.reads)
  let view = match
    self.journal.transaction_with_reads(
      () => {
        if !current() {
          return Err(AuthorizationDenied)
        }
        let run = match self.journal.retained(selected.request, reads~) {
          Ok(Some(value)) => value
          Ok(None) => return Err(CustodyLost)
          Err(issue) => return Err(issue)
        }
        if @publication.publication_contract_identity(run.definition) !=
          @publication.publication_contract_identity(selected.definition) {
          return Err(ForeignRun)
        }
        let plan = match run.run_observation_originals {
          None => None
          Some(wire) => {
            let fields = match
              native_run_observation_fields(wire, [
                "authorization", "plan", "prepared",
              ]) {
              Ok(value) => value
              Err(issue) => return Err(issue)
            }
            match epoch_text(fields, "plan") {
              None => None
              Some(wire) => {
                let original = match
                  read_native_run_plan_original(
                    wire,
                    run.definition,
                    Some(@host.client_request_program_cid(run.request)),
                  ) {
                  Ok(value) => value
                  Err(issue) => return Err(issue)
                }
                Some(original.view)
              }
            }
          }
        }
        if !current() {
          return Err(AuthorizationDenied)
        }
        Ok(plan)
      },
      reads~,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(Unavailable)
    Err(issue) => return Err(Journal(issue))
  }
  if !current() {
    return Err(Journal(AuthorizationDenied))
  }
  Ok({ original: selected, view, })
}

///|
/// Read only the original stored map through this Host's independently current
/// RunRead. Missing legacy plan evidence stays unavailable without recapture.
pub fn NativeLocalHostConnection::lookup_submitted_run_plan_by_id(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  run_id : String,
) -> Result[NativeClientSavedRunPlan, NativeClientSavedRunStateIssue] {
  self.lookup_submitted_run_plan_by_id_with_operations(
    crypto, principal, connection, run_id,
  )
}

///|
/// Same original Read/SQL route as saved status. The outer result preserves
/// scope/return failure independently of the inner saved-metadata refusal.
pub fn NativeLocalJournalCapture::lookup_submitted_run_plan_by_id_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  run_id : String,
) -> Result[
  Result[NativeClientSavedRunPlan, NativeClientSavedRunStateIssue],
  NativeLocalAdoptionIssue,
] {
  self.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    Ok(
      host.lookup_submitted_run_plan_by_id_with_operations(
        self.crypto,
        principal,
        connection,
        run_id,
        operations=Some(operations),
        capture=Some(self),
      ),
    )
  })
}
