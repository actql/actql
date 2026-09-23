///|
pub(all) enum WriteOperation {
  WriteCreate
  WriteUpdateById
  WriteUpsertByExternalId(String)
} derive(Eq, Debug)

///|
pub(all) enum WriteProjectionIssue {
  Observation(CatalogObservationIssue)
  Requirement(ResourceRequirementIssue)
  FieldLimit
  EmptyUpdate
  TargetFieldInBody(String)
  UnconfirmedNullability(String)
  UnsupportedWriteType(String)
  ForeignCurrentObservation
  SchemaChanged(String)
} derive(Eq, Debug)

///|
/// A pure candidate from one exact Resource Catalog observation. This is not
/// an Effect preview, current grant, write attempt, or dispatch permission.
pub struct WriteProjection {
  observation_cid : String
  binding : CatalogObservationBinding
  resource : String
  operation : WriteOperation
  field_names : Array[String]
  fields : Array[FieldMetadata]
  external_target : FieldMetadata?
}

///|
/// This is the scalar subset with an exact JSON representation. Salesforce
/// can still reject a value under constraints not proved by this projection.
fn write_field_type_supported(native_type : String) -> Bool {
  match native_type {
    "id"
    | "reference"
    | "string"
    | "textarea"
    | "email"
    | "phone"
    | "url"
    | "picklist"
    | "combobox"
    | "boolean"
    | "int"
    | "double" => true
    _ => false
  }
}

///|
fn write_target_type_supported(native_type : String) -> Bool {
  match native_type {
    "string" | "email" | "int" => true
    _ => false
  }
}

///|
pub fn prepare_write_projection(
  observation : CatalogObservation,
  current : CatalogObservationBinding,
  resource_name : String,
  operation : WriteOperation,
  field_names : Array[String],
  max_fields : Int,
) -> Result[WriteProjection, WriteProjectionIssue] {
  if max_fields < 0 || field_names.length() > max_fields {
    return Err(FieldLimit)
  }
  let resource = match
    catalog_observation_resource(observation, current, resource_name) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  let admitted = match operation {
    WriteCreate => require_create_fields(resource, field_names)
    WriteUpdateById => {
      if field_names.is_empty() {
        return Err(EmptyUpdate)
      }
      require_update_fields(resource, field_names)
    }
    WriteUpsertByExternalId(target) => {
      if field_names.is_empty() {
        return Err(EmptyUpdate)
      }
      if field_names.contains(target) {
        return Err(TargetFieldInBody(target))
      }
      require_upsert_fields(resource, target, field_names)
    }
  }
  let fields = match admitted {
    Ok(value) => value
    Err(issue) => return Err(Requirement(issue))
  }
  for field in fields {
    if !field.nullability_confirmed {
      return Err(UnconfirmedNullability(field.name))
    }
    if !write_field_type_supported(field.native_type) {
      return Err(UnsupportedWriteType(field.name))
    }
  }
  let external_target = match operation {
    WriteUpsertByExternalId(name) =>
      match require_unique_external_id(resource, name) {
        Ok(field) => {
          if !write_target_type_supported(field.native_type) {
            return Err(UnsupportedWriteType(field.name))
          }
          Some(field)
        }
        Err(issue) => return Err(Requirement(issue))
      }
    _ => None
  }
  Ok({
    observation_cid: catalog_observation_identity(observation),
    binding: current,
    resource: resource.name,
    operation,
    field_names: field_names.copy(),
    fields,
    external_target,
  })
}

///|
fn same_write_field(before : FieldMetadata, after : FieldMetadata) -> Bool {
  if before.name != after.name ||
    before.native_type != after.native_type ||
    before.nullable != after.nullable ||
    before.nullability_confirmed != after.nullability_confirmed ||
    before.defaulted_on_create != after.defaulted_on_create ||
    before.default_on_create_confirmed != after.default_on_create_confirmed ||
    before.createable != after.createable ||
    before.updateable != after.updateable ||
    before.filterable != after.filterable ||
    before.sortable != after.sortable ||
    before.external_id != after.external_id ||
    before.unique != after.unique ||
    before.case_sensitive != after.case_sensitive ||
    before.reference_to.length() != after.reference_to.length() {
    return false
  }
  for index in 0..<before.reference_to.length() {
    if before.reference_to[index] != after.reference_to[index] {
      return false
    }
  }
  true
}

///|
/// Re-admit current field constraints before a write preview or apply. A
/// historical Catalog observation is not current permission or schema proof.
/// Target-state guards and the scoped mutation grant remain separate duties.
pub fn recheck_write_projection(
  plan : WriteProjection,
  current : CatalogObservation,
) -> Result[Unit, WriteProjectionIssue] {
  if !catalog_execution_binding_matches(plan.binding, current.binding) {
    return Err(ForeignCurrentObservation)
  }
  let refreshed = match
    prepare_write_projection(
      current,
      current.binding,
      plan.resource,
      plan.operation,
      plan.field_names,
      plan.field_names.length(),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for index in 0..<plan.fields.length() {
    if !same_write_field(plan.fields[index], refreshed.fields[index]) {
      return Err(SchemaChanged(plan.fields[index].name))
    }
  }
  match (plan.external_target, refreshed.external_target) {
    (Some(before), Some(after)) =>
      if !same_write_field(before, after) {
        Err(SchemaChanged(before.name))
      } else {
        Ok(())
      }
    (None, None) => Ok(())
    _ => Err(SchemaChanged(plan.resource))
  }
}

///|
pub fn write_projection_observation(value : WriteProjection) -> String {
  value.observation_cid
}

///|
pub fn write_projection_resource(value : WriteProjection) -> String {
  value.resource
}

///|
pub fn write_projection_operation(value : WriteProjection) -> WriteOperation {
  value.operation
}

///|
pub fn write_projection_fields(value : WriteProjection) -> Array[String] {
  value.field_names.copy()
}

///|
pub fn write_projection_matches_binding(
  value : WriteProjection,
  current : CatalogObservationBinding,
) -> Bool {
  value.binding == current
}
