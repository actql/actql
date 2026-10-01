///|
/// Checked explicit Graph construction retained without frontend rediscovery.
struct PreparedGraphConstruction {
  step : Int
  node : PreparedNode
  declared_nodes : Bool
  graph : @carrier.Graph
  names : @carrier.GraphRowNames
  node_projection : Array[@schema.FieldName]
  edge_projection : Array[@schema.FieldName]
  expansion : Array[PreparedGraphConstructionExpansionNode]
}

///|
/// One registered node in explicit Graph construction's finite expansion.
priv struct PreparedGraphConstructionExpansionNode {
  role : String
  operation : String
  inputs : Int
  source_node : Bool
} derive(Eq)

///|
fn graph_construction_generated_role_id(step : Int, role : String) -> String {
  "graph_" + role + "_" + step.to_string()
}

///|
fn prepare_graph_construction_expansion(
  declared_nodes : Bool,
) -> Array[PreparedGraphConstructionExpansionNode] {
  if declared_nodes {
    [
      { role: "nodes", operation: "REL.select", inputs: 1, source_node: false, },
      { role: "edges", operation: "REL.select", inputs: 1, source_node: false, },
      {
        role: "source_closed",
        operation: "REL.join",
        inputs: 2,
        source_node: false,
      },
      {
        role: "target_closed",
        operation: "REL.join",
        inputs: 2,
        source_node: false,
      },
      {
        role: "",
        operation: "BRIDGE.rows.to_graph",
        inputs: 2,
        source_node: true,
      },
    ]
  } else {
    [
      {
        role: "source_nodes",
        operation: "REL.select",
        inputs: 1,
        source_node: false,
      },
      {
        role: "target_nodes",
        operation: "REL.select",
        inputs: 1,
        source_node: false,
      },
      {
        role: "all_nodes",
        operation: "REL.unionAll",
        inputs: 2,
        source_node: false,
      },
      {
        role: "nodes",
        operation: "REL.distinct",
        inputs: 1,
        source_node: false,
      },
      { role: "edges", operation: "REL.select", inputs: 1, source_node: false, },
      {
        role: "",
        operation: "BRIDGE.rows.to_graph",
        inputs: 2,
        source_node: true,
      },
    ]
  }
}

///|
fn graph_construction_expansion_reference_count(
  expansion : Array[PreparedGraphConstructionExpansionNode],
) -> Int {
  let mut count = 0
  for node in expansion {
    count += node.inputs
  }
  count
}

///|
pub(all) enum GraphConstructionIssue {
  InvalidGraphConstruction
  InvalidPropertyGraphConstruction
} derive(Eq, Debug)

///|
fn graph_projection_push_unique(
  fields : Array[@schema.FieldName],
  field : @schema.FieldName,
) -> Unit {
  let name = @schema.reference_name(field)
  for existing in fields {
    if @schema.reference_name(existing) == name {
      return
    }
  }
  fields.push(field)
}

