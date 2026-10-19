///|
// Only the current captured Read may invoke this observation. The same
// physical Journal queries leave/reenter that Read around every SQLite call;
// no candidate row, cached currentness or caller Allow replaces the original.
fn[T] NativeLocalJournalCapture::with_current_adoption_material_in_original_read(
  self : NativeLocalJournalCapture,
  operation : (
    NativeLocalHostConnection,
    @host.ClientLocalAdoptedHostMaterial[
      @sqlite.Database,
      NativeLocalAdoptionIssue,
    ],
  ) -> Result[T, NativeLocalAdoptionIssue],
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
  }
  let result = match
    @host.bind_client_local_adopted_host_material(host.database, () => {
      host.current_adoption_material_with_reads(
        () => self.check_current_in_original_read(),
        reads=Some(queries.access()),
      )
    }) {
    Err(issue) => Err(local_current_material_issue(issue))
    Ok(material) => operation(host, material)
  }
  match (queries.failure, self.read_operation_issue) {
    (Some(issue), _) => {
      self.read_operation_issue = Some(issue)
      Err(issue)
    }
    (None, Some(issue)) => Err(issue)
    (None, None) => result
  }
}

///|
/// The same adopted configuration/caller scope under the original Read. This
/// observes identity only; it issues no Submission, execution supply or grant.
pub fn NativeLocalJournalCapture::authority_scope_cid_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
) -> Result[String, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((host, material) => {
    let body = match
      @host.client_local_adopted_authority_scope_body(
        material,
        host.database,
        principal,
        connection,
      ) {
      Ok(body) => body
      Err(issue) => return Err(local_current_material_issue(issue))
    }
    local_adoption_digest(self.crypto, body)
  })
}

///|
/// Repeat the existing Account Owner decision against current original
/// adoption material. Neither a scope CID nor this observation funds work.
pub fn NativeLocalJournalCapture::authorize_in_original_read(
  self : NativeLocalJournalCapture,
  request : @authorization.AccessTuple,
) -> Result[@authorization.AccountOutcome, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((host, material) => {
    @host.client_local_adopted_account_outcome(material, host.database, request).map_err(
      local_current_material_issue,
    )
  })
}
