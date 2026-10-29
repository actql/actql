///|
/// Private Plan material for one checked Result. A transformed root points
/// to its own AoA output, never to the producer's untransformed port.
priv struct ClientResultPlanParts {
  root : @canonical.CanonicalValue
  plan : ClientResultPlanIdentity
  transformation : (@canonical.CanonicalValue, @canonical.CanonicalValue)?
  selection : ClientResultTransformation?
}

///|
pub(all) enum ClientResultPlanPartsIssue {
  Root(ClientDirectResultRootIssue)
  Transformation(ClientResultTransformationIssue)
  Encoding
}

///|
fn emit_result_plan_ref(
  writer : @encode.Writer,
  node : String,
  port : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "node_id")
  @encode.string_value(writer, node)
  @encode.key(writer, "port")
  @encode.string_value(writer, port)
  @encode.end_object(writer)
}

///|
/// The only caller supplies a producer fragment from this same checked graph.
/// Projection and order are selected from the Result owner, not Host JSON.
fn issue_client_result_plan_parts(
  owner : PreparedClientProgram,
  result : Int,
  producer_node : String,
  producer_port : String,
  producer_contract : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  infer_output? : (ClientInferOccurrence, Int)? = None,
  serialization_output? : @lower.PreparedSerialization? = None,
) -> Result[ClientResultPlanParts, ClientResultPlanPartsIssue] {
  if infer_output is Some((inference, selected)) {
    // A direct root must not bypass the same original correspondence merely
    // because its newly retained task output needs no field transformation.
    guard client_infer_occurrence_matches(inference, owner) &&
      @strategy.graph_result_task(owner.graph, result) == Some(inference.task) &&
      @strategy.graph_result_occurrence(owner.graph, result) is Some(occurrence) &&
      physical_equal(
        @execution.managed_result_occurrence_owner(occurrence),
        inference.preparation,
      ) &&
      selected >= inference.step &&
      client_infer_occurrence_output_step(inference)
      .map(last => selected <= last)
      .unwrap_or(false) &&
      @results.port_target(
        @execution.managed_result_occurrence_port(occurrence),
      ) ==
      @pipeline.Step(selected) &&
      @lower.node_at(@lower.bound_preparation(inference.preparation), selected)
      is Some(node) &&
      @lower.node_id(node) == producer_port else {
      return Err(Root(RequiresResultTransformation))
    }
  }
  match
    issue_prepared_client_direct_result_root_for_output(
      owner, result, producer_node, producer_port, producer_contract, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(root) => {
      let plan = root.plan
      guard parse_plan_identity_value(
          root.wire,
          max_wire_bytes,
          max_nodes,
          max_depth,
        )
        is Some(root) else {
        return Err(Encoding)
      }
      return Ok({ root, plan, transformation: None, selection: None, })
    }
    Err(RequiresResultTransformation) => ()
    Err(issue) => return Err(Root(issue))
  }
  // A transformation may change projection/order, not the producer selected
  // by the checked graph. The direct-root refusal also covers other targets.
  guard @strategy.graph_result_task(owner.graph, result) is Some(task) &&
    @strategy.graph_result_occurrence(owner.graph, result) is Some(occurrence) else {
    return Err(Root(RequiresResultTransformation))
  }
  let target = if serialization_output is Some(barrier) {
    // The Content compiler supplies the exact checked producer and original
    // Result occurrence. It may be an intermediate output retained alongside
    // a later Effect terminal, never the acquisition or an invented port.
    let step = @lower.serialization_step(barrier)
    guard @strategy.graph_task_owner(owner.graph, task) is Some(prepared) &&
      physical_equal(prepared, @lower.serialization_owner(barrier)) &&
      @lower.node_at(
        @lower.bound_preparation(@lower.serialization_owner(barrier)),
        step,
      )
      is Some(node) &&
      @lower.node_id(node) == producer_port &&
      physical_equal(
        @execution.managed_result_occurrence_owner(occurrence),
        prepared,
      ) else {
      return Err(Root(RequiresResultTransformation))
    }
    @pipeline.Step(step)
  } else if infer_output is Some((inference, selected)) {
    // A component retains the actual node for this checked Result. The
    // terminal may instead be a later Effect-only projection. Keep the
    // nominal preparation, occurrence, node and Result-target correspondence.
    guard client_infer_occurrence_matches(inference, owner) &&
      inference.task == task &&
      @strategy.graph_task_owner(owner.graph, task) is Some(prepared) &&
      physical_equal(prepared, inference.preparation) &&
      @lower.node_at(@lower.bound_preparation(prepared), inference.step)
      is Some(infer_node) &&
      @lower.payload(infer_node) is @lower.Infer(_) &&
      selected >= inference.step &&
      @lower.preparation_output_target(@lower.bound_preparation(prepared))
      is Some(@pipeline.Step(terminal)) &&
      selected <= terminal &&
      @lower.node_at(@lower.bound_preparation(prepared), selected) is Some(node) &&
      @lower.node_id(node) == producer_port &&
      physical_equal(
        @execution.managed_result_occurrence_owner(occurrence),
        prepared,
      ) else {
      return Err(Root(RequiresResultTransformation))
    }
    @pipeline.Step(selected)
  } else {
    match @strategy.graph_task_target(owner.graph, task) {
      Some(target) => target
      None => {
        guard client_publication_task_target(owner, task) is Some(captured) else {
          return Err(Root(RequiresResultTransformation))
        }
        captured
      }
    }
  }
  guard @results.port_target(
      @execution.managed_result_occurrence_port(occurrence),
    ) ==
    target else {
    return Err(Root(RequiresResultTransformation))
  }
  let selected = match
    prepare_client_result_transformation(
      owner, result, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Transformation(issue))
  }
  let port = @execution.managed_result_occurrence_port(selected.occurrence)
  let order = @results.port_order(port)
  let ordered = @results.publication_term_count(order) != 0
  let output = if ordered { "ordered" } else { "projected" }
  let node_id = "result_" + result.to_string()
  let plan = selected.plan
  let pipeline_writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    emit_client_result_projection_pipeline(pipeline_writer, port)
    guard parse_plan_identity_value(
        @encode.finish(pipeline_writer),
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      is Some(pipeline) else {
      return Err(Encoding)
    }
    let logical_cid = @canonical.cid_value(
      pipeline, max_wire_bytes, max_nodes, max_depth,
    )
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    @encode.key(writer, "node")
    emit_client_result_projection_node(
      writer,
      producer_contract,
      logical_cid,
      node_id,
      output,
      plan.row_contract_cid,
      pipeline,
      @canonical.emit_value,
      (value, writer) => @encode.string_value(writer, value),
    )
    @encode.key(writer, "edge")
    emit_client_result_projection_edge(
      writer,
      producer_contract,
      producer_node,
      producer_port,
      node_id,
      (value, writer) => @encode.string_value(writer, value),
    )
    @encode.key(writer, "root")
    emit_client_requested_result_root(writer, plan.result_name, node_id, output)
    @encode.end_object(writer)
    guard parse_plan_identity_value(
        @encode.finish(writer),
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      is Some(parts) &&
      @canonical.object_field(parts, "root") is Some(root) &&
      @canonical.object_field(parts, "node") is Some(node) &&
      @canonical.object_field(parts, "edge") is Some(edge) else {
      return Err(Encoding)
    }
    Ok({
      root,
      plan,
      transformation: Some((node, edge)),
      selection: Some(selected),
    })
  } catch {
    _ => Err(Encoding)
  }
}

