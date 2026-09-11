///|
pub enum MembershipIssue {
  WrongSection
  InvalidSnapshot(Issue)
  BudgetExceeded
}

///|
struct EnvironmentSnapshot {
  entry : @environment.Member
  snapshot : Snapshot
}

///|
/// Preserve exact envelope membership, not full environment or Host admission.
pub fn read_member(
  entry : @environment.Member,
  limits : Limits,
) -> Result[EnvironmentSnapshot, MembershipIssue] {
  if @environment.member_section(entry) != @environment.SchemaSnapshots {
    return Err(WrongSection)
  }
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidSnapshot(InvalidLimits))
  }
  try {
    // Only this bounded member is serialized, never the whole environment.
    let writer = @encode.writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    @environment.emit_member(entry, writer)
    let bytes = @utf8.encode(@encode.finish(writer))
    match read(bytes, @environment.member_cid(entry), limits) {
      Ok(snapshot) => Ok({ entry, snapshot, })
      Err(e) => Err(InvalidSnapshot(e))
    }
  } catch {
    _ => Err(BudgetExceeded)
  }
}

///|
pub fn environment_member(v : EnvironmentSnapshot) -> @environment.Member {
  v.entry
}

///|
pub fn environment_snapshot(v : EnvironmentSnapshot) -> Snapshot {
  v.snapshot
}
