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
  read_member_owned(entry, limits)
}

///|
/// SAME member reader, with the original writer's charged UTF8 bytes, value
/// nodes and peak container depth. None means no writer was constructed, not
/// zero full-reader work. This observes no parse/admission/schema/hash work.
pub fn observe_read_member(
  entry : @environment.Member,
  limits : Limits,
) -> (Result[EnvironmentSnapshot, MembershipIssue], (Int, Int, Int)?) {
  let usage : Ref[(Int, Int, Int)?] = Ref(None)
  let result = read_member_owned(entry, limits, usage_out=Some(usage))
  (result, usage.val)
}

///|
/// Additional observation DATA: Ref1H1R, its Some1H1R1W, original writer
/// usage tuple1H3W, its Some1H1R1W and returned result/observation pair1H2R.
/// Writer/emit/UTF8/parse/schema/hash/borrowed and VM frames stay separate.
pub fn member_emission_observation_extent() -> @shape.CollectionConstructionExtent {
  member_emission_observation_units
}

///|
let member_emission_observation_units : @shape.CollectionConstructionExtent = {
  record_headers: 5L,
  reference_slots: 5L,
  scalar_words: 5L,
}

///|
fn read_member_owned(
  entry : @environment.Member,
  limits : Limits,
  usage_out? : Ref[(Int, Int, Int)?]? = None,
) -> Result[EnvironmentSnapshot, MembershipIssue] {
  if @environment.member_section(entry) != @environment.SchemaSnapshots {
    return Err(WrongSection)
  }
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidSnapshot(InvalidLimits))
  }
  let text = match emit_member_text_owned(entry, limits, usage_out) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let bytes = @utf8.encode(text)
  match read(bytes, @environment.member_cid(entry), limits) {
    Ok(snapshot) => Ok({ entry, snapshot, })
    Err(e) => Err(InvalidSnapshot(e))
  }
}

///|
// This scope returns only text. No Writer/builder/frame alias can cross into
// UTF8 parsing or typed admission; the original partial observation is kept.
fn emit_member_text_owned(
  entry : @environment.Member,
  limits : Limits,
  usage_out : Ref[(Int, Int, Int)?]?,
) -> Result[String, MembershipIssue] {
  // Creation failure has no invented writer usage. The same initial policy
  // guards still precede all emission and the original byte reader.
  let writer = @encode.writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  let text = try {
    // Only this bounded member is serialized, never the whole environment.
    @environment.emit_member(entry, writer)
    @encode.finish(writer)
  } catch {
    _ => {
      capture_member_emission(writer, usage_out)
      return Err(BudgetExceeded)
    }
  }
  // Capture before UTF8/reader entry, not in a deferred closure retaining the
  // first writer through either later phase. Only scalar cells enter the
  // observation; emission success and refusal are exclusive paths.
  capture_member_emission(writer, usage_out)
  Ok(text)
}

///|
fn capture_member_emission(
  writer : @encode.Writer,
  usage_out : Ref[(Int, Int, Int)?]?,
) -> Unit {
  if usage_out is Some(captured) {
    captured.val = Some(@encode.observed_writer_usage(writer))
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
