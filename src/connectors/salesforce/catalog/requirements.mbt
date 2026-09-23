///|
/// These checks only admit facts from one complete describe response. Site,
/// connection, current authority, and schema revision are checked separately.
pub(all) enum ResourceRequirementIssue {
  DuplicateRequestedField(String)
  FieldUnconfirmed(String)
  ResourceNotQueryable
  ResourceNotCreateable
  ResourceNotUpdateable
  FieldNotCreateable(String)
  FieldNotUpdateable(String)
  ExternalIdNotUnique(String)
} derive(Eq, Debug)

///|
fn require_distinct_fields(
  resource : ResourceMetadata,
  names : Array[String],
) -> Result[Array[FieldMetadata], ResourceRequirementIssue] {
  let selected = []
  let seen : Map[String, Bool] = Map([])
  for name in names {
    if seen.contains(name) {
      return Err(DuplicateRequestedField(name))
    }
    seen[name] = true
    guard described_field(resource, name) is Some(field) else {
      // A field omitted by field-level security is not proven absent.
      return Err(FieldUnconfirmed(name))
    }
    selected.push(field)
  }
  Ok(selected)
}

///|
/// Reading is allowed only for fields present in the exact described view.
/// This does not authorize a query or declare filter semantic equivalence.
pub fn require_read_fields(
  resource : ResourceMetadata,
  names : Array[String],
) -> Result[Array[FieldMetadata], ResourceRequirementIssue] {
  if !resource.queryable {
    return Err(ResourceNotQueryable)
  }
  require_distinct_fields(resource, names)
}

///|
pub fn require_create_fields(
  resource : ResourceMetadata,
  names : Array[String],
) -> Result[Array[FieldMetadata], ResourceRequirementIssue] {
  if !resource.createable {
    return Err(ResourceNotCreateable)
  }
  let fields = match require_distinct_fields(resource, names) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for field in fields {
    if !field.createable {
      return Err(FieldNotCreateable(field.name))
    }
  }
  Ok(fields)
}

///|
pub fn require_update_fields(
  resource : ResourceMetadata,
  names : Array[String],
) -> Result[Array[FieldMetadata], ResourceRequirementIssue] {
  if !resource.updateable {
    return Err(ResourceNotUpdateable)
  }
  let fields = match require_distinct_fields(resource, names) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for field in fields {
    if !field.updateable {
      return Err(FieldNotUpdateable(field.name))
    }
  }
  Ok(fields)
}

///|
/// External-ID targeting alone does not prove once-only side effects or an
/// exact historical write outcome. Both unique and externalId are required.
pub fn require_unique_external_id(
  resource : ResourceMetadata,
  name : String,
) -> Result[FieldMetadata, ResourceRequirementIssue] {
  let fields = match require_distinct_fields(resource, [name]) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let field = match fields {
    [field] => field
    _ => return Err(FieldUnconfirmed(name))
  }
  if !field.external_id || !field.unique {
    return Err(ExternalIdNotUnique(name))
  }
  Ok(field)
}
