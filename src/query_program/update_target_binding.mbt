///|
/// Positive names published by the installed Effect owner. These are not
/// Source aliases, inferred Resource names, or current write grants.
pub(all) struct UpdateTargetAlias {
  name : Array[@query.NamePart]
  target_ref : String
  installation_binding_cid : String
  installation_owner_cid : String
}

///|
pub(all) enum UpdateTargetIssue {
  InvalidPublication
  UnresolvedTarget
  AmbiguousTarget
  UnresolvedMapping
  AmbiguousMapping
  WorkLimit
} derive(Eq, Debug)

///|
/// One immutable projection of the original admitted environment. Candidate
/// coverage comes from its complete Mapping inventory, never visible metadata.
pub struct UpdateTargetPublication {
  mappings : @environment.MappingContractShapes
  aliases : Array[UpdateTargetAlias]
  candidates : Array[@environment.MappingContractShape]
}

///|
pub struct ResolvedUpdateTarget {
  publication : UpdateTargetPublication
  target_alias : UpdateTargetAlias
  mapping : @environment.MappingContractShape
}

///|
pub fn resolved_update_target(value : ResolvedUpdateTarget) -> (String, String) {
  (
    value.target_alias.target_ref,
    @environment.mapping_shape_reference(value.mapping),
  )
}

///|
/// Expose the selection's existing identities for original Run-owner binding.
/// This proof alone does not persist installation custody or issue Capability.
pub fn resolved_update_target_identity(
  value : ResolvedUpdateTarget,
) -> (String, String, String) {
  (
    @environment.cid(
      @environment.mapping_shape_environment(value.publication.mappings),
    ),
    @environment.mapping_shape_cid(value.mapping),
    value.target_alias.installation_binding_cid,
  )
}

///|
// Shared immutable alias representation from the installed Effect publisher.
// This neither selects an operation nor admits current installation/authority.
fn copy_effect_target_aliases(
  aliases : Array[UpdateTargetAlias],
  max_work : Int,
) -> Result[(Array[UpdateTargetAlias], Int), UpdateTargetIssue] {
  if aliases.length() > 1024 || max_work < 0 {
    return Err(InvalidPublication)
  }
  let mut remaining = max_work
  let owned : Array[UpdateTargetAlias] = []
  for target_alias in aliases {
    let cost = target_alias.name.length() + 1
    if cost > remaining {
      return Err(WorkLimit)
    }
    remaining -= cost
    if target_alias.name.is_empty() ||
      target_alias.name.length() > 16 ||
      target_alias.name.any(part => {
        part.value.is_empty() || part.value.length() > 1024
      }) ||
      !target_alias.target_ref.has_prefix("connector://") ||
      target_alias.target_ref.length() <= 12 ||
      target_alias.target_ref.length() > 4096 ||
      !table_write_cid(target_alias.installation_binding_cid) ||
      !table_write_cid(target_alias.installation_owner_cid) {
      return Err(InvalidPublication)
    }
    owned.push({ ..target_alias, name: target_alias.name.copy(), })
  }
  Ok((owned, max_work - remaining))
}

///|
pub fn bind_update_target_publication(
  mappings : @environment.MappingContractShapes,
  aliases : Array[UpdateTargetAlias],
  max_work : Int,
) -> Result[UpdateTargetPublication, UpdateTargetIssue] {
  let (owned, alias_work) = match
    copy_effect_target_aliases(aliases, max_work) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut remaining = max_work - alias_work
  let candidates : Array[@environment.MappingContractShape] = []
  for index in 0..<@environment.mapping_shape_count(mappings) {
    if remaining < 1 {
      return Err(WorkLimit)
    }
    remaining -= 1
    let mapping = @environment.mapping_shape_at(mappings, index).unwrap()
    let (supported, work) = match
      @environment.mapping_supports_operation(
        mapping, "update", "id", remaining,
      ) {
      Ok(value) => value
      Err(@environment.MappingPermissionIssue::WorkLimit) =>
        return Err(WorkLimit)
      Err(_) => return Err(InvalidPublication)
    }
    remaining -= work
    if supported {
      candidates.push(mapping)
    }
  }
  Ok({ mappings, aliases: owned, candidates, })
}

///|
/// Resolve before SET types and current authority are considered. An explicit
/// Mapping is an exact reference, not a preference or a permission filter.
/// Errors deliberately carry no forbidden target, Mapping, or candidate count.
pub fn resolve_update_target_binding(
  publication : UpdateTargetPublication,
  name : Array[@query.NamePart],
  explicit_mapping : @query.NamePart?,
  max_work : Int,
) -> Result[ResolvedUpdateTarget, UpdateTargetIssue] {
  resolve_effect_target_candidates(
    publication,
    publication.candidates,
    name,
    explicit_mapping,
    max_work,
  )
}

