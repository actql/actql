///|
pub(all) enum LocalResultPublicationIssue {
  ForeignCompute
  AuthorizationMismatch
  Source(LocalSourcePublicationIssue)
  MissingFacts
  ForeignPublication
  Manifest(@publication.ResultManifestIssuanceIssue)
  Normalization(LocalRunNormalizationIssue)
  Receipt(@publication.RunReceiptIssuanceIssue)
  Invocation(@publication.RunEvidenceValueIssue)
  Authoring(@host.ClientAuthoringContextIssue)
  Output(@host.PublicationOutputExportIssue)
}

///|
/// Existing invocation and observation issued from the original capture.
/// This projection neither commits publication nor changes a Run's state.
pub struct LocalSourceInvocation {
  source : LocalSourcePublication
  observation : @publication.RunEvidenceValue
  invocation : @publication.PublicationContract
  data_policy_cid : String
}

///|
fn local_publication_current(
  host : LocalComputeHost,
  account : @authorization.AdmittedAccountConfiguration,
) -> Bool {
  account.account_id() == host.plan.account_id &&
  @authorization.evaluate_account(account, host.plan.tuple)
  is @authorization.Allow(_)
}

///|
pub fn issue_local_source_invocation(
  host : LocalComputeHost,
  source : LocalSourcePublication,
  account : @authorization.AdmittedAccountConfiguration,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[LocalSourceInvocation, LocalResultPublicationIssue] {
  if !physical_equal(host, source.host) {
    return Err(ForeignCompute)
  }
  if !local_publication_current(host, account) {
    return Err(AuthorizationMismatch)
  }
  match authorize_local_native_source(source.configuration, account) {
    Err(issue) => return Err(Source(Authorization(issue)))
    Ok(_) => ()
  }
  if !@acquisition_host.native_host_source_capture_identity_matches(
      source.capture,
      source.identity,
    ) {
    return Err(Source(Source(@query.Unavailable)))
  }
  guard @planning.query_requirement_source_evidence_facts(
      source.configuration.requirement,
    )
    is Some(facts) else {
    return Err(MissingFacts)
  }
  let values = @planning.query_source_evidence_fact_values(facts)
  let plan = host.plan
  let (observation, invocation) = match
    @host.issue_client_task_invocation(
      plan.prepared,
      plan.compilation,
      plan.admission,
      plan.definition,
      @publication.run_evidence_value_json(source.evidence),
      @publication.run_evidence_value_json(source.logical),
      values[0],
      values[1],
      @host.client_request_authority_scope_cid(plan.request),
      values[3],
      capture_started_at,
      capture_completed_at,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(issued) => issued
    Err(issue) => return Err(Invocation(issue))
  }
  Ok({ source, observation, invocation, data_policy_cid: values[3], })
}

///|
pub fn local_source_invocation_contract(
  value : LocalSourceInvocation,
) -> @publication.PublicationContract {
  value.invocation
}

///|
pub fn local_source_invocation_observation(
  value : LocalSourceInvocation,
) -> @publication.RunEvidenceValue {
  value.observation
}

///|
/// Result occurrence, schema, content and identity remain owned by the exact
/// completed export. No supplied CID or success flag can replace those facts.
pub struct LocalResultPublication {
  host : LocalComputeHost
  invocation : LocalSourceInvocation
  output : @host.PublicationOutputExport
  definition : @publication.PublicationContract
  artifact : @publication.PublicationContract
  derivation : @publication.PublicationContract
  ordering : @publication.PublicationContract
  retention : @publication.PublicationContract
}

///|
pub fn issue_local_result_publication(
  host : LocalComputeHost,
  invocation : LocalSourceInvocation,
  output : @host.PublicationOutputExport,
  retention : @publication.PublicationContract,
  account : @authorization.AdmittedAccountConfiguration,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[LocalResultPublication, LocalResultPublicationIssue] {
  if !physical_equal(host, invocation.source.host) {
    return Err(ForeignCompute)
  }
  if !output.matches_captured_run(local_compute_run(host)) {
    return Err(ForeignCompute)
  }
  if !local_publication_current(host, account) {
    return Err(AuthorizationMismatch)
  }
  match
    authorize_local_native_source(invocation.source.configuration, account) {
    Err(issue) => return Err(Source(Authorization(issue)))
    Ok(_) => ()
  }
  let definition = match output.definition() {
    Ok(definition) => definition
    Err(issue) => return Err(Output(issue))
  }
  let plan = host.plan
  match
    output.issue_result_evidence(
      @publication.publication_contract_identity(
        @host.client_task_compilation_compiled_plan(plan.compilation),
      ),
      [@query.captured_source_relation_logical_cid(invocation.source.identity)],
      @publication.publication_contract_identity(plan.definition),
      invocation.data_policy_cid,
      @host.client_request_authority_scope_cid(plan.request),
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Output(issue))
  }
  let artifact = match
    output.issue_artifact(
      invocation.invocation,
      retention,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(artifact) => artifact
    Err(issue) => return Err(Output(issue))
  }
  let derivation = match output.derivation() {
    Ok(value) => value
    Err(issue) => return Err(Output(issue))
  }
  let ordering = match output.ordering() {
    Ok(value) => value
    Err(issue) => return Err(Output(issue))
  }
  Ok({
    host,
    invocation,
    output,
    definition,
    artifact,
    derivation,
    ordering,
    retention,
  })
}

///|
pub fn local_result_publication_contracts(
  value : LocalResultPublication,
) -> Array[@publication.PublicationContract] {
  [
    value.definition,
    value.artifact,
    value.derivation,
    value.ordering,
    value.retention,
  ]
}

///|
/// Borrow the original one-shot issuance for another bounded snapshot child.
/// Equal-looking replacement owners and changed retention cannot acquire it.
/// Current authority is checked again; the cached projection is not a grant.
pub fn reuse_local_result_publication(
  value : LocalResultPublication,
  host : LocalComputeHost,
  invocation : LocalSourceInvocation,
  output : @host.PublicationOutputExport,
  retention : @publication.PublicationContract,
  account : @authorization.AdmittedAccountConfiguration,
) -> Result[LocalResultPublication, LocalResultPublicationIssue] {
  if !physical_equal(value.host, host) ||
    !physical_equal(value.invocation, invocation) ||
    !physical_equal(value.output, output) ||
    @publication.publication_contract_identity(value.retention) !=
    @publication.publication_contract_identity(retention) ||
    @publication.publication_contract_json(value.retention) !=
    @publication.publication_contract_json(retention) {
    return Err(ForeignPublication)
  }
  validate_local_result_publication_current(value, account).map(_ => value)
}

///|
pub fn start_local_result_publication_snapshot(
  value : LocalResultPublication,
  account : @authorization.AdmittedAccountConfiguration,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @host.PublicationOutputSnapshotPreparation,
  LocalResultPublicationIssue,
] {
  match validate_local_result_publication_current(value, account) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  value.output
  .start_captured_snapshot(max_wire_bytes, max_nodes, max_depth)
  .map_err(issue => Output(issue))
}

///|
/// Recheck the original live custody and current authority around a physical
/// Host yield. This issues no new projection and performs no Source I/O.
pub fn validate_local_result_publication_current(
  value : LocalResultPublication,
  account : @authorization.AdmittedAccountConfiguration,
) -> Result[Unit, LocalResultPublicationIssue] {
  if !physical_equal(value.host, value.invocation.source.host) ||
    !value.output.matches_captured_run(local_compute_run(value.host)) {
    return Err(ForeignCompute)
  }
  if !local_publication_current(value.host, account) {
    return Err(AuthorizationMismatch)
  }
  match
    authorize_local_native_source(
      value.invocation.source.configuration,
      account,
    ) {
    Err(issue) => return Err(Source(Authorization(issue)))
    Ok(_) => ()
  }
  Ok(())
}

///|
pub struct LocalRunManifest {
  host : LocalComputeHost
  invocation : LocalSourceInvocation
  results : Array[LocalResultPublication]
  manifest : @publication.PublicationContract
}

///|
pub fn issue_local_run_manifest(
  host : LocalComputeHost,
  invocation : LocalSourceInvocation,
  results : Array[LocalResultPublication],
  account : @authorization.AdmittedAccountConfiguration,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[LocalRunManifest, LocalResultPublicationIssue] {
  if !physical_equal(host, invocation.source.host) {
    return Err(ForeignCompute)
  }
  if !local_publication_current(host, account) {
    return Err(AuthorizationMismatch)
  }
  match
    authorize_local_native_source(invocation.source.configuration, account) {
    Err(issue) => return Err(Source(Authorization(issue)))
    Ok(_) => ()
  }
  let definitions = []
  let artifacts = []
  for result in results {
    if !physical_equal(result.host, host) ||
      !physical_equal(result.invocation, invocation) ||
      !result.output.matches_captured_run(local_compute_run(host)) {
      return Err(ForeignCompute)
    }
    definitions.push(result.definition)
    artifacts.push(result.artifact)
  }
  let manifest = match
    @publication.issue_result_manifest(
      host.plan.definition,
      invocation.invocation,
      definitions,
      artifacts,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Manifest(issue))
  }
  Ok({ host, invocation, results: results.copy(), manifest, })
}

///|
pub fn local_run_manifest_contract(
  value : LocalRunManifest,
) -> @publication.PublicationContract {
  value.manifest
}

///|
/// One final Receipt consumes the original admission and normalization proof.
/// Issuance does not publish durable bytes or change the original Run state.
pub fn issue_local_run_receipt(
  value : LocalRunManifest,
  normalization : LocalRunNormalization,
  account : @authorization.AdmittedAccountConfiguration,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.PublicationContract, LocalResultPublicationIssue] {
  if !local_publication_current(value.host, account) {
    return Err(AuthorizationMismatch)
  }
  match
    authorize_local_native_source(
      value.invocation.source.configuration,
      account,
    ) {
    Err(issue) => return Err(Source(Authorization(issue)))
    Ok(_) => ()
  }
  for result in value.results {
    if !result.output.matches_captured_run(local_compute_run(value.host)) {
      return Err(ForeignCompute)
    }
  }
  let plan = value.host.plan
  let journal = match local_run_normalization_evidence(plan, normalization) {
    Ok(journal) => journal
    Err(issue) => return Err(Normalization(issue))
  }
  @publication.issue_effect_free_run_receipt(
    plan.admission,
    plan.definition,
    value.invocation.invocation,
    value.invocation.observation,
    value.results.map(result => result.definition),
    value.results.map(result => result.artifact),
    value.manifest,
    journal,
    [],
    [],
    [value.invocation.source.evidence],
    [],
    [],
    max_wire_bytes,
    max_nodes,
    max_depth,
  ).map_err(issue => Receipt(issue))
}

///|
/// Capture the full immutable publication chain with the existing bounded
/// Owner. This remains distinct from durable commit and public Run admission.
pub fn start_local_run_capture(
  value : LocalRunManifest,
  normalization : LocalRunNormalization,
  snapshots : Array[@publication.CapturedResultSnapshot],
  account : @authorization.AdmittedAccountConfiguration,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace_slots : Int,
) -> Result[
  (
    @publication.CapturedRunIssuancePreparation,
    @publication.PublicationContract,
  ),
  LocalResultPublicationIssue,
] {
  for result in value.results {
    match validate_local_result_publication_current(result, account) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if !local_publication_current(value.host, account) {
    return Err(AuthorizationMismatch)
  }
  match
    authorize_local_native_source(
      value.invocation.source.configuration,
      account,
    ) {
    Err(issue) => return Err(Source(Authorization(issue)))
    Ok(_) => ()
  }
  let plan = value.host.plan
  match local_run_normalization_evidence(plan, normalization) {
    Ok(_) => ()
    Err(issue) => return Err(Normalization(issue))
  }
  let authoring = match
    @host.issue_prepared_client_authoring_context(
      plan.prepared,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Authoring(issue))
  }
  // Issue the single final Receipt from this exact original chain. Accepting
  // an arbitrary caller-supplied contract here could replace journal custody.
  let receipt = match
    issue_local_run_receipt(
      value, normalization, account, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(receipt) => receipt
    Err(issue) => return Err(issue)
  }
  Ok(
    (
      @publication.start_effect_free_captured_run(
        plan.definition,
        value.invocation.invocation,
        value.results.map(result => result.definition),
        value.results.map(result => result.artifact),
        value.manifest,
        receipt,
        snapshots,
        [],
        authoring,
        [],
        max_wire_bytes,
        max_nodes,
        max_depth,
        max_workspace_slots,
      ),
      receipt,
    ),
  )
}
