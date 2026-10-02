///|
pub(all) enum GraphKeyOperation {
  GraphOperation(@graph.CheckedGraph)
  MatchOperation(@graph.CheckedMatch)
  TraverseOperation(@graph.CheckedTraverse)
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
    TraverseOperation(op) =>
      (
        @graph.traverse_source(op),
        @graph.traverse_input(op),
        @graph.traverse_output(op),
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
    if input is @carrier.GraphValue(_) {
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
          // The checked definition owns the complete typed element identity.
          // Endpoints and labels cannot identify independent parallel edges.
          if @graph.match_property_definition(op) is Some(_) &&
            @graph.match_property_binding(op, "identity") is Some(identity) {
            names.push(identity)
          }
        TraverseOperation(op) =>
          if @graph.traverse_emission(op) == TraversedNodes {
            names.push(Unqualified("start_id"))
            names.push(Unqualified("node_id"))
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
