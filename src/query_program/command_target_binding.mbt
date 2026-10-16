///|
/// Positive installed names select an exact original Command. They do not issue
/// a ResourceRef, validate a current installation, or grant execution.
pub(all) struct CommandTargetAlias {
  name : Array[@query.NamePart]
  target_ref : String
  command_ref : String
  installation_binding_cid : String
  installation_owner_cid : String
}

///|
pub(all) enum CommandTargetPublicationIssue {
  InvalidPublication
  UnresolvedTarget
  AmbiguousTarget
  UnresolvedCommand
  WorkLimit
} derive(Eq, Debug)

///|
priv struct CommandTargetCandidate {
  target_alias : CommandTargetAlias
  binding : @environment.PublishedCommandBinding
}

///|
struct CommandTargetPublication {
  catalogs : @environment.CatalogContents
  candidates : Array[CommandTargetCandidate]
  work : Int
  nodes : Int
  text : Int
}

///|
struct ResolvedCommandTarget {
  publication : CommandTargetPublication
  candidate : CommandTargetCandidate
}

///|
pub fn command_target_publication_environment(
  publication : CommandTargetPublication,
) -> @environment.WireEnvironment {
  @environment.contract_registry_environment(
    @environment.catalog_registry(publication.catalogs),
  )
}

///|
pub fn command_target_publication_catalogs(
  publication : CommandTargetPublication,
) -> @environment.CatalogContents {
  publication.catalogs
}

///|
pub fn command_target_publication_work(
  publication : CommandTargetPublication,
) -> Int {
  publication.work
}

///|
pub fn command_target_publication_usage(
  publication : CommandTargetPublication,
) -> (Int, Int) {
  (publication.nodes, publication.text)
}

///|
pub fn resolved_command_target(
  value : ResolvedCommandTarget,
) -> (String, String) {
  (
    value.candidate.target_alias.target_ref,
    value.candidate.target_alias.command_ref,
  )
}

///|
pub fn resolved_command_target_binding(
  value : ResolvedCommandTarget,
) -> @environment.PublishedCommandBinding {
  value.candidate.binding
}

///|
pub fn resolved_command_target_identity(
  value : ResolvedCommandTarget,
) -> (String, String, String, String) {
  let target = @environment.published_command_binding_target(
    value.candidate.binding,
  )
  (
    @environment.cid(command_target_publication_environment(value.publication)),
    @environment.command_target_cid(target),
    value.candidate.target_alias.installation_binding_cid,
    value.candidate.target_alias.installation_owner_cid,
  )
}

///|
/// Admit every selected alias, including unused entries. The original Common
/// Command reader owns mode/domain interpretation; no Mapping is manufactured.
pub fn bind_command_target_publication(
  catalogs : @environment.CatalogContents,
  aliases : Array[CommandTargetAlias],
  limits : @contract.Limits,
  max_work : Int,
) -> Result[CommandTargetPublication, CommandTargetPublicationIssue] {
  if max_work < 0 ||
    aliases.length() > 1024 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 {
    return Err(InvalidPublication)
  }
  let projected : Array[UpdateTargetAlias] = aliases.map(target_alias => {
    name: target_alias.name,
    target_ref: target_alias.target_ref,
    installation_binding_cid: target_alias.installation_binding_cid,
    installation_owner_cid: target_alias.installation_owner_cid,
  })
  let (owned, alias_work) = match
    copy_effect_target_aliases(projected, max_work) {
    Ok(value) => value
    Err(UpdateTargetIssue::WorkLimit) => return Err(WorkLimit)
    Err(_) => return Err(InvalidPublication)
  }
  let candidates : Array[CommandTargetCandidate] = []
  let mut remaining = max_work - alias_work
  let mut nodes = 0
  let mut text = 0
  for index, original in aliases {
    if original.command_ref.is_empty() || original.command_ref.length() > 4096 {
      return Err(InvalidPublication)
    }
    let cost = original.command_ref.length() + 1
    if cost > remaining {
      return Err(WorkLimit)
    }
    remaining -= cost
    let binding = match
      @environment.select_published_command_binding(
        catalogs,
        original.command_ref,
        {
          max_nodes: limits.max_nodes - nodes,
          max_depth: limits.max_depth,
          max_text_bytes: limits.max_text_bytes - text,
        },
        remaining,
      ) {
      Ok(value) => value
      Err(@environment.PublishedCommandBindingIssue::WorkLimit) =>
        return Err(WorkLimit)
      Err(_) => return Err(UnresolvedCommand)
    }
    remaining -= @environment.published_command_binding_work(binding)
    let (child_nodes, child_text) = @environment.published_command_binding_usage(
      binding,
    )
    nodes += child_nodes
    text += child_text
    let target_alias : CommandTargetAlias = {
      name: owned[index].name,
      target_ref: owned[index].target_ref,
      command_ref: original.command_ref,
      installation_binding_cid: owned[index].installation_binding_cid,
      installation_owner_cid: owned[index].installation_owner_cid,
    }
    candidates.push({ target_alias, binding, })
  }
  Ok({ catalogs, candidates, work: max_work - remaining, nodes, text, })
}

///|
pub fn resolve_command_target_binding(
  publication : CommandTargetPublication,
  name : Array[@query.NamePart],
  max_work : Int,
) -> Result[ResolvedCommandTarget, CommandTargetPublicationIssue] {
  if max_work < 0 {
    return Err(WorkLimit)
  }
  if name.is_empty() ||
    name.length() > 16 ||
    name.any(part => part.value.is_empty() || part.value.length() > 1024) {
    return Err(UnresolvedTarget)
  }
  let mut remaining = max_work
  let mut selected : CommandTargetCandidate? = None
  for candidate in publication.candidates {
    let cost = candidate.target_alias.name.length() + name.length() + 1
    if cost > remaining {
      return Err(WorkLimit)
    }
    remaining -= cost
    if same_relation_path(candidate.target_alias.name, name) {
      if selected is Some(_) {
        return Err(AmbiguousTarget)
      }
      selected = Some(candidate)
    }
  }
  match selected {
    Some(candidate) => Ok({ publication, candidate, })
    None => Err(UnresolvedTarget)
  }
}

///|
/// Reconnect an exact normalized occurrence, never a logical alias preference.
/// Retaining this result is not restoration from a current publication.
pub fn resolve_concrete_command_target_binding(
  publication : CommandTargetPublication,
  target : String,
  command_reference : String,
  max_work : Int,
) -> Result[ResolvedCommandTarget, CommandTargetPublicationIssue] {
  if max_work < 0 {
    return Err(WorkLimit)
  }
  let mut remaining = max_work
  let mut selected : CommandTargetCandidate? = None
  for candidate in publication.candidates {
    let target_alias = candidate.target_alias
    let cost = target_alias.target_ref.length() +
      target_alias.command_ref.length() +
      1
    if cost > remaining {
      return Err(WorkLimit)
    }
    remaining -= cost
    if target_alias.target_ref != target ||
      target_alias.command_ref != command_reference {
      continue
    }
    match selected {
      Some(previous) =>
        if previous.target_alias.installation_binding_cid !=
          target_alias.installation_binding_cid ||
          previous.target_alias.installation_owner_cid !=
          target_alias.installation_owner_cid {
          return Err(AmbiguousTarget)
        }
      None => selected = Some(candidate)
    }
  }
  match selected {
    Some(candidate) => Ok({ publication, candidate, })
    None => Err(UnresolvedTarget)
  }
}
