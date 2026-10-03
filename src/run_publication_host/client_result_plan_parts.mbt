///|
/// Private Plan material for one checked Result. A transformed root points
/// to its own AoA output, never to the producer's untransformed port.
priv struct ClientResultPlanParts {
  root : @canonical.CanonicalValue
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
  infer_output? : (Int, Int)? = None,
) -> Result[ClientResultPlanParts, ClientResultPlanPartsIssue] {
  match
    issue_prepared_client_direct_result_root_for_output(
      owner, result, producer_node, producer_port, producer_contract, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(root) => {
      guard parse_plan_identity_value(
          root.wire,
          max_wire_bytes,
          max_nodes,
          max_depth,
        )
        is Some(root) else {
        return Err(Encoding)
      }
      return Ok({ root, transformation: None, selection: None, })
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
  let target = match @strategy.graph_task_target(owner.graph, task) {
    Some(target) => target
    None =>
      if infer_output is None {
        guard client_publication_task_target(owner, task) is Some(captured) else {
          return Err(Root(RequiresResultTransformation))
        }
        captured
      } else {
        // A captured task has no single graph target. The Infer compiler must
        // supply its exact checked terminal, not merely a matching Result name.
        guard task == 0 &&
          infer_output is Some((infer_step, terminal)) &&
          client_acquired_infer_prefix_owner(owner, task, infer_step)
          is Some(prepared) &&
          terminal >= infer_step &&
          @lower.preparation_output_target(@lower.bound_preparation(prepared)) ==
          Some(@pipeline.Step(terminal)) &&
          @lower.node_at(@lower.bound_preparation(prepared), terminal)
          is Some(node) &&
          @lower.node_id(node) == producer_port &&
          physical_equal(
            @execution.managed_result_occurrence_owner(occurrence),
            prepared,
          ) else {
          return Err(Root(RequiresResultTransformation))
        }
        @pipeline.Step(terminal)
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
    @encode.begin_object(pipeline_writer)
    @encode.key(pipeline_writer, "output")
    @encode.string_value(pipeline_writer, output)
    @encode.key(pipeline_writer, "sources")
    @encode.begin_object(pipeline_writer)
    @encode.key(pipeline_writer, "input_0")
    @encode.begin_object(pipeline_writer)
    @encode.key(pipeline_writer, "sort")
    @encode.string_value(pipeline_writer, "relation")
    @encode.end_object(pipeline_writer)
    @encode.end_object(pipeline_writer)
    @encode.key(pipeline_writer, "steps")
    @encode.begin_array(pipeline_writer)
    @encode.begin_object(pipeline_writer)
    @encode.key(pipeline_writer, "id")
    @encode.string_value(pipeline_writer, "projected")
    @encode.key(pipeline_writer, "in")
    @encode.begin_array(pipeline_writer)
    @encode.string_value(pipeline_writer, "input_0")
    @encode.end_array(pipeline_writer)
    @encode.key(pipeline_writer, "op")
    @encode.string_value(pipeline_writer, "REL.select")
    @encode.key(pipeline_writer, "params")
    @encode.begin_object(pipeline_writer)
    @encode.key(pipeline_writer, "columns")
    @encode.begin_array(pipeline_writer)
    for field in @results.fields(@results.port_result(port)) {
      @encode.string_value(pipeline_writer, field)
    }
    @encode.end_array(pipeline_writer)
    @encode.end_object(pipeline_writer)
    @encode.end_object(pipeline_writer)
    if ordered {
      @encode.begin_object(pipeline_writer)
      @encode.key(pipeline_writer, "id")
      @encode.string_value(pipeline_writer, "ordered")
      @encode.key(pipeline_writer, "in")
      @encode.begin_array(pipeline_writer)
      @encode.string_value(pipeline_writer, "projected")
      @encode.end_array(pipeline_writer)
      @encode.key(pipeline_writer, "op")
      @encode.string_value(pipeline_writer, "REL.orderByStable")
      @encode.key(pipeline_writer, "params")
      @encode.begin_object(pipeline_writer)
      @encode.key(pipeline_writer, "by")
      @encode.begin_array(pipeline_writer)
      for index in 0..<@results.publication_term_count(order) {
        let term = @results.publication_term_at(order, index).unwrap()
        @encode.begin_object(pipeline_writer)
        @encode.key(pipeline_writer, "dir")
        @encode.string_value(
          pipeline_writer,
          match @results.publication_term_direction(term) {
            @order.Asc => "asc"
            @order.Desc => "desc"
          },
        )
        @encode.key(pipeline_writer, "field")
        @encode.string_value(
          pipeline_writer,
          @schema.reference_name(@results.publication_term_field(term)),
        )
        @encode.key(pipeline_writer, "nulls")
        @encode.string_value(
          pipeline_writer,
          match @results.publication_term_nulls(term) {
            @order.First => "first"
            @order.Last => "last"
          },
        )
        @encode.end_object(pipeline_writer)
      }
      @encode.end_array(pipeline_writer)
      @encode.end_object(pipeline_writer)
      @encode.end_object(pipeline_writer)
    }
    @encode.end_array(pipeline_writer)
    @encode.key(pipeline_writer, "version")
    @encode.string_value(pipeline_writer, "aoa-pipeline/0.1")
    @encode.end_object(pipeline_writer)
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
    @encode.begin_object(writer)
    @encode.key(writer, "input_contracts")
    @encode.begin_object(writer)
    @encode.key(writer, "input_0")
    @encode.string_value(writer, producer_contract)
    @encode.end_object(writer)
    @encode.key(writer, "kind")
    @encode.string_value(writer, "aoa_fragment")
    @encode.key(writer, "logical_cid")
    @encode.string_value(writer, logical_cid)
    @encode.key(writer, "node_id")
    @encode.string_value(writer, node_id)
    @encode.key(writer, "output_contracts")
    @encode.begin_object(writer)
    @encode.key(writer, output)
    @encode.string_value(writer, plan.row_contract_cid)
    @encode.end_object(writer)
    @encode.key(writer, "pipeline")
    @canonical.emit_value(pipeline, writer)
    @encode.end_object(writer)
    @encode.key(writer, "edge")
    @encode.begin_object(writer)
    @encode.key(writer, "carrier")
    @encode.string_value(writer, "relation")
    @encode.key(writer, "contract_cid")
    @encode.string_value(writer, producer_contract)
    @encode.key(writer, "from")
    emit_result_plan_ref(writer, producer_node, producer_port)
    @encode.key(writer, "to")
    emit_result_plan_ref(writer, node_id, "input_0")
    @encode.end_object(writer)
    @encode.key(writer, "root")
    @encode.begin_object(writer)
    @encode.key(writer, "name")
    @encode.string_value(writer, plan.result_name)
    @encode.key(writer, "ref")
    emit_result_plan_ref(writer, node_id, output)
    @encode.key(writer, "role")
    @encode.string_value(writer, "requested_result")
    @encode.end_object(writer)
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
    Ok({ root, transformation: Some((node, edge)), selection: Some(selected), })
  } catch {
    _ => Err(Encoding)
  }
}
