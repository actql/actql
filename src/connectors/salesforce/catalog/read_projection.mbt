///|
pub(all) enum ReadProjectionIssue {
  Observation(CatalogObservationIssue)
  Requirement(ResourceRequirementIssue)
  EmptyProjection
  QueryLimit
  UnconfirmedNullability(String)
  UnsupportedReadType(String)
  ForeignCurrentObservation
  SchemaChanged(String)
} derive(Eq, Debug)

///|
/// A provider-specific, pure candidate derived from one supplied observation.
/// It grants neither current source authority nor an executable acquisition.
pub struct ReadProjection {
  observation_cid : String
  binding : CatalogObservationBinding
  resource : String
  fields : Array[FieldMetadata]
  contracts : Array[@contract.Contract]
  soql : String
}

///|
/// Only wire forms that have an exact, lossless ActQL scalar admission are
/// enabled. Decimal and temporal types need explicit provider conversion.
fn read_field_contract(field : FieldMetadata) -> @contract.Contract? {
  let kind = match field.native_type {
    "id"
    | "reference"
    | "string"
    | "textarea"
    | "email"
    | "phone"
    | "url"
    | "picklist"
    | "combobox" => @contract.StringType
    "boolean" => @contract.BooleanType
    "int" | "double" => @contract.NumberType
    _ => return None
  }
  Some(@contract.primitive(kind, nullable=field.nullable))
}

///|
pub fn prepare_read_projection(
  observation : CatalogObservation,
  current : CatalogObservationBinding,
  resource_name : String,
  field_names : Array[String],
  max_soql_bytes : Int,
) -> Result[ReadProjection, ReadProjectionIssue] {
  let resource = match
    catalog_observation_resource(observation, current, resource_name) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  if field_names.is_empty() {
    return Err(EmptyProjection)
  }
  let fields = match require_read_fields(resource, field_names) {
    Ok(value) => value
    Err(issue) => return Err(Requirement(issue))
  }
  let contracts = []
  for field in fields {
    if !field.nullability_confirmed {
      return Err(UnconfirmedNullability(field.name))
    }
    match read_field_contract(field) {
      Some(value) => contracts.push(value)
      None => return Err(UnsupportedReadType(field.name))
    }
  }
  // All identifiers came from the bounded describe projection. Its API-name
  // grammar excludes SOQL punctuation; no caller text is interpolated here.
  let mut bytes = 13 + resource.name.length()
  if max_soql_bytes < bytes {
    return Err(QueryLimit)
  }
  for field in fields {
    if field.name.length() > max_soql_bytes - bytes {
      return Err(QueryLimit)
    }
    bytes += field.name.length()
  }
  if fields.length() - 1 > max_soql_bytes - bytes {
    return Err(QueryLimit)
  }
  bytes += fields.length() - 1
  let sql = StringBuilder()
  sql.write_string("SELECT ")
  for index in 0..<fields.length() {
    if index != 0 {
      sql.write_string(",")
    }
    sql.write_string(fields[index].name)
  }
  sql.write_string(" FROM ")
  sql.write_string(resource.name)
  Ok({
    observation_cid: observation.cid,
    binding: current,
    resource: resource.name,
    fields,
    contracts,
    soql: sql.to_string(),
  })
}

///|
pub fn read_projection_soql(plan : ReadProjection) -> String {
  plan.soql
}

///|
pub fn read_projection_observation(plan : ReadProjection) -> String {
  plan.observation_cid
}

///|
pub fn read_projection_resource(plan : ReadProjection) -> String {
  plan.resource
}

///|
/// Recheck the fields used by this historical plan against a newly observed
/// Resource Catalog. The new sync occurrence and dispatch are independent;
/// the connection, authority, and Site must still be exact. This does not
/// establish a provider-wide point-in-time snapshot or grant query access.
pub fn recheck_read_projection(
  plan : ReadProjection,
  current : CatalogObservation,
) -> Result[Unit, ReadProjectionIssue] {
  let old = plan.binding
  let next = current.binding
  if !catalog_execution_binding_matches(old, next) {
    return Err(ForeignCurrentObservation)
  }
  let resource = match
    catalog_observation_resource(current, next, plan.resource) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  let names = read_projection_fields(plan)
  let fields = match require_read_fields(resource, names) {
    Ok(value) => value
    Err(issue) => return Err(Requirement(issue))
  }
  for index in 0..<fields.length() {
    let before = plan.fields[index]
    let after = fields[index]
    if before.native_type != after.native_type ||
      !after.nullability_confirmed ||
      before.nullable != after.nullable ||
      before.filterable != after.filterable ||
      before.sortable != after.sortable ||
      before.reference_to.length() != after.reference_to.length() {
      return Err(SchemaChanged(before.name))
    }
    for reference in 0..<before.reference_to.length() {
      if before.reference_to[reference] != after.reference_to[reference] {
        return Err(SchemaChanged(before.name))
      }
    }
  }
  Ok(())
}

///|
/// The physical credential use must belong to the same observed authority
/// and Site. The catalog-sync dispatch is historical observation evidence;
/// a query has its own dispatch. Credential control separately verifies the
/// signed query grant and its current use conditions.
pub fn read_projection_matches_site_scope(
  plan : ReadProjection,
  tenant : String,
  principal : String,
  environment : String,
  site_key : String,
  site_generation : Int,
  connector_registration : String,
  connector_revision : String,
  resource_origin : String,
  run_invocation_cid : String,
  dispatch_request_cid : String,
) -> Bool {
  let binding = plan.binding
  binding.tenant == tenant &&
  binding.principal == principal &&
  binding.environment == environment &&
  binding.site_key == site_key &&
  binding.site_generation == site_generation &&
  binding.connector_registration == connector_registration &&
  binding.connector_revision == connector_revision &&
  binding.resource_origin == resource_origin &&
  binding.run_invocation_cid == run_invocation_cid &&
  observation_cid(dispatch_request_cid)
}

///|
pub fn read_projection_fields(plan : ReadProjection) -> Array[String] {
  let names = []
  for field in plan.fields {
    names.push(field.name)
  }
  names
}

///|
/// Bind the exact checked output contracts before any provider value is read.
/// A merely equivalent contract may select this plan, but cannot later attach
/// its identity to values that were admitted under another output owner.
pub fn bind_read_projection_contracts(
  plan : ReadProjection,
  contracts : Array[@contract.Contract],
) -> ReadProjection? {
  if contracts.length() != plan.contracts.length() {
    return None
  }
  for index in 0..<contracts.length() {
    if !(@contract.type_equal(plan.contracts[index], contracts[index], 2) catch {
        _ => false
      }) {
      return None
    }
  }
  Some({ ..plan, contracts: contracts.copy(), })
}