///|
// One field definition for actual publication projection and construction
// geometry. The checked port owns authored fields and the exact ordering law.
fn emit_client_result_projection_pipeline(
  writer : @encode.Writer,
  port : @results.ResultPort,
) -> Unit raise @encode.EncodeFailure {
  let order = @results.port_order(port)
  let ordered = @results.publication_term_count(order) != 0
  let output = if ordered { "ordered" } else { "projected" }
  @encode.begin_object(writer)
  @encode.key(writer, "output")
  @encode.string_value(writer, output)
  @encode.key(writer, "sources")
  @encode.begin_object(writer)
  @encode.key(writer, "input_0")
  @encode.begin_object(writer)
  @encode.key(writer, "sort")
  @encode.string_value(writer, "relation")
  @encode.end_object(writer)
  @encode.end_object(writer)
  @encode.key(writer, "steps")
  @encode.begin_array(writer)
  @encode.begin_object(writer)
  @encode.key(writer, "id")
  @encode.string_value(writer, "projected")
  @encode.key(writer, "in")
  @encode.begin_array(writer)
  @encode.string_value(writer, "input_0")
  @encode.end_array(writer)
  @encode.key(writer, "op")
  @encode.string_value(writer, "REL.select")
  @encode.key(writer, "params")
  @encode.begin_object(writer)
  @encode.key(writer, "columns")
  @encode.begin_array(writer)
  for field in @results.fields(@results.port_result(port)) {
    @encode.string_value(writer, field)
  }
  @encode.end_array(writer)
  @encode.end_object(writer)
  @encode.end_object(writer)
  if ordered {
    @encode.begin_object(writer)
    @encode.key(writer, "id")
    @encode.string_value(writer, "ordered")
    @encode.key(writer, "in")
    @encode.begin_array(writer)
    @encode.string_value(writer, "projected")
    @encode.end_array(writer)
    @encode.key(writer, "op")
    @encode.string_value(writer, "REL.orderByStable")
    @encode.key(writer, "params")
    @encode.begin_object(writer)
    @encode.key(writer, "by")
    @encode.begin_array(writer)
    for index in 0..<@results.publication_term_count(order) {
      let term = @results.publication_term_at(order, index).unwrap()
      @encode.begin_object(writer)
      @encode.key(writer, "dir")
      @encode.string_value(
        writer,
        match @results.publication_term_direction(term) {
          @order.Asc => "asc"
          @order.Desc => "desc"
        },
      )
      @encode.key(writer, "field")
      @encode.string_value(
        writer,
        @schema.reference_name(@results.publication_term_field(term)),
      )
      @encode.key(writer, "nulls")
      @encode.string_value(
        writer,
        match @results.publication_term_nulls(term) {
          @order.First => "first"
          @order.Last => "last"
        },
      )
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "aoa-pipeline/0.1")
  @encode.end_object(writer)
}

///|
fn[P, C] emit_client_result_projection_node(
  writer : @encode.Writer,
  producer_contract : C,
  logical_cid : C,
  node_id : String,
  output : String,
  row_contract_cid : C,
  pipeline : P,
  emit_pipeline : (P, @encode.Writer) -> Unit raise @encode.EncodeFailure,
  emit_cid : (C, @encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "input_contracts")
  @encode.begin_object(writer)
  @encode.key(writer, "input_0")
  emit_cid(producer_contract, writer)
  @encode.end_object(writer)
  @encode.key(writer, "kind")
  @encode.string_value(writer, "aoa_fragment")
  @encode.key(writer, "logical_cid")
  emit_cid(logical_cid, writer)
  @encode.key(writer, "node_id")
  @encode.string_value(writer, node_id)
  @encode.key(writer, "output_contracts")
  @encode.begin_object(writer)
  @encode.key(writer, output)
  emit_cid(row_contract_cid, writer)
  @encode.end_object(writer)
  @encode.key(writer, "pipeline")
  emit_pipeline(pipeline, writer)
  @encode.end_object(writer)
}

///|
fn[C] emit_client_result_projection_edge(
  writer : @encode.Writer,
  producer_contract : C,
  producer_node : String,
  producer_port : String,
  node_id : String,
  emit_cid : (C, @encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "carrier")
  @encode.string_value(writer, "relation")
  @encode.key(writer, "contract_cid")
  emit_cid(producer_contract, writer)
  @encode.key(writer, "from")
  emit_result_plan_ref(writer, producer_node, producer_port)
  @encode.key(writer, "to")
  emit_result_plan_ref(writer, node_id, "input_0")
  @encode.end_object(writer)
}

///|
fn emit_client_requested_result_root(
  writer : @encode.Writer,
  result_name : String,
  node_id : String,
  output : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "name")
  @encode.string_value(writer, result_name)
  @encode.key(writer, "ref")
  emit_result_plan_ref(writer, node_id, output)
  @encode.key(writer, "role")
  @encode.string_value(writer, "requested_result")
  @encode.end_object(writer)
}
