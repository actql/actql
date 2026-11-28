///|
/// Only the bounded observations supplied by the existing SDK publication
/// input. The authority, policy, target and Result names come from originals.
pub(all) struct LocalCapturedTaskPublicationClock {
  at : String
  attempt_id : String
  fence_cid : String
  external_idempotency_key : String?
}

///|
pub(all) enum LocalCapturedTaskPublicationPreflightIssue[E] {
  Binding(LocalRunPublicationBindingIssue[E])
  Intent(LocalPublicationIntentIssue)
  Payload(@host.PublicationOutputPayloadIssue)
  Source(@local.ClientInstalledManagedRunIssue)
}

///|
/// File preflight owns the same checked contracts as ordinary publication,
/// with a captured Task start in place of an ordinary LocalRunInvocation.
struct LocalCapturedTaskPublicationPreflight[Store, E] {
  observed : LocalCapturedTaskStartObservation[Store, E]
  owner : @local.ClientInstalledManagedRun
  dag : @strategy.CapturedDAG
  source : @row_host.RowSourceCapture
  source_identity : @query.CapturedSourceRelationIdentity
  invocation : @publication.PublicationContract
  source_relation_cid : String
  data_policy_cid : String
  contracts : LocalPublicationContracts
  retention : @publication.PublicationContract
}

///|
fn[Store, E] captured_task_preflight_current(
  observed : LocalCapturedTaskStartObservation[Store, E],
  owner : @local.ClientInstalledManagedRun,
  source : @row_host.RowSourceCapture,
  identity : @query.CapturedSourceRelationIdentity,
  invocation : @publication.PublicationContract,
  snapshot : @host.ClientSavedSubmissionSnapshot,
  locator : @host.ClientJournalPhysicalRow,
  account : @authorization.AdmittedAccountConfiguration,
  context : String,
  validate_read : () -> Result[Unit, LocalRunPublicationBindingIssue[E]],
  saved_state_update? : @host.ClientSavedRunStateUpdate? = None,
) -> Result[
  (@strategy.CapturedDAG, String),
  LocalCapturedTaskPublicationPreflightIssue[E],
] {
  let step = observed.step
  let binding = step.publication.step
  guard !step.dispatch &&
    @host.client_saved_submission_run_row(snapshot) is Some(run) else {
    return Err(Binding(CustodyLost))
  }
  let original = binding.candidate.task_materials.plan
  let prepared = @host.client_captured_task_run_materials_prepared(original)
  let checked_rows = match saved_state_update {
    None =>
      check_local_captured_task_start_successor(
        step,
        run,
        @host.client_saved_submission_row(snapshot),
        locator,
        account,
        context,
        validate_read,
      )
    Some(update) =>
      check_local_captured_task_saved_state_successor(
        step, run, snapshot, locator, account, context, validate_read, update,
      )
  }
  match checked_rows {
    Err(issue) => return Err(Binding(issue))
    Ok(_) => ()
  }
  let adopted = match
    @host.client_local_adopted_current_account(binding.adopted, binding.store) {
    Err(issue) => return Err(Binding(Current(issue)))
    Ok(value) => value
  }
  if account.configuration_cid() != adopted.configuration_cid() {
    return Err(Binding(AuthorizationMismatch))
  }
  let checked = match
    @local.installed_single_whole_publication_source(
      owner,
      prepared,
      original.request,
      original.compiled,
      original.definition,
      invocation,
      source,
      identity,
    ) {
    Err(issue) => return Err(Source(issue))
    Ok(value) => value
  }
  validate_read()
  .map_err(issue => LocalCapturedTaskPublicationPreflightIssue::Binding(issue))
  .map(_ => checked)
}

