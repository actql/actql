///|
pub(all) enum LocalSavedSubmissionObservationIssue[E] {
  Rows(LocalSubmittedRunRowsIssue)
  Inspection(E)
  UnresolvedHistory
  NotAdmitted
}

///|
/// The exact observed saved rows stay bound to their original nominal input.
/// This object is read-only: it is not a COMMIT ACK, current-authority grant,
/// dispatch/physical-start permit, terminal Run, Result or resource release.
pub struct LocalSavedSubmissionObservation {
  rows : LocalSubmittedRunRows
  plan : LocalRunPlan
  preparation : @input.LocalSubmittedPreparation
  snapshot : @host.ClientSavedSubmissionSnapshot
}

///|
/// Consume the original full-inventory and saved-row observations. The trusted
/// Host holds the same physical snapshot, authenticated epoch/current scope
/// and input/workspace loans; its original semantic validators are mandatory.
/// No count/partial-scan/earlier candidate can stand in for actual saved bytes.
pub fn[E] inspect_local_saved_submission(
  rows : LocalSubmittedRunRows,
  plan : LocalRunPlan,
  preparation : @input.LocalSubmittedPreparation,
  max_records : Int,
  scan : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  validate_run : (@host.ClientJournalPhysicalRow) -> Result[
    @host.ClientRunJournalInspection,
    E,
  ],
  confirm_cancellation : () -> Result[Unit, E],
  custody_lost : E,
  task_material_count? : ((Int) -> Result[Bool?, E])? = None,
) -> Result[
  LocalSavedSubmissionObservation,
  LocalSavedSubmissionObservationIssue[E],
] {
  observe_local_saved_submission(rows, plan, preparation, () => {
    @host.inspect_client_saved_submission(
      rows.reference,
      max_records,
      scan,
      read,
      validate_run,
      confirm_cancellation,
      custody_lost,
      task_material_count~,
    )
  })
}

///|
/// Confirm the exact first committed rows of this live checked issuer. The
/// writer already validated the full predecessor in its transaction. Require
/// the actual same-reader Run, Submission, Task materials, and locator here.
pub fn[E] read_local_first_saved_submission(
  rows : LocalSubmittedRunRows,
  plan : LocalRunPlan,
  preparation : @input.LocalSubmittedPreparation,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  validate_run : (@host.ClientJournalPhysicalRow) -> Result[
    @host.ClientRunJournalInspection,
    E,
  ],
  custody_lost : E,
) -> Result[
  LocalSavedSubmissionObservation,
  LocalSavedSubmissionObservationIssue[E],
] {
  let first_read = (table, key) => {
    read(table, key).bind(observed => {
      guard observed is Some(row) else { return Ok(None) }
      if (table == "client_runs" &&
          (row.revision != 0L || row.body != rows.run)) ||
        (table == "client_submitted_intents" &&
          (row.revision != 1L || row.body != rows.submitted)) {
        return Err(custody_lost)
      }
      Ok(observed)
    })
  }
  observe_local_saved_submission(rows, plan, preparation, () => {
    @host.read_client_saved_submission_with_task_original(
      rows.reference, first_read, validate_run, custody_lost, rows.task_materials,
    )
  }).bind(original => {
    confirm_local_saved_submission_locator(rows, plan, read, custody_lost)
    .map(_ => original)
  })
}

///|
fn[E] confirm_local_saved_submission_locator(
  rows : LocalSubmittedRunRows,
  plan : LocalRunPlan,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  custody_lost : E,
) -> Result[Unit, LocalSavedSubmissionObservationIssue[E]] {
  let (key, body) = match @host.client_saved_run_reference_locator(
    rows.reference, plan.request, plan.definition,
  ) {
    Ok(value) => value
    Err(_) => return Err(Rows(CustodyLost))
  }
  match read("client_run_reference_index", key) {
    Ok(Some(row)) if row.key == key && row.revision == 0L && row.body == body =>
      Ok(())
    Err(issue) => Err(Inspection(issue))
    _ => Err(Inspection(custody_lost))
  }
}

///|
/// Reobserve the local continuation using its retained row issuer.
/// After checking the original Run and locator, follow only the
/// cancellation head admitted from that Run's current bytes.
pub fn[E] read_local_current_saved_submission(
  rows : LocalSubmittedRunRows,
  plan : LocalRunPlan,
  preparation : @input.LocalSubmittedPreparation,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  validate_run : (@host.ClientJournalPhysicalRow) -> Result[
    @host.ClientRunJournalInspection,
    E,
  ],
  custody_lost : E,
  require_claimed? : Bool = false,
  row_original? : (() -> @host.ClientRunJournalRowOriginal?)? = None,
) -> Result[
  LocalSavedSubmissionObservation,
  LocalSavedSubmissionObservationIssue[E],
] {
  observe_local_saved_submission(
    rows,
    plan,
    preparation,
    () => {
      @host.read_client_saved_submission_with_task_original(
        rows.reference,
        read,
        validate_run,
        custody_lost,
        rows.task_materials,
      )
    },
    require_claimed~,
    row_original~,
    confirm=Some((revision, head, publication_binding) => {
      match
        confirm_local_saved_submission_locator(rows, plan, read, custody_lost) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      guard head is Some(accepted) else { return Ok(()) }
      guard @publication.run_definition_namespace(plan.definition)
        is Some(namespace_id) else {
        return Err(Rows(CustodyLost))
      }
      @host.observe_client_accepted_cancellation_head(
        accepted,
        namespace_id,
        {
          request: plan.request,
          definition: plan.definition,
          revision,
          cancellation_requested: true,
          publication_binding,
        },
        read,
        custody_lost,
      )
      .map(_ => ())
      .map_err(issue => Inspection(issue))
    }),
  )
}

