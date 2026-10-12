///|
// An immutable declaration supplied by the trusted Node installation, not a
// second canonical Profile, a reservation, or Model-send authority. The layout
// artifact must justify the COMPLETE simultaneous read-phase envelope, including
// early Execution, preparation/seal, all prepared rows (also masked rows),
// callbacks, ABI/decoder workspace, cleanup and escaped-reference lifetimes.
// Matching these references cannot prove the physical adequacy of a declaration.
// A Host must not supply this record without its reviewed runtime/layout basis.
// Its installation-lifetime storage is distinct from the original Run bootstrap
// that must already cover validation frames and the returned one-shot control.
pub(all) struct ClientNodeModelPreparationLayout {
  response_profile : @environment.ModelResponseProfile
  runtime_artifact_cid : String
  layout_artifact_cid : String
  program_definition_cid : String
  parameter_values_cid : String
  barrier_cid : String
  prepared_rows : Int64
  retained_bytes : Int64
  execution_bytes : Int64
}

///|
pub(all) enum ClientModelPreparationLayoutIssue {
  Unavailable
  InvalidLayout
  RuntimeMismatch
  LayoutMismatch
  PreparationMismatch
  PreparedRowsLimit
  Profile(@environment.ModelTaskIssueKind)
  Read(ClientModelReadPreparationIssue)
} derive(Eq, Debug)

///|
// Selected installation/runtime/layout originals come from the existing trusted
// Host binding, never from a Program, response, usage aggregate or Source alias.
// Keep them immutable across awaits. This is a read-only predicate: neither a
// claim nor a new reservation/serial is issued here. The caller's original
// bootstrap covers this validation before it funds/constructs read preparation.
pub fn check_client_node_model_preparation_layout(
  layout : ClientNodeModelPreparationLayout?,
  plan : ClientInferPlanGraph,
  installation : @environment.ModelResponseProfileInstallation,
  runtime_artifact_cid : String,
  layout_artifact_cid : String,
  probability : @environment.DecisionProbabilityProfile?,
) -> Result[Unit, ClientModelPreparationLayoutIssue] {
  guard layout is Some(layout) else { return Err(Unavailable) }
  if !client_infer_dependency_cid(layout.runtime_artifact_cid) ||
    !client_infer_dependency_cid(layout.layout_artifact_cid) ||
    layout.prepared_rows < 0L ||
    layout.retained_bytes <= 0L ||
    layout.execution_bytes <= 0L {
    return Err(InvalidLayout)
  }
  if layout.runtime_artifact_cid != runtime_artifact_cid {
    return Err(RuntimeMismatch)
  }
  if layout.layout_artifact_cid != layout_artifact_cid {
    return Err(LayoutMismatch)
  }
  // The same ModelTask and row count do not justify different key shapes,
  // input contracts or checked preparation. Reuse the existing originals;
  // do not mint another CID, reconstruct them from response bytes, or keep a
  // reference to the original Run/plan graph in an installation declaration.
  let identity = prepared_client_identity(plan.owner)
  if layout.program_definition_cid != identity.program_definition_cid ||
    layout.parameter_values_cid != identity.parameter_values_cid ||
    layout.barrier_cid != plan.barrier_cid {
    return Err(PreparationMismatch)
  }
  match
    @environment.check_model_response_profile_binding(
      layout.response_profile,
      @environment.model_execution_task(plan.execution),
      installation,
      probability,
    ) {
    Err(issue) => return Err(Profile(issue))
    Ok(_) => ()
  }
  // This is the existing checked all-row upper bound, not actual rows, eligible
  // cursors, active Slots or a mask count. Zero actual rows cannot reduce it.
  if layout.prepared_rows < @checked.infer_item_limit_maximum(plan.item_limit) {
    return Err(PreparedRowsLimit)
  }
  let support = @environment.model_response_profile_limits(
    layout.response_profile,
  )
  // Necessary support bounds, not an invented sum or per-Slot multiplier. The
  // installed layout still has to justify every overlapping lifetime. Passing
  // these inequalities alone is NOT normal-profile or wholephase acceptance.
  if layout.retained_bytes < support.adapter_holding_bytes.to_int64() ||
    layout.execution_bytes < support.adapter_workspace_bytes.to_int64() {
    return Err(InvalidLayout)
  }
  Ok(())
}

///|
// The original checked Run owner already funds/owns scope bootstrap. Validate
// its exact original binding and the selected immutable installation BEFORE
// constructing a read descriptor or reserving the complete read envelope.
// This reuses prepare_client_model_read's same Ledger and opaque read; it does
// not issue a second bootstrap, accept free-capacity aggregates, or establish
// the numerical adequacy of the trusted installation declaration.
pub fn prepare_client_node_model_read_layout(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  layout : ClientNodeModelPreparationLayout?,
  installation : @environment.ModelResponseProfileInstallation,
  runtime_artifact_cid : String,
  layout_artifact_cid : String,
  probability : @environment.DecisionProbabilityProfile?,
) -> Result[ClientModelReadPreparation, ClientModelPreparationLayoutIssue] {
  if !client_model_origin_matches(scope.origin, compiled, definition, plan) {
    return Err(Read(ForeignRun))
  }
  match
    check_client_node_model_preparation_layout(
      layout, plan, installation, runtime_artifact_cid, layout_artifact_cid, probability,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard layout is Some(layout) else { return Err(Unavailable) }
  prepare_client_model_read(
    scope,
    layout.retained_bytes,
    layout.execution_bytes,
  ).map_err(issue => Read(issue))
}

///|
// Revalidate the selected installation before the first additional allocation,
// then consume the original Owner's one-shot claim. A refusal leaves its read
// token, quantity usage, spent serial and cleanup responsibility unchanged.
// There is no fallback, permissive default, or post-begin funding. The read must
// already be funded for this SAME complete envelope by the original Ledger.
pub fn claim_client_node_model_preparation_layout(
  read : ClientModelReadPreparation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  layout : ClientNodeModelPreparationLayout?,
  installation : @environment.ModelResponseProfileInstallation,
  runtime_artifact_cid : String,
  layout_artifact_cid : String,
  probability : @environment.DecisionProbabilityProfile?,
) -> Result[ClientModelReadConsumer, ClientModelPreparationLayoutIssue] {
  match
    check_client_node_model_preparation_layout(
      layout, plan, installation, runtime_artifact_cid, layout_artifact_cid, probability,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard layout is Some(layout) else { return Err(Unavailable) }
  claim_client_model_read_preparation(
    read,
    compiled,
    definition,
    plan,
    layout.retained_bytes,
    layout.execution_bytes,
  ).map_err(issue => Read(issue))
}
