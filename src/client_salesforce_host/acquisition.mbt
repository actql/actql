///|
pub(all) enum ClientSalesforceIssue {
  InvalidInput
  ForeignBinding
  Recovery(@catalog.CatalogObservationRecoveryIssue)
  UnknownRevision
  Declaration(@catalog.DeclarationIssue)
  ForeignDeclaration
  UndeclaredSource
  Projection(@catalog.ReadProjectionIssue)
  Broad(@salesforce_host.SalesforceBroadIssue)
  InvalidContracts
  Registration
  Candidate
  Selection
  Host(@salesforce_host.SalesforceBroadHostIssue)
  Evidence(@salesforce_host.SalesforceSourceEvidenceIssue)
}

///|
let connector_registration = "salesforce"

///|
let connector_revision = "salesforce/0.1"

///|
/// The installed Salesforce Site this runtime reads for: every observation
/// and declaration it accepts must carry exactly this binding (apart from the
/// dispatch that observed it).
pub struct ClientSalesforceSite {
  tenant : String
  principal : String
  environment : String
  connection_revision : String
  org_id : String
  site_key : String
  site_generation : Int
  resource_origin : String
}

///|
pub fn client_salesforce_site(
  tenant : String,
  principal : String,
  environment : String,
  connection_revision : String,
  org_id : String,
  site_key : String,
  site_generation : Int,
  resource_origin : String,
) -> Result[ClientSalesforceSite, ClientSalesforceIssue] {
  if [
      tenant, principal, environment, connection_revision, org_id, site_key, resource_origin,
    ].any(value => value.is_empty()) ||
    site_generation < 0 {
    return Err(InvalidInput)
  }
  Ok({
    tenant,
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
  site : ClientSalesforceSite,
  binding : @catalog.CatalogObservationBinding,
) -> Bool {
  binding.tenant == site.tenant &&
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
pub fn recover_client_salesforce_observation(
  site : ClientSalesforceSite,
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
) -> Result[@catalog.CatalogObservation, ClientSalesforceIssue] {
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
    tenant: site.tenant,
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
pub struct ClientSalesforceDeclaration {
  site : ClientSalesforceSite
  declaration : @catalog.StaticDeclaration
}

///|
/// Regenerate the declaration of the described targets of a published
/// observation. It must reproduce the published Catalog exactly.
pub fn restore_client_salesforce_declaration(
  site : ClientSalesforceSite,
  observation : @catalog.CatalogObservation,
  connector_id : String,
  catalog_cid : String,
  limits : @catalog.DeclarationLimits,
) -> Result[ClientSalesforceDeclaration, ClientSalesforceIssue] {
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
pub fn client_salesforce_declaration_catalog_cid(
  value : ClientSalesforceDeclaration,
) -> String {
  value.declaration.catalog_cid
}

///|
/// The declared view the checked Program reads: its Resource and fields.
/// A source outside the published declaration is refused.
pub fn client_salesforce_source_target(
  value : ClientSalesforceDeclaration,
  requirement : @planning.QueryRequirement,
) -> Result[(String, Array[String]), ClientSalesforceIssue] {
  let source_ref = @planning.query_requirement_source(requirement).0
  for view in value.declaration.views {
    if view.source_ref == source_ref {
      return Ok((view.resource, view.fields.copy()))
    }
  }
  Err(UndeclaredSource)
}

///|
/// One selected Salesforce acquisition for a checked source, planned from a
/// describe made under this dispatch and held within the published
/// declaration. Physical transport starts only with `start`.
struct ClientSalesforceAcquisition {
  plan : @catalog.ReadProjection
  configuration : @salesforce_host.SalesforceBroadHostConfiguration
  context : @salesforce_host.SalesforceSourceEvidenceContext
}

///|
fn admit_contract(body : String) -> @identity.CanonicalValue? {
  Some(@identity.from_json(@json.parse(body), 10000, 100, 100000)) catch {
    _ => None
  }
}

///|
pub fn prepare_client_salesforce_acquisition(
  declaration : ClientSalesforceDeclaration,
  requirement : @planning.QueryRequirement,
  current : @catalog.CatalogObservation,
  query_contract_body : String,
  evidence_contract_body : String,
  max_soql_bytes : Int,
) -> Result[ClientSalesforceAcquisition, ClientSalesforceIssue] {
  if !site_binding_matches(declaration.site, current.binding) {
    return Err(ForeignBinding)
  }
  let (resource, fields) = match
    client_salesforce_source_target(declaration, requirement) {
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
  // The current describe must still fit the published declaration.
  let preparation = match
    @salesforce_host.prepare_salesforce_broad_query(
      requirement,
      plan,
      declaration.declaration.connector_id,
      declaration.declaration,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Broad(issue))
  }
  guard admit_contract(query_contract_body) is Some(query_contract) &&
    admit_contract(evidence_contract_body) is Some(evidence_contract) &&
    @planning.admit_query_evidence_contracts(
      query_contract,
      evidence_contract,
      { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    )
    is Ok(contracts) else {
    return Err(InvalidContracts)
  }
  guard @connector.prepare_capability_registry(
      [
        {
          name: connector_registration,
          acquisition: true,
          fixed_compute: false,
          effect: false,
        },
      ],
      1,
      20,
    )
    is Ok(registry) &&
    @connector.capability_registration_at(registry, 0) is Some(registration) else {
    return Err(Registration)
  }
  guard @salesforce_host.salesforce_broad_candidate(
      registration,
      preparation,
      [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(10L), }],
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
      100,
    )
    is Ok(candidate) else {
    return Err(Candidate)
  }
  guard @planning.choose_acquisition_candidate(
      registry,
      requirement,
      [@planning.prepared_acquisition_candidate(candidate)],
      None,
      100,
    )
    is Ok(@planning.Proposed(choice)) else {
    return Err(Selection)
  }
  let context = match
    @salesforce_host.prepare_salesforce_source_evidence_context(requirement) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  // The residual filter and capture measure every captured value: their work
  // budgets cover the whole capture. The capture holds at most 500 KB of
  // text, what the standard Host's Local fragments can evaluate at once.
  let values : @execution.ValueLimits = {
    max_nodes: 100000,
    max_text_bytes: 500000,
    max_depth: 100,
    max_work: 20000000,
  }
  let configuration = @salesforce_host.configure_salesforce_broad_host(
    contracts,
    requirement,
    choice,
    candidate,
    {
      execution: {
        rows: {
          max_rows: 100,
          metadata_entries: 10000,
          retained_entries: 10000,
          operation_entries: 10000,
          input_values: values,
          output_values: values,
        },
        max_work: 50000000,
        max_frames: 100,
      },
      guards: {
        max_work: 50000000,
        max_bytes: 1000000,
        max_nodes: 100000,
        max_depth: 100,
      },
      retention: {
        received_wire_bytes: 4000000,
        retained_wire_bytes: 4000000,
        measurement: {
          max_columns: 100,
          max_order_work: 100000,
          max_bytes: 4000000,
          max_nodes: 100000,
          max_depth: 100,
        },
      },
      records: {
        max_work: 1000000,
        max_fields: 100,
        max_parameters: 100,
        max_bytes: 1000000,
        max_nodes: 100000,
        max_depth: 100,
      },
      capture: { max_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
    },
  )
  Ok({ plan, configuration, context, })
}

///|
pub fn client_salesforce_acquisition_plan(
  value : ClientSalesforceAcquisition,
) -> @catalog.ReadProjection {
  value.plan
}

///|
/// Start the selected attempt. `verify` confirms the exact attempt's
/// physical transport has settled before capture completes.
pub fn start_client_salesforce_acquisition(
  value : ClientSalesforceAcquisition,
  nonce : String,
  verify : (@salesforce_host.SalesforceBroadAttempt) -> Bool,
) -> Result[@salesforce_host.SalesforceBroadHostRun, ClientSalesforceIssue] {
  @salesforce_host.start_salesforce_broad_host(
    value.configuration,
    nonce,
    verify,
  ).map_err(issue => Host(issue))
}

///|
/// Complete the settled attempt and hold its captured source.
pub fn capture_client_salesforce_source(
  run : @salesforce_host.SalesforceBroadHostRun,
) -> Result[
  @salesforce_host.SalesforceBroadSourceCapture,
  ClientSalesforceIssue,
] {
  let observation = match @salesforce_host.complete_salesforce_broad_host(run) {
    Ok(value) => value
    Err(issue) => return Err(Host(issue))
  }
  @salesforce_host.capture_salesforce_broad_host_source(run, observation).map_err(issue => {
      Host(issue)
    },
  )
}

///|
pub fn issue_client_salesforce_source_evidence(
  value : ClientSalesforceAcquisition,
  capture : @salesforce_host.SalesforceBroadSourceCapture,
  identity : @query.CapturedSourceRelationIdentity,
  logical_input : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  effective_data_policy_cid : String,
  observed_at : String,
) -> Result[@publication.RunEvidenceValue, ClientSalesforceIssue] {
  @salesforce_host.issue_salesforce_broad_source_evidence(
    capture,
    value.context,
    identity,
    logical_input,
    authority_scope_cid,
    effective_data_policy_cid,
    observed_at,
  ).map_err(issue => Evidence(issue))
}
