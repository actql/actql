///|
priv struct LocalSavedSDKReadSource {
  request : @host.ClientRequestIdentity
  finite_original : Bytes
  definition : @publication.PublicationContract
  publication_request_cid : String
  policy : @publication.CapturedEffectDependencyBody
  principal : String
  connection : String
  adoption_cid : String
  owner : @publication.PublicationCommitPreparation
  view : @publication.PublicationCommitReadView
  index_cid : String
}

///|
priv enum LocalSDKReadOrigin {
  Live(LocalPublicationPreflight)
  Saved(LocalSavedSDKReadSource)
}

///|
/// An original read source inside the existing Local read Owner. It is neither
/// an executable plan nor current authority. Every use still evaluates the
/// current Account and requires the same nominal stored-chain view; the Host
/// separately retains and checks its actual adoption/Store/physical frame.
struct LocalSDKReadSource {
  origin : LocalSDKReadOrigin
}

///|
fn live_sdk_read_source(
  preflight : LocalPublicationPreflight,
) -> LocalSDKReadSource {
  { origin: Live(preflight), }
}

///|
/// Restore only the original saved read metadata. Do not parse/compile the
/// current project, construct a LocalRunPlan, start work or issue a replacement
/// Policy. Missing first-admission originals remain unavailable. A completed
/// commit view does not by itself establish payload availability or a grant.
pub fn prepare_local_saved_sdk_read_source(
  snapshot : @host.ClientSavedSubmissionSnapshot,
  finite : @host.ClientLocalRunPolicyOriginal,
  source_policy : (String, String),
  account : @authorization.AdmittedAccountConfiguration,
  principal : String,
  connection : String,
  adoption_cid : String,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
) -> Result[LocalSDKReadSource, LocalSDKReadOriginalsIssue] {
  guard @host.client_saved_submission_run_row(snapshot) is Some(row) &&
    @host.decode_client_run_journal_row_with_observation_originals(row.body)
    is Ok((run, Some(policy_wire), Some(observation_wire))) &&
    @host.client_local_run_policy_original_body(finite) ==
    @utf8.encode(policy_wire) &&
    @host.validate_client_local_run_policy_original_run(
      @host.client_local_run_policy_original_body(finite),
      run.request,
      run.definition,
    )
    is Ok(_) &&
    @host.restore_client_run_observation_originals_wire(
      run.definition,
      observation_wire,
      131072,
      8192,
      64,
    )
    is Ok(_) else {
    return Err(InvalidOriginal)
  }
  let index = match owner.finish_observed_commit(view) {
    Ok(value) => value
    Err(issue) => return Err(StoredChain(Commit(issue)))
  }
  let projected = match @publication.project_public_index_read(index) {
    Ok(value) => value
    Err(issue) => return Err(Projection(issue))
  }
  let definition = match owner.view_contract(view, 0) {
    Ok(value) => value
    Err(issue) => return Err(StoredChain(Commit(issue)))
  }
  if @publication.publication_contract_json(definition) !=
    @publication.publication_contract_json(run.definition) ||
    projected.run_definition_cid !=
    @publication.publication_contract_identity(definition) ||
    projected.authority_scope_cid !=
    @host.client_request_authority_scope_cid(run.request) {
    return Err(InvalidOriginal)
  }
  let (adoption, _) = match
    @host.client_local_run_policy_original_read_dependencies(finite) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  if adoption != adoption_cid {
    return Err(InvalidOriginal)
  }
  let policy = match
    @host.admit_source_free_result_policy_body(
      source_policy.0,
      source_policy.1,
      65536,
      8192,
      64,
    ) {
    Ok(value) => value
    Err(_) => return Err(PolicyUnavailable)
  }
  let source : LocalSDKReadSource = {
    origin: Saved({
      request: run.request,
      finite_original: @host.client_local_run_policy_original_body(finite),
      definition,
      publication_request_cid: projected.publication_request_cid,
      policy,
      principal,
      connection,
      adoption_cid,
      owner,
      view,
      index_cid: @publication.publication_contract_identity(index),
    }),
  }
  let manifest = match owner.view_contract(view, 2) {
    Ok(value) => value
    Err(issue) => return Err(StoredChain(Commit(issue)))
  }
  let names = match @publication.manifest_result_names(manifest) {
    Ok(value) => value
    Err(issue) => return Err(Projection(issue))
  }
  // Each operation selects its own Result later; this constructor establishes
  // Run-read and exact current scope without inventing a default Result name.
  if names.is_empty() {
    return Err(InvalidOriginal)
  }
  match source.validate_run_current(account) {
    Ok(_) => Ok(source)
    Err(issue) => Err(issue)
  }
}

///|
fn LocalSDKReadSource::request(
  self : LocalSDKReadSource,
) -> @host.ClientRequestIdentity {
  match self.origin {
    Live(value) => value.intent.plan.request
    Saved(value) => value.request
  }
}

///|
fn LocalSDKReadSource::definition(
  self : LocalSDKReadSource,
) -> @publication.PublicationContract {
  match self.origin {
    Live(value) => value.intent.plan.definition
    Saved(value) => value.definition
  }
}

