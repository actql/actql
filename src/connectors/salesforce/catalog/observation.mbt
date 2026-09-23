///|
/// This is the identity of one authorized catalog observation, not a static
/// Connector Catalog or a grant to use the observed resources later.
pub(all) struct CatalogObservationBinding {
  tenant : String
  principal : String
  environment : String
  connection_revision : String
  org_id : String
  site_key : String
  site_generation : Int
  connector_registration : String
  connector_revision : String
  resource_origin : String
  run_invocation_cid : String
  dispatch_request_cid : String
  sync_occurrence : String
} derive(Eq, Debug)

///|
pub(all) enum CatalogObservationIssue {
  IncompleteSync
  InvalidBinding
  InvalidUseEvidence
  EvidenceCountMismatch
  OutputLimit
  ForeignBinding
  Resource(ResourceSelectionIssue)
} derive(Eq, Debug)

///|
pub struct CatalogObservation {
  names : Array[String]
  outcomes : Array[ResourceDescribeOutcome]
  truncated : Bool
  binding : CatalogObservationBinding
  body : String
  cid : String
}

///|
/// A refresh is a new observation and may use a new sync dispatch. Its
/// execution authority, connection, and Site generation must remain exact.
fn catalog_execution_binding_matches(
  prior : CatalogObservationBinding,
  current : CatalogObservationBinding,
) -> Bool {
  prior.tenant == current.tenant &&
  prior.principal == current.principal &&
  prior.environment == current.environment &&
  prior.connection_revision == current.connection_revision &&
  prior.org_id == current.org_id &&
  prior.site_key == current.site_key &&
  prior.site_generation == current.site_generation &&
  prior.connector_registration == current.connector_registration &&
  prior.connector_revision == current.connector_revision &&
  prior.resource_origin == current.resource_origin &&
  prior.run_invocation_cid == current.run_invocation_cid
}

///|
fn copy_resource(resource : ResourceMetadata) -> ResourceMetadata {
  let fields = []
  for field in resource.fields {
    fields.push({ ..field, reference_to: field.reference_to.copy(), })
  }
  { ..resource, fields, }
}

///|
fn copy_outcome(outcome : ResourceDescribeOutcome) -> ResourceDescribeOutcome {
  match outcome {
    Described(resource) => Described(copy_resource(resource))
    Unavailable(reason) => Unavailable(reason)
    Pending => Pending
  }
}

///|
fn observation_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index in 7..<71 {
    let character = value[index]
    if !((character >= '0' && character <= '9') ||
      (character >= 'a' && character <= 'f')) {
      return false
    }
  }
  true
}

///|
fn observation_digest(value : String) -> Bool {
  value.length() == 64 && observation_cid("sha256:" + value)
}

///|
pub fn catalog_response_sha256(bytes : Bytes) -> String {
  @sha.hex(bytes)
}

///|
fn observation_binding_valid(binding : CatalogObservationBinding) -> Bool {
  !binding.tenant.is_empty() &&
  !binding.principal.is_empty() &&
  !binding.environment.is_empty() &&
  !binding.connection_revision.is_empty() &&
  canonical_write_record_id(binding.org_id) is Some(_) &&
  !binding.site_key.is_empty() &&
  binding.site_generation >= 0 &&
  !binding.connector_registration.is_empty() &&
  !binding.connector_revision.is_empty() &&
  !binding.resource_origin.is_empty() &&
  observation_cid(binding.run_invocation_cid) &&
  observation_cid(binding.dispatch_request_cid) &&
  !binding.sync_occurrence.is_empty()
}

///|
fn observation_failure_name(failure : DescribeFailure) -> String {
  match failure {
    PermissionDenied => "permission_denied"
    RateLimited => "rate_limited"
    ProviderUnavailable => "provider_unavailable"
    TransportInterrupted => "transport_interrupted"
    InvalidMetadata => "invalid_metadata"
    Cancelled => "cancelled"
  }
}

///|
fn observation_field(
  writer : @encode.Writer,
  name : String,
  value : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, name)
  @encode.string_value(writer, value)
}

