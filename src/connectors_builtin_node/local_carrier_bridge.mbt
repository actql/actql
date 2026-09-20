///|
#export_name("strategyModule_local_RelationOutput")
pub fn local_managed_relation_output(
  output : @execution.ManagedCompletedOutput[Int],
) -> @binding10.LocalManagedAvailableOutput[Int] {
  @binding10.local_managed_relation_output(output)
}

///|
#export_name("strategyModule_local_CarrierOutput")
pub fn local_managed_carrier_output(
  output : @execution.CarrierManagedCompletedOutput,
  material : @carrier_runtime.Material,
) -> @binding10.LocalManagedAvailableOutput[Int] {
  @binding10.local_managed_carrier_output(output, material)
}

///|
#export_name("strategyModule_local_ManagedCarrierDispatch")
pub fn local_managed_carrier_dispatch(
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  completed : Array[@binding10.LocalManagedAvailableOutput[Int]],
  output_file_bytes : Int64,
) -> @binding10.LocalManagedDispatchConfiguration[Int]? raise NodeHostFailure {
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
