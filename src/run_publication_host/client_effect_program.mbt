///|
/// Host-selected bounds for an Effectful computation. Static closure is only
/// preparation: current grants, captured values, Preview and apply remain
/// separate obligations.
pub(all) struct ClientEffectComputationLimits {
  program : ClientProgramPreparationLimits
  max_members : Int
  max_header_work : Int
  mapping : @environment.Limits
  max_mapping_work : Int
  effects : @stage_results.EffectStaticCandidateLimits
}

///|
pub(all) enum ClientEffectComputationIssue {
  Syntax(@syntax.SyntaxError)
  Candidate(@checked.EffectComputationIssue)
  Mapping(@environment.MappingShapeIssue)
  Static(@stage_results.EffectStaticCandidateIssue)
  Stage(ClientStageOwnerIssue)
  Graph(@strategy.GraphIssue)
  TargetSelection(ClientEffectUpdateTargetIssue)
}

///|
/// The ordinary checked computation and its exact static Effect inventory
/// share one Program owner. This is not an executable Effect Run or permit.
struct PreparedClientEffectComputation {
  source_intent : ClientSubmittedIntent?
  target_selections : ClientEffectUpdateTargetSelections?
  command_targets : @update_targets.CommandTargetPublication?
  mut normalization : ClientEffectNormalization?
  mut normalization_custody : ClientEffectNormalizationMaterialCustody?
  source : @syntax.Program
  supplied : @decode.Cursor?
  candidate : @checked.EffectProgramStaticCandidate
  graph : @strategy.CheckedEffectComputationDAG
  sequence_preparation_demand : @lower.SequencePreparationDemand
  check_environment_cid : String
}

///|
/// The fixed preparation Owner calls this only after its original borrowers
/// and logical capacity have retired. These cached originals point back to
/// this preparation; sever them before the physical Read waits for aliases.
/// Escaped originals still retain their own data. This neither frees those
/// aliases nor acknowledges physical cleanup, grants execution or reissues
/// normalization/material custody.
pub fn clear_prepared_client_effect_custody_after_cleanup(
  owner : PreparedClientEffectComputation,
) -> Unit {
  owner.normalization_custody = None
  owner.normalization = None
}

///|
/// Private checked graph view for existing query acquisition and Local task
/// preparation. It never escapes as an Effect-free public preparation or
/// rechecks the Program under another owner.
fn client_effect_program_view(
  value : PreparedClientEffectComputation,
) -> PreparedClientProgram {
  {
    graph: @strategy.checked_effect_computation_graph(value.graph),
    source: value.source,
    sequence_preparation_demand: value.sequence_preparation_demand,
    local_values_max_rows: client_standard_values_sequence_limits().max_rows,
    check_environment_cid: value.check_environment_cid,
    local_normalization: None,
    full_sequences: [],
    task_pipeline_inputs: [],
    compiler_contracts: None,
  }
}

///|
/// Same checked projection demand as the Effect compiler and Local sequence
/// owner. This grants no rows, bindings, expression work or physical capacity.
pub fn prepared_client_effect_sequence_limits(
  value : PreparedClientEffectComputation,
) -> @lower.SequenceLimits {
  client_sequence_limits_with_projection_demand(
    value.sequence_preparation_demand,
  )
}

///|
pub fn prepare_client_effect_computation(
  document : String,
  format : @syntax.Format,
  environment : @checked.CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : ClientEffectComputationLimits,
  update_targets? : @update_targets.UpdateTargetPublication? = None,
  store_targets? : @update_targets.StoreTargetPublication? = None,
  command_targets? : @update_targets.CommandTargetPublication? = None,
  source_catalog? : @checked.PreparedSourceCatalog? = None,
) -> Result[PreparedClientEffectComputation, ClientEffectComputationIssue] {
  let parsed = match
    @syntax.parse(document, limits.program.checking.input, format~) {
    Ok(value) => value
    Err(issue) => return Err(Syntax(issue))
  }
  prepare_parsed_client_effect_computation(
    parsed,
    environment,
    supplied,
    evidence,
    limits,
    update_targets~,
    store_targets~,
    command_targets~,
    source_catalog~,
  )
}

