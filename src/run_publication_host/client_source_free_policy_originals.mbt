///|
/// Encode the already-admitted source-free Host policy using the existing
/// policy-original packet. This metadata codec grants no authenticity, custody,
/// read, publication or Effect permission. The Native Host must select its
/// authenticated installation original and retain it with the initial accepted
/// request/Run transaction; a copied body cannot repair missing accepted custody.
/// Source-derived policies keep their full dependency closure and cannot enter
/// this finite source-free alternative.
pub fn encode_client_source_free_policy_originals(
  policy : @publication.CapturedEffectDependencyBody,
) -> Result[String, ClientRunPolicyOriginalsIssue] {
  let cid = @publication.captured_effect_dependency_body_cid(policy)
  let wire = @publication.captured_effect_dependency_body_json(policy)
  if @publication.captured_effect_dependency_body_kind(policy) != "data_policy" ||
    admit_source_free_result_policy_body(cid, wire, 65536, 8192, 64) is Err(_) {
    return Err(PublicationPolicy(@checked.ForeignBody))
  }
  encode_client_run_policy_originals([("data_policy", cid, wire)])
}
