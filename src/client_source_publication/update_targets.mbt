///|
// Same positive installation metadata for UPDATE and STORE. Operation and
// complete Mapping selection stay with their existing Common owners.
fn source_publication_effect_aliases(
  section : @decode.Cursor,
) -> Array[@query_program.UpdateTargetAlias] raise PublicationStop {
  let entries = @decode.elements(section).unwrap_or_else(() => {
    raise PublicationStop(Publication)
  })
  if entries.length() > 1024 {
    raise PublicationStop(Limit)
  }
  if entries.is_empty() {
    return []
  }
  let aliases : Array[@query_program.UpdateTargetAlias] = []
  for entry in entries {
    @decode.closed_object(entry, [
      "name", "targetRef", "installationBindingCid", "installationOwnerCid",
    ]).unwrap_or_else(() => raise PublicationStop(Publication))
    |> ignore
    let name = @query_syntax.parse_relation_path(
      source_publication_text(entry, "name"),
      {
        max_source_bytes: 1024,
        max_tokens: 256,
        max_literal_bytes: 1024,
        max_work: 16384,
      },
    ).unwrap_or_else(() => raise PublicationStop(Publication))
    aliases.push({
      name,
      target_ref: source_publication_text(entry, "targetRef"),
      installation_binding_cid: source_publication_text(
        entry, "installationBindingCid",
      ),
      installation_owner_cid: source_publication_text(
        entry, "installationOwnerCid",
      ),
    })
  }
  aliases
}

///|
/// Read only the existing Host publication selected for this environment.
/// The installed loader owns positive aliases and installation provenance;
/// the common Mapping owner supplies the complete, unfiltered candidate set.
pub fn published_update_targets(
  environment : @program_check.CheckEnvironment,
  publication : String,
) -> Result[@query_program.UpdateTargetPublication?, PublicationIssue] {
  let root = match read_publication_data(publication) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  published_update_targets_from_root(environment, root)
}

///|
fn published_update_targets_from_root(
  environment : @program_check.CheckEnvironment,
  root : @decode.Cursor,
) -> Result[@query_program.UpdateTargetPublication?, PublicationIssue] {
  try {
    let object = @decode.closed_object(root, [
      "environmentCid", "aliases", "tableWrites", "updateTargets", "storeTargets",
      "commandTargets",
    ]).unwrap_or_else(() => raise PublicationStop(Publication))
    if source_publication_text(root, "environmentCid") !=
      @program_check.checking_environment_cid(environment) {
      raise PublicationStop(Publication)
    }
    guard @decode.lookup(object, "updateTargets") is Some(section) else {
      return Ok(None)
    }
    let aliases = source_publication_effect_aliases(section)
    if aliases.is_empty() {
      return Ok(None)
    }
    let mappings = @check_environment.check_mapping_contract_shapes(
      @program_check.checking_environment_wire(environment),
      {
        max_bytes: 1048576,
        max_nodes: 16384,
        max_depth: 32,
        max_members: 32768,
      },
      1000000,
    ).unwrap_or_else(() => raise PublicationStop(Publication))
    match
      @query_program.bind_update_target_publication(mappings, aliases, 1000000) {
      Ok(value) => Ok(Some(value))
      Err(@query_program.UpdateTargetIssue::WorkLimit) => Err(Limit)
      Err(_) => Err(Publication)
    }
  } catch {
    PublicationStop(issue) => Err(issue)
  }
}
