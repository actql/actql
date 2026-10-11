///|
/// Identity of an authorized Direct Local Catalog observation. These are
/// original Host/account/request facts, not Site/Dispatch substitutes or a
/// credential/approval permit. Current authority is checked by Host assembly.
pub(all) struct LocalCatalogObservationBinding {
  account_configuration_cid : String
  account_id : String
  authority_scope_cid : String
  client_request_intent_cid : String
  client_request_scope_cid : String
  connection_revision : String
  connector_registration : String
  connector_revision : String
  environment : String
  host_adoption_cid : String
  namespace_id : String
  org_id : String
  principal : String
  resource_origin : String
  run_invocation_cid : String
  sync_occurrence : String
} derive(Eq, Debug)

///|
/// Closed alternatives within the existing Catalog/projection/request Owner.
/// The existing Site body is emitted unchanged; Local has its own exact body.
pub(all) enum CatalogExecutionBinding {
  SiteCatalog(CatalogObservationBinding)
  DirectLocalCatalog(LocalCatalogObservationBinding)
} derive(Eq, Debug)

///|
fn local_observation_binding_valid(
  binding : LocalCatalogObservationBinding,
) -> Bool {
  observation_cid(binding.account_configuration_cid) &&
  !binding.account_id.is_empty() &&
  observation_cid(binding.authority_scope_cid) &&
  observation_cid(binding.client_request_intent_cid) &&
  observation_cid(binding.client_request_scope_cid) &&
  !binding.connection_revision.is_empty() &&
  !binding.connector_registration.is_empty() &&
  !binding.connector_revision.is_empty() &&
  !binding.environment.is_empty() &&
  observation_cid(binding.host_adoption_cid) &&
  !binding.namespace_id.is_empty() &&
  canonical_write_record_id(binding.org_id) is Some(_) &&
  !binding.principal.is_empty() &&
  !binding.resource_origin.is_empty() &&
  observation_cid(binding.run_invocation_cid) &&
  !binding.sync_occurrence.is_empty()
}

///|
fn catalog_binding_valid(binding : CatalogExecutionBinding) -> Bool {
  match binding {
    SiteCatalog(value) => observation_binding_valid(value)
    DirectLocalCatalog(value) => local_observation_binding_valid(value)
  }
}

///|
fn catalog_binding_org_id(binding : CatalogExecutionBinding) -> String {
  match binding {
    SiteCatalog(value) => value.org_id
    DirectLocalCatalog(value) => value.org_id
  }
}

///|
fn catalog_binding_connector_revision(
  binding : CatalogExecutionBinding,
) -> String {
  match binding {
    SiteCatalog(value) => value.connector_revision
    DirectLocalCatalog(value) => value.connector_revision
  }
}

///|
fn catalog_binding_connector_registration(
  binding : CatalogExecutionBinding,
) -> String {
  match binding {
    SiteCatalog(value) => value.connector_registration
    DirectLocalCatalog(value) => value.connector_registration
  }
}

///|
fn catalog_binding_observation_version(
  binding : CatalogExecutionBinding,
) -> String {
  match binding {
    SiteCatalog(_) => "actql-salesforce-catalog-observation/0.1"
    DirectLocalCatalog(_) => "actql-salesforce-local-catalog-observation/0.1"
  }
}

///|
fn local_catalog_installation_matches(
  prior : LocalCatalogObservationBinding,
  current : LocalCatalogObservationBinding,
) -> Bool {
  prior.account_configuration_cid == current.account_configuration_cid &&
  prior.account_id == current.account_id &&
  prior.authority_scope_cid == current.authority_scope_cid &&
  prior.connection_revision == current.connection_revision &&
  prior.connector_registration == current.connector_registration &&
  prior.connector_revision == current.connector_revision &&
  prior.environment == current.environment &&
  prior.host_adoption_cid == current.host_adoption_cid &&
  prior.namespace_id == current.namespace_id &&
  prior.org_id == current.org_id &&
  prior.principal == current.principal &&
  prior.resource_origin == current.resource_origin
}

///|
fn catalog_execution_binding_matches(
  prior : CatalogExecutionBinding,
  current : CatalogExecutionBinding,
) -> Bool {
  match (prior, current) {
    (SiteCatalog(before), SiteCatalog(after)) =>
      catalog_site_execution_binding_matches(before, after)
    (DirectLocalCatalog(before), DirectLocalCatalog(after)) =>
      local_catalog_installation_matches(before, after) &&
      before.client_request_intent_cid == after.client_request_intent_cid &&
      before.client_request_scope_cid == after.client_request_scope_cid &&
      before.run_invocation_cid == after.run_invocation_cid
    _ => false
  }
}

///|
fn declaration_owned_binding_matches(
  declared : CatalogExecutionBinding,
  current : CatalogExecutionBinding,
) -> Bool {
  match (declared, current) {
    (SiteCatalog(before), SiteCatalog(after)) =>
      declaration_site_binding_matches(before, after)
    (DirectLocalCatalog(before), DirectLocalCatalog(after)) =>
      local_catalog_installation_matches(before, after)
    _ => false
  }
}

