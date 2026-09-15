///|
struct NumericImplementation {
  registration : @connector.CapabilityRegistration
}

///|
/// Rebuild-time module contribution; installation creates no resources and has
/// no Acquisition entrypoint. Resource bindings are not registration names.
pub fn numeric_bundle(
  name : String,
) -> @connector.CapabilityBundle[Unit, NumericImplementation] {
  {
    name,
    acquisition: None,
    fixed_compute: Some(fn(_registry, registration) { { registration, } }),
  }
}

///|
pub fn propose_numeric_compute(
  implementation : NumericImplementation,
  request : @connector.FixedComputeRequest,
  max_entries : Int,
  max_name_bytes : Int,
  expressions : @lower.ExpressionLimits,
  work_slots : Int,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : @connector.QueryQuantities,
) -> Result[@connector.PreparedCompute[NumericCompute], PlanIssue] {
  offer_numeric_compute(
    implementation.registration,
    request,
    max_entries,
    max_name_bytes,
    expressions,
    work_slots,
    estimates,
    quantities,
  )
}
