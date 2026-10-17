///|
/// Select the actual components of this original Describe parent. Suffixes
/// identify the documented component role only after the parent is confirmed.
/// A same-looking field name alone supplies no association or digit contract.
fn geolocation_components(
  parent : FieldMetadata,
  fields : Array[FieldMetadata],
) -> Array[(String, FieldMetadata)]? {
  if parent.native_type != "location" ||
    !parent.nullability_confirmed ||
    parent.compound_field_name is Some(_) {
    return None
  }
  let mut latitude = None
  let mut longitude = None
  for field in fields {
    if field.compound_field_name != Some(parent.name) {
      continue
    }
    if field.native_type != "double" ||
      !field.nullability_confirmed ||
      described_decimal(field) is None {
      return None
    }
    if field.name.has_suffix("Latitude") ||
      field.name.has_suffix("__Latitude__s") {
      if latitude is Some(_) {
        return None
      }
      latitude = Some(field)
    } else if field.name.has_suffix("Longitude") ||
      field.name.has_suffix("__Longitude__s") {
      if longitude is Some(_) {
        return None
      }
      longitude = Some(field)
    } else {
      return None
    }
  }
  guard latitude is Some(latitude) && longitude is Some(longitude) else {
    return None
  }
  Some([("latitude", latitude), ("longitude", longitude)])
}

///|
fn geolocation_contract(
  parent : FieldMetadata,
  components : Array[(String, FieldMetadata)],
) -> @contract.Contract? {
  if parent.native_type != "location" || components.length() != 2 {
    return None
  }
  let fields = []
  for (name, component) in components {
    guard described_decimal(component) is Some((precision, scale)) &&
      @contract.decimal_contract(precision, scale, nullable=component.nullable)
      is Some(contract) else {
      return None
    }
    fields.push((name, contract))
  }
  match
    @contract.object_contract(
      fields,
      nullable=parent.nullable,
      max_fields=components.length(),
      max_name_bytes="latitude".length() + "longitude".length(),
    ) {
    Ok(contract) => Some(contract)
    Err(_) => None
  }
}
