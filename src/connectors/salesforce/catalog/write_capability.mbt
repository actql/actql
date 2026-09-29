///|
pub(all) enum WriteCapabilityRoute {
  SerialRows
  ContinueCollection
} derive(Eq, Debug)

///|
pub(all) enum WriteCapabilityIssue {
  InvalidLimits
  InvalidRuntime
  ForeignRequest
  OutputLimit
  CurrentCatalog(WriteProjectionIssue)
} derive(Eq, Debug)

///|
/// The implemented REST profile for one admitted projection. The Site must
/// authenticate its runtime binding before issuance and recheck current grant
/// authority before use. This evidence is not a mutation permit.
pub struct WriteCapabilityEvidence {
  projection : WriteProjection
  fields : Map[String, FieldMetadata]
  api_version : String
  runtime_bundle_cid : String
  route : WriteCapabilityRoute
  body : String
  cid : String
}

///|
fn capability_flag(
  writer : @encode.Writer,
  key : String,
  value : Bool,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, key)
  @encode.bool_value(writer, value)
}

///|
fn capability_field(
  writer : @encode.Writer,
  field : FieldMetadata,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "case_sensitive")
  match field.case_sensitive {
    Some(value) => @encode.bool_value(writer, value)
    None => @encode.null_value(writer)
  }
  capability_flag(writer, "createable", field.createable)
  capability_flag(
    writer,
    "default_on_create_confirmed",
    field.default_on_create_confirmed,
  )
  capability_flag(writer, "defaulted_on_create", field.defaulted_on_create)
  capability_flag(writer, "external_id", field.external_id)
  capability_flag(writer, "filterable", field.filterable)
  observation_field(writer, "name", field.name)
  observation_field(writer, "native_type", field.native_type)
  capability_flag(writer, "nullability_confirmed", field.nullability_confirmed)
  capability_flag(writer, "nullable", field.nullable)
  @encode.key(writer, "reference_to")
  @encode.begin_array(writer)
  let references = field.reference_to.copy()
  references.sort()
  for reference in references {
    @encode.string_value(writer, reference)
  }
  @encode.end_array(writer)
  capability_flag(writer, "sortable", field.sortable)
  capability_flag(writer, "unique", field.unique)
  capability_flag(writer, "updateable", field.updateable)
  // A written datetime is sent in whole seconds only.
  if field.native_type == "datetime" {
    observation_field(writer, "write_timestamp_precision", "second")
  }
  @encode.end_object(writer)
}

///|
pub fn prepare_write_capability_evidence(
  request : SingleWriteRequest,
  runtime_bundle_cid : String,
  route : WriteCapabilityRoute,
  max_bytes : Int,
) -> Result[WriteCapabilityEvidence, WriteCapabilityIssue] {
  if max_bytes < 1 ||
    max_bytes > 1000000 ||
    request.projection.fields.length() > 1000 {
    return Err(InvalidLimits)
  }
  if !observation_cid(runtime_bundle_cid) {
    return Err(InvalidRuntime)
  }
  let plan = request.projection
  let binding = plan.binding
  let writer = @encode.writer(max_bytes, 100000, 8) catch {
    _ => return Err(OutputLimit)
  }
  try {
    @encode.begin_object(writer)
    observation_field(writer, "api_version", request.api_version)
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
    observation_field(writer, "environment", binding.environment)
    observation_field(writer, "org_id", binding.org_id)
    observation_field(writer, "principal", binding.principal)
    observation_field(writer, "resource_origin", binding.resource_origin)
    observation_field(writer, "runtime_bundle_cid", runtime_bundle_cid)
    @encode.key(writer, "site_generation")
    @encode.number_value(writer, binding.site_generation.to_double())
    observation_field(writer, "site_key", binding.site_key)
    observation_field(writer, "namespace_id", binding.namespace_id)
    @encode.end_object(writer)
    @encode.key(writer, "external_target")
    match plan.external_target {
      Some(field) => capability_field(writer, field)
      None => @encode.null_value(writer)
    }
    observation_field(writer, "failure_granularity", "per_item")
    @encode.key(writer, "fields")
    @encode.begin_array(writer)
    let fields = plan.fields.copy()
    fields.sort_by((a, b) => a.name.compare(b.name))
    for field in fields {
      capability_field(writer, field)
    }
    @encode.end_array(writer)
    observation_field(writer, "idempotency", "unavailable")
    observation_field(writer, "mutation_atomicity", "per_item")
    observation_field(
      writer,
      "operation",
      single_write_request_effect_kind(request),
    )
    observation_field(writer, "reconciliation", "manual")
    capability_flag(writer, "request_order_preserved", route == SerialRows)
    observation_field(writer, "resource", plan.resource)
    observation_field(
      writer,
      "route",
      match route {
        SerialRows => "single_serial"
        ContinueCollection => "collection_continue"
      },
    )
    capability_flag(writer, "row_error_identity", true)
    observation_field(
      writer, "version", "actql-salesforce-write-capability/0.1",
    )
    @encode.end_object(writer)
  } catch {
    _ => return Err(OutputLimit)
  }
  let body = @encode.finish(writer) catch { _ => return Err(OutputLimit) }
  let fields = Map([])
  for field in plan.fields {
    fields[field.name] = field
  }
  Ok({
    projection: plan,
    fields,
    api_version: request.api_version,
    runtime_bundle_cid,
    route,
    body,
    cid: "sha256:" + @sha.hex(@utf8.encode(body)),
  })
}

///|
pub fn write_capability_identity(value : WriteCapabilityEvidence) -> String {
  value.cid
}

///|
pub fn write_capability_body(value : WriteCapabilityEvidence) -> String {
  value.body
}

///|
pub fn write_capability_route(
  value : WriteCapabilityEvidence,
) -> WriteCapabilityRoute {
  value.route
}

///|
/// Rows may differ in target and payload but must share the same admitted
/// field/operation profile. No response or request body is rehashed here.
pub fn check_write_capability_request(
  evidence : WriteCapabilityEvidence,
  request : SingleWriteRequest,
  runtime_bundle_cid : String,
) -> Result[Unit, WriteCapabilityIssue] {
  let before = evidence.projection
  let after = request.projection
  if evidence.runtime_bundle_cid != runtime_bundle_cid ||
    evidence.api_version != request.api_version ||
    !catalog_execution_binding_matches(before.binding, after.binding) ||
    before.resource != after.resource ||
    before.operation != after.operation ||
    before.fields.length() != after.fields.length() {
    return Err(ForeignRequest)
  }
  for field in after.fields {
    guard evidence.fields.get(field.name) is Some(other) &&
      same_write_field(field, other) else {
      return Err(ForeignRequest)
    }
  }
  match (before.external_target, after.external_target) {
    (None, None) => ()
    (Some(a), Some(b)) if same_write_field(a, b) => ()
    _ => return Err(ForeignRequest)
  }
  Ok(())
}

///|
pub fn recheck_write_capability(
  evidence : WriteCapabilityEvidence,
  current : CatalogObservation,
) -> Result[Unit, WriteCapabilityIssue] {
  recheck_write_projection(evidence.projection, current).map_err(issue => {
    CurrentCatalog(issue)
  })
}
