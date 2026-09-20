///|
/// Prepare Local execution from the exact ordered managed Carrier output set.
/// Other configured implementations keep their Relation-only entrypoints.
pub fn[E] dispatch_managed_local_outputs(
  value : ConfiguredComputeModules[E],
  completed : Array[@binding4.LocalManagedAvailableOutput[Int]],
  obligations : @execution.ManagedObligations,
  output_file_bytes : Int64,
) -> Result[
  @binding4.LocalManagedDispatchConfiguration[Int]?,
  ConfiguredDispatchIssue[E],
] {
  match value.installed_local {
    None => Err(MissingImplementation)
    Some((installed, project, _)) =>
      @binding4.prepare_local_managed_dispatch_with_outputs(
        installed, completed, obligations, output_file_bytes,
      ).map_err(issue => Implementation(project(issue)))
  }
}
