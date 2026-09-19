///|
priv struct PreparedGraphEndpoint {
  checked : @graph.PathEndpoint
  predicate : Expression?
  input_port : Int?
}

///|
struct PreparedGraphShortest {
  node : PreparedNode
  checked : @graph.CheckedShortest
  source : PreparedGraphEndpoint
  target : PreparedGraphEndpoint
  output_guard : Int64?
}

///|
pub(all) enum GraphShortestIssue {
  InvalidGraphShortestLimits
  InvalidGraphShortestWiring
  GraphShortestPreparationLimit
  MissingGraphShortestParameter(String)
  InvalidGraphShortestParameter(String)
  GraphShortestExpression(ExpressionIssue)
}

///|
fn prepare_graph_shortest_node(
  owner : BoundPrepared,
  step_index : Int,
  max_entries~ : Int,
  max_name_bytes~ : Int,
  expressions~ : ExpressionLimits,
) -> Result[
  (PreparedGraphShortest, Int, Int, ExpressionLimits),
  GraphShortestIssue,
] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidGraphShortestLimits)
  }
  guard owner.prepared.nodes.get(step_index) is Some(node) &&
    node.payload is GraphShortestRows(checked) else {
    return Err(InvalidGraphShortestWiring)
  }
  let mut entries = 0
  let mut name_bytes = 0
  let mut next_port = 1
  let mut remaining = expressions
  let lower = fn(index : Int) -> Result[Expression, GraphShortestIssue] {
    let (expression, usage) = match
      lower_expression_measured(owner, step_index, index, remaining) {
      Ok(value) => value
      Err(issue) => return Err(GraphShortestExpression(issue))
    }
    remaining = {
      ..remaining,
      max_nodes: remaining.max_nodes - usage.nodes,
      max_work: remaining.max_work - usage.work,
      max_literal_nodes: remaining.max_literal_nodes - usage.literal_nodes,
      max_literal_text_bytes: remaining.max_literal_text_bytes -
      usage.literal_bytes,
    }
    Ok(expression)
  }
  let prepare_endpoint = fn(
    endpoint : @graph.PathEndpoint,
    index : Int,
  ) -> Result[PreparedGraphEndpoint, GraphShortestIssue] {
    entries += 1
    if entries > max_entries {
      return Err(GraphShortestPreparationLimit)
    }
    match endpoint {
      @graph.Single(_) =>
        Ok({ checked: endpoint, predicate: None, input_port: None, })
      @graph.Selected(selector) => {
        let predicate = match @graph.selector_predicate(selector) {
          None => None
          Some(_) =>
            match lower(index) {
              Ok(value) => Some(value)
              Err(issue) => return Err(issue)
            }
        }
        let input_port = match @graph.selector_form(selector) {
          @graph.RelationIds(field~, ..) => {
            let bytes = @utf8.encode(@schema.reference_name(field)).length()
            if bytes > max_name_bytes - name_bytes {
              return Err(GraphShortestPreparationLimit)
            }
            name_bytes += bytes
            let port = next_port
            next_port += 1
            Some(port)
          }
          @graph.ExplicitIds | @graph.PredicateNodes => None
        }
        entries += @graph.selector_id_count(selector)
        if entries > max_entries {
          return Err(GraphShortestPreparationLimit)
        }
        Ok({ checked: endpoint, predicate, input_port, })
      }
    }
  }
  let source = match
    prepare_endpoint(@graph.shortest_endpoint(checked, @schema.Left), 0) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let target = match
    prepare_endpoint(@graph.shortest_endpoint(checked, @schema.Right), 1) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if node.inputs.length() != next_port {
    return Err(InvalidGraphShortestWiring)
  }
  let type_count = @graph.shortest_type_count(checked).unwrap_or(0)
  if type_count > max_entries - entries {
    return Err(GraphShortestPreparationLimit)
  }
  entries += type_count
  for index in 0..<type_count {
    guard @graph.shortest_type_at(checked, index) is Some(name) else {
      return Err(InvalidGraphShortestWiring)
    }
    let bytes = @utf8.encode(name).length()
    if bytes > max_name_bytes - name_bytes {
      return Err(GraphShortestPreparationLimit)
    }
    name_bytes += bytes
  }
  if @graph.shortest_weight(checked) is Some(field) {
    let bytes = @utf8.encode(@schema.reference_name(field)).length()
    if bytes > max_name_bytes - name_bytes {
      return Err(GraphShortestPreparationLimit)
    }
    name_bytes += bytes
  }
  let output_guard = match @graph.shortest_output_guard(checked) {
    None => None
    Some(@graph.Literal(value)) => Some(value)
    Some(@graph.Parameter(name)) => {
      let bytes = @utf8.encode(name).length()
      if entries >= max_entries || bytes > max_name_bytes - name_bytes {
        return Err(GraphShortestPreparationLimit)
      }
      entries += 1
      name_bytes += bytes
      guard parameter_value(owner, name) is Some(value) else {
        return Err(MissingGraphShortestParameter(name))
      }
      guard value.value is @value.Number(number) &&
        @scalar.read_safe_integer(number) is Some(integer) &&
        integer >= 1L else {
        return Err(InvalidGraphShortestParameter(name))
      }
      Some(integer)
    }
  }
  Ok(
    (
      { node, checked, source, target, output_guard, },
      entries,
      name_bytes,
      remaining,
    ),
  )
}

