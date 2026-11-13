///|
#export_name("clientProgramInstalledManagedSourceOccurrence")
pub fn client_program_installed_managed_source_occurrence(
  value : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  slot : Int,
) -> Result[(Int, Int, Int), @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.installed_managed_source_occurrence(
    value, prepared, request, slot,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedSourceOccurrence")
pub fn client_program_installed_effect_managed_source_occurrence(
  value : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  slot : Int,
) -> Result[(Int, Int, Int), @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.installed_effect_managed_source_occurrence(
    value, prepared, request, slot,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedPlanSourceCoordinates")
pub fn client_program_installed_effect_managed_plan_source_coordinates(
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  Array[Array[Int]],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  let selected = match
    @client_local_host.prepared_installed_effect_source_occurrences(
      plan, prepared, request,
    ) {
    Err(issue) => return Err(issue)
    Ok(None) => return Ok([])
    Ok(Some(selected)) => selected
  }
  Ok(
    Array::makei(
      @publication_host.client_direct_acquisition_occurrence_count(selected),
      slot => {
        let (stage, input, task) = @publication_host.client_direct_acquisition_occurrence_at(
          selected, slot,
        ).unwrap()
        [stage, input, slot, task]
      },
    ),
  )
}

///|
#export_name("clientProgramInstalledEffectManagedRunCheck")
pub fn client_program_installed_effect_managed_run_check(
  value : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.check_installed_effect_managed_run(
    value, prepared, request,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedRunPrepareLedger")
pub fn client_program_installed_effect_managed_run_prepare_ledger(
  value : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  capacities : Array[@client_local_host.ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[
  @resources.Ledger,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_effect_managed_run_ledger(
    value, prepared, request, capacities, transport_bytes, transport_execution_bytes,
    installed_contracts, values_body, fragment_body, ordered_body,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedRunRequirements")
pub fn client_program_installed_effect_managed_run_requirements(
  prepared : @publication_host.PreparedClientEffectComputation,
  declarations : Array[@client_row_source_host.RowDeclaration],
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[Array[Int64], @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.installed_effect_managed_run_requirements(
    prepared, declarations, query_contract_body, evidence_contract_body, transport_bytes,
    transport_execution_bytes, installed_contracts, values_body, fragment_body, ordered_body,
  )
}