///|
/// Preserve the parser's Program and supplied values at the frontend/Host
/// handoff. Static closure, Mapping admission and graph preparation remain
/// the same Effect owner as document-based preparation.
pub fn prepare_parsed_client_effect_computation(
  parsed : @syntax.Program,
  environment : @checked.CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : ClientEffectComputationLimits,
  update_targets? : @update_targets.UpdateTargetPublication? = None,
  store_targets? : @update_targets.StoreTargetPublication? = None,
  command_targets? : @update_targets.CommandTargetPublication? = None,
  source_catalog? : @checked.PreparedSourceCatalog? = None,
) -> Result[PreparedClientEffectComputation, ClientEffectComputationIssue] {
  if command_targets is Some(publication) &&
    !physical_equal(
      @checked.checking_environment_wire(environment),
      @update_targets.command_target_publication_environment(publication),
    ) {
    return Err(TargetSelection(ForeignEnvironment))
  }
  let computation = match
    @checked.prepare_effect_computation_candidate(
      parsed,
      environment,
      supplied,
      evidence,
      limits.program.checking,
      limits.max_members,
      limits.max_header_work,
      source_catalog~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Candidate(issue))
  }
  prepare_checked_client_effect_computation_owned(
    computation, limits, update_targets, store_targets, command_targets,
  )
}

///|
/// Continue the SAME original checked Effect computation. Mapping closure,
/// target selection, lowering and graph construction keep their original
/// owners and limits; there is no parser, checker or identity-based upgrade.
pub fn prepare_checked_client_effect_computation(
  computation : @checked.EffectComputationCandidate,
  limits : ClientEffectComputationLimits,
  update_targets? : @update_targets.UpdateTargetPublication? = None,
  store_targets? : @update_targets.StoreTargetPublication? = None,
  command_targets? : @update_targets.CommandTargetPublication? = None,
) -> Result[PreparedClientEffectComputation, ClientEffectComputationIssue] {
  if command_targets is Some(publication) &&
    !physical_equal(
      @checked.effect_computation_environment(computation),
      @update_targets.command_target_publication_environment(publication),
    ) {
    return Err(TargetSelection(ForeignEnvironment))
  }
  prepare_checked_client_effect_computation_owned(
    computation, limits, update_targets, store_targets, command_targets,
  )
}

///|
/// Completed original lowering Usage only, not complete binding/Graph work.
pub fn observe_prepare_checked_client_effect_computation(
  computation : @checked.EffectComputationCandidate,
  limits : ClientEffectComputationLimits,
  update_targets? : @update_targets.UpdateTargetPublication? = None,
  store_targets? : @update_targets.StoreTargetPublication? = None,
  command_targets? : @update_targets.CommandTargetPublication? = None,
) -> (
  Result[PreparedClientEffectComputation, ClientEffectComputationIssue],
  Int64,
) {
  if command_targets is Some(publication) &&
    !physical_equal(
      @checked.effect_computation_environment(computation),
      @update_targets.command_target_publication_environment(publication),
    ) {
    return (Err(TargetSelection(ForeignEnvironment)), 0L)
  }
  let work = Ref(0L)
  let result = prepare_checked_client_effect_computation_owned(
    computation,
    limits,
    update_targets,
    store_targets,
    command_targets,
    lowering_work_out=Some(work),
  )
  (result, work.val)
}

///|
fn prepare_checked_client_effect_computation_owned(
  computation : @checked.EffectComputationCandidate,
  limits : ClientEffectComputationLimits,
  update_targets : @update_targets.UpdateTargetPublication?,
  store_targets : @update_targets.StoreTargetPublication?,
  command_targets : @update_targets.CommandTargetPublication?,
  lowering_work_out? : Ref[Int64]? = None,
  source_intent? : ClientSubmittedIntent? = None,
) -> Result[PreparedClientEffectComputation, ClientEffectComputationIssue] {
  let mappings = match
    @environment.check_mapping_contract_shapes(
      @checked.effect_computation_environment(computation),
      limits.mapping,
      limits.max_mapping_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Mapping(issue))
  }
  let candidate = match
    @checked.close_effect_computation_static(
      computation,
      mappings,
      limits.effects,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Static(issue))
  }
  compile_static_client_effect_computation(
    candidate,
    @checked.effect_program_static_environment(candidate),
    limits.program,
    limits.max_mapping_work,
    update_targets,
    store_targets,
    command_targets,
    lowering_work_out~,
    source_intent~,
  )
}

