///|
/// Host-selected limits for checking and lowering one Effect-free document.
/// They do not grant execution, publication or retained storage.
pub(all) struct ClientProgramPreparationLimits {
  checking : @checked.CheckLimits
  lowering : @lower.Limits
  max_parameters : Int
  max_parameter_name_bytes : Int
  max_tasks : Int
  max_graph_work : Int
  // Selected Local Values execution envelope; None retains ordinary demand.
  values_max_rows : Int?
}

///|
pub(all) enum ClientProgramPreparationIssue {
  Syntax(@syntax.SyntaxError)
  EffectNotSupported(String)
  ValuesProfileUnsupported
  NeedsInputs(@checked.InputRequests)
  Check(@checked.CheckDiagnostic)
  MissingCheckedStage(Int)
  MissingStageIdentity(Int)
  Lowering(@lower.Issue)
  Binding(@lower.BindingIssue)
  Graph(@strategy.GraphIssue)
}

///|
/// The checked graph owns the declared Result inventory. This value is a
/// preparation, not a durable Run acceptance or a physical Site selection.
struct PreparedClientProgram {
  graph : @strategy.CheckedDAG
  check_environment_cid : String
  source : @syntax.Program
  local_values_max_rows : Int
  sequence_preparation_demand : @lower.SequencePreparationDemand
  mut local_normalization : ClientLocalNormalization?
  full_sequences : Array[ClientFullSequence]
  task_pipeline_inputs : Array[ClientTaskPipelineRetained]
  mut compiler_contracts : ClientCompilerContracts?
}

///|
/// Trusted Local configuration for an already checked source-free Values
/// owner. This preserves the Program and its checker bindings; it does not
/// grant execution or increase cell, value, work, byte or ledger budgets.
/// Other execution profiles keep their existing bounds.
pub fn with_prepared_client_values_row_limit(
  value : PreparedClientProgram,
  max_rows : Int,
) -> PreparedClientProgram? {
  if !client_values_row_limit_supported(value.graph, max_rows) {
    return None
  }
  Some({
    ..value,
    local_values_max_rows: max_rows,
    full_sequences: [],
    task_pipeline_inputs: [],
  })
}

///|
fn client_values_row_limit_supported(
  graph : @strategy.CheckedDAG,
  max_rows : Int,
) -> Bool {
  // Rows are an explicit finite Host policy, not a product ceiling inferred
  // from a different unit (cells). Authored cell demand and actual resources
  // remain independently checked by lowering and the original capacity plan.
  if max_rows < 1 ||
    @strategy.graph_task_count(graph) != 1 ||
    client_graph_uses_graph_carrier(graph) {
    return false
  }
  guard @strategy.graph_task_owner(graph, 0) is Some(owner) else {
    return false
  }
  let prepared = @lower.bound_preparation(owner)
  let pipeline = @lower.pipeline(prepared)
  if !@pipeline.starts_with_values(pipeline) {
    return false
  }
  for step in 0..<@pipeline.step_count(pipeline) {
    if @lower.node_at(prepared, step) is Some(node) &&
      @lower.payload(node) is @lower.Infer(_) {
      return false
    }
  }
  true
}

///|
pub fn prepared_client_values_sequence_limits(
  value : PreparedClientProgram,
) -> @lower.SequenceLimits {
  {
    ..client_standard_values_sequence_limits(),
    max_rows: value.local_values_max_rows,
    max_cells: Int::max(
      client_standard_values_sequence_limits().max_cells,
      value.sequence_preparation_demand.authored_literal_cells,
    ),
  }
}

///|
/// Full lowering of the same original task. Runtime registry, contexts,
/// query-time binding, capacity and permission remain separate obligations.
pub fn prepare_prepared_client_full_sequence(
  value : PreparedClientProgram,
  task : Int,
  limits : @lower.SequenceLimits,
) -> Result[@lower.PreparedSequence, ClientValuesPipelineIssue] {
  prepared_client_full_sequence(value, task, limits)
}

///|
fn prepared_client_full_sequence(
  value : PreparedClientProgram,
  task : Int,
  limits : @lower.SequenceLimits,
  prepare? : (@lower.BoundPrepared, @lower.SequenceLimits) -> Result[
    @lower.PreparedSequence,
    @lower.SequenceIssue,
  ] = @lower.prepare_sequence,
) -> Result[@lower.PreparedSequence, ClientValuesPipelineIssue] {
  guard @strategy.graph_task_owner(value.graph, task) is Some(owner) else {
    return Err(MissingTask)
  }
  for retained in value.full_sequences {
    if retained.task == task &&
      physical_equal(@lower.sequence_owner(retained.sequence), owner) &&
      client_full_sequence_limits_match(retained.limits, limits) {
      return Ok(retained.sequence)
    }
  }
  let sequence = match prepare(owner, limits) {
    Ok(sequence) => sequence
    Err(issue) => return Err(Sequence(issue))
  }
  if !physical_equal(@lower.sequence_owner(sequence), owner) {
    return Err(MissingTask)
  }
  let retained = { task, limits, sequence, }
  for index in 0..<value.full_sequences.length() {
    if value.full_sequences[index].task == task {
      value.full_sequences[index] = retained
      return Ok(sequence)
    }
  }
  // Only a task of this checked graph can enter. One successful full sequence
  // per task is retained; changed limits replace it rather than growing a map.
  value.full_sequences.push(retained)
  Ok(sequence)
}

///|
priv struct ClientFullSequence {
  task : Int
  limits : @lower.SequenceLimits
  sequence : @lower.PreparedSequence
}

///|
fn client_full_sequence_limits_match(
  first : @lower.SequenceLimits,
  second : @lower.SequenceLimits,
) -> Bool {
  first.max_steps == second.max_steps &&
  first.max_rows == second.max_rows &&
  first.max_cells == second.max_cells &&
  first.max_bindings == second.max_bindings &&
  first.max_name_bytes == second.max_name_bytes &&
  first.expressions == second.expressions
}

///|
pub fn prepared_client_values_max_rows(value : PreparedClientProgram) -> Int {
  value.local_values_max_rows
}

///|
/// A checked Graph input needs the task compiler; the direct Values compiler
/// only represents Relation inputs. This reads the admitted owner, not source
/// text or a caller-supplied mode flag.
pub fn prepared_client_uses_graph_carrier(
  value : PreparedClientProgram,
) -> Bool {
  client_graph_uses_graph_carrier(value.graph)
}

///|
fn client_graph_uses_graph_carrier(graph : @strategy.CheckedDAG) -> Bool {
  for task in 0..<@strategy.graph_task_count(graph) {
    guard @strategy.graph_task_owner(graph, task) is Some(owner) else {
      continue
    }
    let pipeline = @lower.pipeline(@lower.bound_preparation(owner))
    for input in 0..<@pipeline.input_count(pipeline) {
      if @pipeline.input_at(pipeline, input) is Some((_, carrier)) &&
        @carrier.kind(carrier) == GraphKind {
        return true
      }
    }
  }
  false
}

///|
/// Select the compiler from the retained owner, without issuing a Run.
pub fn prepared_client_requires_task_compilation(
  value : PreparedClientProgram,
) -> Bool {
  if @strategy.graph_task_count(value.graph) > 1 ||
    prepared_client_result_count(value) != 1 ||
    prepared_client_uses_graph_carrier(value) {
    return true
  }
  if !@strategy.graph_source_free_inputs_complete(value.graph) {
    // A single captured task still has an original receiving input. The
    // direct Values compiler requires its own source-free Values root.
    return true
  }
  guard @strategy.graph_task_owner(value.graph, 0) is Some(owner) else {
    return false
  }
  let pipeline = @lower.pipeline(@lower.bound_preparation(owner))
  @pipeline.starts_with_selected_local_generator(pipeline) &&
  !@pipeline.starts_with_values(pipeline)
}

///|
/// The same checked Stage lowering is used by Effect-free and Effectful
/// computations. This does not admit an Effect or grant physical execution.
pub(all) enum ClientStageOwnerIssue {
  MissingCheckedStage(Int)
  MissingStageIdentity(Int)
  Lowering(@lower.Issue)
  Binding(@lower.BindingIssue)
}

///|
/// Checked identity components of one prepared Program. Request admission
/// additionally binds scope, authority, grants, owner and durability; these
/// two CIDs alone are not a complete Client request fingerprint.
pub(all) struct ClientProgramIdentity {
  program_definition_cid : String
  parameter_values_cid : String
} derive(Eq, Debug)

///|
pub fn prepared_client_identity(
  value : PreparedClientProgram,
) -> ClientProgramIdentity {
  let source = @checked.source_identity(@strategy.graph_program(value.graph))
  {
    program_definition_cid: @context.program_identity_definition_cid(source),
    parameter_values_cid: @context.program_identity_parameter_values_cid(source),
  }
}

