///|
/// Private callbacks borrow existing policy and task custody; they issue no
/// evidence permission. The serving loop keeps its independent default-deny
/// evidence gate and owns any Catalog handles returned by this installation.
priv struct HolderEffectReviewCallbacks {
  catalog : (HolderEffectOriginalPolicyContext) -> HolderEffectCatalogReviewCustody?
  publication : (@remote.DispatchRequest) -> HolderEffectReviewPublication?
}

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
/// The first genuine original consumer selects this invocation's installation.
/// Later publication must name that exact dispatch; a candidate wire cannot
/// select a policy, original producer or Provider grant. Loading is lazy, after
/// the existing serving loop has checked its independent evidence permission.
fn holder_effect_review_callbacks(
  matches : @argparse.Matches,
  sqlite : @sqlite.Library,
  resources : HolderOutputResources,
  export_limits : @host.PublicationOutputExportLimits,
) -> HolderEffectReviewCallbacks {
  let selected : Ref[(String, HolderEffectReviewPolicyInstallation)?] = Ref(
    None,
  )
  let catalog = (original : HolderEffectOriginalPolicyContext) => {
    guard holder_effect_review_roots(
        optional(matches, "effect-review-root"),
        optional(matches, "effect-catalog-root"),
      )
      is Some((policy_root, catalog_root)) &&
      original.current() else {
      return None
    }
    let dispatch = @remote.dispatch_request_identity(original.task.request)
    if selected.val is None {
      let policy = load_holder_effect_review_policy(
        policy_root, matches, resources, export_limits,
      ) catch {
        CommandStop(_) => {
          report("effect-review-pending", [
            ("request_cid", dispatch),
            ("reason", "policy-installation"),
          ])
          return None
        }
      }
      selected.val = Some((dispatch, policy))
    }
    guard selected.val is Some((expected, policy)) &&
      expected == dispatch &&
      original.current() &&
      (policy.current)() else {
      return None
    }
    let installed = open_holder_effect_catalog_installation(
      catalog_root,
      matches,
      sqlite,
      resources,
      original,
      policy.configuration.preview_limits.max_wire_bytes,
      policy.configuration.preview_limits.max_nodes,
      policy.configuration.preview_limits.max_depth,
      policy.current,
    ) catch {
      CommandStop(_) => {
        report("effect-review-pending", [
          ("request_cid", dispatch),
          ("reason", "catalog-installation"),
        ])
        return None
      }
    }
    guard installed is Some(installed) else { return None }
    // Transfer acquired handles immediately, including a setup-time authority
    // change. The existing task Owner retains and closes them before release.
    Some(
      new_holder_effect_catalog_review_custody(
        installed,
        resources.store,
        policy.configuration,
        policy.connector_id,
        policy.describe_limits,
        policy.declaration_limits,
        policy.max_observation_bytes,
        policy.publication.crypto,
        policy.publication.key,
        () => {
          match
            original.journal.effect_checkpoint_report(
              original.task.request,
              policy.publication.limits,
            ) {
            Ok(_) => false
            Err(issue) => holder_catalog_checkpoint_missing(issue)
          }
        },
      ),
    )
  }
  let publication = (request : @remote.DispatchRequest) => {
    guard selected.val is Some((dispatch, policy)) &&
      dispatch == @remote.dispatch_request_identity(request) &&
      (policy.current)() else {
      return None
    }
    Some(policy.publication)
  }
  { catalog, publication, }
}