///|
/// Continue from the same completed static Effect check without repeating
/// parsing, semantic checking, Mapping admission or static Effect closure.
/// The caller funds lowering and graph coexistence before entering here.
/// The original supplied values and Environment remain with the candidate;
/// this preparation grants neither Run admission nor Preview/apply authority.
pub fn prepare_static_client_effect_computation(
  candidate : @checked.EffectProgramStaticCandidate,
  limits : ClientProgramPreparationLimits,
  max_mapping_work : Int,
  update_targets? : @update_targets.UpdateTargetPublication? = None,
  store_targets? : @update_targets.StoreTargetPublication? = None,
  command_targets? : @update_targets.CommandTargetPublication? = None,
) -> Result[PreparedClientEffectComputation, ClientEffectComputationIssue] {
  let environment = @checked.effect_program_static_environment(candidate)
  if command_targets is Some(publication) &&
    !physical_equal(
      environment,
      @update_targets.command_target_publication_environment(publication),
    ) {
    return Err(TargetSelection(ForeignEnvironment))
  }
  compile_static_client_effect_computation(
    candidate, environment, limits, max_mapping_work, update_targets, store_targets,
    command_targets,
  )
}

///|
// Both entries consume the same static owner. Each entry checks its original
// command-target Environment once, at its own pre-construction boundary.
fn compile_static_client_effect_computation(
  candidate : @checked.EffectProgramStaticCandidate,
  environment : @environment.WireEnvironment,
  limits : ClientProgramPreparationLimits,
  max_mapping_work : Int,
  update_targets : @update_targets.UpdateTargetPublication?,
  store_targets : @update_targets.StoreTargetPublication?,
  command_targets : @update_targets.CommandTargetPublication?,
  lowering_work_out? : Ref[Int64]? = None,
  source_intent? : ClientSubmittedIntent? = None,
) -> Result[PreparedClientEffectComputation, ClientEffectComputationIssue] {
  let target_selections = match
    prepare_client_effect_target_selections(
      candidate,
      update_targets,
      max_mapping_work,
      store_targets~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(TargetSelection(issue))
  }
  let checked = @checked.effect_program_static_checked_computation(candidate)
  let owners = match
    prepare_client_stage_owners(
      checked,
      limits.lowering,
      max_parameters=limits.max_parameters,
      max_parameter_name_bytes=limits.max_parameter_name_bytes,
      lowering_work_out~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Stage(issue))
  }
  let sequence_preparation_demand = match
    client_sequence_preparation_demand(owners, limits.max_graph_work) {
    Ok(value) => value
    Err(issue) => return Err(Graph(issue))
  }
  let graph = match
    @strategy.prepare_checked_effect_computation_dag(
      candidate,
      owners,
      limits.max_tasks,
      limits.max_graph_work,
      captured_prefix=client_program_acquisition_prefix(checked),
      source_free_root=owners.length() > 0 &&
        @pipeline.starts_with_values(
          @lower.pipeline(@lower.bound_preparation(owners[0])),
        ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Graph(issue))
  }
  let (parsed, supplied) = @checked.effect_program_static_original_input(
    candidate,
  )
  Ok({
    target_selections,
    command_targets,
    normalization: None,
    normalization_custody: None,
    source_intent,
    source: parsed,
    supplied,
    candidate,
    sequence_preparation_demand,
    graph,
    check_environment_cid: @environment.cid(environment),
  })
}

///|
/// Borrow the same publication admitted at this preparation boundary. This
/// does not resolve aliases, issue a captured target, or authenticate saved
/// material. Restored DATA cannot reconstruct this original publication.
pub fn prepared_client_effect_command_target_publication(
  value : PreparedClientEffectComputation,
) -> @update_targets.CommandTargetPublication? {
  value.command_targets
}

