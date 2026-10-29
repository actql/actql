///|
#export_name("clientValuesHostEffectReviewProjectionBindingFacts")
pub fn client_values_host_effect_review_projection_binding_facts(
  review : @publication.RunEvidenceValue,
) -> Array[String] {
  match @publication.effect_review_projection_binding_facts(review) {
    Some((preview, authoring, authority, claims)) => {
      let facts = [preview, authoring, authority]
      for claim in claims {
        facts.push(claim)
      }
      facts
    }
    None => []
  }
}