///|
// One alias/Mapping resolution path. Candidates come only from the original
// Common operation classifier, never payload fit or current permissions.
fn resolve_effect_target_candidates(
  publication : UpdateTargetPublication,
  candidates : Array[@environment.MappingContractShape],
  name : Array[@query.NamePart],
  explicit_mapping : @query.NamePart?,
  max_work : Int,
) -> Result[ResolvedUpdateTarget, UpdateTargetIssue] {
  if name.is_empty() || name.length() > 16 || max_work < 0 {
    return Err(UnresolvedTarget)
  }
  let mut remaining = max_work
  let mut selected_alias : UpdateTargetAlias? = None
  for target_alias in publication.aliases {
    let cost = target_alias.name.length() + name.length() + 1
    if cost > remaining {
      return Err(WorkLimit)
    }
    remaining -= cost
    if same_relation_path(target_alias.name, name) {
      if selected_alias is Some(_) {
        return Err(AmbiguousTarget)
      }
      selected_alias = Some(target_alias)
    }
  }
  guard selected_alias is Some(target_alias) else {
    return Err(UnresolvedTarget)
  }
  let mut selected_mapping : @environment.MappingContractShape? = None
  for mapping in candidates {
    if remaining < 1 {
      return Err(WorkLimit)
    }
    remaining -= 1
    if @environment.mapping_shape_target(mapping) != target_alias.target_ref {
      continue
    }
    if explicit_mapping is Some(reference) &&
      @environment.mapping_shape_reference(mapping) != reference.value {
      continue
    }
    if selected_mapping is Some(_) {
      return Err(AmbiguousMapping)
    }
    selected_mapping = Some(mapping)
  }
  match selected_mapping {
    Some(mapping) => Ok({ publication, target_alias, mapping, })
    None => Err(UnresolvedMapping)
  }
}

///|
/// The original admitted environment owner, not an equal-CID replacement.
pub fn update_target_publication_environment(
  value : UpdateTargetPublication,
) -> @environment.WireEnvironment {
  @environment.mapping_shape_environment(value.mappings)
}

///|
/// Identity of the existing installed row owner, including its generation.
pub fn resolved_update_target_owner_cid(value : ResolvedUpdateTarget) -> String {
  value.target_alias.installation_owner_cid
}

///|
/// Bind an already checked concrete UPDATE or DELETE without resolving names.
/// Equal aliases may publish the same owner; conflicting owners never choose
/// a winner. The caller's ordinary Effect checker remains authoritative.
pub fn resolve_concrete_update_target_binding(
  publication : UpdateTargetPublication,
  target : String,
  mapping_reference : String,
  max_work : Int,
  effect_kind? : String = "update",
) -> Result[ResolvedUpdateTarget, UpdateTargetIssue] {
  if effect_kind != "update" && effect_kind != "delete" {
    return Err(InvalidPublication)
  }
  resolve_concrete_effect_target_candidates(
    publication,
    publication.candidates,
    target,
    mapping_reference,
    max_work,
    effect_kind~,
  )
}

///|
fn resolve_concrete_effect_target_candidates(
  publication : UpdateTargetPublication,
  candidates : Array[@environment.MappingContractShape],
  target : String,
  mapping_reference : String,
  max_work : Int,
  effect_kind? : String = "update",
) -> Result[ResolvedUpdateTarget, UpdateTargetIssue] {
  if max_work < 0 {
    return Err(WorkLimit)
  }
  let mut remaining = max_work
  let mut selected_alias : UpdateTargetAlias? = None
  for target_alias in publication.aliases {
    if remaining < 1 {
      return Err(WorkLimit)
    }
    remaining -= 1
    if target_alias.target_ref != target {
      continue
    }
    match selected_alias {
      Some(previous) =>
        if previous.installation_binding_cid !=
          target_alias.installation_binding_cid ||
          previous.installation_owner_cid != target_alias.installation_owner_cid {
          return Err(AmbiguousTarget)
        }
      None => selected_alias = Some(target_alias)
    }
  }
  guard selected_alias is Some(target_alias) else {
    return Err(UnresolvedTarget)
  }
  let mut selected_mapping : @environment.MappingContractShape? = None
  // Concrete checked DELETE uses the original complete Mapping inventory.
  // Short keyed selections retain their operation-classified candidates.
  let mapping_count = if effect_kind == "update" {
    candidates.length()
  } else {
    @environment.mapping_shape_count(publication.mappings)
  }
  for index in 0..<mapping_count {
    let mapping = if effect_kind == "update" {
      candidates[index]
    } else {
      @environment.mapping_shape_at(publication.mappings, index).unwrap()
    }
    if remaining < 1 {
      return Err(WorkLimit)
    }
    remaining -= 1
    if @environment.mapping_shape_target(mapping) != target ||
      @environment.mapping_shape_reference(mapping) != mapping_reference {
      continue
    }
    if selected_mapping is Some(_) {
      return Err(AmbiguousMapping)
    }
    selected_mapping = Some(mapping)
  }
  match selected_mapping {
    Some(mapping) => Ok({ publication, target_alias, mapping, })
    None => Err(UnresolvedMapping)
  }
}
