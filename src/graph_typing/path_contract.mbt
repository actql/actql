///|
pub(all) enum PathOutput {
  TraversedPaths
} derive(Eq, Debug)

///|
struct CheckedPathContract {
  output : @carrier.Carrier
  usage : Usage
}

///|
/// Current paths retain complete independent node and edge identities.
pub fn check_path_contract(
  _kind : PathOutput,
  source : @decode.Cursor,
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedPathContract, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    guard input is @carrier.GraphValue(g) else {
      if @carrier.kind(input) != @carrier.GraphKind {
        fail(source, WrongCarrier(@carrier.kind(input)))
      }
      fail(source, IncompleteGraph)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    let id = @carrier.graph_identity(g)
    let number = @contract.primitive(NumberType, nullable=false)
    let fields : Array[(@row.FieldName, @contract.Contract?)] = []
    // New array wrappers retain the complete admitted element identity.
    let wrappers = 2
    if b.nodes < wrappers || limits.max_depth < 2 {
      fail(source, BudgetExceeded)
    }
    b.nodes -= wrappers
    spend(b, source, 2)
    let node_ids = @contract.array_contract(id, nullable=false).unwrap()
    let edge_ids = @contract.array_contract(id, nullable=false).unwrap()
    fields.push((Unqualified("start_id"), Some(id)))
    fields.push((Unqualified("end_id"), Some(id)))
    fields.push((Unqualified("hop_count"), Some(number)))
    fields.push((Unqualified("node_ids"), Some(node_ids)))
    fields.push((Unqualified("edge_ids"), Some(edge_ids)))
    spend(b, source, fields.length())
    for (name, _) in fields {
      charge(b, source, @row.reference_name(name))
    }
    let rows = match
      @carrier.rows(
        fields,
        field_set=Closed,
        max_fields=fields.length(),
        max_name_bytes=limits.max_text_bytes,
      ) {
      Ok(r) => r
      Err(_) => fail(source, BudgetExceeded)
    }
    Ok({
      output: @carrier.relation(rows),
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn path_output(c : CheckedPathContract) -> @carrier.Carrier {
  c.output
}

///|
pub fn path_usage(c : CheckedPathContract) -> Usage {
  c.usage
}
