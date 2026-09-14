///|
pub enum EnvironmentIssue {
  InvalidLimits
  BudgetExceeded
  ForeignEnvironment(Int)
  Snapshots(SnapshotIssue)
  Scores(String, @vector_checks.Issue)
  InputEvidence(String, @pipeline.Issue)
}

///|
struct EnvironmentInputs {
  environment : @environment.WireEnvironment
  checked : CheckedSnapshots
  members : Array[@snapshot.EnvironmentSnapshot]
  usage : Usage
  registrations : Array[(String, @pipeline.InputContract)]
  score_snapshots : Array[@snapshot.Snapshot?]
}

///|
/// Retain membership while resolving a selected stage's snapshots and types.
/// This does not admit the whole environment, policy or Host authority.
pub fn reconcile_environment(
  prepared : Prepared,
  index : @refs.Index,
  environment : @environment.WireEnvironment,
  members : Array[@snapshot.EnvironmentSnapshot],
  limits : Limits,
) -> Result[EnvironmentInputs, EnvironmentIssue] {
  if limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  if members.length() > limits.max_work {
    return Err(BudgetExceeded)
  }
  let snapshots = []
  for i in 0..<members.length() {
    let entry = @snapshot.environment_member(members[i])
    if !physical_equal(@environment.member_environment(entry), environment) {
      return Err(ForeignEnvironment(i))
    }
    snapshots.push(@snapshot.environment_snapshot(members[i]))
  }
  let checked = match
    reconcile_snapshots(prepared, index, snapshots, {
      ..limits,
      max_work: limits.max_work - members.length(),
    }) {
    Ok(v) => v
    Err(SnapshotIssue::BudgetExceeded) => return Err(BudgetExceeded)
    Err(e) => return Err(Snapshots(e))
  }
  let cost = snapshot_usage(checked)
  let mut work = limits.max_work - cost.work - members.length()
  let mut nodes = limits.max_nodes - cost.nodes
  let mut text = limits.max_text_bytes - cost.text_bytes
  if prepared.entries.length() > work ||
    snapshot_count(checked) > work - prepared.entries.length() {
    return Err(BudgetExceeded)
  }
  work -= prepared.entries.length() + snapshot_count(checked)
  let registrations = []
  let positions : Map[String, Int] = Map([])
  let score_snapshots = Array::make(prepared.entries.length(), None)
  for i in 0..<prepared.entries.length() {
    let entry = reconciled_input_at(checked, i).unwrap()
    positions[entry.0] = i
    registrations.push(entry)
  }
  for i in 0..<snapshot_count(checked) {
    let binding = snapshot_binding_at(checked, i).unwrap()
    let snapshot = bound_snapshot(binding)
    if @snapshot.score_count(snapshot) == 0 {
      continue
    }
    let name = @source_ref.input_name(@snapshot.source_reference(snapshot))
    let position = positions[name]
    let source = @snapshot.score_source(snapshot).unwrap()
    let assertion = match
      @evidence.declare_ranking_scores(
        source,
        @local_input.schema_carrier(bound_schema(binding)),
        {
          max_work: work,
          max_nodes: nodes,
          max_text_bytes: text,
          max_depth: limits.max_depth,
        },
      ) {
      Ok(value) => value
      Err({ kind: BudgetExceeded, .. }) => return Err(BudgetExceeded)
      Err(issue) => return Err(Scores(name, issue))
    }
    work -= assertion.usage.work
    nodes -= assertion.usage.nodes
    text -= assertion.usage.text_bytes
    let input = match @local_input.schema_primary_key(bound_schema(binding)) {
      None => @pipeline.RankingInput(assertion.input)
      Some(key) =>
        match
          @pipeline.combine_relation_evidence(
            source,
            @evidence.singleton_key(key),
            assertion.input,
          ) {
          Ok(combined) => @pipeline.RelationEvidenceInput(combined)
          Err(issue) => return Err(InputEvidence(name, issue))
        }
    }
    registrations[position] = (name, input)
    score_snapshots[position] = Some(snapshot)
  }
  Ok({
    environment,
    checked,
    members: members.copy(),
    registrations,
    score_snapshots,
    usage: {
      work: limits.max_work - work,
      nodes: limits.max_nodes - nodes,
      text_bytes: limits.max_text_bytes - text,
    },
  })
}

///|
/// Declaration index, not snapshot order. Retains source membership and meaning.
pub fn environment_score_snapshot_at(
  value : EnvironmentInputs,
  index : Int,
) -> @snapshot.Snapshot? {
  value.score_snapshots.get(index).bind(value => value)
}

///|
pub fn input_environment(v : EnvironmentInputs) -> @environment.WireEnvironment {
  v.environment
}

///|
pub fn environment_assertions(v : EnvironmentInputs) -> CheckedSnapshots {
  v.checked
}

///|
pub fn environment_usage(v : EnvironmentInputs) -> Usage {
  v.usage
}

///|
/// Positions correspond to snapshot_binding_at(environment_assertions(v), i).
pub fn environment_snapshot_at(
  v : EnvironmentInputs,
  i : Int,
) -> @snapshot.EnvironmentSnapshot? {
  v.members.get(i)
}
