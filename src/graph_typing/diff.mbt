///|
pub(all) enum DeltaObligation {
  EmitDeltaVersion
  AdmitSnapshotsUnderCommonContract
  ResolveGraphContractIdentity
  BindBaseAndTargetIdentities
  EmitCompleteBeforeAfterRecords
  SortUniqueActionIdentities
  ResolveDeltaResources
  ResolveSgaProfile
} derive(Eq, Debug)

///|
struct CheckedDiff {
  comparison : CheckedEquality
  delta : @contract.Contract
  usage : Usage
}

///|
fn delta_object(
  b : Budget,
  s : @decode.Cursor,
  fields : Array[(String, @contract.Contract)],
) -> @contract.Contract raise Stop {
  spend(b, s, fields.length() + 1)
  if fields.length() + 1 > b.nodes {
    fail(s, BudgetExceeded)
  }
  b.nodes -= fields.length() + 1
  for (name, _) in fields {
    charge(b, s, name)
  }
  match
    @contract.object_contract(
      fields,
      nullable=false,
      max_fields=fields.length(),
      max_name_bytes=b.limits.max_text_bytes,
    ) {
    Ok(c) => c
    Err(_) => fail(s, BudgetExceeded)
  }
}

///|
fn delta_properties(
  b : Budget,
  s : @decode.Cursor,
  properties : @carrier.Knowledge,
) -> @contract.Contract raise Stop {
  let fields : Array[(String, @contract.Contract)] = []
  let count = @carrier.field_count(properties)
  if count > b.work || count > b.nodes {
    fail(s, BudgetExceeded)
  }
  for i in 0..<count {
    let f = @carrier.field_at(properties, i).unwrap()
    fields.push((@row.reference_name(f.name), f.contract.unwrap()))
  }
  delta_object(b, s, fields)
}

///|
fn delta_actions(
  b : Budget,
  s : @decode.Cursor,
  record : @contract.Contract,
) -> @contract.Contract raise Stop {
  let update = delta_object(b, s, [("before", record), ("after", record)])
  spend(b, s, 2)
  if b.nodes < 2 {
    fail(s, BudgetExceeded)
  }
  b.nodes -= 2
  let records = @contract.array_contract(record, nullable=false).unwrap()
  let updates = @contract.array_contract(update, nullable=false).unwrap()
  delta_object(b, s, [
    ("add", records),
    ("remove", records),
    ("update", updates),
  ])
}

///|
pub fn check_diff(
  source : @decode.Cursor,
  left : @carrier.Carrier,
  right : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedDiff, Issue] {
  try {
    let comparison = match check_equality(source, left, right, limits) {
      Ok(c) => c
      Err(e) => raise Stop(e)
    }
    let u = comparison.usage
    let b : Budget = {
      limits,
      work: limits.max_work - u.work,
      nodes: limits.max_nodes - u.nodes,
      text: limits.max_text_bytes - u.text_bytes,
    }
    // delta -> actions -> updates -> update -> record -> properties.
    if limits.max_depth < 6 {
      fail(source, BudgetExceeded)
    }
    let graph = comparison.common
    let id = @carrier.graph_identity(graph)
    let node_props = delta_properties(
      b,
      source,
      @carrier.graph_node_properties(graph),
    )
    let edge_props = delta_properties(
      b,
      source,
      @carrier.graph_edge_properties(graph),
    )
    let node = delta_object(b, source, [("id", id), ("props", node_props)])
    let edge = delta_object(b, source, [
      ("src", id),
      ("dst", id),
      ("rel", @contract.primitive(StringType, nullable=true)),
      ("props", edge_props),
    ])
    let nodes = delta_actions(b, source, node)
    let edges = delta_actions(b, source, edge)
    let text = @contract.primitive(StringType, nullable=false)
    let delta = delta_object(b, source, [
      ("version", text),
      ("base_graph_cid", text),
      ("target_graph_cid", text),
      ("graph_contract_cid", text),
      ("nodes", nodes),
      ("edges", edges),
    ])
    // Account for the enclosing one-row Relation field separately.
    spend(b, source, 1)
    charge(b, source, "delta")
    Ok({
      comparison,
      delta,
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
pub fn diff_output(v : CheckedDiff) -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [(Unqualified("delta"), Some(v.delta))],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=5,
    ).unwrap(),
  )
}

///|
pub fn diff_contract(v : CheckedDiff) -> @contract.Contract {
  v.delta
}

///|
pub fn diff_common_graph(v : CheckedDiff) -> @carrier.Graph {
  v.comparison.common
}

///|
pub fn diff_usage(v : CheckedDiff) -> Usage {
  v.usage
}

///|
pub fn diff_with_name(v : CheckedDiff) -> String {
  v.comparison.with_name
}

///|
pub fn diff_source(v : CheckedDiff) -> @decode.Cursor {
  v.comparison.source
}

///|
pub fn diff_pending(_v : CheckedDiff) -> Array[DeltaObligation] {
  [
    EmitDeltaVersion,
    AdmitSnapshotsUnderCommonContract,
    ResolveGraphContractIdentity,
    BindBaseAndTargetIdentities,
    EmitCompleteBeforeAfterRecords,
    SortUniqueActionIdentities,
    ResolveDeltaResources,
    ResolveSgaProfile,
  ]
}
