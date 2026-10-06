/// Canonical Graph entry points for the admitted structural carrier.
///
/// The implementation types are defined under their canonical Graph names in
/// `property_graph.mbt`. Deprecated `PropertyGraph*` aliases remain there as
/// a migration surface without changing representation, canonical bytes, CIDs,
/// or public JSON contracts.

/// Return the admitted Graph definition through the canonical API.
pub fn graph_definition(graph : Graph) -> GraphDefinition {
  graph_property_definition(graph)
}

/// Construct an admitted Graph node definition through the canonical API.
pub fn graph_node_definition(
  name : String,
  key_contracts : Array[@value.Contract],
  properties : Knowledge,
  labels : Array[String],
  max_fields~ : Int,
  max_name_bytes~ : Int,
  label_properties? : Array[(String, Knowledge)] = [],
  key_columns? : Array[String] = [],
  max_contract_work? : Int = 10000,
) -> Result[GraphNodeDefinition, GraphIssue] {
  property_node_definition(
    name,
    key_contracts,
    properties,
    labels,
    max_fields~,
    max_name_bytes~,
    label_properties~,
    key_columns~,
    max_contract_work~,
  )
}

/// Construct an admitted Graph edge definition through the canonical API.
pub fn graph_edge_definition(
  element : GraphNodeDefinition,
  source_definition : String,
  target_definition : String,
) -> Result[GraphEdgeDefinition, GraphIssue] {
  property_edge_definition(element, source_definition, target_definition)
}

/// Construct an admitted Graph carrier through the canonical API.
pub fn graph(
  domain : String,
  nodes : Array[GraphNodeDefinition],
  edges : Array[GraphEdgeDefinition],
  max_definitions~ : Int,
  max_contract_work~ : Int,
) -> Result[Carrier, GraphIssue] {
  property_graph(
    domain,
    nodes,
    edges,
    max_definitions~,
    max_contract_work~,
  )
}

/// Construct an admitted Graph carrier and return its consumed validation work.
pub fn graph_usage(
  domain : String,
  nodes : Array[GraphNodeDefinition],
  edges : Array[GraphEdgeDefinition],
  max_definitions~ : Int,
  max_contract_work~ : Int,
) -> Result[(Carrier, Int), GraphIssue] {
  property_graph_usage(
    domain,
    nodes,
    edges,
    max_definitions~,
    max_contract_work~,
  )
}

/// Return the Graph domain without changing its authored spelling.
pub fn graph_domain(value : GraphDefinition) -> String {
  property_graph_domain(value)
}

/// Return Graph definitions in their admitted order.
pub fn graph_node_definitions(
  value : GraphDefinition,
) -> Array[GraphNodeDefinition] {
  property_graph_node_definitions(value)
}

/// Return Graph edge definitions in their admitted order.
pub fn graph_edge_definitions(
  value : GraphDefinition,
) -> Array[GraphEdgeDefinition] {
  property_graph_edge_definitions(value)
}

pub fn graph_node_at(
  value : GraphDefinition,
  index : Int,
) -> GraphNodeDefinition? {
  property_graph_node_at(value, index)
}

pub fn graph_node_named(
  value : GraphDefinition,
  name : String,
) -> GraphNodeDefinition? {
  property_graph_node_named(value, name)
}

pub fn graph_edge_at(
  value : GraphDefinition,
  index : Int,
) -> GraphEdgeDefinition? {
  property_graph_edge_at(value, index)
}

pub fn graph_edge_named(
  value : GraphDefinition,
  name : String,
) -> GraphEdgeDefinition? {
  property_graph_edge_named(value, name)
}

pub fn graph_node_count(value : GraphDefinition) -> Int {
  property_graph_node_count(value)
}

pub fn graph_edge_count(value : GraphDefinition) -> Int {
  property_graph_edge_count(value)
}

pub fn graph_key_descriptor(
  contract : @value.Contract,
) -> GraphKeyDescriptor? {
  property_key_descriptor(contract)
}
