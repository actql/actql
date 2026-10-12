///|
/// Original checked inventory and publication intent. These are projections of
/// existing Owners, not a Run admission, Store acknowledgement or permission.
struct LocalPublicationIntent {
  plan : LocalRunPlan
  inventory : @publication.CheckedPublicationInventory
  definitions : Array[@publication.PublicationContract]
  request : @publication.PublicationContract
  attempt : @publication.PublicationContract
}

///|
/// Immutable scope admitted by the existing publication preflight. Retentions
/// stay bound to the original complete inventory through Result issuance.
struct LocalPublicationPreflight {
  intent : LocalPublicationIntent
  invocation : LocalRunInvocation
  retentions : Array[@publication.PublicationContract]
}

///|
pub(all) struct LocalPublicationIntentLimits {
  max_results : Int
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum LocalPublicationIntentIssue {
  MissingResult
  InventoryLimit
  Inventory(@publication.PublicationInventoryIssue)
  Contract(@publication.PublicationCommitIssuanceIssue)
  ForeignCompute
  AuthorizationMismatch
  Source(LocalNativeSourceIssue)
  UnavailableSource
  PreflightMismatch
  ComputeAlreadyStarted
  ResultPublication(LocalResultPublicationIssue)
  CommitCandidate(@publication.PublicationCommitIssuanceIssue)
}

///|
/// Derive every occurrence from the original checked graph. No caller-supplied
/// subset, alias or Result definition can enter this inventory.
pub fn prepare_local_publication_intent(
  plan : LocalRunPlan,
  namespace_id : String,
  publication_policy_cid : String,
  publication_target_cid : String,
  requested_at : String,
  attempt_id : String,
  fence_cid : String,
  external_idempotency_key : String?,
  started_at : String,
  limits : LocalPublicationIntentLimits,
) -> Result[LocalPublicationIntent, LocalPublicationIntentIssue] {
  let graph = @host.prepared_client_graph(plan.prepared)
  let count = @strategy.graph_result_count(graph)
  if count == 0 {
    return Err(MissingResult)
  }
  if limits.max_results <= 0 || count > limits.max_results {
    return Err(InventoryLimit)
  }
  let names : Array[String] = []
  let tasks : Array[Int] = []
  for index in 0..<count {
    guard @strategy.graph_result_name(graph, index) is Some(name) &&
      @strategy.graph_result_task(graph, index) is Some(task) else {
      return Err(MissingResult)
    }
    names.push(name)
    tasks.push(task)
  }
  let inventory = match
    @publication.prepare_checked_publication_inventory(
      @host.prepared_client_identity(plan.prepared).program_definition_cid,
      names,
      tasks,
    ) {
    Ok(inventory) => inventory
    Err(issue) => return Err(Inventory(issue))
  }
  let definitions : Array[@publication.PublicationContract] = []
  for index in 0..<count {
    match
      @publication.checked_publication_inventory_definition(inventory, index) {
      Ok(definition) => definitions.push(definition)
      Err(issue) => return Err(Inventory(issue))
    }
  }
  let request = match
    @publication.issue_publication_request(
      plan.definition,
      definitions,
      namespace_id,
      @host.client_request_authority_scope_cid(plan.request),
      publication_policy_cid,
      publication_target_cid,
      requested_at,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(request) => request
    Err(issue) => return Err(Contract(issue))
  }
  let attempt = match
    @publication.issue_publication_attempt(
      request,
      plan.definition,
      attempt_id,
      fence_cid,
      external_idempotency_key,
      started_at,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(attempt) => attempt
    Err(issue) => return Err(Contract(issue))
  }
  Ok({ plan, inventory, definitions, request, attempt, })
}

///|
pub fn local_publication_intent_inventory(
  intent : LocalPublicationIntent,
) -> @publication.CheckedPublicationInventory {
  intent.inventory
}

///|
pub fn local_publication_intent_contracts(
  intent : LocalPublicationIntent,
) -> (@publication.PublicationContract, @publication.PublicationContract) {
  (intent.request, intent.attempt)
}

///|
/// Call before Compute activation with the original typed Run invocation.
/// Current Run/Source access and immutable publication preflight are separate
/// checks. Success grants neither activation nor physical publication authority.
pub fn check_local_publication_preflight(
  intent : LocalPublicationIntent,
  invocation : LocalRunInvocation,
  account : @authorization.AdmittedAccountConfiguration,
  retentions : Array[@publication.PublicationContract],
) -> Result[LocalPublicationPreflight, LocalPublicationIntentIssue] {
  match local_publication_intent_current(intent, invocation, account) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let host = invocation.host
  let run = local_compute_run(host)
  if !local_publication_compute_unstarted(run) {
    return Err(ComputeAlreadyStarted)
  }
  let count = intent.definitions.length()
  if retentions.length() != count {
    return Err(PreflightMismatch)
  }
  let plan = intent.plan
  let computation = @publication.publication_contract_identity(
    @host.client_task_compilation_compiled_plan(plan.compilation),
  )
  let sources = local_run_invocation_source_cids(invocation)
  let scope = @publication.publication_contract_identity(plan.definition)
  let authority = @host.client_request_authority_scope_cid(plan.request)
  if !@publication.publication_preflight_valid(
      plan.admission,
      plan.definition,
      invocation.invocation,
      intent.definitions,
      retentions,
      Array::make(count, computation),
      Array::makei(count, _ => sources.copy()),
      Array::make(count, scope),
      Array::make(count, invocation.data_policy_cid),
      Array::make(count, authority),
      intent.request,
      intent.attempt,
      @host.prepared_client_identity(plan.prepared).program_definition_cid,
    ) {
    return Err(PreflightMismatch)
  }
  Ok({ intent, invocation, retentions: retentions.copy(), })
}

///|
fn local_publication_compute_unstarted(run : @strategy.CapturedDAG) -> Bool {
  let first = @strategy.captured_compute_first_task(run)
  if @strategy.next_captured_task(run) != Some(first) ||
    @strategy.captured_task_activation_granted(run, first) {
    return false
  }
  for
    index in first..<@strategy.graph_task_count(
      @strategy.captured_dag_graph(run),
    ) {
    if @strategy.captured_task_completed(run, index) {
      return false
    }
  }
  true
}

///|
/// Recheck original custody and current access; immutable intent is not a
/// permanent authorization, execution grant or Store acknowledgement.
pub fn validate_local_publication_preflight_current(
  preflight : LocalPublicationPreflight,
  account : @authorization.AdmittedAccountConfiguration,
) -> Result[Unit, LocalPublicationIntentIssue] {
  local_publication_intent_current(
    preflight.intent,
    preflight.invocation,
    account,
  )
}

///|
fn local_publication_intent_current(
  intent : LocalPublicationIntent,
  invocation : LocalRunInvocation,
  account : @authorization.AdmittedAccountConfiguration,
) -> Result[Unit, LocalPublicationIntentIssue] {
  let host = invocation.host
  if !physical_equal(intent.plan, host.plan) {
    return Err(ForeignCompute)
  }
  if !local_publication_current(host, account) {
    return Err(AuthorizationMismatch)
  }
  match validate_local_run_invocation_current(invocation, account) {
    Err(AuthorizationMismatch) => return Err(AuthorizationMismatch)
    Err(Source(Authorization(issue))) => return Err(Source(issue))
    Err(_) => return Err(UnavailableSource)
    Ok(_) => ()
  }
  Ok(())
}

///|
/// Publish one original Result using the retention checked before activation.
/// The completed-output and Result publication Owners keep their own custody;
/// a caller cannot substitute another definition, invocation or policy here.
pub fn issue_local_preflight_result_publication(
  preflight : LocalPublicationPreflight,
  result : Int,
  output : @host.PublicationOutputExport,
  account : @authorization.AdmittedAccountConfiguration,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[LocalResultPublication, LocalPublicationIntentIssue] {
  match validate_local_preflight_result(preflight, result, output, account) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  issue_local_result_publication(
    preflight.invocation.host,
    preflight.invocation,
    output,
    preflight.retentions[result],
    account,
    max_wire_bytes,
    max_nodes,
    max_depth,
  ).map_err(issue => ResultPublication(issue))
}

///|
fn validate_local_preflight_result(
  preflight : LocalPublicationPreflight,
  result : Int,
  output : @host.PublicationOutputExport,
  account : @authorization.AdmittedAccountConfiguration,
) -> Result[Unit, LocalPublicationIntentIssue] {
  match validate_local_publication_preflight_current(preflight, account) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let intent = preflight.intent
  if result < 0 || result >= intent.definitions.length() {
    return Err(PreflightMismatch)
  }
  let definition = match output.definition() {
    Ok(definition) => definition
    Err(issue) => return Err(ResultPublication(Output(issue)))
  }
  if @publication.publication_contract_identity(definition) !=
    @publication.publication_contract_identity(intent.definitions[result]) {
    return Err(PreflightMismatch)
  }
  Ok(())
}

///|
/// Reuse the original nominal Result after child cancellation. Checking a
/// retained preflight must not reissue its Receipt or replace its artifact.
pub fn reuse_local_preflight_result_publication(
  preflight : LocalPublicationPreflight,
  result : Int,
  original : LocalResultPublication,
  output : @host.PublicationOutputExport,
  account : @authorization.AdmittedAccountConfiguration,
) -> Result[LocalResultPublication, LocalPublicationIntentIssue] {
  match validate_local_preflight_result(preflight, result, output, account) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  reuse_local_result_publication(
    original,
    preflight.invocation.host,
    preflight.invocation,
    output,
    preflight.retentions[result],
    account,
  ).map_err(issue => ResultPublication(issue))
}

///|
pub fn local_publication_preflight_count(
  preflight : LocalPublicationPreflight,
) -> Int {
  preflight.intent.definitions.length()
}

///|
/// Project sealed intent; this is not current physical publisher authority.
pub fn local_publication_preflight_contracts(
  preflight : LocalPublicationPreflight,
) -> (@publication.PublicationContract, @publication.PublicationContract) {
  local_publication_intent_contracts(preflight.intent)
}

///|
/// Encode a proposed index from the original sealed intent and completed
/// inventory, then start the existing bounded full-chain validator. Neither
/// return value is current publisher authority or a durable Store commit.
pub fn prepare_local_preflight_commit_candidate(
  preflight : LocalPublicationPreflight,
  manifest : LocalRunManifest,
  normalization : LocalRunNormalization,
  receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
  bindings : Array[@publication.PublicationContract],
  committed_at : String,
  account : @authorization.AdmittedAccountConfiguration,
  limits : LocalPublicationIntentLimits,
  max_workspace_slots : Int,
) -> Result[
  (@publication.PublicationContract, @publication.PublicationCommitPreparation),
  LocalPublicationIntentIssue,
] {
  match validate_local_publication_preflight_current(preflight, account) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(manifest.host, preflight.invocation.host) ||
    !physical_equal(manifest.invocation, preflight.invocation) {
    return Err(ForeignCompute)
  }
  let count = local_publication_preflight_count(preflight)
  if manifest.results.length() != count ||
    bindings.length() != count ||
    count > limits.max_results {
    return Err(PreflightMismatch)
  }
  for index, result in manifest.results {
    match
      validate_local_preflight_result(preflight, index, result.output, account) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let original = preflight.retentions[index]
    if @publication.publication_contract_identity(result.retention) !=
      @publication.publication_contract_identity(original) ||
      @publication.publication_contract_json(result.retention) !=
      @publication.publication_contract_json(original) {
      return Err(PreflightMismatch)
    }
  }
  let (request, attempt) = local_publication_preflight_contracts(preflight)
  let index_entry = match
    @publication.issue_public_index_entry(
      manifest.host.plan.definition,
      preflight.invocation.invocation,
      manifest.manifest,
      receipt,
      captured_run,
      bindings,
      request,
      attempt,
      committed_at,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(index_entry) => index_entry
    Err(issue) => return Err(CommitCandidate(issue))
  }
  let validation = match
    start_local_publication_commit_check(
      manifest,
      normalization,
      receipt,
      captured_run,
      bindings,
      request,
      attempt,
      index_entry,
      account,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
      max_workspace_slots,
    ) {
    Ok(validation) => validation
    Err(issue) => return Err(ResultPublication(issue))
  }
  Ok((index_entry, validation))
}