///|
fn prepare_graph_construction_node(
  node : PreparedNode,
  step~ : Int,
  max_entries~ : Int,
  max_name_bytes~ : Int,
  max_work~ : Int,
) -> Result[(PreparedGraphConstruction, Int, Int, Int), GraphConstructionIssue] {
  guard node.payload is GraphConstructionValue(checked) &&
    @graph.construction_output(checked) is @carrier.GraphValue(graph) &&
    @carrier.graph_names(graph) is Some(names) &&
    node.graph_construction_expansion is Some(expansion) else {
    return Err(InvalidGraphConstruction)
  }
  let declared_nodes = @graph.construction_nodes_name(checked) is Some(_)
  if node.inputs.length() != (if declared_nodes { 2 } else { 1 }) ||
    expansion != prepare_graph_construction_expansion(declared_nodes) {
    return Err(InvalidGraphConstruction)
  }
  let (identity, source, target, label) = @carrier.graph_row_fields(names)
  let node_projection : Array[@schema.FieldName] = []
  let edge_projection : Array[@schema.FieldName] = []
  graph_projection_push_unique(node_projection, identity)
  graph_projection_push_unique(edge_projection, source)
  graph_projection_push_unique(edge_projection, target)
  match label {
    Some(field) => graph_projection_push_unique(edge_projection, field)
    None => ()
  }
  let node_properties = @carrier.graph_node_properties(graph)
  for index in 0..<@carrier.field_count(node_properties) {
    graph_projection_push_unique(
      node_projection,
      @carrier.field_at(node_properties, index).unwrap().name,
    )
  }
  let edge_properties = @carrier.graph_edge_properties(graph)
  for index in 0..<@carrier.field_count(edge_properties) {
    graph_projection_push_unique(
      edge_projection,
      @carrier.field_at(edge_properties, index).unwrap().name,
    )
  }
  let projection_count = node_projection.length() + edge_projection.length()
  let mut used_names = 0
  for projection in [node_projection, edge_projection] {
    for field in projection {
      let bytes = @utf8.encode(@schema.reference_name(field)).length()
      if projection_count > max_entries ||
        used_names > max_name_bytes - bytes ||
        projection_count > max_work {
        return Err(InvalidGraphConstruction)
      }
      used_names += bytes
    }
  }
  Ok(
    (
      {
        step,
        node,
        declared_nodes,
        graph,
        names,
        node_projection,
        edge_projection,
        expansion,
      },
      projection_count,
      used_names,
      projection_count,
    ),
  )
}

///|
pub fn graph_construction_output_carrier(
  value : PreparedGraphConstruction,
) -> @carrier.Carrier {
  @carrier.graph_carrier(value.graph)
}

///|
pub fn graph_construction_derives_nodes(
  value : PreparedGraphConstruction,
) -> Bool {
  !value.declared_nodes
}

///|
pub fn graph_construction_node_identity(
  value : PreparedGraphConstruction,
) -> @schema.FieldName {
  let (node, _, _, _) = @carrier.graph_row_fields(value.names)
  node
}

///|
pub fn graph_construction_edge_source(
  value : PreparedGraphConstruction,
) -> @schema.FieldName {
  let (_, source, _, _) = @carrier.graph_row_fields(value.names)
  source
}

///|
pub fn graph_construction_edge_target(
  value : PreparedGraphConstruction,
) -> @schema.FieldName {
  let (_, _, target, _) = @carrier.graph_row_fields(value.names)
  target
}

///|
pub fn graph_construction_edge_label(
  value : PreparedGraphConstruction,
) -> @schema.FieldName? {
  let (_, _, _, label) = @carrier.graph_row_fields(value.names)
  label
}

///|
pub fn graph_construction_node_property_count(
  value : PreparedGraphConstruction,
) -> Int {
  @carrier.field_count(@carrier.graph_node_properties(value.graph))
}

///|
pub fn graph_construction_node_property_at(
  value : PreparedGraphConstruction,
  index : Int,
) -> @schema.FieldName? {
  @carrier.field_at(@carrier.graph_node_properties(value.graph), index).map(field => {
    field.name
  })
}

///|
pub fn graph_construction_edge_property_count(
  value : PreparedGraphConstruction,
) -> Int {
  @carrier.field_count(@carrier.graph_edge_properties(value.graph))
}

///|
pub fn graph_construction_edge_property_at(
  value : PreparedGraphConstruction,
  index : Int,
) -> @schema.FieldName? {
  @carrier.field_at(@carrier.graph_edge_properties(value.graph), index).map(field => {
    field.name
  })
}

///|
fn emit_graph_field(
  name : @schema.FieldName,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.string_value(out, @schema.reference_name(name))
}

///|
fn emit_graph_properties(
  properties : @carrier.Knowledge,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(out)
  for index in 0..<@carrier.field_count(properties) {
    emit_graph_field(@carrier.field_at(properties, index).unwrap().name, out)
  }
  @encode.end_array(out)
}

