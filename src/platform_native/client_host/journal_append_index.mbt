///|
// Explicit bounded compatibility collection. No ordinary open/read enters it.
fn NativeClientRunJournal::collect_legacy_append_usage_locked(
  self : NativeClientRunJournal,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[
  (
    Bytes,
    (Int, Int64),
    Array[(NativeClientSubmissionReference, NativeClientRunRecord)],
  ),
  NativeClientRunJournalIssue,
] {
  if !self.transaction_active {
    return Err(CustodyLost)
  }
  let reads = operations.map(value => value.reads)
  let runs : Map[String, NativeClientRunRecord] = Map([])
  let (run_count, run_revision) = match
    run_journal_custody(
      self.database,
      self.max_records,
      reads~,
      observe=Some((key, run) => {
        runs[key] = run
        Ok(())
      }),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if run_count.to_int64() != run_revision {
    return Err(CustodyLost)
  }
  let references : Array[
    (NativeClientSubmissionReference, NativeClientRunRecord),
  ] = []
  let (count, bytes, revision) = match
    self.submitted_intent_custody(
      reads~,
      runs=Some(runs),
      observe=Some(original => {
        if original.run_admission is Some((request, _, _)) {
          let run = match runs.get(@host.client_request_scope_cid(request)) {
            Some(value) => value
            None => return Err(CustodyLost)
          }
          references.push(
            (native_submission_reference_record(original.reference), run),
          )
        }
        Ok(())
      }),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if count.to_int64() != revision {
    return Err(CustodyLost)
  }
  let body = match
    @host.client_submitted_journal_usage_body(count, bytes, self.max_records) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  Ok((body, (count, revision), references))
}
