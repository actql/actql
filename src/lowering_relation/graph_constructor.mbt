///|
/// Column coordinates belong to the exact checked producer occurrences. These
/// are operation preparation, not a second graph model or execution owner.
struct GraphElementBinding {
  input : Int
  name : String
  keys : Array[Int]
  properties : Array[Int]
}

///|
struct GraphEdgeBinding {
  element : GraphElementBinding
  source : Array[Int]
  target : Array[Int]
}

///|
struct PreparedGraphConstruction {
  step : Int
  node : PreparedNode
  checked : @graph.CheckedGraphConstruction
  contract : @graph_contract.CheckedContract
  nodes : Array[GraphElementBinding]
  edges : Array[GraphEdgeBinding]
}

///|
priv struct GraphBindingBudget {
  mut work : Int
  mut entries : Int
  mut names : Int
}

///|
priv suberror GraphBindingStop {
  InvalidGraphBinding
  GraphBindingLimit
}

///|
fn graph_binding_columns(
  schema : @schema.Schema,
  fields : Array[@schema.FieldName],
  budget : GraphBindingBudget,
) -> Array[Int] raise GraphBindingStop {
  let columns = []
  for name in fields {
    let bytes = @utf8.encode(@schema.reference_name(name)).length()
    if budget.entries == 0 || bytes > budget.names {
      raise GraphBindingLimit
    }
    budget.entries -= 1
    budget.names -= bytes
    let mut found = None
    for index in 0..<@schema.field_count(schema) {
      if budget.work == 0 {
        raise GraphBindingLimit
      }
      budget.work -= 1
      if @schema.field_at(schema, index).unwrap().name == name {
        found = Some(index)
        break
      }
    }
    guard found is Some(index) else { raise InvalidGraphBinding }
    columns.push(index)
  }
  columns
}

///|
fn graph_element_binding(
  pipeline : @pipeline.CheckedPipeline,
  node : PreparedNode,
  input : Int,
  element : @graph.GraphElementConstruction,
  budget : GraphBindingBudget,
) -> GraphElementBinding raise GraphBindingStop {
  if budget.entries == 0 || budget.work == 0 {
    raise GraphBindingLimit
  }
  budget.entries -= 1
  budget.work -= 1
  guard node.input_targets.get(input) is Some(target) &&
    @pipeline.schema_at(pipeline, target) is Some(schema) else {
    raise InvalidGraphBinding
  }
  let name = @carrier.graph_element_definition_name(
    @graph.graph_element_definition(element),
  )
  let bytes = @utf8.encode(name).length()
  if bytes > budget.names {
    raise GraphBindingLimit
  }
  budget.names -= bytes
  let keys = graph_binding_columns(
    schema,
    @graph.graph_element_keys(element),
    budget,
  )
  let properties = graph_binding_columns(
    schema,
    @graph.graph_element_properties(element).map(pair => pair.0),
    budget,
  )
  { input, name, keys, properties, }
}

///|
fn prepare_graph_construction_node(
  owner : BoundPrepared,
  step : Int,
  max_entries~ : Int,
  max_name_bytes~ : Int,
  max_work~ : Int,
  max_depth~ : Int,
) -> Result[(PreparedGraphConstruction, Int, Int, Int), GraphConstructionIssue] {
  if max_entries < 0 || max_name_bytes < 0 || max_work < 0 {
    return Err(InvalidGraphConstruction)
  }
  guard owner.prepared.nodes.get(step) is Some(node) &&
    node.payload is GraphConstructionValue(checked) &&
    node.output_carrier is @carrier.GraphValue(_) else {
    return Err(InvalidGraphConstruction)
  }
  let n = @graph.construction_node_count(checked)
  let e = @graph.construction_edge_count(checked)
  if node.input_targets.length() != n + e || node.inputs.length() != n + e {
    return Err(InvalidGraphConstruction)
  }
  let budget : GraphBindingBudget = {
    work: max_work,
    entries: max_entries,
    names: max_name_bytes,
  }
  try {
    let nodes = []
    let edges = []
    for index in 0..<n {
      nodes.push(
        graph_element_binding(
          owner.prepared.owner,
          node,
          index,
          @graph.construction_node_at(checked, index).unwrap(),
          budget,
        ),
      )
    }
    for index in 0..<e {
      let edge = @graph.construction_edge_at(checked, index).unwrap()
      let input = n + index
      let element = graph_element_binding(
        owner.prepared.owner,
        node,
        input,
        @graph.graph_edge_element(edge),
        budget,
      )
      let schema = @pipeline.schema_at(
        owner.prepared.owner,
        node.input_targets[input],
      ).unwrap()
      let (source, target) = @graph.graph_edge_keys(edge)
      edges.push({
        element,
        source: graph_binding_columns(schema, source, budget),
        target: graph_binding_columns(schema, target, budget),
      })
    }
    let contract = match
      @graph_contract.admit(node.output_carrier, {
        max_bytes: budget.names,
        max_nodes: budget.work,
        max_depth,
      }) {
      Ok(contract) => contract
      Err(_) => raise GraphBindingLimit
    }
    budget.work -= @graph_contract.nodes(contract)
    budget.names -= @graph_contract.bytes(contract)
    Ok(
      (
        { step, node, checked, contract, nodes, edges, },
        max_entries - budget.entries,
        max_name_bytes - budget.names,
        max_work - budget.work,
      ),
    )
  } catch {
    _ => Err(InvalidGraphConstruction)
  }
}