///|
/// Validate and fund every checked Result before activating the exact File
/// DAG. The resulting contracts authorize no task, publisher or Store write.
pub fn[Store, E] prepare_local_captured_task_publication_preflight(
  observed : LocalCapturedTaskStartObservation[Store, E],
  owner : @local.ClientInstalledManagedRun,
  source : @row_host.RowSourceCapture,
  identity : @query.CapturedSourceRelationIdentity,
  invocation : @publication.PublicationContract,
  snapshot : @host.ClientSavedSubmissionSnapshot,
  locator : @host.ClientJournalPhysicalRow,
  account : @authorization.AdmittedAccountConfiguration,
  context : String,
  clock : LocalCapturedTaskPublicationClock,
  limits : LocalPublicationIntentLimits,
  validate_read : () -> Result[Unit, LocalRunPublicationBindingIssue[E]],
  fund : (Int, LocalPublicationIntentLimits) -> Result[
    Unit,
    LocalRunPublicationBindingIssue[E],
  ],
) -> Result[
  LocalCapturedTaskPublicationPreflight[Store, E],
  LocalCapturedTaskPublicationPreflightIssue[E],
] {
  let binding = observed.step.publication.step
  let candidate = binding.candidate
  let original = candidate.task_materials.plan
  let prepared = @host.client_captured_task_run_materials_prepared(original)
  fn current() -> Result[
    (@strategy.CapturedDAG, String),
    LocalCapturedTaskPublicationPreflightIssue[E],
  ] {
    captured_task_preflight_current(
      observed, owner, source, identity, invocation, snapshot, locator, account,
      context, validate_read,
    )
  }
  let (dag, source_relation_cid) = match current() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !local_publication_compute_unstarted(dag) {
    return Err(Intent(ComputeAlreadyStarted))
  }
  let count = @strategy.graph_result_count(
    @host.prepared_client_graph(prepared),
  )
  if count == 0 {
    return Err(Intent(MissingResult))
  }
  if count > limits.max_results {
    return Err(Intent(InventoryLimit))
  }
  guard local_captured_task_start_finite_policy(observed, candidate)
    is Some(finite) &&
    @publication.run_definition_namespace(original.definition)
    is Some(run_namespace) else {
    return Err(Binding(CustodyLost))
  }
  match fund(count, limits) {
    Err(issue) => return Err(Binding(issue))
    Ok(_) => ()
  }
  fn check_ready() -> Result[
    Unit,
    LocalCapturedTaskPublicationPreflightIssue[E],
  ] {
    current().bind(value => {
      if !physical_equal(value.0, dag) || value.1 != source_relation_cid {
        return Err(Binding(CustodyLost))
      }
      if !local_publication_compute_unstarted(dag) {
        return Err(Intent(ComputeAlreadyStarted))
      }
      Ok(())
    })
  }
  match check_ready() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard @host.prepared_client_publication_data_policy_cid(prepared)
    is Some(data_policy_cid) else {
    return Err(Intent(PreflightMismatch))
  }
  let contracts = match
    prepare_local_publication_contracts(
      prepared,
      original.request,
      original.definition,
      run_namespace,
      account.configuration_cid(),
      binding.store_authority_cid,
      clock.at,
      clock.attempt_id,
      clock.fence_cid,
      clock.external_idempotency_key,
      clock.at,
      limits,
    ) {
    Err(issue) => return Err(Intent(issue))
    Ok(value) => value
  }
  // Apply the already checked effective Source policy to the admitted
  // finite Run window. The existing issuer preserves the precise endpoints
  // and clock and does not issue or renew Run custody.
  let retention = match
    @publication.issue_result_retention_for_data_policy(
      @host.client_local_run_policy_original_retention(finite),
      data_policy_cid,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(retention) => retention
    Err(_) => return Err(Intent(PreflightMismatch))
  }
  let computation = @publication.publication_contract_identity(
    @host.client_compiled_run_plan(original.compiled),
  )
  if !local_publication_preflight_contracts_match(
      prepared,
      original.request,
      @host.client_compiled_run_admission(original.compiled),
      original.definition,
      invocation,
      computation,
      [source_relation_cid],
      data_policy_cid,
      contracts.definitions,
      Array::make(count, retention),
      contracts.request,
      contracts.attempt,
    ) {
    return Err(Intent(PreflightMismatch))
  }
  check_ready().map(_ => {
    observed,
    owner,
    dag,
    source,
    source_identity: identity,
    invocation,
    source_relation_cid,
    data_policy_cid,
    contracts,
    retention,
  })
}

