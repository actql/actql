///|
pub(all) enum EffectFootprintKind {
  ExactTargets
  Collection
  Opaque
} derive(Eq, Debug)

///|
pub(all) struct EffectMemberFootprint {
  effect_id : String
  kind : EffectFootprintKind
  provider_namespace : String
  provider_boundary_cid : String
  resource_identity_scheme_cid : String
  resource_kind : String
  provider_object_identity_cids : Array[String]
}

///|
pub(all) enum EffectFootprintIssue {
  InvalidLimits
  InvalidMember
  InvalidFootprint
  CapacityExceeded
  UnprovenIndependence
  OverlappingTarget
} derive(Eq, Debug)

///|
/// Check every member's footprint as one set before any mutation. This is
/// neither Preview admission nor authorization. A single opaque or collection
/// footprint is valid, but coexistence within one provider boundary requires
/// separate admitted independence evidence not represented here.
pub fn check_effect_set_footprint_conflicts(
  members : Array[EffectMemberFootprint],
  max_members : Int,
  max_targets : Int,
  max_work : Int,
) -> Result[Unit, EffectFootprintIssue] {
  if max_members < 1 ||
    max_members > 1000 ||
    max_targets < 0 ||
    max_targets > 100000 ||
    max_work < 1 ||
    max_work > 100000000 ||
    members.is_empty() ||
    members.length() > max_members {
    return Err(InvalidLimits)
  }
  let mut work = 0
  let mut targets = 0
  for index in 0..<members.length() {
    work += 1
    if work > max_work {
      return Err(CapacityExceeded)
    }
    let current = members[index]
    if !canonical_bounded_text(current.effect_id, 4096) {
      return Err(InvalidMember)
    }
    if !canonical_bounded_text(current.provider_namespace, 4096) ||
      !canonical_bounded_text(current.resource_kind, 4096) ||
      !effect_cid_valid(current.provider_boundary_cid) ||
      !effect_cid_valid(current.resource_identity_scheme_cid) {
      return Err(InvalidFootprint)
    }
    if current.provider_object_identity_cids.length() > max_targets - targets {
      return Err(CapacityExceeded)
    }
    targets += current.provider_object_identity_cids.length()
    for target_index in 0..<current.provider_object_identity_cids.length() {
      work += 1
      if work > max_work {
        return Err(CapacityExceeded)
      }
      let target = current.provider_object_identity_cids[target_index]
      if !effect_cid_valid(target) {
        return Err(InvalidFootprint)
      }
      for prior_target in 0..<target_index {
        work += 1
        if work > max_work {
          return Err(CapacityExceeded)
        }
        if current.provider_object_identity_cids[prior_target] == target {
          return Err(OverlappingTarget)
        }
      }
    }
    for prior_index in 0..<index {
      work += 1
      if work > max_work {
        return Err(CapacityExceeded)
      }
      let prior = members[prior_index]
      if prior.effect_id == current.effect_id {
        return Err(InvalidMember)
      }
      if prior.provider_boundary_cid != current.provider_boundary_cid {
        continue
      }
      if prior.provider_namespace != current.provider_namespace ||
        prior.resource_identity_scheme_cid !=
        current.resource_identity_scheme_cid ||
        prior.kind != ExactTargets ||
        current.kind != ExactTargets {
        return Err(UnprovenIndependence)
      }
      for target in current.provider_object_identity_cids {
        for prior_target in prior.provider_object_identity_cids {
          work += 1
          if work > max_work {
            return Err(CapacityExceeded)
          }
          if target == prior_target {
            return Err(OverlappingTarget)
          }
        }
      }
    }
  }
  Ok(())
}

///|
pub fn check_effect_set_footprint_conflicts_from_codes(
  effect_ids : Array[String],
  kinds : Array[Int],
  namespaces : Array[String],
  boundary_cids : Array[String],
  scheme_cids : Array[String],
  resource_kinds : Array[String],
  target_cids : Array[Array[String]],
  max_members : Int,
  max_targets : Int,
  max_work : Int,
) -> Result[Unit, EffectFootprintIssue] {
  let length = effect_ids.length()
  if kinds.length() != length ||
    namespaces.length() != length ||
    boundary_cids.length() != length ||
    scheme_cids.length() != length ||
    resource_kinds.length() != length ||
    target_cids.length() != length ||
    length > max_members {
    return Err(InvalidLimits)
  }
  let members : Array[EffectMemberFootprint] = []
  for index in 0..<length {
    let kind = match kinds[index] {
      0 => ExactTargets
      1 => Collection
      2 => Opaque
      _ => return Err(InvalidFootprint)
    }
    members.push({
      effect_id: effect_ids[index],
      kind,
      provider_namespace: namespaces[index],
      provider_boundary_cid: boundary_cids[index],
      resource_identity_scheme_cid: scheme_cids[index],
      resource_kind: resource_kinds[index],
      provider_object_identity_cids: target_cids[index],
    })
  }
  check_effect_set_footprint_conflicts(
    members, max_members, max_targets, max_work,
  )
}
