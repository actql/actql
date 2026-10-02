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
}

///|
pub(all) enum ClientProgramPreparationIssue {
  Syntax(@syntax.SyntaxError)
  EffectNotSupported(String)
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
}

///|
/// A checked Graph input needs the task compiler; the direct Values compiler
/// only represents Relation inputs. This reads the admitted owner, not source
/// text or a caller-supplied mode flag.
pub fn prepared_client_uses_graph_carrier(
  value : PreparedClientProgram,
) -> Bool {
  for task in 0..<@strategy.graph_task_count(value.graph) {
    guard @strategy.graph_task_owner(value.graph, task) is Some(owner) else {
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
  guard @strategy.graph_task_owner(value.graph, task) is Some(owner) else {
    return Err(MissingTask)
  }
  let sequence = match @lower.prepare_sequence(owner, limits) {
    Ok(result) => result
    Err(issue) => return Err(Sequence(issue))
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  @lower.emit_sequence_steps(sequence, writer) catch {
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
/// Emit the checked AoA pipeline of one task, including its declared input
/// ports. A source input remains an input port; this does not claim that its
/// physical acquisition, barrier, or Run observation has been admitted.
pub fn emit_prepared_client_task_pipeline(
  value : PreparedClientProgram,
  task : Int,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientTaskPipelineIssue] {
  guard @strategy.graph_task_owner(value.graph, task) is Some(owner) else {
    return Err(MissingTask)
  }
  let pipeline = @lower.pipeline(@lower.bound_preparation(owner))
  let count = @pipeline.step_count(pipeline)
  let selected = @strategy.graph_task_selected_step(value.graph, task)
  let prefix_end = @strategy.graph_task_prefix_end(value.graph, task)
  guard client_task_output_step(value.graph, task, count) is Some(end_step) &&
    @lower.node_at(@lower.bound_preparation(owner), end_step) is Some(output) else {
    return Err(MissingOutput)
  }
  emit_client_task_pipeline_prefix(
    owner, end_step, output, selected, prefix_end, false, limits, max_wire_bytes,
    max_nodes, max_depth,
  )
}

///|
/// The caller chooses a checked output before preparing pure computation.
/// Acquisition steps after that output must not enter its AoA fragment.
fn emit_client_task_pipeline_prefix(
  owner : @lower.BoundPrepared,
  end_step : Int,
  output : @lower.PreparedNode,
  selected : Int?,
  prefix_end : Int?,
  acquisition_prefix : Bool,
  limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  infer_boundary? : Int? = None,
) -> Result[String, ClientTaskPipelineIssue] {
  let pipeline = @lower.pipeline(@lower.bound_preparation(owner))
  let prepared_sequence = if infer_boundary is Some(step) {
    @lower.prepare_sequence_with_infer_boundary(owner, step, limits)
  } else if acquisition_prefix {
    @lower.prepare_sequence_prefix(owner, end_step, limits)
  } else {
    @lower.prepare_sequence(owner, limits)
  }
  let sequence = match prepared_sequence {
    Ok(value) => value
    Err(issue) => return Err(Sequence(issue))
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "output")
    @encode.string_value(writer, @lower.node_id(output))
    @encode.key(writer, "sources")
    @encode.begin_object(writer)
    for index in 0..<@pipeline.input_count(pipeline) {
      guard @pipeline.input_at(pipeline, index) is Some((name, carrier)) else {
        return Err(Encoding)
      }
      let sort = client_task_carrier_sort(carrier)
      @encode.key(writer, name)
      @encode.begin_object(writer)
      @encode.key(writer, "sort")
      @encode.string_value(writer, sort)
      @encode.end_object(writer)
    }
    @encode.end_object(writer)
    @encode.key(writer, "steps")
    if infer_boundary is Some(_) {
      guard selected is Some(step) else { return Err(Encoding) }
      @lower.emit_sequence_step_range(sequence, step, step + 1, writer)
    } else {
      @lower.emit_sequence_steps(sequence, writer)
    }
    @encode.key(writer, "version")
    @encode.string_value(writer, "aoa-pipeline/0.1")
    @encode.end_object(writer)
    let raw = @encode.finish(writer)
    guard parse_plan_identity_value(raw, max_wire_bytes, max_nodes, max_depth)
      is Some(body) else {
      return Err(Encoding)
    }
    if selected is None && prefix_end is None {
      return Ok(
        @canonical.stringify_value(body, max_wire_bytes, max_nodes, max_depth),
      )
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
    @encode.begin_object(task_writer)
    @encode.key(task_writer, "output")
    @encode.string_value(task_writer, @lower.node_id(output))
    @encode.key(task_writer, "sources")
    @encode.begin_object(task_writer)
    if selected is Some(step) {
      let node = @lower.node_at(@lower.bound_preparation(owner), step).unwrap()
      for input in 0..<@lower.node_input_count(node) {
        guard @lower.node_input_target(node, input) is Some(target) &&
          @lower.preparation_carrier_at(@lower.bound_preparation(owner), target)
          is Some(carrier) else {
          return Err(UnsupportedCarrier)
        }
        let sort = client_task_carrier_sort(carrier)
        @encode.key(task_writer, "input_" + input.to_string())
        @encode.begin_object(task_writer)
        @encode.key(task_writer, "sort")
        @encode.string_value(task_writer, sort)
        @encode.end_object(task_writer)
      }
    } else {
      for input in 0..<@pipeline.input_count(pipeline) {
        guard @pipeline.input_at(pipeline, input) is Some((name, carrier)) else {
          return Err(UnsupportedCarrier)
        }
        let sort = client_task_carrier_sort(carrier)
        @encode.key(task_writer, name)
        @encode.begin_object(task_writer)
        @encode.key(task_writer, "sort")
        @encode.string_value(task_writer, sort)
        @encode.end_object(task_writer)
      }
    }
    @encode.end_object(task_writer)
    @encode.key(task_writer, "steps")
    @encode.begin_array(task_writer)
    let mut emitted = 0
    for node in @canonical.array_values(step_values) {
      guard @canonical.object_field(node, "id") is Some(@canonical.String(id)) else {
        return Err(Encoding)
      }
      if !included.contains(id) {
        continue
      }
      emitted += 1
      if selected is None {
        @canonical.emit_value(node, task_writer)
        continue
      }
      guard @canonical.object_fields(node) is Some(fields) else {
        return Err(Encoding)
      }
      @encode.begin_object(task_writer)
      for (key, field) in fields {
        @encode.key(task_writer, key)
        if key == "in" {
          guard field is @canonical.Array(refs) else { return Err(Encoding) }
          @encode.begin_array(task_writer)
          for reference in @canonical.array_values(refs) {
            guard reference is @canonical.String(name) else {
              return Err(Encoding)
            }
            let mut resolved = if included.contains(name) {
              Some(name)
            } else {
              None
            }
            if resolved is None {
              for pair in remap {
                if pair.0 == name {
                  resolved = Some(pair.1)
                  break
                }
              }
            }
            guard resolved is Some(port) else { return Err(Encoding) }
            @encode.string_value(task_writer, port)
          }
          @encode.end_array(task_writer)
        } else {
          @canonical.emit_value(field, task_writer)
        }
      }
      @encode.end_object(task_writer)
    }
    if emitted != included.length() {
      return Err(Encoding)
    }
    @encode.end_array(task_writer)
    @encode.key(task_writer, "version")
    @encode.string_value(task_writer, "aoa-pipeline/0.1")
    @encode.end_object(task_writer)
    let task_raw = @encode.finish(task_writer)
    guard parse_plan_identity_value(
        task_raw, max_wire_bytes, max_nodes, max_depth,
      )
      is Some(task_body) else {
      return Err(Encoding)
    }
    Ok(
      @canonical.stringify_value(
        task_body, max_wire_bytes, max_nodes, max_depth,
      ),
    )
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
) -> Result[String, ClientValuesPipelineIssue] {
  guard @strategy.graph_task_owner(graph, task) is Some(owner) else {
    return Err(MissingTask)
  }
  let sequence = match @lower.prepare_sequence(owner, limits) {
    Ok(result) => result
    Err(issue) => return Err(Sequence(issue))
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  let emitted = @lower.emit_source_free_values_pipeline(sequence, writer) catch {
    _ => return Err(Encoding)
  }
  match emitted {
    Ok(_) => ()
    Err(_) => return Err(NotSingleValues)
  }
  let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok(body)
}

///|
/// Canonical AoA identity of one checked source-free Values pipeline. This
/// identifies the fragment body, not the complete Executable Plan or Run.
pub struct ClientValuesAoAIdentity {
  wire : String
  cid : String
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
  guard client_task_output_step(
      value.graph,
      task,
      @pipeline.step_count(@lower.pipeline(prepared)),
    )
    is Some(output_step) &&
    @lower.node_at(prepared, output_step) is Some(node) else {
    return Err(MissingCheckedOutput)
  }
  @execution.identify_relation_schema(
    @lower.node_output_schema(node),
    schema_limits,
  ).map_err(issue => Identity(issue))
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
) -> Result[ClientValuesAoAIdentity, ClientValuesAoAIdentityIssue] {
  let wire = match
    emit_client_values_pipeline_graph(
      graph, task, limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(body) => body
    Err(issue) => return Err(Pipeline(issue))
  }
  guard parse_plan_identity_value(wire, max_wire_bytes, max_nodes, max_depth)
    is Some(body) else {
    return Err(NoncanonicalPipeline)
  }
  let canonical = @canonical.stringify_value(
    body, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  if canonical != wire {
    return Err(NoncanonicalPipeline)
  }
  let cid = @canonical.cid_value(body, max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  Ok({ wire, cid, })
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
  let count = @lower.sequence_count(sequence)
  if count == 0 {
    return Err(EmptyTask)
  }
  guard client_task_output_step(graph, task, count) is Some(last_step) &&
    @lower.node_at(@lower.bound_preparation(owner), last_step) is Some(last) else {
    return Err(EmptyTask)
  }
  match
    @execution.prepare_generated_sequence(
      contracts,
      sequence,
      contexts,
      [@lower.node_id(last)],
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
  limits : ClientProgramPreparationLimits,
) -> Result[Array[@lower.BoundPrepared], ClientStageOwnerIssue] {
  let identity = @checked.source_identity(checked)
  let selected = @checked.selected_expression_profiles(checked)
  let owners : Array[@lower.BoundPrepared] = []
  for stage in 0..<@checked.unit_count(checked) {
    guard @checked.unit_pipeline(checked, stage) is Some(pipeline) else {
      return Err(MissingCheckedStage(stage))
    }
    let preparation = match @lower.prepare(pipeline, limits.lowering) {
      Ok(value) => value
      Err(issue) => return Err(Lowering(issue))
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
        max_parameters=limits.max_parameters,
        max_name_bytes=limits.max_parameter_name_bytes,
        expression_profiles={
          text_time: selected.text_time,
          veca: selected.veca,
        },
      ) {
      Ok(value) => value
      Err(issue) => return Err(Binding(issue))
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
) -> Result[PreparedClientProgram, ClientProgramPreparationIssue] {
  let parsed = match @syntax.parse(document, limits.checking.input, format~) {
    Ok(value) => value
    Err(issue) => return Err(Syntax(issue))
  }
  for stage in @syntax.stages(parsed) {
    if !@syntax.effect_names(stage).is_empty() {
      return Err(EffectNotSupported(stage.id))
    }
  }
  let checked = match
    @checked.check_parsed(parsed, environment, supplied, limits.checking) {
    Checked(value) => value
    NeedsInputs(requests) => return Err(NeedsInputs(requests))
    Rejected(diagnostic) => return Err(Check(diagnostic))
  }
  let owners = match prepare_client_stage_owners(checked, limits) {
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
  match
    @strategy.prepare_checked_dag(
      checked,
      owners,
      limits.max_tasks,
      limits.max_graph_work,
      captured_prefix=client_program_acquisition_prefix(checked),
      source_free_root=owners.length() > 0 &&
        @pipeline.starts_with_values(
          @lower.pipeline(@lower.bound_preparation(owners[0])),
        ),
    ) {
    Ok(graph) =>
      Ok({
        graph,
        check_environment_cid: @checked.checking_environment_cid(environment),
        source: parsed,
      })
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
    if subject.stage < 0 || subject.stage > 1 {
      return 1
    }
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
