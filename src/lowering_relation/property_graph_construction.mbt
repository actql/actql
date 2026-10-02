///|
/// Column coordinates belong to the exact checked producer occurrences. These
/// are operation preparation, not a second graph model or execution owner.
struct PropertyElementBinding {
  input : Int
  name : String
  keys : Array[Int]
  properties : Array[Int]
}

///|
struct PropertyEdgeBinding {
  element : PropertyElementBinding
  source : Array[Int]
  target : Array[Int]
}

///|
struct PreparedPropertyGraphConstruction {
  step : Int
  node : PreparedNode
  checked : @graph.CheckedPropertyConstruction
  contract : @graph_contract.CheckedContract
  nodes : Array[PropertyElementBinding]
  edges : Array[PropertyEdgeBinding]
}

///|
priv struct PropertyBindingBudget {
  mut work : Int
  mut entries : Int
  mut names : Int
}

///|
priv suberror PropertyBindingStop {
  InvalidPropertyBinding
  PropertyBindingLimit
}

///|
fn property_binding_columns(
  schema : @schema.Schema,
  fields : Array[@schema.FieldName],
  budget : PropertyBindingBudget,
) -> Array[Int] raise PropertyBindingStop {
  let columns = []
  for name in fields {
    let bytes = @utf8.encode(@schema.reference_name(name)).length()
    if budget.entries == 0 || bytes > budget.names {
      raise PropertyBindingLimit
    }
    budget.entries -= 1
    budget.names -= bytes
    let mut found = None
    for index in 0..<@schema.field_count(schema) {
      if budget.work == 0 {
        raise PropertyBindingLimit
      }
      budget.work -= 1
      if @schema.field_at(schema, index).unwrap().name == name {
        found = Some(index)
        break
      }
    }
    guard found is Some(index) else { raise InvalidPropertyBinding }
    columns.push(index)
  }
  columns
}

///|
fn property_element_binding(
  pipeline : @pipeline.CheckedPipeline,
  node : PreparedNode,
  input : Int,
  element : @graph.PropertyElement,
  budget : PropertyBindingBudget,
) -> PropertyElementBinding raise PropertyBindingStop {
  if budget.entries == 0 || budget.work == 0 {
    raise PropertyBindingLimit
  }
  budget.entries -= 1
  budget.work -= 1
  guard node.input_targets.get(input) is Some(target) &&
    @pipeline.schema_at(pipeline, target) is Some(schema) else {
    raise InvalidPropertyBinding
  }
  let name = @carrier.property_definition_name(
    @graph.property_element_definition(element),
  )
  let bytes = @utf8.encode(name).length()
  if bytes > budget.names {
    raise PropertyBindingLimit
  }
  budget.names -= bytes
  let keys = property_binding_columns(
    schema,
    @graph.property_element_keys(element),
    budget,
  )
  let properties = property_binding_columns(
    schema,
    @graph.property_element_properties(element).map(pair => pair.0),
    budget,
  )
  { input, name, keys, properties, }
}

