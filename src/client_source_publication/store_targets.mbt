///|
// Positive Host installation metadata only. Static publication is not a
// ResourceRef issuer, current grant, captured target or execution permission.
pub fn published_store_targets(
  environment : @program_check.CheckEnvironment,
  publication : String,
) -> Result[@query_program.StoreTargetPublication?, PublicationIssue] {
  let root = match read_publication_data(publication) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  published_store_targets_from_root(environment, root)
}

///|
fn published_store_targets_from_root(
  environment : @program_check.CheckEnvironment,
  root : @decode.Cursor,
  admission? : PublicationEnvironmentAdmission? = None,
) -> Result[@query_program.StoreTargetPublication?, PublicationIssue] {
  try {
    let object = @decode.closed_object(root, [
      "environmentCid", "aliases", "tableWrites", "updateTargets", "storeTargets",
      "commandTargets",
    ]).unwrap_or_else(() => raise PublicationStop(Publication))
    if source_publication_text(root, "environmentCid") !=
      @program_check.checking_environment_cid(environment) {
      raise PublicationStop(Publication)
    }
    guard @decode.lookup(object, "storeTargets") is Some(section) else {
      return Ok(None)
    }
    let aliases = source_publication_effect_aliases(section)
    if aliases.is_empty() {
      return Ok(None)
    }
    let wire = @program_check.checking_environment_wire(environment)
    let limits : @check_environment.Limits = {
      max_bytes: 1048576,
      max_nodes: 16384,
      max_depth: 32,
      max_members: 32768,
    }
    let mappings = match admission {
      Some(admission) => publication_admission_mappings(admission)
      None =>
        @check_environment.check_mapping_contract_shapes(wire, limits, 1000000).unwrap_or_else(() => {
            raise PublicationStop(Publication)
          },
        )
    }
    let catalogs = match admission {
      Some(admission) => publication_admission_contents(admission)
      None => {
        let registry = @check_environment.check_contract_registry(wire, limits).unwrap_or_else(() => {
            raise PublicationStop(Publication)
          },
        )
        @check_environment.check_catalog_contents(registry, limits).unwrap_or_else(() => {
            raise PublicationStop(Publication)
          },
        )
      }
    }
    match
      @query_program.bind_store_target_publication(
        mappings, catalogs, aliases, 1000000,
      ) {
      Ok(value) => Ok(Some(value))
      Err(@query_program.StoreTargetIssue::WorkLimit) => Err(Limit)
      Err(_) => Err(Publication)
    }
  } catch {
    PublicationStop(issue) => Err(issue)
  }
}
