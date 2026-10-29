///|
/// Read immutable binding DATA from this already admitted public Review.
/// The caller retains its original Checkpoint/Preview and current-authority
/// duties. This neither parses a wire nor admits or issues any evidence.
pub fn effect_review_projection_binding_facts(
  review : RunEvidenceValue,
) -> (String, String, String, Array[String])? {
  if review.name != "review_projection" {
    return None
  }
  guard @json.object_field(review.value, "effect_preview_cid")
    is Some(@json.String(preview)) &&
    @json.object_field(review.value, "authoring_context_cid")
    is Some(@json.String(authoring)) &&
    @json.object_field(review.value, "authority_scope_cid")
    is Some(@json.String(authority)) &&
    @json.object_field(review.value, "approval_claims")
    is Some(@json.Array(original_claims)) else {
    return None
  }
  let claims : Array[String] = []
  for index in 0..<@json.array_count(original_claims) {
    guard @json.array_at(original_claims, index) is Some(@json.String(claim)) else {
      return None
    }
    claims.push(claim)
  }
  Some((preview, authoring, authority, claims))
}
