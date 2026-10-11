///|
/// Lazy composition of existing policy, Catalog credential and Store Owners.
/// The holder invokes it only after its separate evidence gate and genuine
/// completed producer/consumer selection. This adds no authorization entry.
fn open_holder_effect_review_installation(
  matches : @argparse.Matches,
  sqlite_library : @sqlite.Library,
  resources : HolderOutputResources,
  export_limits : @host.PublicationOutputExportLimits,
  original : HolderEffectOriginalPolicyContext,
) -> HolderEffectCatalogReviewCustody? raise CommandStop {
  guard optional(matches, "effect-review-root") is Some(root) &&
    original.current() else {
    return None
  }
  let policy = load_holder_effect_review_policy(
    root, matches, resources, export_limits,
  )
  if !(policy.current)() || !original.current() {
    return None
  }
  guard open_holder_effect_catalog_installation(
      root,
      matches,
      sqlite_library,
      resources,
      original,
      policy.configuration.preview_limits.max_wire_bytes,
      policy.configuration.preview_limits.max_nodes,
      policy.configuration.preview_limits.max_depth,
    )
    is Some(installed) else {
    return None
  }
  // After service acquisition the task must retain the cleanup handle even
  // if policy changes. Its current fences deny reads and publication, while
  // the existing close/retry path still owns every acquired resource.
  let publication = {
    ..policy.publication,
    current: () => (policy.current)() && original.current(),
  }
  Some(
    new_holder_effect_catalog_review_custody(
      installed,
      resources.store,
      policy.configuration,
      policy.connector_id,
      policy.describe_limits,
      policy.declaration_limits,
      policy.max_observation_bytes,
      publication.crypto,
      publication.key,
      publication,
    ),
  )
}
