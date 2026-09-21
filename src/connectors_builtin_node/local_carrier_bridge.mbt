///|
#export_name("strategyModule_local_RelationOutput")
pub fn local_managed_relation_output(
  output : @execution.ManagedCompletedOutput[Int],
) -> @local_driver.LocalManagedAvailableOutput[Int] {
  @local_driver.local_managed_relation_output(output)
}

///|
#export_name("strategyModule_local_CapturedRelationInput")
pub fn local_managed_captured_relation_input() -> @local_driver.LocalManagedAvailableOutput[
  Int,
] {
  @local_driver.local_managed_captured_relation_input()
}

///|
#export_name("strategyModule_local_SuppliedRelationInput")
pub fn local_managed_supplied_relation_input() -> @local_driver.LocalManagedAvailableOutput[
  Int,
] {
  @local_driver.local_managed_supplied_relation_input()
}

///|
#export_name("strategyModule_local_CarrierOutput")
pub fn local_managed_carrier_output(
  output : @execution.CarrierManagedCompletedOutput,
  material : @carrier_runtime.Material,
) -> @local_driver.LocalManagedAvailableOutput[Int] {
  @local_driver.local_managed_carrier_output(output, material)
}

///|
#export_name("strategyModule_local_ManagedCarrierDispatch")
pub fn local_managed_carrier_dispatch(
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  completed : Array[@local_driver.LocalManagedAvailableOutput[Int]],
  output_file_bytes : Int64,
) -> @local_driver.LocalManagedDispatchConfiguration[Int]? raise NodeHostFailure {
  let obligations = match
    @strategy.captured_next_managed_obligations(
      @host_driver.dispatch_driver_run(@builtin.configured_host_driver(setup)),
      @host_driver.compute_host_max_entries(
        @builtin.configured_host_runtime(setup),
      ),
    ) {
    Ok(value) => value
    Err(_) => raise InvalidCommand
  }
  match
    @builtin.dispatch_managed_local_outputs(
      @builtin.configured_host_modules(setup),
      completed,
      obligations,
      output_file_bytes,
    ) {
    Ok(value) => value
    Err(MissingImplementation) => raise InvalidCommand
    Err(Implementation(issue)) => raise Execution(issue)
  }
}

///|
#export_name("strategyModule_local_ManagedUsesProvider")
pub fn local_managed_uses_provider(
  setup : @local_driver.LocalManagedDispatchConfiguration[Int],
) -> Bool {
  @local_driver.local_managed_dispatch_uses_provider(setup)
}
