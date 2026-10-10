///|
/// Serialize the original report-bound delivery using the common Owner.
/// Authentication facts and the claim come from trusted callers; this bridge
/// performs no physical signature check, durable claim or Provider write.
#export_name("coordinatorEffectResumeDeliveryJson")
pub fn coordinator_effect_resume_delivery_json(
  report : @remote.RemoteEffectCheckpointReport,
  resolution_wire : String,
  authentication : Array[String],
  reviewer_keys : Array[String],
  reviewer_ids : Array[String],
  claimant : String,
  generation : Int64,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @remote.DispatchIssue] {
  if authentication.length() != 6 ||
    reviewer_keys.length() != reviewer_ids.length() ||
    reviewer_keys.length() > 64 {
    return Err(@remote.InvalidDispatch)
  }
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes,
    max_nodes,
    max_depth,
  }
  let auth : @checkpoint.HostAuthentication = {
    key_id: authentication[0],
    reviewer_id: authentication[1],
    expected_authority_scope_cid: authentication[2],
    authority_context_cid: authentication[3],
    policy_cid: authentication[4],
    proof_preimage: authentication[5],
  }
  let reviewers : Array[@checkpoint.ReviewerAuthority] = []
  for index = 0; index < reviewer_keys.length(); index = index + 1 {
    reviewers.push({
      key_id: reviewer_keys[index],
      reviewer_id: reviewer_ids[index],
    })
  }
  let admitted = match
    @checkpoint.admit_attested_effect_resolution(
      @remote.remote_effect_checkpoint_report_checkpoint(report),
      resolution_wire,
      auth,
      reviewers,
      limits,
    ) {
    Ok(value) => value
    Err(_) => return Err(@remote.InvalidDispatch)
  }
  match
    @remote.prepare_remote_effect_resume_delivery(
      report,
      admitted.resolution,
      { claimant, generation, },
      limits,
    ) {
    Ok(value) => Ok(@remote.remote_effect_resume_delivery_json(value))
    Err(issue) => Err(issue)
  }
}