///|
/// Return the semantic identity already sealed by the ordinary checker.
/// Publication may use it to bind a Compiled Plan, but this identity alone
/// does not authorize execution or attest to a physical executable plan.
pub fn prepared_client_program_semantics_cid(
  value : PreparedClientProgram,
) -> String {
  let source = @checked.source_identity(@strategy.graph_program(value.graph))
  @program_refs.program_definition_semantics_cid(
    @context.program_identity_definition(source),
  )
}

///|
pub(all) enum ClientIdentityMaterialIssue {
  MissingStage
  Encoding
}

///|
/// Emit the accepted, annotation-free AQL document retained with the checked
/// Program. A saved Plan must still replan this document with exact bindings.
pub fn emit_prepared_client_semantic_program(
  value : PreparedClientProgram,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientIdentityMaterialIssue] {
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  @syntax.emit_metadata_stripped_program(value.source, writer) catch {
    _ => return Err(Encoding)
  }
  let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok(body)
}

///|
/// Emit the Program Definition sealed by the checker, not a reconstruction
/// from the caller's document. This is private compilation material and does
/// not authorize a Run or establish an Executable Plan.
pub fn emit_prepared_client_program_definition(
  value : PreparedClientProgram,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientIdentityMaterialIssue] {
  let source = @checked.source_identity(@strategy.graph_program(value.graph))
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  @program_refs.emit_program_definition(
    @context.program_identity_definition(source),
    writer,
  ) catch {
    _ => return Err(Encoding)
  }
  let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok(body)
}

///|
/// Emit the annotation-free Program Semantics behind the checked Definition.
/// Its CID is already bound into that Definition, and no Host input may
/// replace the stage inventory or semantic references here.
pub fn emit_prepared_client_program_semantics(
  value : PreparedClientProgram,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientIdentityMaterialIssue] {
  let source = @checked.source_identity(@strategy.graph_program(value.graph))
  let definition = @context.program_identity_definition(source)
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  @program_refs.emit_program_semantics(
    @program_refs.program_definition_semantics(definition),
    writer,
  ) catch {
    _ => return Err(Encoding)
  }
  let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok(body)
}