///|
fn LocalSDKReadSource::publication_request_cid(
  self : LocalSDKReadSource,
) -> String {
  match self.origin {
    Live(value) =>
      @publication.publication_contract_identity(value.intent.request)
    Saved(value) => value.publication_request_cid
  }
}

///|
fn LocalSDKReadSource::principal_connection(
  self : LocalSDKReadSource,
) -> (String, String) {
  match self.origin {
    Live(value) =>
      (value.intent.plan.tuple.principal, value.intent.plan.tuple.connection)
    Saved(value) => (value.principal, value.connection)
  }
}

///|
fn LocalSDKReadSource::source_policy(
  self : LocalSDKReadSource,
) -> @publication.CapturedEffectDependencyBody? {
  match self.origin {
    Live(value) =>
      @host.client_compiled_run_source_free_result_policy_body(
        value.intent.plan.compiled,
      )
    Saved(value) => Some(value.policy)
  }
}

///|
fn LocalSDKReadSource::validate_view(
  self : LocalSDKReadSource,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
) -> Result[Unit, LocalSDKReadOriginalsIssue] {
  match self.origin {
    Live(_) => Ok(())
    Saved(value) => {
      if !physical_equal(value.owner, owner) ||
        !physical_equal(value.view, view) {
        return Err(InvalidOriginal)
      }
      match owner.finish_observed_commit(view) {
        Ok(index) if @publication.publication_contract_identity(index) ==
          value.index_cid => Ok(())
        Err(issue) => Err(StoredChain(Commit(issue)))
        _ => Err(InvalidOriginal)
      }
    }
  }
}

///|
fn LocalSDKReadSource::validate_run_current(
  self : LocalSDKReadSource,
  account : @authorization.AdmittedAccountConfiguration,
) -> Result[Unit, LocalSDKReadOriginalsIssue] {
  match self.origin {
    Live(preflight) =>
      validate_local_preflight_run_read_current(preflight, account).map_err(issue => {
        Preflight(issue)
      })
    Saved(saved) => {
      let scope = match
        @host.client_local_authority_scope_body(
          account,
          saved.adoption_cid,
          saved.principal,
          saved.connection,
        ) {
        Ok(value) => value
        Err(_) => return Err(InvalidOriginal)
      }
      if "sha256:" + @sha.hex(scope) !=
        @host.client_request_authority_scope_cid(saved.request) {
        return Err(InvalidOriginal)
      }
      let tuple : @authorization.AccessTuple = {
        principal: saved.principal,
        connection: saved.connection,
        resource: "run",
        operation: "read",
      }
      if @authorization.evaluate_account(account, tuple)
        is @authorization.Allow(_) {
        self.validate_view(saved.owner, saved.view)
      } else {
        Err(Preflight(AuthorizationMismatch))
      }
    }
  }
}

///|
fn LocalSDKReadSource::validate_current(
  self : LocalSDKReadSource,
  account : @authorization.AdmittedAccountConfiguration,
  result_name : String,
) -> Result[Unit, LocalSDKReadOriginalsIssue] {
  match self.origin {
    Live(preflight) =>
      validate_local_preflight_result_read_current(
        preflight, account, result_name,
      ).map_err(issue => Preflight(issue))
    Saved(saved) => {
      match self.validate_run_current(account) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      match
        saved.owner.observed_result_read_materials(saved.view, result_name, 16) {
        Ok(_) => ()
        Err(issue) => return Err(StoredChain(issue))
      }
      let tuple : @authorization.AccessTuple = {
        principal: saved.principal,
        connection: saved.connection,
        resource: "result/" + result_name,
        operation: "read",
      }
      if @authorization.evaluate_account(account, tuple)
        is @authorization.Allow(_) {
        Ok(())
      } else {
        Err(Preflight(AuthorizationMismatch))
      }
    }
  }
}

///|
fn LocalSDKReadSource::validate_finite_original(
  self : LocalSDKReadSource,
  finite : @host.ClientLocalRunPolicyOriginal,
) -> Result[Unit, LocalSDKReadOriginalsIssue] {
  match self.origin {
    Live(_) => Ok(())
    Saved(value) =>
      if @host.client_local_run_policy_original_body(finite) ==
        value.finite_original {
        Ok(())
      } else {
        Err(InvalidOriginal)
      }
  }
}

///|
/// Reuse the original checked live entry. This projection grants no authority.
pub fn local_sdk_read_source(
  preflight : LocalPublicationPreflight,
) -> LocalSDKReadSource {
  live_sdk_read_source(preflight)
}

///|
/// Evaluate the independent current Account for this original read source.
/// Actual same-Host/Store/FD currentness remains with the physical caller.
pub fn validate_local_sdk_read_source_current(
  source : LocalSDKReadSource,
  account : @authorization.AdmittedAccountConfiguration,
  result_name : String,
) -> Result[Unit, LocalSDKReadOriginalsIssue] {
  source.validate_current(account, result_name)
}
