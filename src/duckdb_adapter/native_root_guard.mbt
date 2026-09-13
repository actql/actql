///|
pub(all) enum NativeRootGuardIssue {
  InvalidLimit
  UnsupportedCeiling
}

///|
/// A static eligibility witness for this exact compiled comparison. It proves
/// only the demanded root byte ceiling, not scan admission, execution, work,
/// lifetime, source authority or completion. No row is evaluated to create it.
struct NativeRootGuard {
  query : NativeQuery
  ceiling : Int
  bound : Int
}

///|
/// The compiler admits one eager primitive comparison, with no lazy branches
/// or arithmetic. Its root is true (4 bytes), false (5), or null (4). A bound
/// NULL RHS makes the comparison root NULL for every admitted input value.
/// Smaller ceilings make this native realization ineligible, not the language
/// or the separately offered Local residual. Do not retry after execution.
pub fn prepare_native_root_guard(
  query : NativeQuery,
  max_value_bytes : Int,
) -> Result[NativeRootGuard, NativeRootGuardIssue] {
  if max_value_bytes < 0 {
    return Err(InvalidLimit)
  }
  let null_rhs = match query.parameter.value {
    Null | Admitted(@admitted.Null) => true
    _ => false
  }
  let bound = if null_rhs { 4 } else { 5 }
  if max_value_bytes < bound {
    return Err(UnsupportedCeiling)
  }
  Ok({ query, ceiling: max_value_bytes, bound, })
}

///|
pub fn native_root_guard_matches(
  witness : NativeRootGuard,
  query : NativeQuery,
  max_value_bytes : Int,
) -> Bool {
  physical_equal(witness.query, query) && witness.ceiling == max_value_bytes
}

///|
pub fn native_root_guard_bound(witness : NativeRootGuard) -> Int {
  witness.bound
}