///|
fn[E] observe_local_saved_submission(
  rows : LocalSubmittedRunRows,
  plan : LocalRunPlan,
  preparation : @input.LocalSubmittedPreparation,
  observe : () -> Result[@host.ClientSavedSubmissionSnapshot?, E],
  require_claimed? : Bool = false,
  row_original? : (() -> @host.ClientRunJournalRowOriginal?)? = None,
  confirm? : ((Int64, @host.ClientAcceptedCancellationHead?, String?) -> Result[
    Unit,
    LocalSavedSubmissionObservationIssue[E],
  ])? = None,
) -> Result[
  LocalSavedSubmissionObservation,
  LocalSavedSubmissionObservationIssue[E],
] {
  if !physical_equal(rows.plan, plan) ||
    !physical_equal(rows.preparation, preparation) {
    return Err(Rows(ForeignPreparation))
  }
  let snapshot = match observe() {
    Ok(Some(value)) => value
    Ok(None) => return Err(UnresolvedHistory)
    Err(issue) => return Err(Inspection(issue))
  }
  let record = @host.client_saved_submission_record(snapshot)
  guard record.run_admission is Some(_) else { return Err(NotAdmitted) }
  guard @host.client_saved_submission_run_row(snapshot) is Some(run) else {
    return Err(Rows(CustodyLost))
  }
  let submission = @host.client_saved_submission_row(snapshot)
  // This optional port can lend only a Common-admitted original from the
  // same Run inspection. Match the physical body before using typed DATA.
  let original = match row_original {
    None => None
    Some(retained) =>
      match retained() {
        Some(value) if @host.client_run_journal_row_original_matches(value, run.body) =>
          Some(value)
        _ => return Err(Rows(CustodyLost))
      }
  }
  match
    local_saved_submitted_row_originals(
      rows,
      plan,
      preparation,
      run.key,
      run.revision,
      run.body,
      submission.key,
      submission.revision,
      submission.body,
      decode_run=body => {
        @host.decode_client_run_journal_row_with_observation_originals(
          body, original~,
        )
      },
    ) {
    Ok((actual, _, _)) => {
      if require_claimed &&
        (!actual.dispatch_reserved || !actual.physical_start_claimed) {
        return Err(Rows(CustodyLost))
      }
      if confirm is Some(confirm) {
        match
          confirm(
            run.revision,
            actual.cancellation_head,
            actual.publication_binding,
          ) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      }
      Ok({ rows, plan, preparation, snapshot, })
    }
    Err(issue) => Err(Rows(issue))
  }
}

///|
/// Borrow the validated physical snapshot under the same nominal Plan and
/// preparation. This carries no Account decision, authorization or Store ACK.
pub fn local_saved_submission_snapshot(
  value : LocalSavedSubmissionObservation,
  rows : LocalSubmittedRunRows,
  plan : LocalRunPlan,
  preparation : @input.LocalSubmittedPreparation,
) -> Result[@host.ClientSavedSubmissionSnapshot, LocalSubmittedRunRowsIssue] {
  if !physical_equal(value.rows, rows) ||
    !physical_equal(value.plan, plan) ||
    !physical_equal(value.preparation, preparation) {
    return Err(ForeignPreparation)
  }
  Ok(value.snapshot)
}

///|
/// Read the original immutable admission and actual observed revisions. The
/// Host must still recheck current authority for any subsequent operation.
pub fn local_saved_submission_revisions(
  value : LocalSavedSubmissionObservation,
  rows : LocalSubmittedRunRows,
  plan : LocalRunPlan,
  preparation : @input.LocalSubmittedPreparation,
) -> Result[(Int64, Int64, Int64), LocalSubmittedRunRowsIssue] {
  if !physical_equal(value.rows, rows) ||
    !physical_equal(value.plan, plan) ||
    !physical_equal(value.preparation, preparation) {
    return Err(ForeignPreparation)
  }
  let record = @host.client_saved_submission_record(value.snapshot)
  guard record.run_admission is Some((_, _, original_revision)) &&
    @host.client_saved_submission_run_row(value.snapshot) is Some(run) else {
    return Err(CustodyLost)
  }
  Ok(
    (
      original_revision,
      run.revision,
      @host.client_saved_submission_revision(value.snapshot),
    ),
  )
}

///|
/// Transfer the original saved admission, not the candidate write or current
/// control revision. The same nominal Plan/input/rows and current Host frame
/// remain required; the caller retains all loans until explicit cleanup.
pub fn local_saved_submission_admission_wire(
  value : LocalSavedSubmissionObservation,
  rows : LocalSubmittedRunRows,
  plan : LocalRunPlan,
  preparation : @input.LocalSubmittedPreparation,
) -> Result[String, @host.ClientSavedSubmissionViewIssue] {
  if !physical_equal(value.rows, rows) ||
    !physical_equal(value.plan, plan) ||
    !physical_equal(value.preparation, preparation) {
    return Err(@host.CustodyLost)
  }
  @host.client_saved_submission_admission_wire(value.snapshot)
}
