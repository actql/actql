///|
/// Checked explicit Graph construction retained without frontend rediscovery.
struct PreparedGraphConstruction {
  node : PreparedNode
  graph : @carrier.Graph
  names : @carrier.GraphRowNames
}

///|
pub(all) enum GraphConstructionIssue {
  InvalidGraphConstruction
} derive(Eq, Debug)

///|
fn prepare_graph_construction_node(
  node : PreparedNode,
) -> Result[PreparedGraphConstruction, GraphConstructionIssue] {
  guard node.payload is GraphConstructionValue(checked) &&
    node.inputs.length() == 2 &&
    @graph.construction_output(checked) is @carrier.GraphValue(graph) &&
    @carrier.graph_names(graph) is Some(names) else {
    return Err(InvalidGraphConstruction)
  }
  Ok({ node, graph, names, })
}

///|
pub fn graph_construction_output_carrier(
  value : PreparedGraphConstruction,
) -> @carrier.Carrier {
  @carrier.graph_carrier(value.graph)
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
fn emit_graph_construction_node(
  prepared : PreparedGraphConstruction,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let (node, source, target, label) = @carrier.graph_row_fields(prepared.names)
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
  @encode.string_value(out, operation(prepared.node))
  @encode.key(out, "params")
  @encode.begin_object(out)
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
  @encode.end_object(out)
  @encode.end_object(out)
}