///|
pub fn prepared_client_effect_computation_graph(
  value : PreparedClientEffectComputation,
) -> @strategy.CheckedEffectComputationDAG {
  value.graph
}

///|
/// The checked Result inventory is available before Run acceptance. Reading
/// it does not compile a second Program or grant execution authority.
pub fn prepared_client_effect_result_count(
  value : PreparedClientEffectComputation,
) -> Int {
  @strategy.graph_result_count(
    @strategy.checked_effect_computation_graph(value.graph),
  )
}

///|
pub fn prepared_client_effect_result_name(
  value : PreparedClientEffectComputation,
  index : Int,
) -> String? {
  @strategy.graph_result_name(
    @strategy.checked_effect_computation_graph(value.graph),
    index,
  )
}

///|
pub fn prepared_client_effect_computation_candidate(
  value : PreparedClientEffectComputation,
) -> @checked.EffectProgramStaticCandidate {
  value.candidate
}

///|
pub fn prepared_client_effect_computation_source(
  value : PreparedClientEffectComputation,
) -> @syntax.Program {
  value.source
}

///|
pub fn prepared_client_effect_computation_environment_cid(
  value : PreparedClientEffectComputation,
) -> String {
  value.check_environment_cid
}

///|
pub fn prepared_client_effect_computation_definition_cid(
  value : PreparedClientEffectComputation,
) -> String {
  @checked.effect_program_static_definition_cid(value.candidate)
}

///|
pub fn prepared_client_effect_computation_semantics_cid(
  value : PreparedClientEffectComputation,
) -> String {
  @checked.effect_program_static_semantics_cid(value.candidate)
}

///|
pub fn prepared_client_effect_identity(
  value : PreparedClientEffectComputation,
) -> ClientProgramIdentity {
  let checked = @checked.effect_program_static_checked_computation(
    value.candidate,
  )
  let source = @checked.source_identity(checked)
  {
    program_definition_cid: @context.program_identity_definition_cid(source),
    parameter_values_cid: @context.program_identity_parameter_values_cid(source),
  }
}

///|
/// Admit an Effectful Run only when the template, prepared invocation,
/// authorization, and compiled plan bind the exact checked Effect owner.
/// This is Run admission, not a Preview or mutation permit.
pub fn admit_prepared_client_effect_run_publication(
  value : PreparedClientEffectComputation,
  template : @publication.RunEvidenceValue,
  prepared : @publication.RunEvidenceValue,
  authorization : @publication.RunEvidenceValue,
  compiled_plan : @publication.PublicationContract,
) -> Result[
  @publication.RunPublicationAdmission,
  @publication.RunPublicationAdmissionIssue,
] {
  let identity = prepared_client_effect_identity(value)
  if @publication.publication_contract_effect_target_selections_cid(
      compiled_plan,
    ) !=
    client_effect_target_selections_cid(value) {
    return Err(@publication.RunAdmissionCheckedProgramMismatch)
  }
  @publication.admit_checked_run_publication(
    template,
    prepared,
    authorization,
    compiled_plan,
    identity.program_definition_cid,
    identity.parameter_values_cid,
    prepared_client_effect_computation_semantics_cid(value),
    prepared_client_effect_computation_environment_cid(value),
  )
}

///|
/// Bind the prepared computation to its admitted exact Run. This preserves
/// the Effect closure instead of passing only its graph to a source-free Host.
pub(all) enum ClientEffectRunIssue {
  Admission(@effect_binding.EffectProgramRunIssue)
  Binding(@strategy.RunIssue)
  TargetSelection
}

///|
struct PreparedClientEffectRun {
  computation : PreparedClientEffectComputation
  checked : @strategy.CheckedEffectRunDAG
  source_dispatch : @remote.DispatchRequest?
}