///|
fn emit_local_observation_binding(
  writer : @encode.Writer,
  binding : LocalCatalogObservationBinding,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  for
    (key, value) in [
      ("account_configuration_cid", binding.account_configuration_cid),
      ("account_id", binding.account_id),
      ("authority_scope_cid", binding.authority_scope_cid),
      ("client_request_intent_cid", binding.client_request_intent_cid),
      ("client_request_scope_cid", binding.client_request_scope_cid),
      ("connection_revision", binding.connection_revision),
      ("connector_registration", binding.connector_registration),
      ("connector_revision", binding.connector_revision),
      ("environment", binding.environment),
      ("host_adoption_cid", binding.host_adoption_cid),
      ("namespace_id", binding.namespace_id),
      ("org_id", binding.org_id),
      ("principal", binding.principal),
      ("resource_origin", binding.resource_origin),
      ("run_invocation_cid", binding.run_invocation_cid),
      ("sync_occurrence", binding.sync_occurrence),
    ] {
    observation_field(writer, key, value)
  }
  @encode.end_object(writer)
}

///|
pub fn prepare_local_catalog_observation(
  sync : CatalogSync,
  binding : LocalCatalogObservationBinding,
  list_use_cid : String,
  describe_use_cids : Array[String?],
  describe_response_sha256 : Array[String?],
  max_bytes : Int,
) -> Result[CatalogObservation, CatalogObservationIssue] {
  prepare_owned_catalog_observation(
    sync,
    DirectLocalCatalog(binding),
    list_use_cid,
    describe_use_cids,
    describe_response_sha256,
    max_bytes,
  )
}

///|
pub fn catalog_observation_matches_local_binding(
  observation : CatalogObservation,
  current : LocalCatalogObservationBinding,
) -> Bool {
  observation.binding == DirectLocalCatalog(current)
}

///|
pub fn catalog_observation_local_resource(
  observation : CatalogObservation,
  current : LocalCatalogObservationBinding,
  name : String,
) -> Result[ResourceMetadata, CatalogObservationIssue] {
  catalog_owned_observation_resource(
    observation,
    DirectLocalCatalog(current),
    name,
  )
}

///|
pub fn prepare_local_write_projection(
  observation : CatalogObservation,
  current : LocalCatalogObservationBinding,
  resource_name : String,
  operation : WriteOperation,
  field_names : Array[String],
  max_fields : Int,
) -> Result[WriteProjection, WriteProjectionIssue] {
  prepare_owned_write_projection(
    observation,
    DirectLocalCatalog(current),
    resource_name,
    operation,
    field_names,
    max_fields,
  )
}

///|
pub fn generate_local_static_declaration(
  observation : CatalogObservation,
  current : LocalCatalogObservationBinding,
  implementation : SalesforceImplementation,
  connector_id : String,
  resource_names : Array[String],
  limits : DeclarationLimits,
) -> Result[StaticDeclaration, DeclarationIssue] {
  generate_owned_static_declaration(
    observation,
    DirectLocalCatalog(current),
    implementation,
    connector_id,
    resource_names,
    limits,
  )
}

///|
fn emit_local_capability_binding(
  writer : @encode.Writer,
  binding : LocalCatalogObservationBinding,
  runtime_bundle_cid : String,
) -> Unit raise @encode.EncodeFailure {
  // Static capability binds the admitted installation, not a fabricated Site
  // or a future call. Original Run/request facts are checked on each request.
  @encode.begin_object(writer)
  for
    (key, value) in [
      ("account_configuration_cid", binding.account_configuration_cid),
      ("account_id", binding.account_id),
      ("authority_scope_cid", binding.authority_scope_cid),
      ("connection_revision", binding.connection_revision),
      ("connector_registration", binding.connector_registration),
      ("connector_revision", binding.connector_revision),
      ("environment", binding.environment),
      ("host_adoption_cid", binding.host_adoption_cid),
      ("namespace_id", binding.namespace_id),
      ("org_id", binding.org_id),
      ("principal", binding.principal),
      ("resource_origin", binding.resource_origin),
      ("runtime_bundle_cid", runtime_bundle_cid),
    ] {
    observation_field(writer, key, value)
  }
  @encode.end_object(writer)
}

///|
pub fn single_write_request_matches_local_binding(
  request : SingleWriteRequest,
  current : LocalCatalogObservationBinding,
) -> Bool {
  request.projection.binding == DirectLocalCatalog(current)
}

///|
/// Readmit exact retained metadata bytes and use evidence under their original
/// Local binding. This performs no metadata refresh, I/O or authorization.
pub fn recover_local_named_catalog_observation(
  expected_body : String,
  names : Array[String],
  describe_bytes : Array[Bytes?],
  outcomes : Array[Int],
  binding : LocalCatalogObservationBinding,
  describe_use_cids : Array[String?],
  describe_response_sha256 : Array[String?],
  describe_limits : DescribeLimits,
  max_observation_bytes : Int,
) -> Result[CatalogObservation, CatalogObservationRecoveryIssue] {
  recover_owned_named_catalog_observation(
    expected_body,
    names,
    describe_bytes,
    outcomes,
    DirectLocalCatalog(binding),
    describe_use_cids,
    describe_response_sha256,
    describe_limits,
    max_observation_bytes,
  )
}
