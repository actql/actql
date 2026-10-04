///|
pub(all) enum InstalledSalesforceIssue {
  InvalidInput
  ForeignBinding
  Recovery(@catalog.CatalogObservationRecoveryIssue)
  UnknownRevision
  Declaration(@catalog.DeclarationIssue)
  ForeignDeclaration
  UndeclaredSource
  Projection(@catalog.ReadProjectionIssue)
  Preparation(SalesforceReadPreparationIssue)
  Row(@rows.RowHostIssue)
  Source(@rows.RowSourceIssue)
}

///|
let connector_registration = "salesforce"

///|
let connector_revision = "salesforce/0.1"

///|
/// The installed Salesforce Site this runtime reads for: every observation
/// and declaration it accepts must carry exactly this binding (apart from the
/// dispatch that observed it).
pub struct InstalledSalesforceSite {
  namespace_id : String
  principal : String
  environment : String
  connection_revision : String
  org_id : String
  site_key : String
  site_generation : Int
  resource_origin : String
}

///|
pub fn installed_salesforce_site(
  namespace_id : String,
  principal : String,
  environment : String,
  connection_revision : String,
  org_id : String,
  site_key : String,
  site_generation : Int,
  resource_origin : String,
) -> Result[InstalledSalesforceSite, InstalledSalesforceIssue] {
  if [
      namespace_id, principal, environment, connection_revision, org_id, site_key,
      resource_origin,
    ].any(value => value.is_empty()) ||
    site_generation < 0 {
    return Err(InvalidInput)
  }
  Ok({
    namespace_id,
    principal,
    environment,
    connection_revision,
    org_id,
    site_key,
    site_generation,
    resource_origin,
  })
}

///|
fn site_binding_matches(
  site : InstalledSalesforceSite,
  binding : @catalog.CatalogObservationBinding,
) -> Bool {
  binding.namespace_id == site.namespace_id &&
  binding.principal == site.principal &&
  binding.environment == site.environment &&
  binding.connection_revision == site.connection_revision &&
  binding.org_id == site.org_id &&
  binding.site_key == site.site_key &&
  binding.site_generation == site.site_generation &&
  binding.resource_origin == site.resource_origin &&
  binding.connector_registration == connector_registration &&
  binding.connector_revision == connector_revision
}

///|
/// Reproject one describe-only observation from its exact retained provider
/// bytes. The bytes must reproduce `observation_json` exactly, and the
/// observation must be bound to `site`; with `run_invocation_cid`, it must
/// also belong to that dispatch. Nothing here is current read authority.
pub fn recover_installed_salesforce_observation(
  site : InstalledSalesforceSite,
  observation_json : String,
  run_invocation_cid : String,
  dispatch_request_cid : String,
  sync_occurrence : String,
  names : Array[String],
  describe_bytes : Array[Bytes?],
  outcomes : Array[Int],
  describe_use_cids : Array[String?],
  describe_response_sha256 : Array[String?],
  describe_limits : @catalog.DescribeLimits,
  max_observation_bytes : Int,
  expected_run_invocation_cid : String?,
) -> Result[@catalog.CatalogObservation, InstalledSalesforceIssue] {
  if observation_json.length() > max_observation_bytes ||
    names.is_empty() ||
    names.length() > 200 {
    return Err(InvalidInput)
  }
  match expected_run_invocation_cid {
    Some(expected) if expected != run_invocation_cid =>
      return Err(ForeignBinding)
    _ => ()
  }
  let binding : @catalog.CatalogObservationBinding = {
    namespace_id: site.namespace_id,
    principal: site.principal,
    environment: site.environment,
    connection_revision: site.connection_revision,
    org_id: site.org_id,
    site_key: site.site_key,
    site_generation: site.site_generation,
    connector_registration,
    connector_revision,
    resource_origin: site.resource_origin,
    run_invocation_cid,
    dispatch_request_cid,
    sync_occurrence,
  }
  // The retained bytes must reproduce the exact observation text, which
  // carries its binding: another Site's observation cannot match `binding`.
  @catalog.recover_named_catalog_observation(
    observation_json, names, describe_bytes, outcomes, binding, describe_use_cids,
    describe_response_sha256, describe_limits, max_observation_bytes,
  ).map_err(issue => Recovery(issue))
}

