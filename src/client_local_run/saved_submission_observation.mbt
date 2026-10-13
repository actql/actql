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
) -> Result[
  LocalSavedSubmissionObservation,
  LocalSavedSubmissionObservationIssue[E],
] {
  // Refuse a foreign nominal owner before observing any physical row.
  if !physical_equal(rows.plan, plan) ||
    !physical_equal(rows.preparation, preparation) {
    return Err(Rows(ForeignPreparation))
  }
  let snapshot = match
    @host.inspect_client_saved_submission(
      rows.reference,
      max_records,
      scan,
      read,
      validate_run,
      confirm_cancellation,
      custody_lost,
    ) {
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
  match
    validate_local_saved_submitted_rows(
      rows,
      plan,
      preparation,
      run.key,
      run.revision,
      run.body,
      submission.key,
      submission.revision,
      submission.body,
    ) {
    Ok(_) => Ok({ rows, plan, preparation, snapshot, })
    Err(issue) => Err(Rows(issue))
  }
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