///|
fn prepare_property_graph_construction_node(
  owner : BoundPrepared,
  step : Int,
  max_entries~ : Int,
  max_name_bytes~ : Int,
  max_work~ : Int,
  max_depth~ : Int,
) -> Result[
  (PreparedPropertyGraphConstruction, Int, Int, Int),
  GraphConstructionIssue,
] {
  if max_entries < 0 || max_name_bytes < 0 || max_work < 0 {
    return Err(InvalidPropertyGraphConstruction)
  }
  guard owner.prepared.nodes.get(step) is Some(node) &&
    node.payload is PropertyGraphConstructionValue(checked) &&
    node.output_carrier is @carrier.GraphValue(graph) &&
    @carrier.graph_property_definition(graph) is Some(_) else {
    return Err(InvalidPropertyGraphConstruction)
  }
  let n = @graph.property_construction_node_count(checked)
  let e = @graph.property_construction_edge_count(checked)
  if node.input_targets.length() != n + e || node.inputs.length() != n + e {
    return Err(InvalidPropertyGraphConstruction)
  }
  let budget : PropertyBindingBudget = {
    work: max_work,
    entries: max_entries,
    names: max_name_bytes,
  }
  try {
    let nodes = []
    let edges = []
    for index in 0..<n {
      nodes.push(
        property_element_binding(
          owner.prepared.owner,
          node,
          index,
          @graph.property_construction_node_at(checked, index).unwrap(),
          budget,
        ),
      )
    }
    for index in 0..<e {
      let edge = @graph.property_construction_edge_at(checked, index).unwrap()
      let input = n + index
      let element = property_element_binding(
        owner.prepared.owner,
        node,
        input,
        @graph.property_edge_element(edge),
        budget,
      )
      let schema = @pipeline.schema_at(
        owner.prepared.owner,
        node.input_targets[input],
      ).unwrap()
      let (source, target) = @graph.property_edge_keys(edge)
      edges.push({
        element,
        source: property_binding_columns(schema, source, budget),
        target: property_binding_columns(schema, target, budget),
      })
    }
    let contract = match
      @graph_contract.admit_property_graph(node.output_carrier, {
        max_bytes: budget.names,
        max_nodes: budget.work,
        max_depth,
      }) {
      Ok(contract) => contract
      Err(_) => raise PropertyBindingLimit
    }
    budget.work -= @graph_contract.property_nodes(contract)
    budget.names -= @graph_contract.property_bytes(contract)
    Ok(
      (
        { step, node, checked, contract, nodes, edges, },
        max_entries - budget.entries,
        max_name_bytes - budget.names,
        max_work - budget.work,
      ),
    )
  } catch {
    _ => Err(InvalidPropertyGraphConstruction)
  }
}

///|
pub fn property_graph_construction_step(
  value : PreparedPropertyGraphConstruction,
) -> Int {
  value.step
}

///|
pub fn property_graph_construction_checked(
  value : PreparedPropertyGraphConstruction,
) -> @graph.CheckedPropertyConstruction {
  value.checked
}

///|
pub fn property_graph_construction_node_count(
  value : PreparedPropertyGraphConstruction,
) -> Int {
  value.nodes.length()
}

///|
pub fn property_graph_construction_edge_count(
  value : PreparedPropertyGraphConstruction,
) -> Int {
  value.edges.length()
}

///|
pub fn property_graph_construction_node_at(
  value : PreparedPropertyGraphConstruction,
  index : Int,
) -> PropertyElementBinding? {
  value.nodes.get(index)
}

///|
pub fn property_graph_construction_edge_at(
  value : PreparedPropertyGraphConstruction,
  index : Int,
) -> PropertyEdgeBinding? {
  value.edges.get(index)
}

///|
pub fn property_binding_input(value : PropertyElementBinding) -> Int {
  value.input
}

///|
pub fn property_binding_keys(value : PropertyElementBinding) -> Array[Int] {
  value.keys.copy()
}

///|
pub fn property_binding_properties(
  value : PropertyElementBinding,
) -> Array[Int] {
  value.properties.copy()
}

///|
pub fn property_edge_binding_element(
  value : PropertyEdgeBinding,
) -> PropertyElementBinding {
  value.element
}

///|
pub fn property_edge_binding_keys(
  value : PropertyEdgeBinding,
) -> (Array[Int], Array[Int]) {
  (value.source.copy(), value.target.copy())
}

///|
fn emit_property_binding(
  value : PropertyElementBinding,
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
fn emit_property_graph_construction_node(
  value : PreparedPropertyGraphConstruction,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  begin_graph_construction_node(
    out,
    value.node.id,
    value.node.inputs,
    "BRIDGE.rows.to_property_graph",
  )
  @encode.key(out, "contract")
  @graph_contract.emit_checked_property_graph(value.contract, out)
  @encode.key(out, "edges")
  @encode.begin_array(out)
  for edge in value.edges {
    @encode.begin_object(out)
    @encode.key(out, "element")
    emit_property_binding(edge.element, out)
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
    emit_property_binding(node, out)
  }
  @encode.end_array(out)
  end_graph_construction_node(out)
}
