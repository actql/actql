///|
pub enum EnvironmentIssue {
  InvalidLimits
  BudgetExceeded
  ForeignEnvironment(Int)
  Snapshots(SnapshotIssue)
}

///|
struct EnvironmentInputs {
  environment : @environment.WireEnvironment
  checked : CheckedSnapshots
  members : Array[@snapshot.EnvironmentSnapshot]
  usage : Usage
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
  Ok({
    environment,
    checked,
    members: members.copy(),
    usage: { ..cost, work: cost.work + members.length(), },
  })
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