///|
fn begin_graph_construction_node(
  out : @encode.Writer,
  id : String,
  inputs : Array[String],
  operation : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  for input in inputs {
    @encode.string_value(out, input)
  }
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, operation)
  @encode.key(out, "params")
  @encode.begin_object(out)
}

///|
fn end_graph_construction_node(
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.end_object(out)
  @encode.end_object(out)
}

///|
fn emit_graph_projection_column(
  out : @encode.Writer,
  field : @schema.FieldName,
) -> Unit raise @encode.EncodeFailure {
  let name = @schema.reference_name(field)
  @encode.begin_object(out)
  @encode.key(out, "from")
  @encode.string_value(out, name)
  @encode.key(out, "to")
  @encode.string_value(out, name)
  @encode.end_object(out)
}

///|
fn emit_graph_renamed_column(
  out : @encode.Writer,
  from : @schema.FieldName,
  to : @schema.FieldName,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "from")
  @encode.string_value(out, @schema.reference_name(from))
  @encode.key(out, "to")
  @encode.string_value(out, @schema.reference_name(to))
  @encode.end_object(out)
}

///|
fn emit_graph_join_column(
  out : @encode.Writer,
  side : String,
  field : @schema.FieldName,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "path")
  @encode.begin_array(out)
  @encode.string_value(out, side)
  @encode.string_value(out, @schema.reference_name(field))
  @encode.end_array(out)
  @encode.key(out, "type")
  @encode.string_value(out, "col")
  @encode.end_object(out)
}

///|
fn emit_graph_endpoint_closure(
  prepared : PreparedGraphConstruction,
  out : @encode.Writer,
  id : String,
  edges : String,
  nodes : String,
  endpoint : @schema.FieldName,
) -> Unit raise @encode.EncodeFailure {
  let (identity, _, _, _) = @carrier.graph_row_fields(prepared.names)
  begin_graph_construction_node(out, id, [edges, nodes], "REL.join")
  @encode.key(out, "how")
  @encode.string_value(out, "semi")
  @encode.key(out, "key_pairs")
  @encode.begin_array(out)
  @encode.begin_object(out)
  @encode.key(out, "left")
  emit_graph_field(endpoint, out)
  @encode.key(out, "right")
  emit_graph_field(identity, out)
  @encode.end_object(out)
  @encode.end_array(out)
  @encode.key(out, "null_key")
  @encode.string_value(out, "no_match")
  @encode.key(out, "on")
  @encode.begin_object(out)
  @encode.key(out, "left")
  emit_graph_join_column(out, "left", endpoint)
  @encode.key(out, "op")
  @encode.string_value(out, "eq")
  @encode.key(out, "right")
  emit_graph_join_column(out, "right", identity)
  @encode.key(out, "type")
  @encode.string_value(out, "cmp")
  @encode.end_object(out)
  end_graph_construction_node(out)
}

