///|
// Only this Native Host assembly constructs the authority binding. No public
// operation accepts a caller-provided allow callback inside a transaction.
priv enum NativeLocalPolicyAuthorityPurpose {
  SubmitOriginals
  PublishRun
  ReadRunMaterials
  ReadResultPolicy(String)
}

///|
priv struct NativeLocalPolicyAuthority {
  host : NativeLocalHostConnection
  crypto : @crypto.Library
  principal : String
  connection : String
  scope : String
  purpose : NativeLocalPolicyAuthorityPurpose
}

///|
fn NativeLocalPolicyAuthority::current_for(
  self : NativeLocalPolicyAuthority,
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
) -> Bool {
  if !physical_equal(self.host.journal, journal) ||
    @host.client_request_authority_scope_cid(request) != self.scope {
    return false
  }
  // Fresh only for this synchronous predicate. Each Common operation still
  // observes actual current custody before and after its scope/Account work.
  let material = match self.host.adopted_current_material() {
    Ok(value) => value
    Err(_) => return false
  }
  let scope = {
    let body = match
      @host.client_local_adopted_authority_scope_body(
        material,
        self.host.database,
        self.principal,
        self.connection,
      ) {
      Ok(value) => value
      Err(_) => return false
    }
    match local_adoption_digest(self.crypto, body) {
      Ok(value) => value
      Err(_) => return false
    }
  }
  if scope != self.scope {
    return false
  }
  let operation = match self.purpose {
    SubmitOriginals => "submit"
    PublishRun => "publish"
    ReadRunMaterials | ReadResultPolicy(_) => "read"
  }
  if !(@host.client_local_adopted_account_outcome(
      material,
      self.host.database,
      {
        principal: self.principal,
        connection: self.connection,
        resource: "run",
        operation,
      },
    )
    is Ok(@authorization.Allow(_))) {
    return false
  }
  match self.purpose {
    SubmitOriginals | PublishRun | ReadRunMaterials => true
    ReadResultPolicy(name) =>
      @host.client_local_adopted_account_outcome(material, self.host.database, {
        principal: self.principal,
        connection: self.connection,
        resource: "result/" + name,
        operation: "read",
      })
      is Ok(@authorization.Allow(_))
  }
}

///|
fn native_local_policy_authority_for(
  host : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  purpose : NativeLocalPolicyAuthorityPurpose,
) -> Result[NativeLocalPolicyAuthority, NativeClientRunJournalIssue] {
  if purpose is ReadResultPolicy(name) &&
    (name.is_empty() || name.length() > 128) {
    return Err(AuthorizationDenied)
  }
  let authority : NativeLocalPolicyAuthority = {
    host,
    crypto,
    principal,
    connection,
    scope: @host.client_request_authority_scope_cid(request),
    purpose,
  }
  if !authority.current_for(host.journal, request) {
    return Err(AuthorizationDenied)
  }
  Ok(authority)
}

///|
// Preserve the existing submit and named-Result Policy entry semantics.
fn native_local_policy_authority(
  host : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  result_name : String?,
) -> Result[NativeLocalPolicyAuthority, NativeClientRunJournalIssue] {
  native_local_policy_authority_for(
    host,
    crypto,
    principal,
    connection,
    request,
    match result_name {
      None => SubmitOriginals
      Some(name) => ReadResultPolicy(name)
    },
  )
}

///|
/// Bound to the real adopted Host and its current submit Account tuple. The
/// original checked compilation/Run is still verified by the journal Owner.
pub fn NativeLocalHostConnection::retain_publication_policy_originals(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  let authority = match
    native_local_policy_authority(
      self,
      crypto,
      principal,
      connection,
      request,
      None,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.journal.retain_publication_policy_originals(
    request, prepared, compiled, definition, authority,
  )
}

///|
/// Current Run and named-Result read tuples are separate from submit/Source
/// permission and the retained Policy. Lookup grants no bytes or execution.
pub fn NativeLocalHostConnection::lookup_publication_policy_original(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  result_name : String,
  actual_policy_cid : String,
) -> Result[
  @publication.CapturedEffectDependencyBody,
  NativeClientRunJournalIssue,
] {
  let authority = match
    native_local_policy_authority(
      self,
      crypto,
      principal,
      connection,
      request,
      Some(result_name),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.journal.lookup_publication_policy_original(
    request, actual_policy_cid, authority,
  )
}
