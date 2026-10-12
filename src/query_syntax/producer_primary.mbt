///|
// A producer primary retains syntax and source provenance, not an admitted
// Carrier. The existing checker owns the output kind and definition contract.
pub(all) enum ProducerPrimary {
  GraphValue(GraphConstructor)
  GraphGenerator(SgaCall)
}

///|
fn copy_graph_labels(labels : Array[GraphLabel]) -> Array[GraphLabel] {
  labels.map(label => {
    ..label,
    properties: match label.properties {
      AllColumnsExcept(columns) => AllColumnsExcept(columns.copy())
      Columns(columns) => Columns(columns.copy())
      other => other
    },
  })
}

///|
fn copy_graph_constructor(mapping : GraphConstructor) -> GraphConstructor {
  {
    ..mapping,
    nodes: mapping.nodes.map(node => {
      ..node,
      producer: node.producer.copy(),
      key: node.key.copy(),
      labels: copy_graph_labels(node.labels),
    }),
    edges: mapping.edges.map(edge => {
      ..edge,
      producer: edge.producer.copy(),
      key: edge.key.copy(),
      labels: copy_graph_labels(edge.labels),
      source: {
        ..edge.source,
        key: edge.source.key.copy(),
        referenced_key: edge.source.referenced_key.map(keys => keys.copy()),
      },
      destination: {
        ..edge.destination,
        key: edge.destination.key.copy(),
        referenced_key: edge.destination.referenced_key.map(keys => keys.copy()),
      },
    }),
  }
}

///|
pub fn producer_primary(query : Query) -> ProducerPrimary? {
  query.primary.map(primary => {
    match primary {
      GraphValue(mapping) => GraphValue(copy_graph_constructor(mapping))
      GraphGenerator(call) => GraphGenerator(copy_sga_call(call))
    }
  })
}

///|
// Consume the primary once; the remaining operators keep the original source.
// No binding-only projection, normalization or acquisition is introduced.
pub fn after_producer_primary(query : Query) -> Query {
  { ..query, primary: None, }
}

///|
pub fn after_query_bindings(query : Query) -> Query {
  { ..query, bindings: [], }
}

///|
fn QueryParser::producer_query(
  self : QueryParser,
  primary : ProducerPrimary,
) -> Query {
  {
    source: self.source,
    primary: Some(primary),
    implicit_source_alias: false,
    positional_output: false,
    bound_source: None,
    bindings: [],
    relation: [],
    source_alias: None,
    graph: Some({ pattern: None, expectation: None, }),
    joins: [],
    operations: [],
    sets: [],
    final_operations: [],
    effect: None,
    table_effect: None,
    work: self.work,
  }
}

///|
// Strip only a parser-generated row qualifier after resolving a Graph body.
// An authored alias still reaches the existing Carrier-specific refusal.
pub fn graph_source_query(query : Query) -> Query {
  if query.implicit_source_alias {
    { ..query, source_alias: None, implicit_source_alias: false, }
  } else {
    query
  }
}
