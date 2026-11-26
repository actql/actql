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

///|
#export_name("clientProgramAdvanceRelationSampleStartControl")
pub fn client_program_advance_relation_sample_start_control(
  profile : @client_local_host.ClientCheckedRelationSampleProfile,
  owner : @client_local_host.ClientInstalledManagedRun,
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  account : AuthorizationAccount,
  principal : String,
  connection : String,
  start_acknowledged : Bool,
) -> Result[Unit, @client_local_host.InstalledRelationSampleStartIssue] {
  guard account.state is @authorization.Admitted(original) else {
    return Err(
      @client_local_host.SampleStartControl(@strategy.AuthorizationMismatch),
    )
  }
  @client_local_host.advance_installed_relation_sample_start_control(
    profile,
    owner,
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(setup)),
    original,
    principal,
    connection,
    start_acknowledged,
  )
}

///|
#export_name("clientProgramAdvanceRelationSampleDebugEntry")
pub fn client_program_advance_relation_sample_debug_entry(
  profile : @client_local_host.ClientCheckedRelationSampleProfile,
  owner : @client_local_host.ClientInstalledManagedRun,
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  account : AuthorizationAccount,
  principal : String,
  connection : String,
  command : String,
  revision : Int,
) -> Result[Unit, @client_local_host.InstalledRelationSampleStartIssue] {
  guard account.state is @authorization.Admitted(original) else {
    return Err(
      @client_local_host.SampleStartControl(@strategy.AuthorizationMismatch),
    )
  }
  let selected : @client_local_host.InstalledRelationSampleEntryCommand = match
    command {
    "prepare" if revision == 0 => PrepareEntry
    "step" if revision > 0 => ResumeEntryStep(revision)
    "terminal" if revision > 0 => ResumeEntryTerminal(revision)
    _ => return Err(@client_local_host.SampleStartRequiresControl)
  }
  @client_local_host.advance_installed_relation_sample_debug_entry(
    profile,
    owner,
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(setup)),
    original,
    principal,
    connection,
    selected,
  )
}

///|
#export_name("clientProgramRelationSampleDebugEntryStep")
pub fn client_program_relation_sample_debug_entry_step(
  profile : @client_local_host.ClientCheckedRelationSampleProfile,
  owner : @client_local_host.ClientInstalledManagedRun,
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> String {
  @client_local_host.installed_relation_sample_debug_entry_step(
    profile,
    owner,
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(setup)),
  )
}

///|
#export_name("clientProgramRelationSampleDebugEntryRunnable")
pub fn client_program_relation_sample_debug_entry_runnable(
  profile : @client_local_host.ClientCheckedRelationSampleProfile,
  owner : @client_local_host.ClientInstalledManagedRun,
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  start_revision : Int,
) -> Result[Bool, @client_local_host.InstalledRelationSampleStartIssue] {
  @client_local_host.installed_relation_sample_debug_entry_runnable(
    profile,
    owner,
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(setup)),
    start_revision,
  )
}

///|
#export_name("clientProgramRelationSampleDebugTaskPause")
pub fn client_program_relation_sample_debug_task_pause(
  profile : @client_local_host.ClientCheckedRelationSampleProfile,
  owner : @client_local_host.ClientInstalledManagedRun,
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  start_revision : Int,
) -> Result[
  (Int, String, String, Int),
  @client_local_host.InstalledRelationSampleStartIssue,
] {
  @client_local_host.installed_relation_sample_debug_task_pause(
    profile,
    owner,
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(setup)),
    start_revision,
  )
}

///|
#export_name("clientProgramRelationSampleDebugNextInput")
pub fn client_program_relation_sample_debug_next_input(
  profile : @client_local_host.ClientCheckedRelationSampleProfile,
  owner : @client_local_host.ClientInstalledManagedRun,
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  start_revision : Int,
  control_revision : Int,
  pause_generation : Int,
  next_step_id : String,
  input : Int,
  max_work : Int,
) -> Result[(String, String, String, Int, Int)?, String] {
  @client_local_host.installed_relation_sample_debug_next_input(
    profile,
    owner,
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(setup)),
    start_revision,
    control_revision,
    pause_generation,
    next_step_id,
    input,
    max_work,
  ).map_err(issue => {
    match issue {
      @client_local_host.NextInputForeignOriginal => "foreign"
      @client_local_host.NextInputStalePause => "stale"
      @client_local_host.NextInputWorkLimit => "capacity"
    }
  })
}

///|
#export_name("clientProgramRelationSampleDebugResumeAllowed")
pub fn client_program_relation_sample_debug_resume_allowed(
  profile : @client_local_host.ClientCheckedRelationSampleProfile,
  owner : @client_local_host.ClientInstalledManagedRun,
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  account : AuthorizationAccount,
  principal : String,
  connection : String,
) -> Bool {
  guard account.state is @authorization.Admitted(original) else { return false }
  @client_local_host.installed_relation_sample_debug_resume_allowed(
    profile,
    owner,
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(setup)),
    original,
    principal,
    connection,
  )
}

///|
#export_name("clientProgramResumeRelationSampleDebugTask")
pub fn client_program_resume_relation_sample_debug_task(
  profile : @client_local_host.ClientCheckedRelationSampleProfile,
  owner : @client_local_host.ClientInstalledManagedRun,
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  account : AuthorizationAccount,
  principal : String,
  connection : String,
  start_revision : Int,
  control_revision : Int,
  step_id : String,
  next_step_id : String,
  committed_generation : Int,
  step : Bool,
) -> Result[Unit, @client_local_host.InstalledRelationSampleStartIssue] {
  guard account.state is @authorization.Admitted(original) else {
    return Err(
      @client_local_host.SampleStartControl(@strategy.AuthorizationMismatch),
    )
  }
  @client_local_host.resume_installed_relation_sample_debug_task(
    profile,
    owner,
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(setup)),
    original,
    principal,
    connection,
    start_revision,
    control_revision,
    step_id,
    next_step_id,
    committed_generation,
    step,
  )
}
