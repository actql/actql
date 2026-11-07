///|
/// Open only the exact Direct occurrence already retained on the same Plan.
#export_name("clientProgramInstalledManagedRunSourceReadAt")
pub fn client_program_installed_managed_run_source_read_at(
  value : @client_local_host.ClientInstalledManagedRun,
  stage : Int,
  input : Int,
  task : Int,
) -> Result[
  @client_local_host.ClientInstalledSourceRead,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_installed_managed_run_source_read_at(
    value, stage, input, task,
  )
}
