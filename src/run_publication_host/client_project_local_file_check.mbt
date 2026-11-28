///|
/// The original Checker and its admitted SQL-facing Local file publication.
pub struct ClientProjectLocalFileCheck {
  environment : @checked.CheckEnvironment
  publication : String
  scope_cid : String
  prepared : @source_publication.PreparedPublishedQueryEnvironment
  retained_bytes : Int64
  priv catalogs : Array[ClientProjectLocalFileCatalog]
  priv account : @authorization.AdmittedAccountConfiguration
  priv principal : String
}

///|
pub(all) enum ClientProjectLocalFileCheckIssue {
  InvalidCatalog
  ConstructionQuote
  InvalidCheckEnvironment
  InvalidPublication
  PublicationLimit
  PublicationAlias
  Publication
} derive(Debug)

///|
/// Quote generated aliases before projecting any Account-visible member. This
/// includes the extra short listing alias and repeated names and references in
/// the publication wire and in its independent audience preimage.
fn local_file_check_alias_inventory(
  catalogs : Array[ClientProjectLocalFileCatalog],
) -> @execution.PreparationRepresentationUnits? {
  let mut aliases = 0L
  let mut bytes = 256L
  for catalog in catalogs {
    let connection_units = catalog.project_files.connection.length().to_int64()
    for view in catalog.declaration.views {
      let copies = if view.resource == "files" { 2L } else { 1L }
      aliases += copies
      bytes += copies *
        (
          256L +
          6L *
          (
            connection_units +
            view.resource.length().to_int64() +
            view.source_ref.length().to_int64()
          )
        )
    }
  }
  let nodes = 4L + 5L * aliases
  guard bytes <= 4000000L && nodes <= 400000L else { return None }
  mock_check_codec_inventory(bytes.to_int(), nodes.to_int(), aliases, 2L)
}

///|
/// The visibility decision names the same connection and declared resource.
/// Resource aliases, roots, and other connections supply no Account fact.
fn local_file_check_aliases(
  catalogs : Array[ClientProjectLocalFileCatalog],
  account : @authorization.AdmittedAccountConfiguration,
  principal : String,
) -> Array[Json] {
  let aliases : Array[Json] = []
  for catalog in catalogs {
    let connection = catalog.project_files.connection
    for view in catalog.declaration.views {
      guard @authorization.evaluate_account(account, {
          principal,
          connection,
          resource: view.resource,
          operation: "read",
        })
        is Allow(_) else {
        continue
      }
      let name = connection + "." + view.resource
      aliases.push(local_file_check_alias(name, view))
      if view.resource == "files" {
        aliases.push(local_file_check_alias(connection, view))
      }
    }
  }
  aliases
}

///|
fn local_file_check_alias(
  name : String,
  view : @row_host.RowDeclaredView,
) -> Json {
  {
    "name": Json::string(name),
    "sourceRef": Json::string(view.source_ref),
    "sourceViewContractCid": Json::string(view.view_cid),
    "schemaContractCid": Json::string(view.carrier_schema_cid),
  }
}

