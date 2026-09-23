///|
pub(all) enum EffectPreviewFootprintIssue {
  PreviewShape(@publication.PublicationContractIssue)
  InvalidPreviewFootprint
  InventoryMismatch
  FailurePolicyMismatch
  EffectIdentityMismatch
  Conflict(EffectFootprintIssue)
} derive(Debug)

///|
fn preview_footprint_text(
  value : @json.CanonicalValue,
  name : String,
) -> String? {
  match @json.object_field(value, name) {
    Some(@json.String(text)) => Some(text)
    _ => None
  }
}

///|
/// Compare the complete private Preview to a checked Stage's Effect inventory
/// before deriving its write footprints. The caller must supply the inventory
/// from a sealed checked Plan, never from the Preview or an authored override.
/// The claimed Effect identity must also be checked against the admitted
/// Effect semantics; this comparison alone does not establish that claim.
/// This is not semantic Preview CID or current authority admission.
pub fn check_effect_preview_footprint_conflicts(
  preview_wire : String,
  declared_effect_ids : Array[String],
  declared_failure_policies : Array[Int],
  declared_effect_identity_cids : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_members : Int,
  max_targets : Int,
  max_work : Int,
) -> Result[Unit, EffectPreviewFootprintIssue] {
  let preview = match
    @publication.parse_effect_preview_shape(
      preview_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(PreviewShape(issue))
  }
  guard @json.object_field(preview, "effects") is Some(@json.Array(frozen)) else {
    return Err(InvalidPreviewFootprint)
  }
  let effects = @json.array_values(frozen)
  if max_members < 1 ||
    effects.is_empty() ||
    effects.length() > max_members ||
    declared_effect_ids.length() != effects.length() ||
    declared_failure_policies.length() != effects.length() ||
    declared_effect_identity_cids.length() != effects.length() {
    return Err(InventoryMismatch)
  }
  if max_work < 1 {
    return Err(Conflict(InvalidLimits))
  }
  let members : Array[EffectMemberFootprint] = []
  let mut total_targets = 0
  let mut remaining = max_work
  for effect in effects {
    guard preview_footprint_text(effect, "effect_id") is Some(effect_id) &&
      preview_footprint_text(effect, "effect_identity_cid")
      is Some(effect_identity_cid) &&
      preview_footprint_text(effect, "on_item_failure") is Some(policy) &&
      @json.object_field(effect, "write_footprint") is Some(footprint) &&
      preview_footprint_text(footprint, "kind") is Some(kind_text) &&
      preview_footprint_text(footprint, "provider_namespace")
      is Some(provider_namespace) &&
      preview_footprint_text(footprint, "provider_boundary_cid")
      is Some(provider_boundary_cid) &&
      preview_footprint_text(footprint, "resource_identity_scheme_cid")
      is Some(resource_identity_scheme_cid) &&
      preview_footprint_text(footprint, "resource_kind") is Some(resource_kind) &&
      @json.object_field(footprint, "provider_object_identity_cids")
      is Some(@json.Array(targets_frozen)) else {
      return Err(InvalidPreviewFootprint)
    }
    if remaining <= 0 {
      return Err(Conflict(CapacityExceeded))
    }
    remaining -= 1
    let mut matched = -1
    for index in 0..<declared_effect_ids.length() {
      if remaining <= 0 {
        return Err(Conflict(CapacityExceeded))
      }
      remaining -= 1
      if declared_effect_ids[index] == effect_id {
        if matched >= 0 {
          return Err(InventoryMismatch)
        }
        matched = index
      }
    }
    if matched < 0 {
      return Err(InventoryMismatch)
    }
    if !effect_cid_valid(declared_effect_identity_cids[matched]) ||
      effect_identity_cid != declared_effect_identity_cids[matched] {
      return Err(EffectIdentityMismatch)
    }
    let declared_policy = declared_failure_policies[matched]
    if (policy == "halt" && declared_policy != 0) ||
      (policy == "continue" && declared_policy != 1) ||
      (policy != "halt" && policy != "continue") {
      return Err(FailurePolicyMismatch)
    }
    let kind = match kind_text {
      "exact_targets" => ExactTargets
      "collection" => Collection
      "opaque" => Opaque
      _ => return Err(InvalidPreviewFootprint)
    }
    let targets = @json.array_values(targets_frozen)
    if max_targets < 0 || targets.length() > max_targets - total_targets {
      return Err(Conflict(CapacityExceeded))
    }
    total_targets += targets.length()
    let provider_object_identity_cids : Array[String] = []
    for target in targets {
      if remaining <= 0 {
        return Err(Conflict(CapacityExceeded))
      }
      remaining -= 1
      match target {
        @json.String(cid) => provider_object_identity_cids.push(cid)
        _ => return Err(InvalidPreviewFootprint)
      }
    }
    members.push({
      effect_id,
      kind,
      provider_namespace,
      provider_boundary_cid,
      resource_identity_scheme_cid,
      resource_kind,
      provider_object_identity_cids,
    })
  }
  if remaining <= 0 {
    return Err(Conflict(CapacityExceeded))
  }
  match
    check_effect_set_footprint_conflicts(
      members, max_members, max_targets, remaining,
    ) {
    Ok(_) => Ok(())
    Err(issue) => Err(Conflict(issue))
  }
}
