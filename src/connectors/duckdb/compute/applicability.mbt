///|
/// Connector-local applicability and diagnostic vocabulary. Common planning
/// treats these reasons as opaque explanations, not provider status branches.
pub fn duckdb_compute_static_rejection(
  owner : @lower.BoundPrepared,
  capacity : @connector.FixedComputeCapacity,
  compilation : @duckdb.NativeQueryLimits,
) -> String? {
  if capacity.common_fragment is Some(_) {
    return Some("unsupported_common_fragment")
  }
  match check_duckdb_compute_static(owner, compilation) {
    Ok(_) => None
    Err(UnsupportedPredicate) => Some("unsupported_predicate")
    Err(UnsupportedShape) => Some("unsupported_shape")
    Err(UnsupportedField) => Some("unsupported_field")
    Err(Parameter(_)) => Some("unsupported_parameter_type")
    Err(_) => Some("native_compilation_limits_or_contract")
  }
}

///|
pub fn duckdb_resident_static_rejection(
  owner : @lower.BoundPrepared,
) -> String? {
  guard @lower.preparation_output_target(@lower.bound_preparation(owner))
    is Some(target) else {
    return Some("unsupported_resident_output_names")
  }
  match @duckdb.check_resident_output_static(owner, target) {
    Ok(_) => None
    Err(_) => Some("unsupported_resident_output_names")
  }
}
