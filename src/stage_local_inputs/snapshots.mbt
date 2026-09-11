///|
pub enum SnapshotIssue {
  InvalidLimits
  BudgetExceeded
  ForeignProgram
  ForeignStage(String)
  Resolution(@refs.Issue)
  Assertions(SchemaIssue)
}

///|
struct SnapshotBinding {
  snapshot : @snapshot.Snapshot
  input : @refs.ResolvedInput
  agreement : @local_input.SchemaAgreement
}

///|
struct CheckedSnapshots {
  prepared : Prepared
  resolved : @refs.Resolved
  assertions : SchemaAssertions
  bindings : Array[SnapshotBinding]
  usage : Usage
}

///|
/// Bind integrity-checked snapshots to one exact prepared stage and its types.
/// Check Environment membership, Host authority and data claims remain open.
pub fn reconcile_snapshots(
  prepared : Prepared,
  index : @refs.Index,
  snapshots : Array[@snapshot.Snapshot],
  limits : Limits,
) -> Result[CheckedSnapshots, SnapshotIssue] {
  if limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(prepared.source, @refs.source(index)) {
    return Err(ForeignProgram)
  }
  let mut work = limits.max_work
  let mut nodes = limits.max_nodes
  let mut text = limits.max_text_bytes
  for cost in [snapshots.length(), prepared.entries.length()] {
    if cost > work {
      return Err(BudgetExceeded)
    }
    work -= cost
  }
  // Bound collection before building selector or binding arrays. Full snapshot
  // bytes/nodes are charged per occurrence, including optional evidence claims.
  for snapshot in snapshots {
    let (bytes, count) = @snapshot.usage(snapshot)
    if bytes > text || count > nodes || count > work {
      return Err(BudgetExceeded)
    }
    text -= bytes
    nodes -= count
    work -= count
  }
  let resolved = match
    @refs.resolve(index, snapshots.map(@snapshot.source_reference), {
      max_work: work,
      max_text_bytes: text,
    }) {
    Ok(v) => v
    Err(@refs.BudgetExceeded) => return Err(BudgetExceeded)
    Err(e) => return Err(Resolution(e))
  }
  let resolved_cost = @refs.resolved_usage(resolved)
  work -= resolved_cost.work
  text -= resolved_cost.text_bytes
  let supplied = []
  for i in 0..<snapshots.length() {
    let input = @refs.entry_at(resolved, i).unwrap()
    if @refs.stage_index(input) != prepared.stage {
      return Err(
        ForeignStage(@source_ref.stringify(@refs.input_reference(input))),
      )
    }
    supplied.push(
      (
        @source_ref.input_name(@refs.input_reference(input)),
        @snapshot.schema(snapshots[i]),
      ),
    )
  }
  let assertions = match
    reconcile_schemas(prepared, supplied, {
      max_work: work,
      max_nodes: nodes,
      max_depth: limits.max_depth,
      max_text_bytes: text,
    }) {
    Ok(v) => v
    Err(SchemaIssue::BudgetExceeded) => return Err(BudgetExceeded)
    Err(e) => return Err(Assertions(e))
  }
  let cost = schema_assertion_usage(assertions)
  work -= cost.work
  nodes -= cost.nodes
  text -= cost.text_bytes
  let names : Map[String, Int] = Map([])
  for i in 0..<prepared.entries.length() {
    names[prepared.entries[i].0] = i
  }
  let bindings = []
  for i in 0..<snapshots.length() {
    let input = @refs.entry_at(resolved, i).unwrap()
    let name = @source_ref.input_name(@refs.input_reference(input))
    let position = names.get(name).unwrap()
    bindings.push({
      snapshot: snapshots[i],
      input,
      agreement: schema_agreement_at(assertions, position).unwrap(),
    })
  }
  Ok({
    prepared,
    resolved,
    assertions,
    bindings,
    usage: {
      work: limits.max_work - work,
      nodes: limits.max_nodes - nodes,
      text_bytes: limits.max_text_bytes - text,
    },
  })
}

///|
pub fn snapshot_inputs(v : CheckedSnapshots) -> Prepared {
  v.prepared
}

///|
pub fn snapshot_resolutions(v : CheckedSnapshots) -> @refs.Resolved {
  v.resolved
}

///|
pub fn snapshot_assertions(v : CheckedSnapshots) -> SchemaAssertions {
  v.assertions
}

///|
pub fn snapshot_usage(v : CheckedSnapshots) -> Usage {
  v.usage
}

///|
pub fn snapshot_count(v : CheckedSnapshots) -> Int {
  v.bindings.length()
}

///|
pub fn snapshot_binding_at(v : CheckedSnapshots, i : Int) -> SnapshotBinding? {
  v.bindings.get(i)
}

///|
pub fn bound_snapshot(v : SnapshotBinding) -> @snapshot.Snapshot {
  v.snapshot
}

///|
pub fn bound_input(v : SnapshotBinding) -> @refs.ResolvedInput {
  v.input
}

///|
pub fn bound_schema(v : SnapshotBinding) -> @local_input.SchemaAgreement {
  v.agreement
}
