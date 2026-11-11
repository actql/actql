///|
/// Exact field counts and primitive metadata text of this recovered historical
/// observation. Describe admission already checked the complete original body;
/// dimensions grant neither a declaration, current permission nor capacity.
pub fn catalog_observation_construction_dimensions(
  observation : CatalogObservation,
) -> Array[Int] {
  let result = []
  for outcome in observation.outcomes {
    match outcome {
      Described(resource) => {
        let mut units = 0
        for field in resource.fields {
          units += field.name.length() + field.native_type.length()
          for reference in field.reference_to {
            units += reference.length()
          }
          if field.compound_field_name is Some(name) {
            units += name.length()
          }
        }
        result.push(resource.fields.length())
        result.push(units)
      }
      _ => {
        result.push(0)
        result.push(0)
      }
    }
  }
  result
}
