///|
/// Bind only the original admitted Run under the same captured Submit Account
/// and actual Journal transaction, before first start. No Store/read grant is
/// issued and a different retained binding is not replaced.
pub fn NativeLocalJournalCapture::bind_installed_publication_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  publication : NativeClientCancellationPublication,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    let authority = match
      native_local_policy_authority_for(
        host,
        self.crypto,
        principal,
        connection,
        request,
        SubmitOriginals,
        capture=Some(self),
      ) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    host.journal
    .bind_installed_publication_with_operations(
      request,
      publication,
      () => authority.current_for(host.journal, request),
      operations=Some(operations),
    )
    .map_err(issue => Journal(issue))
  })
}

///|
/// Retain an actual Store observation from this same original publisher. The
/// existing independent RunRead Account, reference/request join, CAS and
/// terminal current checks remain with their existing Owners.
pub fn NativeLocalJournalCapture::retain_observed_run_state_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  observed : NativeLocalObservedRunState,
  now : Double,
) -> Result[NativeClientSavedRunState, NativeLocalAdoptionIssue] {
  guard observed.publisher.authority.capture is Some(capture) &&
    physical_equal(capture, self) &&
    observed.publisher.operation is Some(operation) &&
    physical_equal(operation.receiver.capture, self) else {
    return Err(Journal(ForeignRun))
  }
  self.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    host
    .retain_submitted_run_state_with_operations(
      self.crypto,
      principal,
      connection,
      reference,
      request,
      observed,
      now,
      operations=Some(operations),
      capture=Some(self),
    )
    .map_err(issue => Journal(issue))
  })
}
