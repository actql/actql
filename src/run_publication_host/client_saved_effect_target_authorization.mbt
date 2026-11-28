///|
/// Bind the checked saved approval to the selected Account and Effect
/// target. The caller has already admitted the signed decision and owns the
/// current lease and physical Store Read.
pub fn bind_client_saved_effect_target_authorization(
  configuration : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  preview_cid : String,
  context_cid : String,
  approval : @checkpoint.ResumedApproval,
  reviewer_id : String,
  required : Array[@checkpoint.CheckpointRequirement],
) -> Result[
  @authorization.DispatchAuthorization,
  @authorization.DispatchBindingIssue,
] {
  if tuple.operation != "effect" ||
    approval.reviewer_id != reviewer_id ||
    !@checkpoint.checkpoint_requirements_valid(@checkpoint.EffectSet, required) {
    return Err(@authorization.ForeignDecision)
  }
  let delegated_action = match
    @authorization.evaluate_account(configuration, tuple) {
    @authorization.Delegate(matched) => {
      let request = match
        @authorization.prepare_decision_request(
          matched,
          configuration_cid=configuration.configuration_cid(),
          boundary=@authorization.EffectCommit,
          subject_cid=preview_cid,
          context_cid~,
          answering_authorities=[reviewer_id],
          required_claims=required.map(@checkpoint.checkpoint_requirement_token),
        ) {
        Ok(value) => value
        Err(_) => return Err(@authorization.ForeignDecision)
      }
      match
        @authorization.admit_host_answer(
          request,
          @authorization.Permit(
            { subject: request.subject(), authority: approval.reviewer_id, },
            approval.claims,
          ),
        ) {
        Ok(value) => Some(value)
        Err(_) => return Err(@authorization.ForeignDecision)
      }
    }
    _ => None
  }
  @authorization.bind_dispatch_authorization(
    configuration,
    tuple,
    @authorization.EffectCommit,
    preview_cid,
    context_cid,
    delegated_action~,
  )
}