///|
pub fn bind_prepared_client_effect_run(
  computation : PreparedClientEffectComputation,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
) -> Result[PreparedClientEffectRun, ClientEffectRunIssue] {
  if @publication.publication_contract_effect_target_selections_cid(
      run_definition,
    ) !=
    client_effect_target_selections_cid(computation) {
    return Err(TargetSelection)
  }
  let owner = match
    @effect_binding.bind_effect_program_static_run(
      computation.candidate,
      admission,
      run_definition,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  let checked = match
    @strategy.bind_checked_effect_run_dag(computation.graph, owner) {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  Ok({ computation, checked, source_dispatch: None, })
}

///|
pub fn prepared_client_effect_run_graph(
  value : PreparedClientEffectRun,
) -> @strategy.CheckedEffectRunDAG {
  value.checked
}

///|
pub fn prepared_client_effect_run_computation(
  value : PreparedClientEffectRun,
) -> PreparedClientEffectComputation {
  value.computation
}

///|
/// Open only a source-free checked Effect Run. This creates an in-memory
/// compute owner after exact Run admission; it is not a mutation permit.
pub fn open_prepared_source_free_client_effect_run(
  value : PreparedClientEffectRun,
  limits : @resources.LedgerLimits,
) -> Result[@strategy.CapturedEffectRunDAG, ClientRunOpenIssue] {
  let ledger = match @resources.create_ledger(limits) {
    Ok(value) => value
    Err(issue) => return Err(Ledger(issue))
  }
  @strategy.open_source_free_effect_run_dag(value.checked, ledger).map_err(issue => {
    Run(issue)
  })
}

///|
/// Open the same checked Effect Run over one Host-retained acquisition. The
/// source owner must remain live until its computed consumers and Effect input
/// holdings are independently retained or released.
pub fn open_prepared_captured_client_effect_run(
  value : PreparedClientEffectRun,
  source : @query.CapturedInputSource,
  limits : @resources.LedgerLimits,
) -> Result[@strategy.CapturedEffectRunDAG, ClientRunOpenIssue] {
  let ledger = match @resources.create_ledger(limits) {
    Ok(value) => value
    Err(issue) => return Err(Ledger(issue))
  }
  @strategy.open_captured_effect_run_dag(value.checked, source, ledger).map_err(issue => {
      Run(issue)
    },
  )
}

///|
/// Acquisition and its registered Content family retain the original ledger.
/// The existing checked Source binding still decides whether Compute can open.
pub fn open_prepared_accounted_captured_client_effect_run(
  value : PreparedClientEffectRun,
  source : @query.CapturedInputSource,
  ledger : @resources.Ledger,
) -> Result[@strategy.CapturedEffectRunDAG, ClientRunOpenIssue] {
  @strategy.open_captured_effect_run_dag(value.checked, source, ledger).map_err(issue => {
      Run(issue)
    },
  )
}

///|
/// The two acquisition owners transfer their existing ledger and original
/// captures; opening Compute must not re-account them on a fresh ledger.
pub fn open_prepared_multi_captured_client_effect_run(
  value : PreparedClientEffectRun,
  sources : Array[(Int, @query.CapturedInputSource)],
  ledger : @resources.Ledger,
) -> Result[@strategy.CapturedEffectRunDAG, ClientRunOpenIssue] {
  @strategy.open_multi_captured_effect_run_dag(value.checked, sources, ledger).map_err(issue => {
      Run(issue)
    },
  )
}

///|
/// Compile an Effectful task through the same checked Local lowering as an
/// Effect-free task, without discarding its static Effect owner.
pub fn prepare_client_effect_task_sequence(
  value : PreparedClientEffectComputation,
  task : Int,
  contracts : @execution.RegisteredRelationContracts,
  contexts : Array[@execution.FragmentRuntimeContext],
  limits : @lower.SequenceLimits,
  max_work : Int,
  max_entries : Int,
  prepared_sequence? : @lower.PreparedSequence? = None,
) -> Result[@execution.GeneratedSequence, ClientTaskSequenceIssue] {
  prepare_client_task_sequence_graph(
    @strategy.checked_effect_computation_graph(value.graph),
    task,
    contracts,
    contexts,
    limits,
    max_work,
    max_entries,
    prepared_sequence~,
  )
}

///|
/// The effective publication policy comes from the original checked Result
/// provenance, including both acquisitions, rather than one installed alias.
pub fn prepared_client_effect_publication_data_policy_cid(
  value : PreparedClientEffectComputation,
) -> String? {
  prepared_client_publication_data_policy_cid(client_effect_program_view(value))
}
