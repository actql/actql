///|
/// Private compilation material, not an executable admission. The installing
/// Host must still admit the referenced limits, retry, media and egress bodies
/// and register a physical provider before accepting a Run.
pub struct ClientInferPlanGraph {
  owner : PreparedClientProgram
  task : Int
  stage : Int
  source_ordinal : Int
  execution : @environment.ModelExecutionContract
  item_limit : @checked.InferItemLimit
  graph : ClientTaskPlanGraph
  input_fragment_cid : String
  request_wire : String
  request_cid : String
  barrier_cid : String
  input : ClientTaskFragmentNode
  output : ClientTaskFragmentNode
  occurrence : ClientInferOccurrence
  result_producers : Array[(Int, String, String, String)]
  serialization : ClientSerializationPlanGraph?

  // Same issuer-owned component arrays and completed writer facts. They are
  // never exposed as caller-mutable DATA or reconstructed from saved wire.
  priv original_graph : ClientTaskPlanGraph
  priv graph_nodes : Array[@canonical.CanonicalValue]
  priv graph_edges : Array[@canonical.CanonicalValue]
  priv graph_roots : Array[@canonical.CanonicalValue]
  priv graph_wire_bytes : Int
  priv graph_wire_nodes : Int
  priv graph_wire_depth : Int
}