///|
/// A published declaration, regenerated in this runtime from its published
/// observation. It is the Check-time declaration the acquisition must stay
/// within; it is not current authority.
pub struct InstalledSalesforceDeclaration {
  site : InstalledSalesforceSite
  declaration : @catalog.StaticDeclaration
}

///|
/// Regenerate the declaration of the described targets of a published
/// observation. It must reproduce the published Catalog exactly.
pub fn restore_installed_salesforce_declaration(
  site : InstalledSalesforceSite,
  observation : @catalog.CatalogObservation,
  connector_id : String,
  catalog_cid : String,
  limits : @catalog.DeclarationLimits,
) -> Result[InstalledSalesforceDeclaration, InstalledSalesforceIssue] {
  if !site_binding_matches(site, observation.binding) {
    return Err(ForeignBinding)
  }
  guard @catalog.salesforce_implementation(connector_revision)
    is Some(implementation) else {
    return Err(UnknownRevision)
  }
  let described = []
  for index, name in observation.names {
    if observation.outcomes[index] is Described(_) {
      described.push(name)
    }
  }
  if described.is_empty() {
    return Err(ForeignDeclaration)
  }
  let declaration = match
    @catalog.generate_static_declaration(
      observation,
      observation.binding,
      implementation,
      connector_id,
      described,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Declaration(issue))
  }
  if declaration.catalog_cid != catalog_cid {
    return Err(ForeignDeclaration)
  }
  Ok({ site, declaration, })
}

///|
/// The declared view the checked Program reads: its Resource and fields.
/// A source outside the published declaration is refused.
pub fn installed_salesforce_source_target(
  value : InstalledSalesforceDeclaration,
  requirement : @planning.QueryRequirement,
) -> Result[(String, Array[String]), InstalledSalesforceIssue] {
  let source_ref = @planning.query_requirement_source(requirement).0
  for view in value.declaration.views {
    if view.source_ref == source_ref {
      return Ok((view.resource, view.fields.copy()))
    }
  }
  Err(UndeclaredSource)
}

///|
/// Recheck the current provider projection under the preserved declaration,
/// then hand off to the provider-neutral acquisition owner. This module owns
/// no admission buffer, attempt state, residual, retention, capture or evidence.
pub fn prepare_installed_salesforce_row_acquisition(
  declaration : InstalledSalesforceDeclaration,
  requirement : @planning.QueryRequirement,
  current : @catalog.CatalogObservation,
  query_contract_body : String,
  evidence_contract_body : String,
  max_soql_bytes : Int,
) -> Result[
  (@catalog.ReadProjection, @rows.RowAcquisition),
  InstalledSalesforceIssue,
] {
  if !site_binding_matches(declaration.site, current.binding) {
    return Err(ForeignBinding)
  }
  let (resource, fields) = match
    installed_salesforce_source_target(declaration, requirement) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let plan = match
    @catalog.prepare_read_projection(
      current,
      current.binding,
      resource,
      fields,
      max_soql_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Projection(issue))
  }
  // Reuse provider projection and exact-int prefilter validation, not its
  // a provider-owned execution/custody path.
  let provider = match
    prepare_salesforce_row_projection(
      requirement,
      plan,
      declaration.declaration.connector_id,
      declaration.declaration,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  let source_ref = @planning.query_requirement_source(requirement).0
  for view in declaration.declaration.views {
    if view.source_ref == source_ref {
      let preparation = match
        @rows.prepare_declared_row_source(
          requirement,
          declaration.declaration.connector_id,
          @rows.declared_row_view(
            view.resource,
            view.source_ref,
            view.view_cid,
            view.fields,
            view.carrier_schema_cid,
            view.data_policy_cid,
          ),
        ) {
        Ok(value) => value
        Err(issue) => return Err(Source(issue))
      }
      return @rows.prepare_declared_row_acquisition(
          preparation, connector_registration, query_contract_body, evidence_contract_body,
        )
        .map(value => (salesforce_read_plan(provider), value))
        .map_err(issue => Row(issue))
    }
  }
  Err(UndeclaredSource)
}
