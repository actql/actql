///|
#export_name("clientProgramPrepareHostAccountRead")
pub fn client_program_prepare_host_account_read(
  owner : @client_local_host.ClientHostInitializationPreparation[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[
  @resources.PreparationAccountRead,
  @client_local_host.ClientHostInitializationIssue,
] {
  @client_local_host.prepare_host_initialization_account_read(owner)
}

///|
#export_name("clientProgramPrepareInstalledAccountRead")
pub fn client_program_prepare_installed_account_read(
  owner : @resources.PreparationCapacity[
    ClientLocalPreparationInputOriginal,
    (
      ClientLocalPreparationInputOriginal,
      @source_publication.PreparedPublishedQueryEnvironment,
    ),
  ],
  input : ClientLocalPreparationInputOriginal,
) -> Result[
  @resources.PreparationAccountRead,
  @resources.PreparationCapacityIssue,
] {
  @client_local_host.prepare_installed_account_read(owner, input)
}

///|
#export_name("clientProgramPrepareAccountReadConstruction")
pub fn client_program_prepare_account_read_construction(
  read : @resources.PreparationAccountRead,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, @resources.PreparationCapacityIssue] {
  @resources.prepare_account_read_construction(read, retained, execution)
}

///|
#export_name("clientProgramCompleteAccountReadConstruction")
pub fn client_program_complete_account_read_construction(
  read : @resources.PreparationAccountRead,
) -> Result[Unit, @resources.PreparationCapacityIssue] {
  @resources.complete_account_read_construction(read)
}

///|
#export_name("clientProgramCloseAccountRead")
pub fn client_program_close_account_read(
  read : @resources.PreparationAccountRead,
  acknowledged : Bool,
) -> Result[Bool, @resources.PreparationCapacityIssue] {
  @resources.close_preparation_account_read(read, acknowledged)
}

///|
#export_name("clientProgramAccountReadControlBytes")
pub fn client_program_account_read_control_bytes() -> Int64 {
  let (h, r, w) = @resources.preparation_account_read_control_slots()
  @execution.preparation_representation_cost({
    record_headers: h,
    reference_slots: r,
    scalar_words: w,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
}

///|
fn account_bridge_cost(
  units : @authorization.AccountConfigurationConstructionUnits,
) -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: units.record_headers,
    reference_slots: units.reference_slots,
    scalar_words: units.scalar_words,
    owned_utf16_units: units.owned_utf16_units,
    owned_wire_bytes: units.owned_wire_bytes,
  })
}

///|
#export_name("executionAuthorizationAdmitPrepared")
pub fn execution_authorization_admit_prepared(
  wire : String,
  prepare : (Int64, Int64) -> Bool,
) -> AuthorizationAccount? {
  match
    @authorization.admit_account_configuration_json_prepared(wire, request => {
      guard account_bridge_cost(request.retained) is Some(r) &&
        account_bridge_cost(request.execution) is Some(e) else {
        return false
      }
      prepare(r, e)
    }) {
    None => None
    Some(Ok(configuration)) =>
      Some({ state: Admitted(configuration), issue: "", })
    Some(Err(issue)) =>
      Some({ state: Missing, issue: @debug.to_string(issue), })
  }
}
