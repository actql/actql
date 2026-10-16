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
  alias : UpdateTargetAlias
  mapping : @environment.MappingContractShape
}

///|
pub fn resolved_update_target(value : ResolvedUpdateTarget) -> (String, String) {
  (value.alias.target_ref, @environment.mapping_shape_reference(value.mapping))
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
    value.alias.installation_binding_cid,
  )
}

///|
pub fn bind_update_target_publication(
  mappings : @environment.MappingContractShapes,
  aliases : Array[UpdateTargetAlias],
  max_work : Int,
) -> Result[UpdateTargetPublication, UpdateTargetIssue] {
  if aliases.length() > 1024 || max_work < 0 {
    return Err(InvalidPublication)
  }
  let mut remaining = max_work
  let owned : Array[UpdateTargetAlias] = []
  for alias in aliases {
    let cost = alias.name.length() + 1
    if cost > remaining {
      return Err(WorkLimit)
    }
    remaining -= cost
    if alias.name.is_empty() ||
      alias.name.length() > 16 ||
      alias.name.any(part => part.value.is_empty() || part.value.length() > 1024) ||
      !alias.target_ref.has_prefix("connector://") ||
      alias.target_ref.length() <= 12 ||
      alias.target_ref.length() > 4096 ||
      !table_write_cid(alias.installation_binding_cid) ||
      !table_write_cid(alias.installation_owner_cid) {
      return Err(InvalidPublication)
    }
    owned.push({ ..alias, name: alias.name.copy(), })
  }
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
  if name.is_empty() || name.length() > 16 || max_work < 0 {
    return Err(UnresolvedTarget)
  }
  let mut remaining = max_work
  let mut selected_alias : UpdateTargetAlias? = None
  for alias in publication.aliases {
    let cost = alias.name.length() + name.length() + 1
    if cost > remaining {
      return Err(WorkLimit)
    }
    remaining -= cost
    if same_relation_path(alias.name, name) {
      if selected_alias is Some(_) {
        return Err(AmbiguousTarget)
      }
      selected_alias = Some(alias)
    }
  }
  guard selected_alias is Some(alias) else { return Err(UnresolvedTarget) }
  let mut selected_mapping : @environment.MappingContractShape? = None
  for mapping in publication.candidates {
    if remaining < 1 {
      return Err(WorkLimit)
    }
    remaining -= 1
    if @environment.mapping_shape_target(mapping) != alias.target_ref {
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
    Some(mapping) => Ok({ publication, alias, mapping, })
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
  value.alias.installation_owner_cid
}

///|
/// Bind an already checked concrete UPDATE without reverse-resolving names.
/// Equal aliases may publish the same owner; conflicting owners never choose
/// a winner. The caller's ordinary Effect checker remains authoritative.
pub fn resolve_concrete_update_target_binding(
  publication : UpdateTargetPublication,
  target : String,
  mapping_reference : String,
  max_work : Int,
) -> Result[ResolvedUpdateTarget, UpdateTargetIssue] {
  if max_work < 0 {
    return Err(WorkLimit)
  }
  let mut remaining = max_work
  let mut selected_alias : UpdateTargetAlias? = None
  for alias in publication.aliases {
    if remaining < 1 {
      return Err(WorkLimit)
    }
    remaining -= 1
    if alias.target_ref != target {
      continue
    }
    match selected_alias {
      Some(previous) =>
        if previous.installation_binding_cid != alias.installation_binding_cid ||
          previous.installation_owner_cid != alias.installation_owner_cid {
          return Err(AmbiguousTarget)
        }
      None => selected_alias = Some(alias)
    }
  }
  guard selected_alias is Some(alias) else { return Err(UnresolvedTarget) }
  let mut selected_mapping : @environment.MappingContractShape? = None
  for mapping in publication.candidates {
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
    Some(mapping) => Ok({ publication, alias, mapping, })
    None => Err(UnresolvedMapping)
  }
}