///|
fn emit_observation(
  sync : CatalogSync,
  binding : CatalogObservationBinding,
  list_use_cid : String,
  describe_use_cids : Array[String?],
  describe_response_sha256 : Array[String?],
  max_bytes : Int,
) -> Result[String, CatalogObservationIssue] {
  let writer = @encode.writer(max_bytes, 100000, 4) catch {
    _ => return Err(OutputLimit)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "binding")
    @encode.begin_object(writer)
    observation_field(
      writer,
      "connection_revision",
      binding.connection_revision,
    )
    observation_field(
      writer,
      "connector_registration",
      binding.connector_registration,
    )
    observation_field(writer, "connector_revision", binding.connector_revision)
    observation_field(
      writer,
      "dispatch_request_cid",
      binding.dispatch_request_cid,
    )
    observation_field(writer, "environment", binding.environment)
    observation_field(writer, "org_id", binding.org_id)
    observation_field(writer, "principal", binding.principal)
    observation_field(writer, "resource_origin", binding.resource_origin)
    observation_field(writer, "run_invocation_cid", binding.run_invocation_cid)
    @encode.key(writer, "site_generation")
    @encode.number_value(writer, binding.site_generation.to_double())
    observation_field(writer, "site_key", binding.site_key)
    observation_field(writer, "sync_occurrence", binding.sync_occurrence)
    observation_field(writer, "tenant", binding.tenant)
    @encode.end_object(writer)
    @encode.key(writer, "listed_resources")
    @encode.begin_array(writer)
    for index in 0..<sync.listing.selected.length() {
      let entry = sync.listing.selected[index]
      @encode.begin_object(writer)
      observation_field(writer, "name", entry.name)
      @encode.key(writer, "outcome")
      match sync.outcomes[index] {
        Described(_) => @encode.string_value(writer, "described")
        Unavailable(reason) =>
          @encode.string_value(writer, observation_failure_name(reason))
        Pending => @encode.string_value(writer, "pending")
      }
      @encode.key(writer, "response_sha256")
      match describe_response_sha256[index] {
        Some(value) => @encode.string_value(writer, value)
        None => @encode.null_value(writer)
      }
      @encode.key(writer, "use_cid")
      match describe_use_cids[index] {
        Some(value) => @encode.string_value(writer, value)
        None => @encode.null_value(writer)
      }
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    observation_field(
      writer,
      "listing_response_sha256",
      sync.listing.response_sha256,
    )
    observation_field(writer, "listing_use_cid", list_use_cid)
    @encode.key(writer, "truncated")
    @encode.bool_value(writer, sync.listing.truncated)
    observation_field(
      writer, "version", "actql-salesforce-catalog-observation/0.1",
    )
    @encode.end_object(writer)
  } catch {
    _ => return Err(OutputLimit)
  }
  let body = @encode.finish(writer) catch { _ => return Err(OutputLimit) }
  Ok(body)
}

///|
/// The durable Store must retain this body and the referenced response bytes
/// before the observation can be used as retained Run evidence.
pub fn prepare_catalog_observation(
  sync : CatalogSync,
  binding : CatalogObservationBinding,
  list_use_cid : String,
  describe_use_cids : Array[String?],
  describe_response_sha256 : Array[String?],
  max_bytes : Int,
) -> Result[CatalogObservation, CatalogObservationIssue] {
  if !sync.finished || sync.next_index != sync.outcomes.length() {
    return Err(IncompleteSync)
  }
  if !observation_binding_valid(binding) {
    return Err(InvalidBinding)
  }
  if !observation_cid(list_use_cid) {
    return Err(InvalidUseEvidence)
  }
  if describe_use_cids.length() != sync.outcomes.length() ||
    describe_response_sha256.length() != sync.outcomes.length() {
    return Err(EvidenceCountMismatch)
  }
  for index in 0..<describe_use_cids.length() {
    match
      (
        sync.outcomes[index],
        describe_use_cids[index],
        describe_response_sha256[index],
      ) {
      (Described(resource), Some(value), Some(digest)) if observation_cid(value) &&
        digest == resource.response_sha256 => ()
      (Described(_), _, _) => return Err(InvalidUseEvidence)
      (_, Some(value), Some(digest)) if observation_cid(value) &&
        observation_digest(digest) => ()
      (_, None, None) => ()
      _ => return Err(InvalidUseEvidence)
    }
  }
  let body = match
    emit_observation(
      sync, binding, list_use_cid, describe_use_cids, describe_response_sha256, max_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let names = []
  let outcomes = []
  for index in 0..<sync.listing.selected.length() {
    names.push(sync.listing.selected[index].name)
    outcomes.push(copy_outcome(sync.outcomes[index]))
  }
  Ok({
    names,
    outcomes,
    truncated: sync.listing.truncated,
    binding,
    body,
    cid: "sha256:" + @sha.hex(@utf8.encode(body)),
  })
}

///|
pub fn catalog_observation_json(value : CatalogObservation) -> String {
  value.body
}

///|
pub fn catalog_observation_identity(value : CatalogObservation) -> String {
  value.cid
}

///|
/// Equal content in a different connection or Site generation is not the
/// observation admitted for this execution. Current authority remains separate.
pub fn catalog_observation_resource(
  observation : CatalogObservation,
  current : CatalogObservationBinding,
  name : String,
) -> Result[ResourceMetadata, CatalogObservationIssue] {
  match catalog_observation_resource_outcome(observation, current, name) {
    Ok(Described(resource)) => Ok(resource)
    Ok(_) => Err(Resource(DescribeRequired))
    Err(issue) => Err(issue)
  }
}

///|
/// A failed describe is an incomplete observation, not proof of absence.
/// This accessor does not grant disclosure or current execution authority.
pub fn catalog_observation_resource_outcome(
  observation : CatalogObservation,
  current : CatalogObservationBinding,
  name : String,
) -> Result[ResourceDescribeOutcome, CatalogObservationIssue] {
  if current != observation.binding {
    return Err(ForeignBinding)
  }
  for index in 0..<observation.names.length() {
    if observation.names[index] == name {
      return Ok(copy_outcome(observation.outcomes[index]))
    }
  }
  Err(
    Resource(if observation.truncated { ListingTruncated } else { NotVisible }),
  )
}
