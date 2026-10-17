///|
/// Borrow one original checked pair for the installed collection issuer.
/// This read does not issue a target Reference or authorize acquisition/apply.
#export_name("clientProgramEffectPublishedStoreBinding")
pub fn client_program_effect_published_store_binding(
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  max_work : Int,
) -> Result[
  @check_environment.StoreCommandBinding?,
  @strategy.CapturedEffectProposalIssue,
] {
  @strategy.captured_effect_published_store_binding(
    inputs, member_index, max_work,
  )
}

///|
#export_name("clientProgramBindEffectCommandTarget")
pub fn client_program_bind_effect_command_target(
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  pair : @check_environment.StoreCommandBinding,
  reference : @admitted.CheckedValue,
  max_work : Int,
) -> Result[
  @strategy.CapturedEffectCommandTarget,
  @strategy.CapturedEffectProposalIssue,
] {
  @strategy.bind_captured_effect_command_target(
    inputs, member_index, pair, reference, max_work,
  )
}

///|
/// The ordinary row-only entry remains unchanged. Only this typed original
/// can supply a published target without adding it to the query schema.
#export_name("clientProgramEffectProposalBeginWithTarget")
pub fn client_program_effect_proposal_begin_with_target(
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  max_fields : Int,
  max_work : Int,
  target : @strategy.CapturedEffectCommandTarget,
  input_key? : @strategy.CapturedEffectCommandKeyValidation? = None,
) -> Result[
  @strategy.CapturedEffectProposalPlan,
  @strategy.CapturedEffectProposalIssue,
] {
  @strategy.prepare_captured_effect_proposal_plan(
    inputs,
    member_index,
    max_fields,
    max_work,
    published_target=Some(target),
    input_key~,
  )
}