///|
fn emit_graph_endpoint(
  endpoint : PreparedGraphEndpoint,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  match endpoint.checked {
    @graph.Single(value) => emit_wire_value(value.value, out)
    @graph.Selected(selector) =>
      match @graph.selector_form(selector) {
        @graph.RelationIds(field~, ..) => {
          @encode.begin_object(out)
          @encode.key(out, "input_port")
          @encode.number_value(out, endpoint.input_port.unwrap().to_double())
          @encode.key(out, "id")
          @encode.string_value(out, @schema.reference_name(field))
          @encode.end_object(out)
        }
        @graph.ExplicitIds => emit_graph_selector(selector, None, out)
        @graph.PredicateNodes =>
          emit_graph_selector(selector, endpoint.predicate, out)
      }
  }
}

///|
fn emit_graph_shortest_node(
  prepared : PreparedGraphShortest,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, prepared.node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  for input in prepared.node.inputs {
    @encode.string_value(out, input)
  }
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, "SGA.shortest_path")
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "source")
  emit_graph_endpoint(prepared.source, out)
  @encode.key(out, "target")
  emit_graph_endpoint(prepared.target, out)
  @encode.key(out, "selection")
  @encode.string_value(
    out,
    match @graph.shortest_selection(prepared.checked) {
      @graph.EachPair => "each_pair"
      @graph.NearestPerSource => "nearest_per_source"
      @graph.NearestPair => "nearest_pair"
    },
  )
  @encode.key(out, "direction")
  emit_graph_direction(@graph.shortest_direction(prepared.checked), out)
  @encode.key(out, "max_hops")
  @encode.number_value(out, @graph.shortest_max_hops(prepared.checked))
  if @graph.shortest_type_count(prepared.checked) is Some(count) {
    @encode.key(out, "edge_types")
    @encode.begin_array(out)
    for index in 0..<count {
      @encode.string_value(
        out,
        @graph.shortest_type_at(prepared.checked, index).unwrap(),
      )
    }
    @encode.end_array(out)
  }
  @encode.key(out, "weight")
  match @graph.shortest_weight(prepared.checked) {
    Some(field) => @encode.string_value(out, @schema.reference_name(field))
    None => @encode.null_value(out)
  }
  if prepared.output_guard is Some(value) {
    @encode.key(out, "max_output_rows")
    @encode.number_value(out, value.to_double())
  }
  @encode.end_object(out)
  @encode.end_object(out)
}