///|
fn emit_graph_construction_node(
  prepared : PreparedGraphConstruction,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let (node, source, target, label) = @carrier.graph_row_fields(prepared.names)
  let nodes = graph_construction_generated_role_id(prepared.step, "nodes")
  let edges = graph_construction_generated_role_id(prepared.step, "edges")
  let source_closed = graph_construction_generated_role_id(
    prepared.step,
    "source_closed",
  )
  let target_closed = graph_construction_generated_role_id(
    prepared.step,
    "target_closed",
  )
  if !prepared.declared_nodes {
    let source_nodes = graph_construction_generated_role_id(
      prepared.step,
      "source_nodes",
    )
    let target_nodes = graph_construction_generated_role_id(
      prepared.step,
      "target_nodes",
    )
    let all_nodes = graph_construction_generated_role_id(
      prepared.step,
      "all_nodes",
    )
    begin_graph_construction_node(
      out,
      source_nodes,
      [prepared.node.inputs[0]],
      "REL.select",
    )
    @encode.key(out, "columns")
    @encode.begin_array(out)
    emit_graph_renamed_column(out, source, node)
    @encode.end_array(out)
    end_graph_construction_node(out)

    begin_graph_construction_node(
      out,
      target_nodes,
      [prepared.node.inputs[0]],
      "REL.select",
    )
    @encode.key(out, "columns")
    @encode.begin_array(out)
    emit_graph_renamed_column(out, target, node)
    @encode.end_array(out)
    end_graph_construction_node(out)

    begin_graph_construction_node(
      out,
      all_nodes,
      [source_nodes, target_nodes],
      "REL.unionAll",
    )
    end_graph_construction_node(out)
    begin_graph_construction_node(out, nodes, [all_nodes], "REL.distinct")
    end_graph_construction_node(out)

    begin_graph_construction_node(
      out,
      edges,
      [prepared.node.inputs[0]],
      "REL.select",
    )
    @encode.key(out, "columns")
    @encode.begin_array(out)
    for field in prepared.edge_projection {
      emit_graph_projection_column(out, field)
    }
    @encode.end_array(out)
    end_graph_construction_node(out)

    begin_graph_construction_node(
      out,
      prepared.node.id,
      [nodes, edges],
      operation(prepared.node),
    )
    @encode.key(out, "edge")
    @encode.begin_object(out)
    @encode.key(out, "label")
    match label {
      Some(name) => emit_graph_field(name, out)
      None => @encode.null_value(out)
    }
    @encode.key(out, "properties")
    emit_graph_properties(@carrier.graph_edge_properties(prepared.graph), out)
    @encode.key(out, "source")
    emit_graph_field(source, out)
    @encode.key(out, "target")
    emit_graph_field(target, out)
    @encode.end_object(out)
    @encode.key(out, "mode")
    @encode.string_value(out, "derived_endpoints")
    @encode.key(out, "node")
    @encode.begin_object(out)
    @encode.key(out, "identity")
    emit_graph_field(node, out)
    @encode.key(out, "properties")
    emit_graph_properties(@carrier.graph_node_properties(prepared.graph), out)
    @encode.end_object(out)
    end_graph_construction_node(out)
    return
  }
  begin_graph_construction_node(
    out,
    nodes,
    [prepared.node.inputs[0]],
    "REL.select",
  )
  @encode.key(out, "columns")
  @encode.begin_array(out)
  for field in prepared.node_projection {
    emit_graph_projection_column(out, field)
  }
  @encode.end_array(out)
  end_graph_construction_node(out)

  begin_graph_construction_node(
    out,
    edges,
    [prepared.node.inputs[1]],
    "REL.select",
  )
  @encode.key(out, "columns")
  @encode.begin_array(out)
  for field in prepared.edge_projection {
    emit_graph_projection_column(out, field)
  }
  @encode.end_array(out)
  end_graph_construction_node(out)

  emit_graph_endpoint_closure(
    prepared, out, source_closed, edges, nodes, source,
  )
  emit_graph_endpoint_closure(
    prepared, out, target_closed, source_closed, nodes, target,
  )

  begin_graph_construction_node(
    out,
    prepared.node.id,
    [nodes, target_closed],
    operation(prepared.node),
  )
  @encode.key(out, "edge")
  @encode.begin_object(out)
  @encode.key(out, "label")
  match label {
    Some(name) => emit_graph_field(name, out)
    None => @encode.null_value(out)
  }
  @encode.key(out, "properties")
  emit_graph_properties(@carrier.graph_edge_properties(prepared.graph), out)
  @encode.key(out, "source")
  emit_graph_field(source, out)
  @encode.key(out, "target")
  emit_graph_field(target, out)
  @encode.end_object(out)
  @encode.key(out, "mode")
  @encode.string_value(out, "declared_nodes")
  @encode.key(out, "node")
  @encode.begin_object(out)
  @encode.key(out, "identity")
  emit_graph_field(node, out)
  @encode.key(out, "properties")
  emit_graph_properties(@carrier.graph_node_properties(prepared.graph), out)
  @encode.end_object(out)
  end_graph_construction_node(out)
}
