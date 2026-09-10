///|
pub(all) enum EntityKind {
  Nodes
  Edges
} derive(Eq, Debug)

///|
struct CheckedScope {
  fields : @carrier.Knowledge
  usage : Usage
}

///|
/// Authored graph expression scope, not an implicit node_rows/edge_rows bridge.
/// Unknown property knowledge stays unknown; carrier-only names are not added.
pub fn check_scope(
  entity : EntityKind,
  source : @decode.Cursor,
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedScope, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    if @carrier.kind(input) != @carrier.GraphKind {
      fail(source, WrongCarrier(@carrier.kind(input)))
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    spend(b, source, 1)
    let properties = match input {
      @carrier.GraphValue(g) =>
        if entity == Nodes {
          @carrier.graph_node_properties(g)
        } else {
          @carrier.graph_edge_properties(g)
        }
      _ => @carrier.unknown_rows()
    }
    let fields : Array[(@row.FieldName, @contract.Contract?)] = []
    if input is @carrier.GraphValue(g) && @carrier.graph_names(g) is Some(names) {
      let (node, src, dst, label) = @carrier.graph_row_fields(names)
      let id = Some(@carrier.graph_identity(g))
      if entity == Nodes {
        fields.push((node, id))
      } else {
        fields.push((src, id))
        fields.push((dst, id))
        if label is Some(name) &&
          @carrier.graph_label_contract(g) is Some(contract) {
          fields.push((name, Some(contract)))
        }
      }
    }
    let count = @carrier.field_count(properties)
    spend(b, source, fields.length())
    spend(b, source, count)
    for i in 0..<count {
      let f = @carrier.field_at(properties, i).unwrap()
      fields.push((f.name, f.contract))
    }
    for (name, _) in fields {
      charge(b, source, @row.reference_name(name))
    }
    let rows = match
      @carrier.rows(
        fields,
        field_set=@carrier.field_set(properties),
        max_fields=fields.length(),
        max_name_bytes=limits.max_text_bytes,
      ) {
      Ok(rows) => rows
      Err(@row.DuplicateField(name)) =>
        fail(source, ScopeCollision(@row.reference_name(name)))
      Err(_) => fail(source, BudgetExceeded)
    }
    Ok({
      fields: rows,
      usage: {
        work: limits.max_work - b.work,
        nodes: 0,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn scope_fields(c : CheckedScope) -> @carrier.Knowledge {
  c.fields
}

///|
pub fn scope_usage(c : CheckedScope) -> Usage {
  c.usage
}
