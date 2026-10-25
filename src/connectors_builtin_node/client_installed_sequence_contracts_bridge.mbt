///|
#export_name("clientPrepareInstalledSequenceContracts")
pub fn client_prepare_installed_sequence_contracts(
  registry : String, values : String, fragment : String?, ordered : String?,
) -> Result[@client_local_host.ClientInstalledSequenceContracts,@client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.prepare_installed_sequence_contracts(registry,values,fragment,ordered)
}

///|
#export_name("clientProgramPrepareInstalledManagedSourceFreeWithContracts")
pub fn client_program_prepare_installed_managed_source_free_with_contracts(
  prepared : @publication_host.PreparedClientProgram,
  original : @client_local_host.ClientInstalledSequenceContracts,
  values : String, fragment : String?, ordered : String?,
) -> Result[@client_local_host.ClientInstalledManagedSourceFreePreparation,@client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.prepare_installed_managed_source_free_with_contracts(
    prepared,original,values,fragment,ordered,
  )
}