///|
// This is an immutable original read, not another graph admission. Retain the
// original writer's complete limits check when a consumer selects tighter
// bounds. A different readonly Graph holder cannot use the former component
// facts, even with equal bytes. No wire comparison or current callback runs.
fn client_infer_graph_original_parts(
  value : ClientInferPlanGraph,
  owner : PreparedClientProgram,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> (
  Array[@canonical.CanonicalValue],
  Array[@canonical.CanonicalValue],
  Array[@canonical.CanonicalValue],
)? {
  if !physical_equal(value.owner, owner) ||
    !physical_equal(value.graph, value.original_graph) ||
    max_wire_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 ||
    value.graph_wire_bytes > max_wire_bytes ||
    value.graph_wire_nodes > max_nodes ||
    value.graph_wire_depth > max_depth {
    return None
  }
  Some((value.graph_nodes, value.graph_edges, value.graph_roots))
}

///|
pub(all) enum ClientInferPlanGraphIssue {
  UnsupportedProgram
  ForeignExecution
  InvalidDependency
  Execution(@environment.ModelTaskIssue)
  Input(ClientTaskFragmentIssue)
  Mapping(@lower.InferInputIssue)
  Result(ClientResultPlanPartsIssue)
  Encoding
  ItemLimit(ClientInferItemLimitIssue)
  Serialization(ClientSerializationEffectPlanIssue)
}

///|
/// Admit an execution-contract body against the ModelTask already installed
/// in this prepared Program. Neither its dependency references nor current
/// egress authority are implicitly admitted by this reader.
pub fn read_prepared_client_infer_model_execution(
  value : PreparedClientProgram,
  step : Int,
  body : Bytes,
  expected_cid : String,
  limits : @environment.Limits,
  max_work : Int,
) -> Result[@environment.ModelExecutionContract, ClientInferPlanGraphIssue] {
  guard client_infer_metadata_owner(value, 0, step) is Some(owner) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(_) else {
    return Err(UnsupportedProgram)
  }
  read_client_infer_owner_model_execution(
    owner, step, body, expected_cid, limits, max_work,
  )
}

///|
fn read_client_infer_owner_model_execution(
  owner : @lower.BoundPrepared,
  step : Int,
  body : Bytes,
  expected_cid : String,
  limits : @environment.Limits,
  max_work : Int,
) -> Result[@environment.ModelExecutionContract, ClientInferPlanGraphIssue] {
  guard @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.payload(node) is @lower.Infer(infer) else {
    return Err(UnsupportedProgram)
  }
  @environment.read_model_execution_contract(
    @infer.model_task(infer),
    body,
    expected_cid,
    limits,
    max_work,
  ).map_err(issue => Execution(issue))
}

///|
pub fn client_infer_plan_graph_matches(
  value : ClientInferPlanGraph,
  owner : PreparedClientProgram,
  execution : @environment.ModelExecutionContract,
) -> Bool {
  physical_equal(value.owner, owner) &&
  physical_equal(value.execution, execution)
}

///|
/// Bind a physical input preparation to the saved logical call occurrence.
/// Equal graph bytes or a different prepared Program cannot substitute.
pub fn client_infer_plan_graph_matches_occurrence(
  value : ClientInferPlanGraph,
  owner : PreparedClientProgram,
  step : Int,
) -> Bool {
  physical_equal(value.owner, owner) && value.source_ordinal == step
}

///|
pub fn client_infer_plan_graph_wire(value : ClientInferPlanGraph) -> String {
  value.graph.wire
}

///|
/// The same component already emitted every post-INFER node. A checked
/// intermediate Result borrows its own producer, not the final Effect input.
/// These tuples are retained by the compiler, never reconstructed by a Host.
fn client_infer_result_producer(
  occurrence : ClientInferOccurrence,
  result : Int,
  producers : Array[(Int, String, String, String)],
) -> (Int, String, String, String)? {
  let graph = occurrence.owner.graph
  guard client_infer_occurrence_matches(occurrence, occurrence.owner) &&
    @strategy.graph_result_task(graph, result) == Some(occurrence.task) &&
    @strategy.graph_result_occurrence(graph, result) is Some(selected) &&
    physical_equal(
      @execution.managed_result_occurrence_owner(selected),
      occurrence.preparation,
    ) &&
    @results.port_target(@execution.managed_result_occurrence_port(selected))
    is @pipeline.Step(step) &&
    step >= occurrence.step &&
    @lower.node_at(@lower.bound_preparation(occurrence.preparation), step)
    is Some(node) else {
    return None
  }
  for producer in producers {
    if producer.0 == step && producer.2 == @lower.node_id(node) {
      return Some(producer)
    }
  }
  None
}

///|
pub fn client_infer_plan_graph_serialization(
  value : ClientInferPlanGraph,
) -> ClientSerializationPlanGraph? {
  value.serialization
}

///|
pub fn client_infer_plan_graph_coordinates(
  value : ClientInferPlanGraph,
) -> (Int, Int, Int) {
  (value.task, value.stage, value.source_ordinal)
}

///|
pub fn client_infer_plan_graph_input_cid(
  value : ClientInferPlanGraph,
) -> String {
  value.input_fragment_cid
}

///|
pub fn client_infer_plan_graph_request_wire(
  value : ClientInferPlanGraph,
) -> String {
  value.request_wire
}

///|
pub fn client_infer_plan_graph_request_cid(
  value : ClientInferPlanGraph,
) -> String {
  value.request_cid
}

///|
pub fn client_infer_plan_graph_barrier_cid(
  value : ClientInferPlanGraph,
) -> String {
  value.barrier_cid
}

///|
/// Retain the owner-derived item evidence alongside the acquisition graph.
/// The complete physical envelope and current egress authority are separate.
pub fn client_infer_plan_graph_item_limit(
  value : ClientInferPlanGraph,
) -> @checked.InferItemLimit {
  value.item_limit
}

///|
/// The exact checked execution contract retained by this selected graph.
/// Reading it grants neither dependency admission nor provider authority.
pub fn client_infer_plan_graph_execution_contract(
  value : ClientInferPlanGraph,
) -> @environment.ModelExecutionContract {
  value.execution
}

///|
/// Installed source-free compilation uses already admitted dependency bodies.
/// The checking environment owns the Host capacities; the exact ModelTask
/// owns its data-handling requirements. These references do not grant egress
/// permission: the current Host observation and account are admitted separately.
pub fn issue_installed_client_infer_plan_graph(
  value : PreparedClientProgram,
  step : Int,
  execution : @environment.ModelExecutionContract,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientInferPlanGraph, ClientInferPlanGraphIssue] {
  issue_prepared_client_infer_plan_graph(
    value,
    step,
    execution,
    prepared_client_check_environment_cid(value),
    @environment.model_task_identity(
      @environment.model_execution_task(execution),
    ).2,
    sequence_limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn client_infer_dependency_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index in 7..<71 {
    let c = value[index].to_int()
    if !((c >= 48 && c <= 57) || (c >= 97 && c <= 102)) {
      return false
    }
  }
  true
}

///|
/// The same installed references, bound to the original composed occurrence.
/// Results belong to the enclosing Effect compiler rather than this component.
pub fn issue_installed_client_composed_infer_plan_graph(
  occurrence : ClientInferOccurrence,
  execution : @environment.ModelExecutionContract,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  construction? : ClientInferGraphConstruction? = None,
) -> Result[ClientInferPlanGraph, ClientInferPlanGraphIssue] {
  if construction is Some(original) {
    if @strategy.graph_program_has_effects(occurrence.owner.graph) ||
      !prepared_client_serialization_occurrences(occurrence.owner).is_empty() {
      return Err(UnsupportedProgram)
    }
    return issue_client_infer_plan_graph_for_occurrence(
      occurrence,
      execution,
      prepared_client_check_environment_cid(occurrence.owner),
      @environment.model_task_identity(
        @environment.model_execution_task(execution),
      ).2,
      sequence_limits,
      max_wire_bytes,
      max_nodes,
      max_depth,
      1000000,
      false,
      construction=Some(original),
    )
  }
  if @strategy.graph_program_has_effects(occurrence.owner.graph) {
    let serialization = match
      issue_client_serialization_effect_plan(
        occurrence.owner,
        sequence_limits,
        max_wire_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Serialization(issue))
    }
    if serialization is Some(component) {
      return issue_prepared_client_serialized_infer_plan_graph(
        occurrence,
        component,
        execution,
        sequence_limits,
        max_wire_bytes,
        max_nodes,
        max_depth,
        include_results=false,
      )
    }
  }
  issue_prepared_client_composed_infer_plan_graph(
    occurrence,
    execution,
    prepared_client_check_environment_cid(occurrence.owner),
    @environment.model_task_identity(
      @environment.model_execution_task(execution),
    ).2,
    sequence_limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
    include_results=false,
  )
}

///|
/// Select one terminal Infer under the ordinary checked Program owner. The
/// prefix stays AoA and the model node stays an acquisition barrier. Checked
/// Result transformations consume the barrier's actual Relation port.
pub fn issue_prepared_client_infer_plan_graph(
  value : PreparedClientProgram,
  step : Int,
  execution : @environment.ModelExecutionContract,
  limits_cid : String,
  egress_requirements_cid : String,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  capacity_work? : Int = 1000000,
) -> Result[ClientInferPlanGraph, ClientInferPlanGraphIssue] {
  guard client_infer_metadata_owner(value, 0, step) is Some(owner) else {
    return Err(UnsupportedProgram)
  }
  issue_client_infer_plan_graph_for_occurrence(
    { owner: value, task: 0, stage: 0, step, preparation: owner, },
    execution,
    limits_cid,
    egress_requirements_cid,
    sequence_limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
    capacity_work,
    true,
  )
}

///|
/// Connect the checked multi-task occurrence to the same Model barrier compiler
/// used by the source-free/acquired component. External producers remain graph
/// inputs; this does not manufacture a Source capture or execution permission.
pub fn issue_prepared_client_composed_infer_plan_graph(
  occurrence : ClientInferOccurrence,
  execution : @environment.ModelExecutionContract,
  limits_cid : String,
  egress_requirements_cid : String,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  capacity_work? : Int = 1000000,
  include_results? : Bool = true,
) -> Result[ClientInferPlanGraph, ClientInferPlanGraphIssue] {
  if !client_infer_occurrence_matches(occurrence, occurrence.owner) {
    return Err(UnsupportedProgram)
  }
  issue_client_infer_plan_graph_for_occurrence(
    occurrence, execution, limits_cid, egress_requirements_cid, sequence_limits,
    max_wire_bytes, max_nodes, max_depth, capacity_work, include_results,
  )
}

///|
/// Connect an already checked Content component to this exact Model
/// occurrence. Generation remains a distinct barrier and retains its original
/// policy/quantity binding; a pure-prefix reconstruction cannot substitute.
pub fn issue_prepared_client_serialized_infer_plan_graph(
  occurrence : ClientInferOccurrence,
  serialization : ClientSerializationPlanGraph,
  execution : @environment.ModelExecutionContract,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  include_results? : Bool = true,
  construction? : ClientInferGraphConstruction? = None,
) -> Result[ClientInferPlanGraph, ClientInferPlanGraphIssue] {
  if !client_infer_occurrence_matches(occurrence, occurrence.owner) {
    return Err(UnsupportedProgram)
  }
  issue_client_infer_plan_graph_for_occurrence(
    occurrence,
    execution,
    prepared_client_check_environment_cid(occurrence.owner),
    @environment.model_task_identity(
      @environment.model_execution_task(execution),
    ).2,
    sequence_limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
    1000000,
    include_results,
    serialization=Some(serialization),
    construction~,
  )
}

///|
fn client_infer_required_profiles(
  value : ClientInferPlanGraph,
) -> Array[(String, String)] {
  let profiles = [
    ("actql-infer/0.1", @environment.compiler_inference_barrier_contract_cid()),
  ]
  if value.serialization is Some(_) {
    profiles.push(
      (
        "actql-content/0.1",
        @environment.compiler_content_barrier_contract_cid(),
      ),
    )
  }
  profiles
}

///|
fn issue_client_infer_plan_graph_for_occurrence(
  occurrence : ClientInferOccurrence,
  execution : @environment.ModelExecutionContract,
  limits_cid : String,
  egress_requirements_cid : String,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  capacity_work : Int,
  include_results : Bool,
  serialization? : ClientSerializationPlanGraph? = None,
  construction? : ClientInferGraphConstruction? = None,
  prepare_mappings? : (
    @infer.CheckedInfer,
    @parameter.BoundValues?,
    @lower.ExpressionLimits,
  ) -> Result[@lower.PreparedInferInputs, @lower.InferInputIssue] = (
    infer,
    parameters,
    limits,
  ) => @lower.prepare_infer_inputs(infer, parameters, limits),
) -> Result[ClientInferPlanGraph, ClientInferPlanGraphIssue] {
  let value = occurrence.owner
  let owner = occurrence.preparation
  let step = occurrence.step
  let task = occurrence.task
  if construction is Some(original) {
    guard physical_equal(original.occurrence, occurrence) &&
      physical_equal(original.execution, execution) &&
      client_full_sequence_limits_match(
        original.sequence_limits,
        sequence_limits,
      ) &&
      original.max_wire_bytes == max_wire_bytes &&
      original.max_nodes == max_nodes &&
      original.max_depth == max_depth &&
      (match (original.serialization, serialization) {
        (None, None) => true
        (Some(original), Some(selected)) => physical_equal(original, selected)
        _ => false
      }) else {
      return Err(UnsupportedProgram)
    }
  }
  guard client_infer_occurrence_output_step(occurrence) is Some(terminal) &&
    terminal >= step &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.payload(node) is @lower.Infer(infer) else {
    return Err(UnsupportedProgram)
  }
  if !physical_equal(
      @infer.model_task(infer),
      @environment.model_execution_task(execution),
    ) {
    return Err(ForeignExecution)
  }
  if !client_infer_dependency_cid(limits_cid) ||
    !client_infer_dependency_cid(egress_requirements_cid) {
    return Err(InvalidDependency)
  }
  let item_limit = match
    (@checked.prepare_infer_item_limit(
      @strategy.graph_program(value.graph),
      occurrence.stage,
      step,
      capacity_work,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) catch {
      issue => return Err(ItemLimit(Preparation(issue)))
    }) {
    value => value
  }
  let prefix = match
    (match serialization {
      Some(component) => {
        guard physical_equal(component.owner, value) &&
          physical_equal(@lower.serialization_owner(component.barrier), owner) &&
          component.task == task &&
          component.step < step else {
          return Err(UnsupportedProgram)
        }
        if component.step + 1 == step {
          Ok(component.output)
        } else {
          match construction {
            Some(original) => {
              guard original.pipeline_inputs.get(step - component.step - 2)
                is Some(input) else {
                return Err(UnsupportedProgram)
              }
              issue_constructed_client_serialized_infer_fragment(
                occurrence,
                component,
                step - 1,
                input,
                max_wire_bytes,
                max_nodes,
                max_depth,
              )
            }
            None =>
              issue_client_serialized_infer_compute_fragment(
                component,
                step,
                step - 1,
                sequence_limits,
                max_wire_bytes,
                max_nodes,
                max_depth,
              )
          }
        }
      }
      None =>
        match construction {
          Some(original) => {
            guard original.pipeline_inputs.get(0) is Some(input) else {
              return Err(UnsupportedProgram)
            }
            issue_constructed_client_infer_fragment(
              occurrence,
              step - 1,
              input,
              max_wire_bytes,
              max_nodes,
              max_depth,
            )
          }
          None =>
            issue_client_infer_prefix_fragment_for_owner(
              owner, task, step, sequence_limits, max_wire_bytes, max_nodes, max_depth,
            )
        }
    }) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  let mappings = match construction {
    Some(original) => original.mappings
    None =>
      match
        prepare_mappings(
          infer,
          @lower.parameter_bindings(owner),
          sequence_limits.expressions,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Mapping(issue))
      }
  }
  guard client_task_carrier_contract(
      @lower.node_output_carrier(node),
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Some(("relation", output_contract_cid)) else {
    return Err(UnsupportedProgram)
  }
  try {
    let request_writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    if !emit_client_infer_request_body(infer, mappings, request_writer) {
      return Err(Encoding)
    }
    guard parse_plan_identity_value(
        @encode.finish(request_writer),
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      is Some(request) else {
      return Err(Encoding)
    }
    let request_wire = @canonical.stringify_value(
      request, max_wire_bytes, max_nodes, max_depth,
    )
    let request_cid = @canonical.cid_value(
      request, max_wire_bytes, max_nodes, max_depth,
    )
    let barrier_writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_infer_barrier_body(
      barrier_writer,
      infer,
      egress_requirements_cid,
      prefix.output_contract_cid,
      prefix.logical_cid,
      limits_cid,
      @environment.model_execution_cid(execution),
      @environment.model_task_identity(@infer.model_task(infer)).2,
      output_contract_cid,
      request_cid,
      None,
      (cid, writer) => @encode.string_value(writer, cid),
    )
    guard parse_plan_identity_value(
        @encode.finish(barrier_writer),
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      is Some(barrier_body) else {
      return Err(Encoding)
    }
    let barrier_cid = @canonical.cid_value(
      barrier_body, max_wire_bytes, max_nodes, max_depth,
    )
    guard @canonical.object_with_string_field(
        barrier_body, "barrier_cid", barrier_cid,
      )
      is Some(barrier) &&
      parse_plan_identity_value(
        prefix.wire,
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      is Some(prefix_node) else {
      return Err(Encoding)
    }
    let barrier_id = "task_" + task.to_string() + "_infer_" + step.to_string()
    let output_port = @lower.node_id(node)
    let nodes : Array[@canonical.CanonicalValue] = []
    if serialization is None {
      nodes.push(prefix_node)
    }
    let edges : Array[@canonical.CanonicalValue] = []
    let roots : Array[@canonical.CanonicalValue] = []
    let transformations : Array[ClientResultTransformation] = []
    let result_plans : Array[ClientResultPlanIdentity] = []
    let content_producers : Array[(Int, String, String, String)] = []
    if serialization is Some(component) {
      guard client_serialization_graph_original_parts(
          component, value, max_wire_bytes, max_nodes, max_depth,
        )
        is Some((content_nodes, content_edges, content_roots)) &&
        content_roots.is_empty() else {
        return Err(Encoding)
      }
      // These opaque component nodes retain the real byte producer and policy,
      // not a reconstruction from Program JSON or a VALUES metadata substitute.
      for node in content_nodes {
        nodes.push(node)
      }
      for edge in content_edges {
        edges.push(edge)
      }
      let producers : Array[ClientTaskFragmentNode] = [component.output]
      content_producers.push(
        (
          component.step,
          component.output.node_id,
          component.output.output_port,
          component.output.output_contract_cid,
        ),
      )
      for next in (component.step + 1)..<step {
        let fragment = if next == step - 1 {
          prefix
        } else {
          let selected = match construction {
            Some(original) => {
              guard original.pipeline_inputs.get(next - component.step - 1)
                is Some(input) else {
                return Err(UnsupportedProgram)
              }
              issue_constructed_client_serialized_infer_fragment(
                occurrence, component, next, input, max_wire_bytes, max_nodes, max_depth,
              )
            }
            None =>
              issue_client_serialized_infer_compute_fragment(
                component, step, next, sequence_limits, max_wire_bytes, max_nodes,
                max_depth,
              )
          }
          match selected {
            Ok(value) => value
            Err(issue) => return Err(Input(issue))
          }
        }
        guard parse_plan_identity_value(
            fragment.wire,
            max_wire_bytes,
            max_nodes,
            max_depth,
          )
          is Some(node) else {
          return Err(Encoding)
        }
        nodes.push(node)
        guard @lower.node_at(@lower.bound_preparation(owner), next)
          is Some(consumer) else {
          return Err(UnsupportedProgram)
        }
        for port in 0..<@lower.node_input_count(consumer) {
          guard @lower.node_input_target(consumer, port)
            is Some(@pipeline.Step(source)) &&
            @lower.node_at(@lower.bound_preparation(owner), source)
            is Some(source_node) else {
            return Err(UnsupportedProgram)
          }
          let mut producer : ClientTaskFragmentNode? = None
          for candidate in producers {
            if candidate.output_port == @lower.node_id(source_node) {
              producer = Some(candidate)
            }
          }
          guard producer is Some(producer) else {
            return Err(UnsupportedProgram)
          }
          let edge = "{\"carrier\":\"relation\",\"contract_cid\":\"" +
            producer.output_contract_cid +
            "\",\"from\":{\"node_id\":\"" +
            producer.node_id +
            "\",\"port\":\"" +
            producer.output_port +
            "\"},\"to\":{\"node_id\":\"" +
            fragment.node_id +
            "\",\"port\":\"input_" +
            port.to_string() +
            "\"}}"
          guard parse_plan_identity_value(
              edge, max_wire_bytes, max_nodes, max_depth,
            )
            is Some(edge) else {
            return Err(Encoding)
          }
          edges.push(edge)
        }
        producers.push(fragment)
        content_producers.push(
          (
            next,
            fragment.node_id,
            fragment.output_port,
            fragment.output_contract_cid,
          ),
        )
      }
    }
    let node_writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_infer_node_body(
      node_writer,
      barrier,
      @canonical.emit_value,
      barrier_id,
      output_port,
      prefix.output_contract_cid,
      output_contract_cid,
      (cid, writer) => @encode.string_value(writer, cid),
    )
    let barrier_wire = @encode.finish(node_writer)
    guard parse_plan_identity_value(
        barrier_wire, max_wire_bytes, max_nodes, max_depth,
      )
      is Some(barrier_node) else {
      return Err(Encoding)
    }
    nodes.push(barrier_node)
    let edge_wire = "{\"carrier\":\"relation\",\"contract_cid\":\"" +
      prefix.output_contract_cid +
      "\",\"from\":{\"node_id\":\"" +
      prefix.node_id +
      "\",\"port\":\"" +
      prefix.output_port +
      "\"},\"to\":{\"node_id\":\"" +
      barrier_id +
      "\",\"port\":\"input_0\"}}"
    guard parse_plan_identity_value(
        edge_wire, max_wire_bytes, max_nodes, max_depth,
      )
      is Some(edge) else {
      return Err(Encoding)
    }
    edges.push(edge)
    let producers : Array[(Int, String, String, String)] = [
      (step - 1, prefix.node_id, prefix.output_port, prefix.output_contract_cid),
      (step, barrier_id, output_port, output_contract_cid),
    ]
    for producer in content_producers {
      if producer.0 != step - 1 {
        producers.push(producer)
      }
    }
    let mut output : ClientTaskFragmentNode = {
      wire: barrier_wire,
      node_id: barrier_id,
      output_port,
      logical_cid: barrier_cid,
      output_contract_cid,
      output_carrier: "relation",
    }
    for next in (step + 1)..<(terminal + 1) {
      let fragment = match
        (match construction {
          Some(original) => {
            let index = match original.serialization {
              Some(component) => next - component.step - 2
              None => next - step
            }
            guard original.pipeline_inputs.get(index) is Some(input) else {
              return Err(UnsupportedProgram)
            }
            issue_constructed_client_infer_fragment(
              occurrence, next, input, max_wire_bytes, max_nodes, max_depth,
            )
          }
          None =>
            issue_client_infer_compute_fragment(
              owner,
              task,
              step,
              next,
              sequence_limits,
              max_wire_bytes,
              max_nodes,
              max_depth,
              serialization_boundary=serialization.map(value => value.step),
            )
        }) {
        Ok(fragment) => fragment
        Err(issue) => return Err(Input(issue))
      }
      guard parse_plan_identity_value(
          fragment.wire,
          max_wire_bytes,
          max_nodes,
          max_depth,
        )
        is Some(fragment_node) &&
        @lower.node_at(@lower.bound_preparation(owner), next) is Some(consumer) else {
        return Err(Encoding)
      }
      nodes.push(fragment_node)
      for port in 0..<@lower.node_input_count(consumer) {
        guard @lower.node_input_target(consumer, port)
          is Some(@pipeline.Step(source)) else {
          return Err(UnsupportedProgram)
        }
        let mut producer : (Int, String, String, String)? = None
        for candidate in producers {
          if candidate.0 == source {
            producer = Some(candidate)
          }
        }
        guard producer is Some((_, from_node, from_port, contract)) else {
          return Err(UnsupportedProgram)
        }
        let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
        @encode.begin_object(writer)
        @encode.key(writer, "carrier")
        @encode.string_value(writer, "relation")
        @encode.key(writer, "contract_cid")
        @encode.string_value(writer, contract)
        @encode.key(writer, "from")
        @encode.begin_object(writer)
        @encode.key(writer, "node_id")
        @encode.string_value(writer, from_node)
        @encode.key(writer, "port")
        @encode.string_value(writer, from_port)
        @encode.end_object(writer)
        @encode.key(writer, "to")
        @encode.begin_object(writer)
        @encode.key(writer, "node_id")
        @encode.string_value(writer, fragment.node_id)
        @encode.key(writer, "port")
        @encode.string_value(writer, "input_" + port.to_string())
        @encode.end_object(writer)
        @encode.end_object(writer)
        guard parse_plan_identity_value(
            @encode.finish(writer),
            max_wire_bytes,
            max_nodes,
            max_depth,
          )
          is Some(edge) else {
          return Err(Encoding)
        }
        edges.push(edge)
      }
      producers.push(
        (
          next,
          fragment.node_id,
          fragment.output_port,
          fragment.output_contract_cid,
        ),
      )
      output = fragment
    }
    for result in 0..<@strategy.graph_result_count(value.graph) {
      if !include_results ||
        @strategy.graph_result_task(value.graph, result) != Some(task) {
        continue
      }
      guard client_infer_result_producer(occurrence, result, producers)
        is Some((result_step, result_node, result_port, result_contract)) else {
        return Err(Result(Root(RequiresResultTransformation)))
      }
      let parts = match
        issue_client_result_plan_parts(
          value,
          result,
          result_node,
          result_port,
          result_contract,
          max_wire_bytes,
          max_nodes,
          max_depth,
          infer_output=Some((occurrence, result_step)),
        ) {
        Ok(parts) => parts
        Err(issue) => return Err(Result(issue))
      }
      if parts.transformation is Some((node, edge)) {
        nodes.push(node)
        edges.push(edge)
      }
      roots.push(parts.root)
      result_plans.push(parts.plan)
      if parts.selection is Some(selection) {
        transformations.push(selection)
      }
    }
    let graph_writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(graph_writer)
    @encode.key(graph_writer, "data_edges")
    client_plan_emit_array(graph_writer, edges, @canonical.emit_value)
    @encode.key(graph_writer, "nodes")
    client_plan_emit_array(graph_writer, nodes, @canonical.emit_value)
    @encode.key(graph_writer, "root_refs")
    client_plan_emit_array(graph_writer, roots, @canonical.emit_value)
    @encode.end_object(graph_writer)

    let (wire, graph_wire_bytes, graph_wire_nodes, graph_wire_depth) = @encode.finish_text_usage(
      graph_writer,
    )
    let original_graph : ClientTaskPlanGraph = {
      wire,
      transformations,
      result_plans,
      standard_progress_keys: None,
    }

    Ok({
      owner: value,
      task,
      stage: occurrence.stage,
      source_ordinal: step,
      execution,
      item_limit,
      graph: original_graph,
      input_fragment_cid: prefix.logical_cid,
      request_wire,
      request_cid,
      barrier_cid,
      input: prefix,
      output,
      occurrence,
      result_producers: producers,
      serialization,
      original_graph,
      graph_nodes: nodes,
      graph_edges: edges,
      graph_roots: roots,
      graph_wire_bytes,
      graph_wire_nodes,
      graph_wire_depth,
    })
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// Coordinates of this immutable installed plan. This profile does not replan
/// an occurrence; its first and only strategy revision is zero.
pub fn client_infer_plan_boundary(
  value : ClientInferPlanGraph,
) -> (Int, Int, Int, String) {
  (value.task, value.stage, 0, value.barrier_cid)
}
