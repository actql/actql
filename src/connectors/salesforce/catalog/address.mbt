///|
/// These are the documented REST Address property roles. A suffix only selects
/// a role after the original Describe positively associates the component with
/// this parent. Standard and custom API names remain unchanged in the plan.
let address_component_roles : ReadOnlyArray[(String, String)] = [
  ("City", "city"),
  ("Country", "country"),
  ("CountryCode", "countryCode"),
  ("GeocodeAccuracy", "geocodeAccuracy"),
  ("Latitude", "latitude"),
  ("Longitude", "longitude"),
  ("PostalCode", "postalCode"),
  ("State", "state"),
  ("StateCode", "stateCode"),
  ("Street", "street"),
]

///|
fn address_component_role(name : String) -> String? {
  for (suffix, role) in address_component_roles {
    if name.has_suffix(suffix) || name.has_suffix("__" + suffix + "__s") {
      return Some(role)
    }
  }
  None
}

///|
fn address_components(
  parent : FieldMetadata,
  fields : Array[FieldMetadata],
) -> Array[(String, FieldMetadata)]? {
  if parent.native_type != "address" ||
    !parent.nullability_confirmed ||
    parent.compound_field_name is Some(_) {
    return None
  }
  let components : Map[String, FieldMetadata] = Map([])
  for field in fields {
    if field.compound_field_name != Some(parent.name) {
      continue
    }
    guard address_component_role(field.name) is Some(role) &&
      field.nullability_confirmed &&
      !components.contains(role) else {
      return None
    }
    if role == "latitude" || role == "longitude" {
      if field.native_type != "double" || described_decimal(field) is None {
        return None
      }
    } else if field.native_type != "string" &&
      field.native_type != "textarea" &&
      field.native_type != "picklist" {
      return None
    }
    components[role] = field
  }
  // Neither a missing component nor a guessed label/code lookup supplies
  // this contract. Country/state and ISO codes remain distinct original data.
  for
    role in [
      "city", "geocodeAccuracy", "latitude", "longitude", "postalCode", "street",
    ] {
    if !components.contains(role) {
      return None
    }
  }
  let labels = components.contains("country") && components.contains("state")
  let codes = components.contains("countryCode") &&
    components.contains("stateCode")
  if (!labels && !codes) ||
    components.contains("country") != components.contains("state") ||
    components.contains("countryCode") != components.contains("stateCode") {
    return None
  }
  let ordered = []
  for (_, role) in address_component_roles {
    if components.get(role) is Some(original) {
      ordered.push((role, original))
    }
  }
  Some(ordered)
}

///|
fn compound_read_components(
  parent : FieldMetadata,
  fields : Array[FieldMetadata],
) -> Array[(String, FieldMetadata)]? {
  match parent.native_type {
    "location" => geolocation_components(parent, fields)
    "address" => address_components(parent, fields)
    _ => None
  }
}

///|
fn address_contract(
  parent : FieldMetadata,
  components : Array[(String, FieldMetadata)],
) -> @contract.Contract? {
  if parent.native_type != "address" || components.is_empty() {
    return None
  }
  let fields = []
  let mut name_bytes = 0
  for (role, component) in components {
    guard read_field_contract(component) is Some(contract) else { return None }
    fields.push((role, contract))
    // Every role above is ASCII; this is the same exact UTF-8 name bound.
    name_bytes += role.length()
  }
  match
    @contract.object_contract(
      fields,
      nullable=parent.nullable,
      max_fields=fields.length(),
      max_name_bytes=name_bytes,
    ) {
    Ok(contract) => Some(contract)
    Err(_) => None
  }
}