///|
/// Assemble and admit the exact selected Local Catalog under the caller's
/// current checking and capacity owner. This projects the ordinary Account
/// read audience. It neither starts a physical Source nor issues a Run grant.
pub fn[E] prepare_funded_client_project_local_file_check(
  base : @checked.CheckEnvironment,
  catalogs : Array[ClientProjectLocalFileCatalog],
  account : @authorization.AdmittedAccountConfiguration,
  principal : String,
  prepare : (@execution.PreparationRepresentationUnits) -> Result[Unit, E],
  invalid : (ClientProjectLocalFileCheckIssue) -> E,
) -> Result[ClientProjectLocalFileCheck, E] {
  guard !catalogs.is_empty() else { return Err(invalid(InvalidCatalog)) }
  guard @execution.preparation_array_representation(
      1L,
      catalogs.length().to_int64(),
      false,
    )
    is Some(catalog_vector) &&
    @execution.compose_preparation_representation([
      catalog_vector,
      {
        record_headers: 1L,
        reference_slots: 3L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(source_custody) &&
    @execution.preparation_representation_cost(source_custody)
    is Some(source_custody_bytes) &&
    local_file_check_assembly_inventory(base, catalogs)
    is Some(environment_inventory) &&
    local_file_check_alias_inventory(catalogs) is Some(alias_inventory) &&
    @execution.compose_preparation_representation([
      alias_inventory, source_custody,
    ])
    is Some(alias_inventory) else {
    return Err(invalid(ConstructionQuote))
  }
  match prepare(environment_inventory) {
    Ok(_) => ()
    Err(cause) => return Err(cause)
  }
  match prepare(alias_inventory) {
    Ok(_) => ()
    Err(cause) => return Err(cause)
  }
  guard assemble_client_project_mock_environment(
      base,
      catalogs,
      () => None,
      catalog => catalog.declaration,
      (_, _) => Iter::empty(),
      _ => Iter::empty(),
    )
    is Some((body, cid)) else {
    return Err(invalid(InvalidCheckEnvironment))
  }
  let aliases = Json::array(
    local_file_check_aliases(catalogs, account, principal),
  )
  guard client_project_mock_wire({
      "environmentCid": Json::string(cid),
      "aliases": aliases,
    })
    is Ok(publication) &&
    client_project_mock_wire(aliases) is Ok(visible) else {
    return Err(invalid(InvalidPublication))
  }
  guard mock_project_check_admission_inventory(body, publication)
    is Some(admission) &&
    @execution.preparation_representation_cost(admission)
    is Some(held_admission) else {
    return Err(invalid(ConstructionQuote))
  }
  match prepare(admission) {
    Ok(_) => ()
    Err(cause) => return Err(cause)
  }
  // The Local merge does not add, remove or rewrite Model Task contracts.
  // A selected Model base carries the exact extra checked contract inventory.
  let base_wire = @checked.checking_environment_wire(base)
  let task_inventory = if @environment.member_count(
      base_wire,
      ModelTaskContracts,
    ) ==
    0 {
    None
  } else {
    guard @environment.model_tasks_admission_construction_extent(base_wire)
      is Some(inventory) else {
      return Err(invalid(ConstructionQuote))
    }
    match
      prepare({
        record_headers: inventory.record_headers,
        reference_slots: inventory.reference_slots,
        scalar_words: inventory.scalar_words,
        owned_utf16_units: inventory.owned_utf16_units,
        owned_wire_bytes: inventory.owned_wire_bytes,
      }) {
      Ok(_) => ()
      Err(cause) => return Err(cause)
    }
    Some(inventory)
  }
  let scope_cid = "sha256:" + @sha.hex(@utf8.encode(visible))
  guard admit_client_check_environment(
      body,
      cid,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    )
    is Some(environment) else {
    return Err(invalid(InvalidCheckEnvironment))
  }
  let prepared = match
    @source_publication.prepare_published_query_environment(
      environment, publication,
    ) {
    Ok(prepared) => prepared
    Err(@source_publication.Limit) => return Err(invalid(PublicationLimit))
    Err(@source_publication.Alias(_)) => return Err(invalid(PublicationAlias))
    Err(_) => return Err(invalid(Publication))
  }
  guard mock_project_check_retained_inventory(
      environment,
      body,
      publication,
      task_inventory~,
    )
    is Some(retained) &&
    @execution.preparation_representation_cost(retained) is Some(retained_bytes) &&
    @execution.checked_preparation_add_product(
      retained_bytes, 1L, held_admission,
    )
    is Some(retained_bytes) &&
    @execution.checked_preparation_add_product(
      retained_bytes, 1L, source_custody_bytes,
    )
    is Some(retained_bytes) else {
    return Err(invalid(ConstructionQuote))
  }
  Ok({
    environment,
    publication,
    scope_cid,
    prepared,
    retained_bytes,
    catalogs: catalogs.copy(),
    account,
    principal,
  })
}