///|
/// Emit one checked Stage Semantics body by its declared stage ordinal.
pub fn emit_prepared_client_stage_semantics(
  value : PreparedClientProgram,
  stage : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientIdentityMaterialIssue] {
  let source = @checked.source_identity(@strategy.graph_program(value.graph))
  guard @context.program_identity_stage_at(source, stage) is Some(stage_owner) else {
    return Err(MissingStage)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  @program_refs.emit_stage_semantics(
    @program_refs.stage_definition_semantics(
      @context.stage_identity_definition(stage_owner),
    ),
    writer,
  ) catch {
    _ => return Err(Encoding)
  }
  let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok(body)
}

///|
pub fn prepared_client_check_environment_cid(
  value : PreparedClientProgram,
) -> String {
  value.check_environment_cid
}

///|
/// Admit publication authority only when it names the exact checked source
/// and effective Parameter Values of this prepared Client Program.
pub fn admit_prepared_client_run_publication(
  value : PreparedClientProgram,
  template : @publication.RunEvidenceValue,
  prepared : @publication.RunEvidenceValue,
  authorization : @publication.RunEvidenceValue,
  compiled_plan : @publication.PublicationContract,
) -> Result[
  @publication.RunPublicationAdmission,
  @publication.RunPublicationAdmissionIssue,
] {
  let identity = prepared_client_identity(value)
  if @publication.publication_contract_effect_target_selections_cid(
      compiled_plan,
    )
    is Some(_) {
    return Err(@publication.RunAdmissionCheckedProgramMismatch)
  }
  @publication.admit_checked_run_publication(
    template,
    prepared,
    authorization,
    compiled_plan,
    identity.program_definition_cid,
    identity.parameter_values_cid,
    prepared_client_program_semantics_cid(value),
    prepared_client_check_environment_cid(value),
  )
}

///|
pub fn prepared_client_graph(
  value : PreparedClientProgram,
) -> @strategy.CheckedDAG {
  value.graph
}

///|
pub(all) enum ClientRunOpenIssue {
  Ledger(@resources.LedgerIssue)
  Run(@strategy.RunIssue)
}

///|
/// Open an admitted source-free preparation in the existing checked task
/// lifecycle. The Host must durably admit a Client request before starting
/// physical work; opening this in-memory task owner is not that admission.
pub fn open_prepared_source_free_client_run(
  value : PreparedClientProgram,
  limits : @resources.LedgerLimits,
) -> Result[@strategy.CapturedDAG, ClientRunOpenIssue] {
  let ledger = match @resources.create_ledger(limits) {
    Ok(value) => value
    Err(issue) => return Err(Ledger(issue))
  }
  @strategy.open_source_free_dag(value.graph, ledger).map_err(issue => {
    Run(issue)
  })
}

///|
/// Open the same checked task lifecycle over one verified acquired source.
/// The physical adapter retains the capture; this does not issue a Run or
/// authorize an external read.
pub fn open_prepared_captured_client_run(
  value : PreparedClientProgram,
  source : @query.CapturedInputSource,
  limits : @resources.LedgerLimits,
) -> Result[@strategy.CapturedDAG, ClientRunOpenIssue] {
  let ledger = match @resources.create_ledger(limits) {
    Ok(value) => value
    Err(issue) => return Err(Ledger(issue))
  }
  @strategy.open_captured_dag(value.graph, source, ledger).map_err(issue => {
    Run(issue)
  })
}

///|
pub fn prepared_client_result_count(value : PreparedClientProgram) -> Int {
  @strategy.graph_result_count(value.graph)
}

///|
pub fn prepared_client_result_name(
  value : PreparedClientProgram,
  index : Int,
) -> String? {
  @strategy.graph_result_name(value.graph, index)
}

///|
pub(all) enum ClientPublicationLimitScope {
  Rows
  Bytes
}

///|
pub(all) enum ClientPublicationLimitIssue {
  MissingPublication
  Encoding
} derive(Eq, Debug)

///|
/// Emit the already checked publication limit for one Unit Result. Its
/// subject, witnesses, effective maximum and self CID come from the common
/// capacity owner. Unit ordinals are private compiler coordinates, not public
/// Result selection or a new Host policy decision.
pub fn emit_prepared_client_publication_limit(
  value : PreparedClientProgram,
  unit : Int,
  index : Int,
  scope : ClientPublicationLimitScope,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientPublicationLimitIssue] {
  let program = @strategy.graph_program(value.graph)
  guard @checked.unit_publication_at(program, unit, index) is Some(publication) else {
    return Err(MissingPublication)
  }
  let claim = match scope {
    Rows => @checked.publication_rows(publication)
    Bytes => @checked.publication_bytes(publication)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  @capacity.emit_limit(claim, writer) catch {
    _ => return Err(Encoding)
  }
  let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok(body)
}

///|
pub(all) enum ClientTaskAoAStepsIssue {
  MissingTask
  Sequence(@lower.SequenceIssue)
  Encoding
}

///|
/// Emit the bounded, parameter-bound AoA steps from the checked task owner.
/// These bytes are compilation material, not an Executable Plan or Run grant.
pub fn emit_prepared_client_task_aoa_steps(
  value : PreparedClientProgram,
  task : Int,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientTaskAoAStepsIssue] {
  let sequence = match
    prepare_prepared_client_full_sequence(value, task, limits) {
    Ok(result) => result
    Err(Sequence(issue)) => return Err(Sequence(issue))
    Err(_) => return Err(MissingTask)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_sequence_steps(
    sequence,
    0,
    @lower.sequence_count(sequence),
    {
      max_body_bytes: max_wire_bytes,
      max_body_nodes: max_nodes,
      max_body_depth: max_depth,
    },
    writer,
    compiler_contracts=value.compiler_contracts,
  ) catch {
    _ => return Err(Encoding)
  }
  let steps = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok(steps)
}

///|
pub(all) enum ClientTaskPipelineIssue {
  MissingTask
  MissingOutput
  UnsupportedCarrier
  Sequence(@lower.SequenceIssue)
  Encoding
}

///|
/// The physical task output can be an authored selected step, a retained
/// prefix end, or the terminal step of an unsplit pipeline.
fn client_task_output_step(
  graph : @strategy.CheckedDAG,
  task : Int,
  count : Int,
) -> Int? {
  if count <= 0 {
    return None
  }
  let step = @strategy.graph_task_selected_step(graph, task).unwrap_or(
    @strategy.graph_task_prefix_end(graph, task).unwrap_or(count - 1),
  )
  if step < 0 || step >= count {
    None
  } else {
    Some(step)
  }
}

///|
/// Resolve a physical output against its checked owner. An empty preparation
/// has a receiving input port, not a fabricated operation or output node.
fn client_task_output_target(
  graph : @strategy.CheckedDAG,
  task : Int,
) -> @pipeline.Target? {
  guard @strategy.graph_task_owner(graph, task) is Some(owner) else {
    return None
  }
  let prepared = @lower.bound_preparation(owner)
  if @lower.node_count(prepared) == 0 {
    return @strategy.graph_task_target(graph, task).bind(target => {
      match target {
        @pipeline.Input(_) =>
          @lower.preparation_carrier_at(prepared, target).map(_ => target)
        _ => None
      }
    })
  }
  client_task_output_step(graph, task, @lower.node_count(prepared)).map(step => {
    @pipeline.Step(step)
  })
}

///|
fn client_task_target_port(
  prepared : @lower.Prepared,
  target : @pipeline.Target,
) -> String? {
  match target {
    @pipeline.Input(index) =>
      @pipeline.input_at(@lower.pipeline(prepared), index).map(input => input.0)
    @pipeline.Step(index) => @lower.node_at(prepared, index).map(@lower.node_id)
  }
}

///|
/// Emit the checked AoA pipeline of one task, including its declared input
/// ports. A source input remains an input port; this does not claim that its
/// physical acquisition, barrier, or Run observation has been admitted.
priv struct ClientTaskPipelineInput {
  owner : @lower.BoundPrepared
  sequence : @lower.PreparedSequence
  end_step : Int
  output : String
  selected : Int?
  prefix_end : Int?
  first_sequence_step : Int
  sequence_end : Int
  mut emission : ClientTaskPipelineEmission?
  compiler_contracts : ClientCompilerContracts?
}

///|
priv struct ClientTaskPipelineEmission {
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  steps : ClientSequenceEmission
}

///|
fn client_task_pipeline_emission(
  input : ClientTaskPipelineInput,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  prepare? : (@lower.PreparedSequence, Int, Int, @execution.RegistryLimits) -> ClientSequenceEmission raise @encode.EncodeFailure = prepare_client_sequence_steps,
) -> ClientSequenceEmission raise @encode.EncodeFailure {
  if input.emission is Some(retained) &&
    retained.max_wire_bytes == max_wire_bytes &&
    retained.max_nodes == max_nodes &&
    retained.max_depth == max_depth {
    return retained.steps
  }
  let physical : @execution.RegistryLimits = {
    max_body_bytes: max_wire_bytes,
    max_body_nodes: max_nodes,
    max_body_depth: max_depth,
  }
  let steps = match input.compiler_contracts {
    Some(original) =>
      prepare_client_sequence_steps_owned(
        input.sequence,
        input.first_sequence_step,
        input.sequence_end,
        physical,
        Some(original),
      )
    None =>
      prepare(
        input.sequence,
        input.first_sequence_step,
        input.sequence_end,
        physical,
      )
  }
  // The ordered-reference work and registered contract belong to this exact
  // sequence/range and codec profile, not to another Program or new bounds.
  input.emission = Some({ max_wire_bytes, max_nodes, max_depth, steps, })
  steps
}

///|
priv struct ClientTaskPipelineRetained {
  task : Int
  limits : @lower.SequenceLimits
  input : ClientTaskPipelineInput
}

///|
fn retain_client_task_pipeline_input(
  original : PreparedClientProgram,
  task : Int,
  limits : @lower.SequenceLimits,
  prepared : Result[ClientTaskPipelineInput, ClientTaskPipelineIssue],
) -> Result[ClientTaskPipelineInput, ClientTaskPipelineIssue] {
  let input = match prepared {
    Ok(input) => input
    Err(issue) => return Err(issue)
  }
  let retained = { task, limits, input, }
  for index in 0..<original.task_pipeline_inputs.length() {
    if original.task_pipeline_inputs[index].task == task {
      original.task_pipeline_inputs[index] = retained
      return Ok(input)
    }
  }
  // One successful selection per original graph task. Changed limits replace
  // it; a failed preparation cannot overwrite an earlier successful selection.
  original.task_pipeline_inputs.push(retained)
  Ok(input)
}

///|
pub fn emit_prepared_client_task_pipeline(
  value : PreparedClientProgram,
  task : Int,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientTaskPipelineIssue] {
  construct_prepared_client_task_pipeline(
    value, task, limits, max_wire_bytes, max_nodes, max_depth,
  ).map(original => original.wire)
}

///|
// The canonical reader already admitted this exact body before its original
// final stringify. Retaining that SAME immutable value avoids parsing our own
// wire again at Fragment construction. This private per-call data is neither
// a foreign-wire admission nor a grant; it is not cached on a Program or Run.
priv struct ClientTaskPipelineConstruction {
  wire : String
  body : @canonical.CanonicalValue
}

///|
fn construct_prepared_client_task_pipeline(
  value : PreparedClientProgram,
  task : Int,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskPipelineConstruction, ClientTaskPipelineIssue] {
  let input = match
    prepare_prepared_client_task_pipeline_input(value, task, limits) {
    Ok(input) => input
    Err(issue) => return Err(issue)
  }
  construct_client_task_pipeline(input, max_wire_bytes, max_nodes, max_depth)
}

///|
/// Measure the actual initial Task pipeline writer, before canonical admission
/// and selected-task projection. This is not the final projected wire size or
/// a grant for lowering, parsing, projection or their overlapping live bodies.
/// The same original task/limits retain the selected sequence for construction.
pub fn measure_prepared_client_task_pipeline_input(
  value : PreparedClientProgram,
  task : Int,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(Int, Int, Int), ClientTaskPipelineIssue] {
  let input = match
    prepare_prepared_client_task_pipeline_input(value, task, limits) {
    Ok(input) => input
    Err(issue) => return Err(issue)
  }
  measure_client_task_pipeline_input(
    input, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
fn measure_client_task_pipeline_input(
  input : ClientTaskPipelineInput,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(Int, Int, Int), ClientTaskPipelineIssue] {
  try {
    let writer = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_task_pipeline_input_body(
      input, max_wire_bytes, max_nodes, max_depth, writer,
    )
    Ok(@encode.finish_measurement_usage(writer))
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// Initial writer geometry and a bound on the final selected pipeline. The
/// initial extent is exact. Projected bytes are an upper bound; nodes/depth
/// retain the same structural counts. Neither tuple admits a pipeline or
/// replaces the original constructor's canonical, reference or codec checks.
pub fn measure_prepared_client_task_pipeline_construction(
  value : PreparedClientProgram,
  task : Int,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[((Int, Int, Int), (Int, Int, Int)), ClientTaskPipelineIssue] {
  let input = match
    prepare_prepared_client_task_pipeline_input(value, task, limits) {
    Ok(input) => input
    Err(issue) => return Err(issue)
  }
  measure_client_task_pipeline_construction(
    input, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
// SAME original selected pipeline measurement for ordinary tasks and private
// Content/Model prefix constructors. No pipeline wire or identity is issued.
fn measure_client_task_pipeline_construction(
  input : ClientTaskPipelineInput,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[((Int, Int, Int), (Int, Int, Int)), ClientTaskPipelineIssue] {
  let initial = match
    measure_client_task_pipeline_input(
      input, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(geometry) => geometry
    Err(issue) => return Err(issue)
  }
  if input.selected is None && input.prefix_end is None {
    // The preserving canonical reader changes object order, not this emitted
    // structure, keys, scalar text or already canonical Number encodings.
    return Ok((initial, initial))
  }
  try {
    let retained = client_task_pipeline_emission(
      input, max_wire_bytes, max_nodes, max_depth,
    )
    let slice_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    emit_prepared_client_sequence_range(
      retained,
      input.selected.unwrap_or(0),
      input.end_step + 1,
      slice_writer,
    )
    let slice = @encode.finish_measurement_usage(slice_writer)
    let label_bytes = if input.selected is Some(step) {
      let count = @lower.node_at(@lower.bound_preparation(input.owner), step)
        .map(@lower.node_input_count)
        .unwrap_or(0)
      if count == 0 {
        0
      } else {
        let label = @encode.measuring_writer(
          max_wire_bytes, max_nodes, max_depth,
        )
        @encode.string_value(label, "input_" + (count - 1).to_string())
        @encode.finish_measurement(label)
      }
    } else {
      0
    }
    // Every replaced reference is a String value node. Count all slice nodes
    // as a conservative occurrence bound, even if most are other payloads;
    // no old reference length is subtracted. Generated labels are ASCII and
    // the largest input ordinal has the longest exact encoded label.
    let step_bytes_upper = if label_bytes == 0 {
      slice.0.to_int64()
    } else {
      guard @execution.checked_preparation_add_product(
          slice.0.to_int64(),
          slice.1.to_int64(),
          label_bytes.to_int64(),
        )
        is Some(bytes) else {
        return Err(Encoding)
      }
      bytes
    }
    let empty = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_array(empty)
    @encode.end_array(empty)
    let empty_steps = @encode.finish_measurement_usage(empty)
    let header_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    match
      emit_client_task_pipeline_body(
        input, true, empty_steps, emit_client_task_pipeline_measurement, header_writer,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let header = @encode.finish_measurement_usage(header_writer)
    // Any successful final writer already satisfies its selected codec bound.
    // Clamp only the sizing bound for its subtree to the exact shared header's
    // remaining byte room. This does not alter admission or a Resource policy.
    let step_room = max_wire_bytes.to_int64() -
      header.0.to_int64() +
      empty_steps.0.to_int64()
    let steps_upper = (
      Int64::min(step_room, step_bytes_upper).to_int(),
      slice.1,
      slice.2,
    )
    let writer = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth)
    match
      emit_client_task_pipeline_body(
        input, true, steps_upper, emit_client_task_pipeline_measurement, writer,
      ) {
      Ok(_) => Ok((initial, @encode.finish_measurement_usage(writer)))
      Err(issue) => Err(issue)
    }
  } catch {
    _ => Err(Encoding)
  }
}

///|
fn prepare_prepared_client_task_pipeline_input(
  value : PreparedClientProgram,
  task : Int,
  limits : @lower.SequenceLimits,
) -> Result[ClientTaskPipelineInput, ClientTaskPipelineIssue] {
  guard @strategy.graph_task_owner(value.graph, task) is Some(owner) else {
    return Err(MissingTask)
  }
  for retained in value.task_pipeline_inputs {
    if retained.task == task &&
      physical_equal(retained.input.owner, owner) &&
      client_full_sequence_limits_match(retained.limits, limits) {
      return Ok(retained.input)
    }
  }
  let pipeline = @lower.pipeline(@lower.bound_preparation(owner))
  let count = @pipeline.step_count(pipeline)
  let selected = @strategy.graph_task_selected_step(value.graph, task)
  let prefix_end = @strategy.graph_task_prefix_end(value.graph, task)
  if count == 0 {
    guard client_task_output_target(value.graph, task) is Some(target) &&
      client_task_target_port(@lower.bound_preparation(owner), target)
      is Some(port) else {
      return Err(MissingOutput)
    }
    return retain_client_task_pipeline_input(
      value,
      task,
      limits,
      prepare_client_task_pipeline_input(
        owner,
        -1,
        port,
        None,
        None,
        false,
        limits,
        preparation=Some((value, task)),
      ),
    )
  }
  guard client_task_output_step(value.graph, task, count) is Some(end_step) &&
    @lower.node_at(@lower.bound_preparation(owner), end_step) is Some(output) else {
    return Err(MissingOutput)
  }
  // Selected consumers of a Content completion retain the original checked
  // producer boundary, rather than trying to lower generation as pure Compute.
  let mut completed_serialization = None
  let mut completed_infer = None
  if selected is Some(step) {
    let prepared = @lower.bound_preparation(owner)
    for producer in 0..<step {
      if @lower.node_at(prepared, producer) is Some(node) &&
        @lower.payload(node) is @lower.Serialize(_) {
        completed_serialization = Some((producer, end_step))
      }
    }
    for
      occurrence in prepared_client_composed_infer_occurrences(value).unwrap_or([],
      ) {
      if physical_equal(occurrence.preparation, owner) && occurrence.step < step {
        completed_infer = Some(occurrence.step)
      }
    }
  }
  retain_client_task_pipeline_input(
    value,
    task,
    limits,
    prepare_client_task_pipeline_input(
      owner,
      end_step,
      @lower.node_id(output),
      selected,
      prefix_end,
      selected is Some(_) && completed_serialization is None,
      limits,
      infer_boundary=completed_infer,
      completed_serialization~,
      preparation=Some((value, task)),
    ),
  )
}

///|
/// The caller chooses a checked output before preparing pure computation.
/// Acquisition steps after that output must not enter its AoA fragment.
fn prepare_client_task_pipeline_input(
  owner : @lower.BoundPrepared,
  end_step : Int,
  output : String,
  selected : Int?,
  prefix_end : Int?,
  acquisition_prefix : Bool,
  limits : @lower.SequenceLimits,
  infer_boundary? : Int? = None,
  serialization_input? : @lower.PreparedSerialization? = None,
  completed_serialization? : (Int, Int)? = None,
  serialization_boundary? : Int? = None,
  preparation? : (PreparedClientProgram, Int)? = None,
) -> Result[ClientTaskPipelineInput, ClientTaskPipelineIssue] {
  let prepared_sequence = if completed_serialization
    is Some((producer, terminal)) {
    guard serialization_input is None &&
      infer_boundary is None &&
      selected is Some(step) &&
      producer < step &&
      step <= terminal &&
      end_step == step else {
      return Err(Encoding)
    }
    @lower.prepare_serialization_consumer_sequence(
      owner, producer, terminal, limits,
    )
  } else if serialization_input is Some(barrier) {
    if !physical_equal(@lower.serialization_owner(barrier), owner) ||
      @lower.serialization_step(barrier) != end_step ||
      @pipeline.serialization_sort(@lower.serialization_checked(barrier))
      is None ||
      infer_boundary is Some(_) ||
      (selected is Some(step) && step != end_step) {
      return Err(Encoding)
    }
    @lower.prepare_serialization_input_sequence(barrier, limits)
  } else if infer_boundary is Some(step) {
    @lower.prepare_sequence_with_infer_boundary(
      owner,
      step,
      limits,
      serialization=serialization_boundary,
    )
  } else if acquisition_prefix {
    @lower.prepare_sequence_prefix(owner, end_step, limits)
  } else if preparation is Some((original, task)) {
    guard @strategy.graph_task_owner(original.graph, task) is Some(selected) &&
      physical_equal(selected, owner) else {
      return Err(MissingTask)
    }
    // Reuse the SAME full lowering already retained by this Program/module.
    // Selected acquisition, Model and Content prefixes stay on their distinct
    // branches above; an equal owner or different limits cannot supply it.
    match prepare_prepared_client_full_sequence(original, task, limits) {
      Ok(sequence) => Ok(sequence)
      Err(Sequence(issue)) => Err(issue)
      Err(_) => return Err(MissingTask)
    }
  } else {
    @lower.prepare_sequence(owner, limits)
  }
  let sequence = match prepared_sequence {
    Ok(value) => value
    Err(issue) => return Err(Sequence(issue))
  }
  let (first_sequence_step, sequence_end) = if infer_boundary is Some(_) ||
    completed_serialization is Some(_) {
    guard selected is Some(step) else { return Err(Encoding) }
    (step, step + 1)
  } else {
    (0, @lower.sequence_count(sequence))
  }
  Ok({
    owner,
    sequence,
    end_step,
    output,
    selected,
    prefix_end,
    first_sequence_step,
    sequence_end,
    emission: None,
    compiler_contracts: preparation.bind(pair => pair.0.compiler_contracts),
  })
}

///|
fn construct_client_task_pipeline_prefix(
  owner : @lower.BoundPrepared,
  end_step : Int,
  output : String,
  selected : Int?,
  prefix_end : Int?,
  acquisition_prefix : Bool,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  infer_boundary? : Int? = None,
  serialization_input? : @lower.PreparedSerialization? = None,
  completed_serialization? : (Int, Int)? = None,
  serialization_boundary? : Int? = None,
  preparation? : (PreparedClientProgram, Int)? = None,
) -> Result[ClientTaskPipelineConstruction, ClientTaskPipelineIssue] {
  let input = match
    prepare_client_task_pipeline_input(
      owner,
      end_step,
      output,
      selected,
      prefix_end,
      acquisition_prefix,
      limits,
      infer_boundary~,
      serialization_input~,
      completed_serialization~,
      serialization_boundary~,
      preparation~,
    ) {
    Ok(input) => input
    Err(issue) => return Err(issue)
  }
  construct_client_task_pipeline(input, max_wire_bytes, max_nodes, max_depth)
}

///|
fn emit_client_task_pipeline_measurement(
  measurement : (Int, Int, Int),
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.emit_measurement(writer, measurement)
}

///|
fn[T] emit_client_task_pipeline_body(
  input : ClientTaskPipelineInput,
  projected : Bool,
  steps : T,
  emit_steps : (T, @encode.Writer) -> Unit raise @encode.EncodeFailure,
  writer : @encode.Writer,
) -> Result[Unit, ClientTaskPipelineIssue] raise @encode.EncodeFailure {
  let prepared = @lower.bound_preparation(input.owner)
  let pipeline = @lower.pipeline(prepared)
  @encode.begin_object(writer)
  @encode.key(writer, "output")
  @encode.string_value(writer, input.output)
  @encode.key(writer, "sources")
  @encode.begin_object(writer)
  if projected && input.selected is Some(step) {
    let node = @lower.node_at(prepared, step).unwrap()
    for index in 0..<@lower.node_input_count(node) {
      guard @lower.node_input_target(node, index) is Some(target) &&
        @lower.preparation_carrier_at(prepared, target) is Some(carrier) else {
        return Err(UnsupportedCarrier)
      }
      @encode.key(writer, "input_" + index.to_string())
      @encode.begin_object(writer)
      @encode.key(writer, "sort")
      @encode.string_value(writer, client_task_carrier_sort(carrier))
      @encode.end_object(writer)
    }
  } else {
    for index in 0..<@pipeline.input_count(pipeline) {
      guard @pipeline.input_at(pipeline, index) is Some((name, carrier)) else {
        return Err(if projected { UnsupportedCarrier } else { Encoding })
      }
      @encode.key(writer, name)
      @encode.begin_object(writer)
      @encode.key(writer, "sort")
      @encode.string_value(writer, client_task_carrier_sort(carrier))
      @encode.end_object(writer)
    }
  }
  @encode.end_object(writer)
  @encode.key(writer, "steps")
  emit_steps(steps, writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "aoa-pipeline/0.1")
  @encode.end_object(writer)
  Ok(())
}

///|
fn emit_client_task_pipeline_initial_steps(
  input : (ClientTaskPipelineInput, Int, Int, Int),
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_prepared_client_sequence_steps(
    client_task_pipeline_emission(input.0, input.1, input.2, input.3),
    writer,
  )
}

///|
fn emit_client_task_pipeline_input_body(
  input : ClientTaskPipelineInput,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  match
    emit_client_task_pipeline_body(
      input,
      false,
      (input, max_wire_bytes, max_nodes, max_depth),
      emit_client_task_pipeline_initial_steps,
      writer,
    ) {
    Ok(_) => ()
    Err(_) => raise @encode.InvalidStructure
  }
}

///|
priv struct ClientTaskPipelineProjection {
  selected : Int?
  included : Array[String]
  remap : Array[(String, String)]
  step_values : @canonical.FrozenArray[@canonical.CanonicalValue]
}

///|
fn emit_client_task_pipeline_projected_steps(
  input : ClientTaskPipelineProjection,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(writer)
  let mut emitted = 0
  for node in @canonical.array_values(input.step_values) {
    guard @canonical.object_field(node, "id") is Some(@canonical.String(id)) else {
      raise @encode.InvalidStructure
    }
    if !input.included.contains(id) {
      continue
    }
    emitted += 1
    if input.selected is None {
      @canonical.emit_value(node, writer)
      continue
    }
    guard @canonical.object_fields(node) is Some(fields) else {
      raise @encode.InvalidStructure
    }
    @encode.begin_object(writer)
    for (key, field) in fields {
      @encode.key(writer, key)
      if key == "in" {
        guard field is @canonical.Array(refs) else {
          raise @encode.InvalidStructure
        }
        @encode.begin_array(writer)
        for reference in @canonical.array_values(refs) {
          guard reference is @canonical.String(name) else {
            raise @encode.InvalidStructure
          }
          let mut resolved = if input.included.contains(name) {
            Some(name)
          } else {
            None
          }
          if resolved is None {
            for pair in input.remap {
              if pair.0 == name {
                resolved = Some(pair.1)
                break
              }
            }
          }
          guard resolved is Some(port) else { raise @encode.InvalidStructure }
          @encode.string_value(writer, port)
        }
        @encode.end_array(writer)
      } else {
        @canonical.emit_value(field, writer)
      }
    }
    @encode.end_object(writer)
  }
  if emitted != input.included.length() {
    raise @encode.InvalidStructure
  }
  @encode.end_array(writer)
}

///|
fn construct_client_task_pipeline(
  input : ClientTaskPipelineInput,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskPipelineConstruction, ClientTaskPipelineIssue] {
  let { owner, sequence, end_step, selected, prefix_end, .. } = input
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    emit_client_task_pipeline_input_body(
      input, max_wire_bytes, max_nodes, max_depth, writer,
    )
    let raw = @encode.finish(writer)
    guard parse_plan_identity_value(raw, max_wire_bytes, max_nodes, max_depth)
      is Some(body) else {
      return Err(Encoding)
    }
    if selected is None && prefix_end is None {
      let wire = @canonical.stringify_value(
        body, max_wire_bytes, max_nodes, max_depth,
      )
      return Ok({ wire, body, })
    }
    let first_step = selected.unwrap_or(0)
    let included : Array[String] = []
    for step in first_step..<(end_step + 1) {
      guard @lower.sequence_canonical_node_count(sequence, step)
        is Some(node_count) else {
        return Err(Encoding)
      }
      for occurrence in 0..<node_count {
        guard @lower.sequence_canonical_node_at(sequence, step, occurrence)
          is Some(node) else {
          return Err(Encoding)
        }
        included.push(node.id)
      }
    }
    let remap : Array[(String, String)] = []
    if selected is Some(step) {
      guard @lower.node_at(@lower.bound_preparation(owner), step)
        is Some(selected_node) else {
        return Err(Encoding)
      }
      for input in 0..<@lower.node_input_count(selected_node) {
        let original = match @lower.node_input_target(selected_node, input) {
          Some(@pipeline.Step(producer)) =>
            match @lower.node_at(@lower.bound_preparation(owner), producer) {
              Some(node) => @lower.node_id(node)
              None => return Err(Encoding)
            }
          Some(@pipeline.Input(source)) => "input_" + source.to_string()
          None => return Err(Encoding)
        }
        remap.push((original, "input_" + input.to_string()))
      }
    }
    guard @canonical.object_field(body, "steps")
      is Some(@canonical.Array(step_values)) else {
      return Err(Encoding)
    }
    let task_writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    match
      emit_client_task_pipeline_body(
        input,
        true,
        { selected, included, remap, step_values, },
        emit_client_task_pipeline_projected_steps,
        task_writer,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let task_raw = @encode.finish(task_writer)
    guard parse_plan_identity_value(
        task_raw, max_wire_bytes, max_nodes, max_depth,
      )
      is Some(task_body) else {
      return Err(Encoding)
    }
    let wire = @canonical.stringify_value(
      task_body, max_wire_bytes, max_nodes, max_depth,
    )
    Ok({ wire, body: task_body, })
  } catch {
    _ => Err(Encoding)
  }
}

///|
pub(all) enum ClientValuesPipelineIssue {
  MissingTask
  Sequence(@lower.SequenceIssue)
  NotSingleValues
  Encoding
}

///|
/// Emit the checked source-free Values pipeline for the first product
/// compilation path. Its identity still needs complete Plan bindings.
pub fn emit_prepared_client_values_pipeline(
  value : PreparedClientProgram,
  task : Int,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientValuesPipelineIssue] {
  emit_client_values_pipeline_graph(
    value.graph,
    task,
    limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
    preparation=Some(value),
  )
}

///|
fn emit_client_values_pipeline_graph(
  graph : @strategy.CheckedDAG,
  task : Int,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  preparation? : PreparedClientProgram? = None,
) -> Result[String, ClientValuesPipelineIssue] {
  // The enclosing original funds this measuring pass before construction.
  // Materialization is bounded by the exact usage of this same serializer;
  // measurement neither creates a new grant nor retains another wire.
  let (bytes, nodes, depth) = match
    measure_client_values_pipeline_graph(
      graph,
      task,
      limits,
      max_wire_bytes,
      max_nodes,
      max_depth,
      preparation~,
    ) {
    Err(issue) => return Err(issue)
    Ok(usage) => usage
  }
  let writer = @encode.writer(bytes, nodes, depth) catch {
    _ => return Err(Encoding)
  }
  match
    emit_client_values_pipeline_into(
      graph,
      task,
      limits,
      max_wire_bytes,
      max_nodes,
      max_depth,
      writer,
      preparation~,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok(body)
}

///|
/// One serializer serves measurement and materialization. The caller retains
/// the same checked preparation and supplies its funded encoding envelope.
fn emit_client_values_pipeline_into(
  graph : @strategy.CheckedDAG,
  task : Int,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  writer : @encode.Writer,
  preparation? : PreparedClientProgram? = None,
) -> Result[Unit, ClientValuesPipelineIssue] {
  guard @strategy.graph_task_owner(graph, task) is Some(owner) else {
    return Err(MissingTask)
  }
  let sequence = match preparation {
    Some(value) => {
      if !physical_equal(value.graph, graph) {
        return Err(MissingTask)
      }
      match prepare_prepared_client_full_sequence(value, task, limits) {
        Ok(result) => result
        Err(issue) => return Err(issue)
      }
    }
    None =>
      match @lower.prepare_sequence(owner, limits) {
        Ok(result) => result
        Err(issue) => return Err(Sequence(issue))
      }
  }
  guard @lower.sequence_step(sequence, 0) is Some(@lower.ValuesStep(_)) &&
    @lower.node_at(
      @lower.bound_preparation(owner),
      @lower.sequence_count(sequence) - 1,
    )
    is Some(output) else {
    return Err(NotSingleValues)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "output")
    @encode.string_value(writer, @lower.node_id(output))
    @encode.key(writer, "sources")
    @encode.begin_object(writer)
    @encode.end_object(writer)
    @encode.key(writer, "steps")
    emit_client_sequence_steps(
      sequence,
      0,
      @lower.sequence_count(sequence),
      {
        max_body_bytes: max_wire_bytes,
        max_body_nodes: max_nodes,
        max_body_depth: max_depth,
      },
      writer,
      compiler_contracts=preparation.bind(value => value.compiler_contracts),
    )
    @encode.key(writer, "version")
    @encode.string_value(writer, "aoa-pipeline/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(Encoding)
  }
  Ok(())
}

///|
/// Measure the original pipeline without retaining a second wire. This is
/// not authority to enlarge the envelope or to compile a different owner.
pub fn measure_prepared_client_values_pipeline(
  value : PreparedClientProgram,
  task : Int,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(Int, Int, Int), ClientValuesPipelineIssue] {
  measure_client_values_pipeline_graph(
    value.graph,
    task,
    limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
    preparation=Some(value),
  )
}

///|
fn measure_client_values_pipeline_graph(
  graph : @strategy.CheckedDAG,
  task : Int,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  preparation? : PreparedClientProgram? = None,
) -> Result[(Int, Int, Int), ClientValuesPipelineIssue] {
  let writer = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  match
    emit_client_values_pipeline_into(
      graph,
      task,
      limits,
      max_wire_bytes,
      max_nodes,
      max_depth,
      writer,
      preparation~,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  Ok(@encode.finish_measurement_usage(writer)) catch {
    _ => Err(Encoding)
  }
}

///|
// Same original pipeline emitter, retaining construction DATA during its
// existing visits. No second pipeline traversal or wire is constructed.
fn measure_prepared_client_values_pipeline_construction(
  value : PreparedClientProgram,
  task : Int,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@encode.EncodingConstructionGeometry, ClientValuesPipelineIssue] {
  let writer = @encode.construction_measuring_writer(
    max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  match
    emit_client_values_pipeline_into(
      value.graph,
      task,
      limits,
      max_wire_bytes,
      max_nodes,
      max_depth,
      writer,
      preparation=Some(value),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  Ok(@encode.finish_construction_measurement(writer)) catch {
    _ => Err(Encoding)
  }
}

///|
/// Canonical AoA identity of one checked source-free Values pipeline. This
/// identifies the fragment body, not the complete Executable Plan or Run.
pub struct ClientValuesAoAIdentity {
  wire : String
  cid : String
}

///|
priv struct ClientValuesAoAParts {
  identity : ClientValuesAoAIdentity
  body : @canonical.CanonicalValue
}

///|
pub(all) enum ClientValuesAoAIdentityIssue {
  Pipeline(ClientValuesPipelineIssue)
  NoncanonicalPipeline
  Encoding
}

///|
pub fn client_values_aoa_identity_wire(
  value : ClientValuesAoAIdentity,
) -> String {
  value.wire
}

///|
pub fn client_values_aoa_identity_cid(
  value : ClientValuesAoAIdentity,
) -> String {
  value.cid
}

///|
pub(all) enum ClientValuesUnitSourceIssue {
  Pipeline(ClientValuesAoAIdentityIssue)
  UnsupportedSource
  Encoding
}

///|
/// Issue unit-form source material only for the checked, source-free,
/// single-stage Values path. The checked AoA identity is required first so
/// this extraction cannot silently stand in for a different task. The
/// resulting source is not an Executable Plan or a Run authorization.
pub fn emit_prepared_client_values_unit_source(
  value : PreparedClientProgram,
  task : Int,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientValuesUnitSourceIssue] {
  if task != 0 || @strategy.graph_task_count(value.graph) != 1 {
    return Err(UnsupportedSource)
  }
  match
    issue_prepared_client_values_aoa_identity(
      value, task, limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Pipeline(issue))
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  let emitted = @syntax.emit_source_free_unit_program(value.source, writer) catch {
    _ => return Err(Encoding)
  }
  if !emitted {
    return Err(UnsupportedSource)
  }
  let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok(body)
}

///|
pub(all) enum ClientValuesOutputSchemaIssue {
  Pipeline(ClientValuesAoAIdentityIssue)
  MissingCheckedOutput
  Identity(@execution.RelationSchemaIdentityIssue)
}

///|
/// Identify the checked Relation output schema of the same source-free Values
/// task. A Plan compiler must validate its output-port contract against this
/// schema; the CID alone is not a complete fragment or Plan.
pub fn issue_prepared_client_values_output_schema(
  value : PreparedClientProgram,
  task : Int,
  sequence_limits : @lower.SequenceLimits,
  schema_limits : @execution.RelationSchemaIdentityLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@execution.RelationSchemaIdentity, ClientValuesOutputSchemaIssue] {
  match
    issue_prepared_client_values_aoa_identity(
      value, task, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Pipeline(issue))
  }
  guard @strategy.graph_task_owner(value.graph, task) is Some(owner) &&
    @lower.node_at(
      @lower.bound_preparation(owner),
      @pipeline.step_count(@lower.pipeline(@lower.bound_preparation(owner))) - 1,
    )
    is Some(node) else {
    return Err(MissingCheckedOutput)
  }
  match
    @execution.identify_relation_schema(
      @lower.node_output_schema(node),
      schema_limits,
    ) {
    Ok(identity) => Ok(identity)
    Err(issue) => Err(Identity(issue))
  }
}

///|
pub(all) enum ClientTaskOutputSchemaIssue {
  Fragment(ClientTaskFragmentIssue)
  MissingCheckedOutput
  Identity(@execution.RelationSchemaIdentityIssue)
}

///|
/// Schema of the exact checked Result port, including any publication
/// projection. This is metadata, not evidence that its transform executed.
pub fn issue_prepared_client_result_schema(
  value : PreparedClientProgram,
  result : Int,
  limits : @execution.RelationSchemaIdentityLimits,
) -> Result[@execution.RelationSchemaIdentity, ClientTaskOutputSchemaIssue] {
  guard @strategy.graph_result_occurrence(value.graph, result)
    is Some(occurrence) &&
    @strategy.graph_result_task(value.graph, result) is Some(task) &&
    @strategy.graph_task_owner(value.graph, task) is Some(owner) &&
    physical_equal(
      owner,
      @execution.managed_result_occurrence_owner(occurrence),
    ) else {
    return Err(MissingCheckedOutput)
  }
  @execution.identify_relation_schema(
    @results.port_schema(@execution.managed_result_occurrence_port(occurrence)),
    limits,
  ).map_err(issue => Identity(issue))
}

///|
pub fn issue_prepared_client_task_output_schema(
  value : PreparedClientProgram,
  task : Int,
  sequence_limits : @lower.SequenceLimits,
  schema_limits : @execution.RelationSchemaIdentityLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@execution.RelationSchemaIdentity, ClientTaskOutputSchemaIssue] {
  match
    issue_prepared_client_task_fragment(
      value, task, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Fragment(issue))
  }
  guard @strategy.graph_task_owner(value.graph, task) is Some(owner) else {
    return Err(MissingCheckedOutput)
  }
  let prepared = @lower.bound_preparation(owner)
  guard client_task_output_target(value.graph, task) is Some(target) &&
    @lower.preparation_schema_at(prepared, target) is Some(schema) else {
    return Err(MissingCheckedOutput)
  }
  @execution.identify_relation_schema(schema, schema_limits).map_err(issue => {
    Identity(issue)
  })
}

///|
/// Reparse the owner-emitted pipeline under the pinned canonical JSON rules
/// before exposing its logical CID to a compiler. No caller-supplied AoA body
/// or claimed CID enters this operation.
pub fn issue_prepared_client_values_aoa_identity(
  value : PreparedClientProgram,
  task : Int,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientValuesAoAIdentity, ClientValuesAoAIdentityIssue] {
  issue_client_values_aoa_identity_graph(
    value.graph,
    task,
    limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
    preparation=Some(value),
  )
}

///|
fn issue_client_values_aoa_identity_graph(
  graph : @strategy.CheckedDAG,
  task : Int,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  preparation? : PreparedClientProgram? = None,
) -> Result[ClientValuesAoAIdentity, ClientValuesAoAIdentityIssue] {
  issue_client_values_aoa_parts_graph(
    graph,
    task,
    limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
    preparation~,
  ).map(parts => parts.identity)
}

///|
fn issue_client_values_aoa_parts_graph(
  graph : @strategy.CheckedDAG,
  task : Int,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  preparation? : PreparedClientProgram? = None,
) -> Result[ClientValuesAoAParts, ClientValuesAoAIdentityIssue] {
  let wire = match
    emit_client_values_pipeline_graph(
      graph,
      task,
      limits,
      max_wire_bytes,
      max_nodes,
      max_depth,
      preparation~,
    ) {
    Ok(body) => body
    Err(issue) => return Err(Pipeline(issue))
  }
  guard parse_plan_identity_value(wire, max_wire_bytes, max_nodes, max_depth)
    is Some(body) else {
    return Err(NoncanonicalPipeline)
  }
  match
    finish_client_values_aoa_identity(
      wire, body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(identity) => Ok({ identity, body, })
    Err(issue) => Err(issue)
  }
}

///|
// The immutable tree is still needed by Plan construction. Compare its exact
// canonical text and compute that same text's identity in one bounded stream.
// Provisional text is not an identity until the original writer completes.
fn finish_client_values_aoa_identity(
  wire : String,
  body : @canonical.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  emit? : (@canonical.CanonicalValue, @encode.Writer) -> Unit raise @encode.EncodeFailure = @canonical.emit_value,
) -> Result[ClientValuesAoAIdentity, ClientValuesAoAIdentityIssue] {
  try {
    let writer = @encode.buffered_hashing_writer(
      max_wire_bytes, max_nodes, max_depth, max_wire_bytes,
    )
    emit(body, writer)
    let canonical = @encode.drain_hash_output(writer)
    if canonical != wire {
      return Err(NoncanonicalPipeline)
    }
    let cid = "sha256:" + @encode.finish_hash(writer)
    Ok({ wire, cid, })
  } catch {
    _ => Err(Encoding)
  }
}

///|
pub(all) enum ClientValuesAoAAdmissionIssue {
  CheckedPipeline(ClientValuesAoAIdentityIssue)
  InvalidPipeline
  PipelineMismatch
  CidMismatch
  Encoding
}

///|
/// Recheck saved AoA material against the same prepared Program. Key order in
/// the saved JSON is not semantic, but rows, typed values and step order are.
pub fn admit_prepared_client_values_aoa_identity(
  value : PreparedClientProgram,
  task : Int,
  saved_wire : String,
  claimed_cid : String,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, ClientValuesAoAAdmissionIssue] {
  let expected = match
    issue_prepared_client_values_aoa_identity(
      value, task, limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(identity) => identity
    Err(issue) => return Err(CheckedPipeline(issue))
  }
  guard parse_plan_identity_value(
      saved_wire, max_wire_bytes, max_nodes, max_depth,
    )
    is Some(saved) else {
    return Err(InvalidPipeline)
  }
  let canonical = @canonical.stringify_value(
    saved, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  if canonical != expected.wire {
    return Err(PipelineMismatch)
  }
  if claimed_cid != expected.cid {
    return Err(CidMismatch)
  }
  Ok(())
}

///|
pub(all) enum ClientTaskSequenceIssue {
  MissingTask
  EmptyTask
  Sequence(@lower.SequenceIssue)
  Generated(@execution.SequenceRunIssue)
}

///|
/// Compile the exact checked task owner for an installed Local realization.
/// Runtime expression contexts and registered contracts remain explicit
/// adapter inputs; this does not select a Site or grant execution.
pub fn prepare_client_task_sequence(
  value : PreparedClientProgram,
  task : Int,
  contracts : @execution.RegisteredRelationContracts,
  contexts : Array[@execution.FragmentRuntimeContext],
  limits : @lower.SequenceLimits,
  max_work : Int,
  max_entries : Int,
  prepared_sequence? : @lower.PreparedSequence? = None,
) -> Result[@execution.GeneratedSequence, ClientTaskSequenceIssue] {
  let prepared_sequence = match prepared_sequence {
    Some(sequence) => Some(sequence)
    None =>
      match prepare_prepared_client_full_sequence(value, task, limits) {
        Ok(sequence) => Some(sequence)
        Err(Sequence(issue)) => return Err(Sequence(issue))
        Err(_) => return Err(MissingTask)
      }
  }
  prepare_client_task_sequence_graph(
    value.graph,
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
/// One lowering path for Effect-free and Effectful checked computations.
/// The caller must retain the graph's original checked Program owner.
fn prepare_client_task_sequence_graph(
  graph : @strategy.CheckedDAG,
  task : Int,
  contracts : @execution.RegisteredRelationContracts,
  contexts : Array[@execution.FragmentRuntimeContext],
  limits : @lower.SequenceLimits,
  max_work : Int,
  max_entries : Int,
  prepared_sequence? : @lower.PreparedSequence? = None,
) -> Result[@execution.GeneratedSequence, ClientTaskSequenceIssue] {
  guard @strategy.graph_task_owner(graph, task) is Some(owner) else {
    return Err(MissingTask)
  }
  let sequence = match prepared_sequence {
    Some(result) => {
      if !physical_equal(@lower.sequence_owner(result), owner) {
        return Err(MissingTask)
      }
      result
    }
    None =>
      match @lower.prepare_sequence(owner, limits) {
        Ok(result) => result
        Err(issue) => return Err(Sequence(issue))
      }
  }
  guard client_task_output_target(graph, task) is Some(target) else {
    return Err(EmptyTask)
  }
  // Physical retained IDs and authored AoA source names are distinct domains.
  let id = match target {
    @pipeline.Input(index) =>
      @lower.input_id(@lower.bound_preparation(owner), index)
    @pipeline.Step(index) =>
      @lower.node_at(@lower.bound_preparation(owner), index).map(@lower.node_id)
  }
  guard id is Some(id) else { return Err(EmptyTask) }
  match
    @execution.prepare_generated_sequence(
      contracts,
      sequence,
      contexts,
      [id],
      max_work,
      max_entries,
    ) {
    Ok(generated) => Ok(generated)
    Err(issue) => Err(Generated(issue))
  }
}

///|
/// Lower only the Stages sealed by the same checked Program. A caller cannot
/// substitute a pipeline, parameter binding, profile, or owner at this step.
fn prepare_client_stage_owners(
  checked : @checked.CheckedProgram,
  limits : @lower.Limits,
  max_parameters~ : Int,
  max_parameter_name_bytes~ : Int,
  lowering_work_out? : Ref[Int64]? = None,
) -> Result[Array[@lower.BoundPrepared], ClientStageOwnerIssue] {
  let identity = @checked.source_identity(checked)
  let selected = @checked.selected_expression_profiles(checked)
  let expressions = @checked.expression_closure(checked)
  let owners : Array[@lower.BoundPrepared] = []
  for stage in 0..<@checked.unit_count(checked) {
    guard @checked.unit_pipeline(checked, stage) is Some(pipeline) else {
      return Err(MissingCheckedStage(stage))
    }
    let preparation = match @lower.prepare(pipeline, limits) {
      Ok(value) => value
      Err(issue) => return Err(Lowering(issue))
    }
    if lowering_work_out is Some(observed) {
      observed.val += @lower.usage(preparation).work.to_int64()
    }
    guard @context.program_identity_stage_at(identity, stage) is Some(source) else {
      return Err(MissingStageIdentity(stage))
    }
    let parameters = @parameters.bound_values(
      @context.stage_identity_parameter_values(source),
    )
    let owner = match
      @lower.bind_parameters(
        preparation,
        Some(parameters),
        max_parameters~,
        max_name_bytes=max_parameter_name_bytes,
        expression_profiles={
          text_time: selected.text_time,
          veca: selected.veca,
        },
      ) {
      Ok(value) => value
      Err(issue) => return Err(Binding(issue))
    }
    let owner = match expressions {
      None => owner
      Some(closure) if @context.expression_closure_count(closure) == 0 => owner
      Some(closure) =>
        match
          @lower.bind_program_expression_closure(
            owner,
            closure,
            stage,
            limits.max_work,
          ) {
          Ok(value) => value
          Err(issue) => return Err(Binding(issue))
        }
    }
    owners.push(owner)
  }
  Ok(owners)
}

///|
/// Use the ordinary parser and semantic checker. Every lowered owner is
/// derived from that same CheckedProgram; callers cannot inject a parallel
/// graph, Result list or effect-free claim.
pub fn prepare_effect_free_client_program(
  document : String,
  format : @syntax.Format,
  environment : @checked.CheckEnvironment,
  supplied : @decode.Cursor?,
  limits : ClientProgramPreparationLimits,
  source_catalog? : @checked.PreparedSourceCatalog? = None,
) -> Result[PreparedClientProgram, ClientProgramPreparationIssue] {
  let parsed = match @syntax.parse(document, limits.checking.input, format~) {
    Ok(value) => value
    Err(issue) => return Err(Syntax(issue))
  }
  prepare_parsed_effect_free_client_program(
    parsed,
    environment,
    supplied,
    limits,
    source_catalog~,
  )
}

///|
/// Continue from the ordinary parser's owned Program. A source frontend may
/// select this owner before semantic checking; an Effectful Program must not
/// be checked here and then retried under the Effect owner.
pub fn prepare_parsed_effect_free_client_program(
  parsed : @syntax.Program,
  environment : @checked.CheckEnvironment,
  supplied : @decode.Cursor?,
  limits : ClientProgramPreparationLimits,
  source_catalog? : @checked.PreparedSourceCatalog? = None,
) -> Result[PreparedClientProgram, ClientProgramPreparationIssue] {
  for stage in @syntax.stages(parsed) {
    if !@syntax.effect_names(stage).is_empty() {
      return Err(EffectNotSupported(stage.id))
    }
  }
  let checked = match
    @checked.check_parsed(
      parsed,
      environment,
      supplied,
      limits.checking,
      source_catalog~,
    ) {
    Checked(value) => value
    NeedsInputs(requests) => return Err(NeedsInputs(requests))
    Rejected(diagnostic) => return Err(Check(diagnostic))
  }
  // The Effect restriction ran before checking, preserving its original
  // refusal precedence. Continue this exact result, without another scan/check.
  compile_effect_free_checked_client_program(
    checked,
    limits.lowering,
    max_parameters=limits.max_parameters,
    max_parameter_name_bytes=limits.max_parameter_name_bytes,
    max_tasks=limits.max_tasks,
    max_graph_work=limits.max_graph_work,
    values_max_rows=limits.values_max_rows,
  )
}

///|
/// Compile the original completed check without parsing, input/evidence
/// admission or semantic checking again. Lowering binds the original checked
/// Parameter values to its own expressions. Source, Environment and Result
/// inventory come only from that original. The caller funds graph coexistence
/// before entry; this function does not create a Resource owner or admit a Run.
/// Effect preparations still require their separate original candidate path.
pub fn prepare_checked_effect_free_client_program(
  checked : @checked.CheckedProgram,
  lowering : @lower.Limits,
  max_parameters~ : Int,
  max_parameter_name_bytes~ : Int,
  max_tasks~ : Int,
  max_graph_work~ : Int,
  values_max_rows? : Int? = None,
) -> Result[PreparedClientProgram, ClientProgramPreparationIssue] {
  prepare_checked_effect_free_client_program_owned(
    checked,
    lowering,
    max_parameters~,
    max_parameter_name_bytes~,
    max_tasks~,
    max_graph_work~,
    values_max_rows~,
  )
}

///|
/// The SAME compiler, with work of each completed original lowering pass.
/// This is a known prefix, not complete binding/Graph or late-failure Usage.
/// No parser, checker, lowering pass or Plan is repeated to obtain it.
pub fn observe_prepare_checked_effect_free_client_program(
  checked : @checked.CheckedProgram,
  lowering : @lower.Limits,
  max_parameters~ : Int,
  max_parameter_name_bytes~ : Int,
  max_tasks~ : Int,
  max_graph_work~ : Int,
  values_max_rows? : Int? = None,
) -> (Result[PreparedClientProgram, ClientProgramPreparationIssue], Int64) {
  let work = Ref(0L)
  let result = prepare_checked_effect_free_client_program_owned(
    checked,
    lowering,
    max_parameters~,
    max_parameter_name_bytes~,
    max_tasks~,
    max_graph_work~,
    values_max_rows~,
    lowering_work_out=Some(work),
  )
  (result, work.val)
}

///|
fn prepare_checked_effect_free_client_program_owned(
  checked : @checked.CheckedProgram,
  lowering : @lower.Limits,
  max_parameters~ : Int,
  max_parameter_name_bytes~ : Int,
  max_tasks~ : Int,
  max_graph_work~ : Int,
  values_max_rows? : Int? = None,
  lowering_work_out? : Ref[Int64]? = None,
) -> Result[PreparedClientProgram, ClientProgramPreparationIssue] {
  // The checker already refused nonempty Effects on its Pure path. Read its
  // retained classification instead of copying/scanning every Stage again.
  // Only an Effect candidate needs its original Stage for the typed refusal.
  if @checked.checked_program_has_effects(checked) {
    for stage in @syntax.stages(@checked.checked_source_program(checked)) {
      if !@syntax.effect_names(stage).is_empty() {
        return Err(EffectNotSupported(stage.id))
      }
    }
  }
  compile_effect_free_checked_client_program(
    checked,
    lowering,
    max_parameters~,
    max_parameter_name_bytes~,
    max_tasks~,
    max_graph_work~,
    values_max_rows~,
    lowering_work_out~,
  )
}

///|
fn compile_effect_free_checked_client_program(
  checked : @checked.CheckedProgram,
  lowering : @lower.Limits,
  max_parameters~ : Int,
  max_parameter_name_bytes~ : Int,
  max_tasks~ : Int,
  max_graph_work~ : Int,
  values_max_rows? : Int? = None,
  lowering_work_out? : Ref[Int64]? = None,
) -> Result[PreparedClientProgram, ClientProgramPreparationIssue] {
  let owners = match
    prepare_client_stage_owners(
      checked,
      lowering,
      max_parameters~,
      max_parameter_name_bytes~,
      lowering_work_out~,
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue {
          MissingCheckedStage(stage) => MissingCheckedStage(stage)
          MissingStageIdentity(stage) => MissingStageIdentity(stage)
          Lowering(issue) => Lowering(issue)
          Binding(issue) => Binding(issue)
        },
      )
  }
  let sequence_preparation_demand = match
    client_sequence_preparation_demand(owners, max_graph_work) {
    Ok(value) => value
    Err(issue) => return Err(Graph(issue))
  }
  match
    @strategy.prepare_checked_dag(
      checked,
      owners,
      max_tasks,
      max_graph_work,
      captured_prefix=client_program_acquisition_prefix(checked),
      source_free_root=owners.length() > 0 &&
        @pipeline.starts_with_selected_local_generator(
          @lower.pipeline(@lower.bound_preparation(owners[0])),
        ),
    ) {
    Ok(graph) => {
      if values_max_rows is Some(max_rows) &&
        !client_values_row_limit_supported(graph, max_rows) {
        return Err(ValuesProfileUnsupported)
      }
      Ok({
        graph,
        sequence_preparation_demand,
        check_environment_cid: @environment.cid(
          @checked.checked_environment(checked),
        ),
        source: @checked.checked_source_program(checked),
        local_normalization: None,
        full_sequences: [],
        task_pipeline_inputs: [],
        compiler_contracts: None,
        // The default covers authored inlet demand and checked closed outputs.
        // An explicit installed row setting selects its first bound. The owned capacity
        // plan still independently admits the actual execution resources.
        local_values_max_rows: match values_max_rows {
          Some(max_rows) => max_rows
          None =>
            Int::max(
              client_standard_values_sequence_limits().max_rows,
              Int::max(
                sequence_preparation_demand.authored_literal_rows,
                client_closed_owner_rows(owners, max_graph_work).unwrap_or(0),
              ),
            )
        },
      })
    }
    Err(issue) => Err(Graph(issue))
  }
}

///|
/// Infer only the admitted two-acquisition prefix from checked requests.
/// The graph owner still validates independence, coverage, and topology.
fn client_program_acquisition_prefix(program : @checked.CheckedProgram) -> Int {
  if @checked.unit_count(program) < 3 {
    return 1
  }
  let acquisitions = [0, 0]
  for index in 0..<@checked.source_execution_count(program) {
    let check = @checked.source_execution_at(program, index).unwrap()
    let subject = @checked.source_execution_subject(check)
    if subject.stage < 0 {
      return 1
    }
    if subject.stage > 1 {
      // Downstream keyed lookup consumes the genuine computed prefix. It is
      // not an independent acquisition task, and does not erase the two
      // original initial Direct tasks. The checked DAG validates its exact
      // request original and graph edges before accepting this profile.
      guard subject.request is @acquisition.Keyed(_, _) else { return 1 }
      continue
    }
    guard subject.request is @acquisition.Direct(_, _) else { return 1 }
    if @checked.source_execution_kind(check) is @checked.HostCombination {
      acquisitions[subject.stage] += 1
    }
  }
  if acquisitions == [1, 1] {
    2
  } else {
    1
  }
}
