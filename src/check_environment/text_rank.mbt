///|
pub(all) enum TextRankSelectionIssue {
  InvalidLimits
  BudgetExceeded
  MissingSelection
  InvalidComponent
} derive(Eq, Debug)

///|
struct TextRankSelection {
  environment : WireEnvironment
  profile_bytes_cid : String
  work : Int
}

///|
/// Admit the selected pin, not the profile artifact or its dependency bytes.
pub fn read_text_rank_selection(
  environment : WireEnvironment,
  max_work : Int,
) -> Result[TextRankSelection, TextRankSelectionIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let count = @decode.object_length(environment.policy).unwrap()
  if count >= max_work {
    return Err(BudgetExceeded)
  }
  let mut remaining = max_work - count - 1
  let policy = @decode.open_object(environment.policy).unwrap()
  guard @decode.lookup(policy, "text_rank") is Some(body) else {
    return Err(MissingSelection)
  }
  guard @decode.object_length(body) is Some(2) else {
    return Err(InvalidComponent)
  }
  if remaining < 3 {
    return Err(BudgetExceeded)
  }
  remaining -= 3
  let object = match
    @decode.closed_object(body, ["version", "profile_bytes_cid"]) {
    Ok(v) => v
    Err(_) => return Err(InvalidComponent)
  }
  let strings = Some(
    (string(object, "version"), string(object, "profile_bytes_cid")),
  ) catch {
    _ => None
  }
  guard strings is Some((version, pin)) else { return Err(InvalidComponent) }
  for n in [version.length(), pin.length()] {
    if n > remaining {
      return Err(BudgetExceeded)
    }
    remaining -= n
  }
  if version != "actql-text-rank-selection/0.1" ||
    pin.length() != 71 ||
    !pin.has_prefix("sha256:") {
    return Err(InvalidComponent)
  }
  for i in 7..<71 {
    let c = pin[i].to_int()
    if !((c >= 48 && c <= 57) || (c >= 97 && c <= 102)) {
      return Err(InvalidComponent)
    }
  }
  Ok({ environment, profile_bytes_cid: pin, work: max_work - remaining, })
}

///|
pub fn text_rank_selection_environment(
  v : TextRankSelection,
) -> WireEnvironment {
  v.environment
}

///|
pub fn text_rank_selection_cid(v : TextRankSelection) -> String {
  v.profile_bytes_cid
}

///|
pub fn text_rank_selection_work(v : TextRankSelection) -> Int {
  v.work
}

///|
struct SelectedTextRankProfile {
  selection : TextRankSelection
  profile : @lexical.Profile
}

///|
/// Uses the environment's selected byte pin, never a caller's substitute CID.
/// All required dependency bytes are checked by the existing profile reader.
pub fn admit_text_rank_profile(
  selection : TextRankSelection,
  bytes : Bytes,
  dependencies : Array[(@lexical.Dependency, Bytes)],
  limits : @lexical.Limits,
) -> Result[SelectedTextRankProfile, @lexical.Issue] {
  match
    @lexical.admit(bytes, selection.profile_bytes_cid, dependencies, limits) {
    Ok(profile) => Ok({ selection, profile, })
    Err(issue) => Err(issue)
  }
}

///|
pub fn selected_text_rank_selection(
  v : SelectedTextRankProfile,
) -> TextRankSelection {
  v.selection
}

///|
pub fn selected_text_rank_profile(
  v : SelectedTextRankProfile,
) -> @lexical.Profile {
  v.profile
}
