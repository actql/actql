///|
pub(all) enum GraphKeyOperation {
  GraphOperation(@graph.CheckedGraph)
  MatchOperation(@graph.CheckedMatch)
  ReachOperation(@graph.CheckedReach)
  TraverseOperation(@graph.CheckedTraverse)
  ShortestOperation(@graph.CheckedShortest)
}

///|
/// Derive only exposed semantic identity; retain the actual checked producer.
pub fn graph_query_keys(
  operation : GraphKeyOperation,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  let (source, input, output) = match operation {
    GraphOperation(op) =>
      (@graph.source(op), @graph.input(op), @graph.output(op))
    MatchOperation(op) =>
      (@graph.match_source(op), @graph.match_input(op), @graph.match_output(op))
    ReachOperation(op) =>
      (@graph.reach_source(op), @graph.reach_input(op), @graph.reach_output(op))
    TraverseOperation(op) =>
      (
        @graph.traverse_source(op),
        @graph.traverse_input(op),
        @graph.traverse_output(op),
      )
    ShortestOperation(op) =>
      (
        @graph.shortest_source(op),
        @graph.shortest_input(op),
        @graph.shortest_output(op),
      )
  }
  try {
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    guard @carrier.relation_rows(output) is Some(records) else {
      fail(source, InputContractMismatch)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, 1)
    let names : Array[@row.FieldName] = []
    let extra_aliases : Array[@row.FieldName] = []
    if input is @carrier.GraphValue(graph) {
      match operation {
        GraphOperation(op) =>
          match @graph.operation(op) {
            Degree => names.push(Unqualified("node"))
            Components => names.push(Unqualified("node_id"))
            GraphBounds => {
              names.push(Unqualified("kind"))
              names.push(Unqualified("node_id"))
            }
            NormalizeGraph => ()
          }
        MatchOperation(op) =>
          if @carrier.graph_names(graph) is Some(roles) {
            let (node, src, dst, label) = @carrier.graph_row_fields(roles)
            if @graph.match_entity(op) == Nodes {
              names.push(node)
            } else if label is Some(label) {
              names.push(src)
              names.push(dst)
              names.push(label)
            }
          }
        ReachOperation(_) => {
          let node = @row.Unqualified("node_id")
          names.push(node)
          if @carrier.graph_names(graph) is Some(roles) {
            let source_name = @carrier.graph_row_fields(roles).0
            if source_name != node {
              extra_aliases.push(source_name)
            }
          }
        }
        TraverseOperation(op) =>
          if @graph.traverse_emission(op) == TraversedNodes {
            names.push(Unqualified("start_id"))
            names.push(Unqualified("node_id"))
          }
        ShortestOperation(op) => {
          names.push(Unqualified("source_id"))
          if @graph.shortest_selection(op) == EachPair {
            names.push(Unqualified("target_id"))
          }
        }
      }
    }
    let fields : Array[KeyField] = []
    let aliases : Array[Array[KeyField]] = []
    let mut complete = !names.is_empty()
    for name in names {
      spend(b, source, 1)
      charge(b, source, name)
      match @carrier.lookup(records, name) {
        Present(field) => {
          let field : KeyField = plain_key_field(name, field.contract)
          fields.push(field)
          aliases.push([field])
        }
        _ => complete = false
      }
    }
    if complete {
      for name in extra_aliases {
        aliases[0].push(graph_projection_field(source, records, name, b))
      }
    }
    let work = limits.max_work - b.work
    let name_bytes = limits.max_name_bytes - b.text
    let witnesses : Array[KeyedRelation] = if complete {
      [
        {
          origin: GraphQueryResult,
          producer: Some(GraphQueryProducer(operation)),
          records,
          declared_records: records,
          declared_fields: fields,
          source,
          fields,
          aliases,
          usage: { fields: fields.length(), name_bytes, },
        },
      ]
    } else {
      []
    }
    Ok({ keys: { records, witnesses, work, name_bytes, }, work, name_bytes, })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn key_graph_query_producer(key : KeyedRelation) -> GraphKeyOperation? {
  match key.producer {
    Some(GraphQueryProducer(op)) => Some(op)
    _ => None
  }
}
