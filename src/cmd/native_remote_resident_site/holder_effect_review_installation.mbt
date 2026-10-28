///|
/// No implicit sharing with Source, Resume or Local issuer configuration.
fn holder_effect_review_roots(
  policy : String?,
  catalog : String?,
) -> (String, String)? {
  match (policy, catalog) {
    (Some(policy), Some(catalog)) if !policy.is_empty() && !catalog.is_empty() =>
      Some((policy, catalog))
    _ => None
  }
}

///|
// No production issuer supplies the retired mapped Review preparation. Preserve
// the original roots-before-current refusal ordering without opening resources.
fn holder_effect_review_installation_available(
  policy : String?,
  catalog : String?,
  current : () -> Bool,
) -> Bool {
  guard holder_effect_review_roots(policy, catalog) is Some(_) && current() else {
    return false
  }
  false
}

///|
fn open_holder_effect_review_installation(
  matches : @argparse.Matches,
  original : HolderEffectOriginalPolicyContext,
) -> Bool {
  holder_effect_review_installation_available(
    optional(matches, "effect-review-root"),
    optional(matches, "effect-catalog-root"),
    () => original.current(),
  )
}
