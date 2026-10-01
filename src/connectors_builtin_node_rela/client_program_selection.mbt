///|
/// The RelA-only package cannot select an SGA capability or provider.
fn selected_sga_supported() -> Bool {
  false
}

///|
fn selected_property_graph_supported() -> Bool {
  false
}

///|
fn installed_client_family_providers(
  _capacity : @execution.ExecutionCapacity,
) -> Array[@local.ManagedProvider] {
  []
}

///|
fn selected_client_sga_providers(
  _generated : Array[@execution.GeneratedSequence],
  _execution : @execution.SequenceExecutionLimits,
  _measurement : @execution.FixedInputGuardMeasureLimits,
) -> Array[@local.ManagedProvider]? {
  Some([])
}