///|
/// Reobserve the same File claim and source before Request or Commit. A saved
/// ReturnCommitted lookup is separate and cannot grant a fresh commitment.
pub fn[Store, E] check_local_captured_task_publication_preflight_current(
  preflight : LocalCapturedTaskPublicationPreflight[Store, E],
  snapshot : @host.ClientSavedSubmissionSnapshot,
  locator : @host.ClientJournalPhysicalRow,
  account : @authorization.AdmittedAccountConfiguration,
  context : String,
  validate_read : () -> Result[Unit, LocalRunPublicationBindingIssue[E]],
) -> Result[Unit, LocalCapturedTaskPublicationPreflightIssue[E]] {
  captured_task_preflight_current(
    preflight.observed,
    preflight.owner,
    preflight.source,
    preflight.source_identity,
    preflight.invocation,
    snapshot,
    locator,
    account,
    context,
    validate_read,
  ).bind(value => {
    if !physical_equal(value.0, preflight.dag) ||
      value.1 != preflight.source_relation_cid {
      return Err(Binding(CustodyLost))
    }
    Ok(())
  })
}

///|
/// The physical Read supplies either the original ready Submission or the
/// exact successor of its held state update. Run/read is checked independently
/// of activation and publishing. This path issues neither authority nor rows.
pub fn[Store, E] check_local_captured_task_publication_run_state(
  preflight : LocalCapturedTaskPublicationPreflight[Store, E],
  snapshot : @host.ClientSavedSubmissionSnapshot,
  locator : @host.ClientJournalPhysicalRow,
  account : @authorization.AdmittedAccountConfiguration,
  context : String,
  validate_read : () -> Result[Unit, LocalRunPublicationBindingIssue[E]],
  saved_state_update? : @host.ClientSavedRunStateUpdate? = None,
  read_predecessor? : Bool = false,
) -> Result[
  (@host.ClientRequestIdentity, @publication.PublicationContract),
  LocalCapturedTaskPublicationPreflightIssue[E],
] {
  let binding = preflight.observed.step.publication.step
  let selected_update = match saved_state_update {
    Some(update) if read_predecessor &&
      @host.validate_client_saved_run_state_update_original(update, snapshot)
      is Ok(_) => None
    _ => saved_state_update
  }
  captured_task_preflight_current(
    preflight.observed,
    preflight.owner,
    preflight.source,
    preflight.source_identity,
    preflight.invocation,
    snapshot,
    locator,
    account,
    context,
    validate_read,
    saved_state_update=selected_update,
  ).bind(value => {
    if !physical_equal(value.0, preflight.dag) ||
      value.1 != preflight.source_relation_cid {
      return Err(Binding(CustodyLost))
    }
    let tuple : @authorization.AccessTuple = {
      ..binding.tuple,
      resource: "run",
      operation: "read",
    }
    if @authorization.evaluate_account(account, tuple)
      is @authorization.Allow(_) {
      let original = binding.candidate.task_materials.plan
      validate_read()
      .map_err(issue => {
        LocalCapturedTaskPublicationPreflightIssue::Binding(issue)
      })
      .map(_ => (original.request, original.definition))
    } else {
      Err(Binding(AuthorizationMismatch))
    }
  })
}

///|
pub fn[Store, E] local_captured_task_publication_preflight_contracts(
  preflight : LocalCapturedTaskPublicationPreflight[Store, E],
) -> (@publication.PublicationContract, @publication.PublicationContract) {
  (preflight.contracts.request, preflight.contracts.attempt)
}

///|
pub fn[Store, E] local_captured_task_publication_preflight_result(
  preflight : LocalCapturedTaskPublicationPreflight[Store, E],
  index : Int,
) -> (@publication.PublicationContract, @publication.PublicationContract)? {
  preflight.contracts.definitions
  .get(index)
  .map(definition => (definition, preflight.retention))
}

///|
pub fn[Store, E] local_captured_task_publication_preflight_count(
  preflight : LocalCapturedTaskPublicationPreflight[Store, E],
) -> Int {
  preflight.contracts.definitions.length()
}

///|
pub fn[Store, E] local_captured_task_publication_preflight_compute_unstarted(
  preflight : LocalCapturedTaskPublicationPreflight[Store, E],
) -> Bool {
  local_publication_compute_unstarted(preflight.dag)
}