///|
pub fn graph_construction_step(value : PreparedGraphConstruction) -> Int {
  value.step
}

///|
pub fn graph_construction_checked(
  value : PreparedGraphConstruction,
) -> @graph.CheckedGraphConstruction {
  value.checked
}

///|
pub fn graph_construction_node_count(value : PreparedGraphConstruction) -> Int {
  value.nodes.length()
}

///|
pub fn graph_construction_edge_count(value : PreparedGraphConstruction) -> Int {
  value.edges.length()
}

///|
pub fn graph_construction_node_at(
  value : PreparedGraphConstruction,
  index : Int,
) -> GraphElementBinding? {
  value.nodes.get(index)
}

///|
pub fn graph_construction_edge_at(
  value : PreparedGraphConstruction,
  index : Int,
) -> GraphEdgeBinding? {
  value.edges.get(index)
}

///|
pub fn graph_binding_input(value : GraphElementBinding) -> Int {
  value.input
}

///|
pub fn graph_binding_keys(value : GraphElementBinding) -> Array[Int] {
  value.keys.copy()
}

///|
pub fn graph_binding_properties(value : GraphElementBinding) -> Array[Int] {
  value.properties.copy()
}

///|
pub fn graph_edge_binding_element(
  value : GraphEdgeBinding,
) -> GraphElementBinding {
  value.element
}

///|
pub fn graph_edge_binding_keys(
  value : GraphEdgeBinding,
) -> (Array[Int], Array[Int]) {
  (value.source.copy(), value.target.copy())
}

///|
fn emit_graph_binding(
  value : GraphElementBinding,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "definition")
  @encode.string_value(out, value.name)
  @encode.key(out, "input")
  @encode.number_value(out, value.input.to_double())
  @encode.key(out, "keys")
  @encode.begin_array(out)
  for column in value.keys {
    @encode.number_value(out, column.to_double())
  }
  @encode.end_array(out)
  @encode.key(out, "properties")
  @encode.begin_array(out)
  for column in value.properties {
    @encode.number_value(out, column.to_double())
  }
  @encode.end_array(out)
  @encode.end_object(out)
}

///|
fn emit_graph_construction_node(
  value : PreparedGraphConstruction,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  begin_graph_construction_node(
    out,
    value.node.id,
    value.node.inputs,
    "BRIDGE.rows.to_graph",
  )
  @encode.key(out, "contract")
  @graph_contract.emit_checked_graph(value.contract, out)
  @encode.key(out, "edges")
  @encode.begin_array(out)
  for edge in value.edges {
    @encode.begin_object(out)
    @encode.key(out, "element")
    emit_graph_binding(edge.element, out)
    @encode.key(out, "source")
    @encode.begin_array(out)
    for column in edge.source {
      @encode.number_value(out, column.to_double())
    }
    @encode.end_array(out)
    @encode.key(out, "target")
    @encode.begin_array(out)
    for column in edge.target {
      @encode.number_value(out, column.to_double())
    }
    @encode.end_array(out)
    @encode.end_object(out)
  }
  @encode.end_array(out)
  @encode.key(out, "nodes")
  @encode.begin_array(out)
  for node in value.nodes {
    emit_graph_binding(node, out)
  }
  @encode.end_array(out)
  end_graph_construction_node(out)
}
