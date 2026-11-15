///|
#export_name("clientProgramInstalledEffectResultWorkPrepare")
pub fn client_program_installed_effect_result_work_prepare(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  source : ClientLocalEffectHost,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.prepare_installed_effect_result_publication_work(
    owner,
    prepared,
    request,
    plan,
    source.run,
  )
}

///|
#export_name("clientProgramInstalledEffectResultAdvance")
pub fn client_program_installed_effect_result_advance(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  source : ClientLocalEffectHost,
  value : StrategyHostResultTransformation,
  quantum : Int,
) -> Result[
  (Bool, Int),
  @client_local_host.ClientInstalledEffectResultPublicationIssue,
] {
  if !value.open {
    return Err(
      @client_local_host.ClientInstalledEffectResultPublicationIssue::Operation(
        ForeignOriginal,
      ),
    )
  }
  @client_local_host.advance_installed_effect_result_publication(
    owner,
    prepared,
    request,
    plan,
    source.run,
    value.core,
    quantum,
  )
}
