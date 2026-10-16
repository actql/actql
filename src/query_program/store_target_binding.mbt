///|
pub(all) enum StoreTargetIssue {
  InvalidPublication
  ForeignEnvironment
  UnresolvedTarget
  AmbiguousTarget
  UnresolvedMapping
  AmbiguousMapping
  WorkLimit
} derive(Eq, Debug)

///|
struct StoreTargetCandidate {
  mapping : @environment.MappingContractShape
  command : @environment.StoreCommandBinding?
}

///|
// A view of the same installed publication and original complete Mapping
// inventory. Resource issuance, current installation and grants are not here.
struct StoreTargetPublication {
  mappings : @environment.MappingContractShapes
  catalogs : @environment.CatalogContents
  aliases : Array[UpdateTargetAlias]
  candidates : Array[StoreTargetCandidate]
  work : Int
}

///|
struct ResolvedStoreTarget {
  publication : StoreTargetPublication
  target_alias : UpdateTargetAlias
  candidate : StoreTargetCandidate
}

///|
pub fn store_target_publication_environment(
  publication : StoreTargetPublication,
) -> @environment.WireEnvironment {
  @environment.mapping_shape_environment(publication.mappings)
}

///|
pub fn store_target_publication_catalogs(
  publication : StoreTargetPublication,
) -> @environment.CatalogContents {
  publication.catalogs
}

///|
pub fn store_target_publication_work(
  publication : StoreTargetPublication,
) -> Int {
  publication.work
}

///|
pub fn resolved_store_target(value : ResolvedStoreTarget) -> (String, String) {
  (
    value.target_alias.target_ref,
    @environment.mapping_shape_reference(value.candidate.mapping),
  )
}

///|
pub fn resolved_store_target_mapping(
  value : ResolvedStoreTarget,
) -> @environment.MappingContractShape {
  value.candidate.mapping
}

///|
// None denotes canonical relation materialization, not a guessed upload.
pub fn resolved_store_target_command(
  value : ResolvedStoreTarget,
) -> @environment.StoreCommandBinding? {
  value.candidate.command
}

///|
pub fn resolved_store_target_identity(
  value : ResolvedStoreTarget,
) -> (String, String, String, String) {
  (
    @environment.cid(store_target_publication_environment(value.publication)),
    @environment.mapping_shape_cid(value.candidate.mapping),
    value.target_alias.installation_binding_cid,
    value.target_alias.installation_owner_cid,
  )
}

///|
pub fn bind_store_target_publication(
  mappings : @environment.MappingContractShapes,
  catalogs : @environment.CatalogContents,
  aliases : Array[UpdateTargetAlias],
  max_work : Int,
) -> Result[StoreTargetPublication, StoreTargetIssue] {
  let (owned, alias_work) = match
    copy_effect_target_aliases(aliases, max_work) {
    Ok(value) => value
    Err(UpdateTargetIssue::WorkLimit) => return Err(WorkLimit)
    Err(_) => return Err(InvalidPublication)
  }
  if !physical_equal(
      @environment.mapping_shape_environment(mappings),
      @environment.contract_registry_environment(
        @environment.catalog_registry(catalogs),
      ),
    ) {
    return Err(ForeignEnvironment)
  }
  let mut remaining = max_work - alias_work
  let candidates : Array[StoreTargetCandidate] = []
  for index in 0..<@environment.mapping_shape_count(mappings) {
    if remaining < 1 {
      return Err(WorkLimit)
    }
    remaining -= 1
    let mapping = @environment.mapping_shape_at(mappings, index).unwrap()
    match @environment.bind_store_command(mapping, catalogs, remaining) {
      Ok(command) => {
        remaining -= @environment.store_command_work(command)
        candidates.push({ mapping, command: Some(command), })
      }
      Err(@environment.StoreCommandIssue::MissingRelationship) => {
        let (supported, work) = match
          @environment.mapping_supports_operation(
            mapping, "store", "none", remaining,
          ) {
          Ok(value) => value
          Err(@environment.MappingPermissionIssue::WorkLimit) =>
            return Err(WorkLimit)
          Err(_) => return Err(InvalidPublication)
        }
        remaining -= work
        if supported {
          candidates.push({ mapping, command: None, })
        }
      }
      Err(@environment.StoreCommandIssue::WorkLimit) => return Err(WorkLimit)
      // A malformed published relationship never becomes relation-store.
      // Refusals expose no candidate references, schemas or private counts.
      Err(_) => return Err(InvalidPublication)
    }
  }
  Ok({
    mappings,
    catalogs,
    aliases: owned,
    candidates,
    work: max_work - remaining,
  })
}

///|
// Resolve the complete structural inventory before SET types or grants.
pub fn resolve_store_target_binding(
  publication : StoreTargetPublication,
  name : Array[@query.NamePart],
  max_work : Int,
) -> Result[ResolvedStoreTarget, StoreTargetIssue] {
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
  let mut selected : StoreTargetCandidate? = None
  for candidate in publication.candidates {
    if remaining < 1 {
      return Err(WorkLimit)
    }
    remaining -= 1
    if @environment.mapping_shape_target(candidate.mapping) !=
      target_alias.target_ref {
      continue
    }
    if selected is Some(_) {
      return Err(AmbiguousMapping)
    }
    selected = Some(candidate)
  }
  match selected {
    Some(candidate) => Ok({ publication, target_alias, candidate, })
    None => Err(UnresolvedMapping)
  }
}

///|
// Reconnect an already normalized concrete occurrence without resolving or
// preferring a logical alias again. Conflicting installation originals refuse.
pub fn resolve_concrete_store_target_binding(
  publication : StoreTargetPublication,
  target : String,
  mapping_reference : String,
  max_work : Int,
) -> Result[ResolvedStoreTarget, StoreTargetIssue] {
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
  let mut selected : StoreTargetCandidate? = None
  for candidate in publication.candidates {
    if remaining < 1 {
      return Err(WorkLimit)
    }
    remaining -= 1
    if @environment.mapping_shape_target(candidate.mapping) != target ||
      @environment.mapping_shape_reference(candidate.mapping) !=
      mapping_reference {
      continue
    }
    if selected is Some(_) {
      return Err(AmbiguousMapping)
    }
    selected = Some(candidate)
  }
  match selected {
    Some(candidate) => Ok({ publication, target_alias, candidate, })
    None => Err(UnresolvedMapping)
  }
}
