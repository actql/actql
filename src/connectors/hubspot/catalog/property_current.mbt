///|
/// Recheck the original complete observation through its own metadata type.
/// Derived equality includes every PropertyMetadata field, including future
/// additions. Property listing order, labels and unselected transport metadata do not
/// replace the admitted property's meaning. This is not credential/current
/// permission or an acquisition/publication ACK.
pub fn recheck_property_catalog(
  original : PropertyCatalog,
  current : PropertyCatalog,
  max_properties : Int,
) -> Result[Unit, PropertyIssue] {
  if max_properties <= 0 {
    return Err(InvalidLimits)
  }
  if original.properties.length() > max_properties ||
    current.properties.length() > max_properties {
    return Err(BudgetExceeded)
  }
  if original.object_type != current.object_type ||
    original.properties.length() != current.properties.length() {
    return Err(ForeignCatalog)
  }
  let by_name : Map[String, PropertyMetadata] = Map([])
  for property in original.properties {
    by_name[property.name] = property
  }
  for property in current.properties {
    guard by_name.get(property.name) is Some(previous) && previous == property else {
      return Err(ForeignCatalog)
    }
  }
  Ok(())
}
