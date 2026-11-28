///|
/// The full Node product selects the portable installed carrier families.
/// The RelA product has a distinct selection and links no family provider.
fn selected_sga_supported() -> Bool {
  @installed_families.has_graph()
}

///|
fn selected_graph_supported() -> Bool {
  @installed_families.has_graph()
}

///|
fn installed_client_family_providers(
  capacity : @execution.ExecutionCapacity,
) -> Array[@local.ManagedProvider] {
  @installed_families.providers(capacity)
}

///|
fn installed_client_family_provider_count() -> Int {
  @installed_families.provider_count()
}

///|
fn selected_client_sga_providers(
  generated : Array[@execution.GeneratedSequence],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Array[@local.ManagedProvider]? {
  @installed_families.graph_providers(generated, execution, measurement)
}
