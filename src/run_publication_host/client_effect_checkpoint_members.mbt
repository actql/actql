///|
pub(all) enum ClientEffectCheckpointMembersIssue {
  Binding(ClientEffectCheckpointBindingIssue)
  InvalidLimits
  WorkLimit
  UnsupportedInventory
}

///|
/// Project members from the original checked unit after the existing Owner
/// admits its exact Checkpoint/Run/window binding. No adapter parses a Program
/// or reconstructs an Effect plan. This grants no evidence access or approval.
pub fn client_effect_review_checkpoint_members(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  checkpoint_wire : String,
  limits : @checkpoint.WireLimits,
  max_members : Int,
  max_work : Int,
) -> Result[Array[String], ClientEffectCheckpointMembersIssue] {
  if max_members < 1 || max_members > 64 || max_work < 1 || max_work > 10000 {
    return Err(InvalidLimits)
  }
  match
    admit_client_effect_review_checkpoint_binding(
      allowed, definition, checkpoint_wire, limits,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Binding(issue))
  }
  let owner = allowed.compilation.owner
  // The current compiler admits exactly one terminal Effect-bearing unit.
  // The admitted Checkpoint above must name this same authored coordinate.
  let stage = @syntax.stage_count(owner.source) - 1
  let headers = @checked.effect_program_static_headers(owner.candidate)
  let count = @syntax.effect_header_count(headers)
  if count > max_work {
    return Err(WorkLimit)
  }
  let members : Array[String] = []
  for index in 0..<count {
    let header = @syntax.effect_header_at(headers, index).unwrap()
    if @syntax.effect_header_stage(header) == stage {
      let member = @syntax.effect_header_id(header)
      // Unique member names are already admitted by the original syntax/static
      // Owner; this projection does not repeat unbudgeted string comparisons.
      if members.length() >= max_members {
        return Err(UnsupportedInventory)
      }
      members.push(member)
    }
  }
  if members.is_empty() {
    return Err(UnsupportedInventory)
  }
  Ok(members)
}
