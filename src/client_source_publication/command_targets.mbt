///|
/// Trusted positive installation metadata. The exact original Command reader
/// supplies the declared mode/domain; publication does not issue its target.
pub fn published_command_targets(
  environment : @program_check.CheckEnvironment,
  publication : String,
) -> Result[@query_program.CommandTargetPublication?, PublicationIssue] {
  let root = match read_publication_data(publication) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  published_command_targets_from_root(environment, root)
}

///|
fn published_command_targets_from_root(
  environment : @program_check.CheckEnvironment,
  root : @decode.Cursor,
) -> Result[@query_program.CommandTargetPublication?, PublicationIssue] {
  try {
    let object = @decode.closed_object(root, [
      "environmentCid", "aliases", "tableWrites", "updateTargets", "storeTargets",
      "commandTargets",
    ]).unwrap_or_else(() => raise PublicationStop(Publication))
    if source_publication_text(root, "environmentCid") !=
      @program_check.checking_environment_cid(environment) {
      raise PublicationStop(Publication)
    }
    guard @decode.lookup(object, "commandTargets") is Some(section) else {
      return Ok(None)
    }
    let entries = @decode.elements(section).unwrap_or_else(() => {
      raise PublicationStop(Publication)
    })
    if entries.length() > 1024 {
      raise PublicationStop(Limit)
    }
    if entries.is_empty() {
      return Ok(None)
    }
    let aliases : Array[@query_program.CommandTargetAlias] = []
    for entry in entries {
      @decode.closed_object(entry, [
        "name", "targetRef", "commandRef", "installationBindingCid", "installationOwnerCid",
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
        command_ref: source_publication_text(entry, "commandRef"),
        installation_binding_cid: source_publication_text(
          entry, "installationBindingCid",
        ),
        installation_owner_cid: source_publication_text(
          entry, "installationOwnerCid",
        ),
      })
    }
    let wire = @program_check.checking_environment_wire(environment)
    let limits : @check_environment.Limits = {
      max_bytes: 1048576,
      max_nodes: 16384,
      max_depth: 32,
      max_members: 32768,
    }
    let registry = @check_environment.check_contract_registry(wire, limits).unwrap_or_else(() => {
        raise PublicationStop(Publication)
      },
    )
    let catalogs = @check_environment.check_catalog_contents(registry, limits).unwrap_or_else(() => {
        raise PublicationStop(Publication)
      },
    )
    match
      @query_program.bind_command_target_publication(
        catalogs,
        aliases,
        { max_nodes: 16384, max_depth: 32, max_text_bytes: 1048576, },
        1000000,
      ) {
      Ok(value) => Ok(Some(value))
      Err(@query_program.CommandTargetPublicationIssue::WorkLimit) => Err(Limit)
      Err(_) => Err(Publication)
    }
  } catch {
    PublicationStop(issue) => Err(issue)
  }
}
