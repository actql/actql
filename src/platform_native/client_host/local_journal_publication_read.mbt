///|
/// Retain only the same checked Program/Run's Policy originals through the
/// existing submission Account and same Journal transaction. No publication,
/// Store payload, grant or physical-start claim is created here.
pub fn NativeLocalJournalCapture::retain_publication_policy_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[NativeClientRunRecord, NativeLocalAdoptionIssue] {
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
    .retain_publication_policy_originals(
      request,
      prepared,
      compiled,
      definition,
      authority,
      operations=Some(operations),
    )
    .map_err(issue => Journal(issue))
  })
}

///|
/// Resolve the retained Policy under independent current Run and named-Result
/// read tuples. Matching body/CID is never a payload or Store permission.
pub fn NativeLocalJournalCapture::lookup_publication_policy_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  result_name : String,
  actual_policy_cid : String,
) -> Result[@publication.CapturedEffectDependencyBody, NativeLocalAdoptionIssue] {
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
        ReadResultPolicy(result_name),
        capture=Some(self),
      ) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    host.journal
    .lookup_publication_policy_original(
      request,
      actual_policy_cid,
      authority,
      reads=Some(operations.reads),
    )
    .map_err(issue => Journal(issue))
  })
}

///|
/// Observe the actual adopted managed path under the captured full current
/// fence. Filesystem opens/ownership and their cleanup remain separate duties.
pub fn NativeLocalJournalCapture::managed_root_path_in_original_read(
  self : NativeLocalJournalCapture,
) -> Result[String?, NativeLocalAdoptionIssue] {
  match self.check_current_in_original_read() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard self.opening is JournalAcquired(host) else { return Err(CustodyLost) }
  Ok(host.session.settings.managed.map(root => root.path))
}

///|
/// Resolve the actual committed Artifact's Policy through this same original
/// Read/SQL exchange. Store facts and retained Policy bodies must still join
/// the original Run and current independent named-Result Account authority.
/// No disclosure admission, grant, payload or receipt is issued here.
pub fn NativeLocalJournalCapture::resolve_result_policy_original_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  store : @publication_store.Store,
  facts : @result_access.NativeResultReadFacts,
) -> Result[@publication.CapturedEffectDependencyBody, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    host
    .resolve_result_policy_original_with_operations(
      self.crypto,
      principal,
      connection,
      request,
      store,
      facts,
      operations=Some(operations),
      capture=Some(self),
    )
    .map_err(issue => Journal(issue))
  })
}
