///|
pub(all) suberror NodeHostFailure {
  Diagnostics(@host_driver.ComputeDiagnosticsIssue)
  Dispatch(@host_driver.ComputeHostIssue[@strategy.RunIssue])
  Execution(@strategy.RunIssue)
  InvalidCommand
  Encoding(@encode.EncodeFailure)
}

///|
#export_name("strategyHostNext")
pub fn strategy_host_next(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> @host_driver.PreparedTaskDispatch? raise NodeHostFailure {
  match @host_driver.prepare_next_compute_task(@builtin.configured_host_runtime(host), ()) {
    Ok(value) => value
    Err(issue) => raise Dispatch(issue)
  }
}

///|
/// Producer indexes needed by the next managed task in exact input-port order.
/// This exposes topology only; opaque completions are checked by preparation.
#export_name("strategyHostManagedProducers")
pub fn strategy_host_managed_producers(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> Array[Int] {
  @strategy.captured_next_managed_producers(
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
  )
}

///|
/// Compatibility accessor for installed unary implementations.
#export_name("strategyHostManagedProducer")
pub fn strategy_host_managed_producer(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> Int {
  @strategy.captured_next_managed_producer(
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
  ).unwrap_or(-1)
}

///|
#export_name("strategyHostReleasableManagedProducers")
pub fn strategy_host_releasable_managed_producers(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> Array[Int] {
  @strategy.captured_releasable_managed_producers(
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
  )
}

///|
#export_name("strategyHostNextTask")
pub fn strategy_host_next_task(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> Int {
  @strategy.next_captured_task(
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
  ).unwrap_or(-1)
}

///|
/// Install the trusted Host policy before connector preparation. These flags
/// strengthen checked consumer and publication requirements; they are not
/// Program-controlled optimization hints.
#export_name("strategyHostConfigureManagedIdentity")
pub fn strategy_host_configure_managed_identity(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  publish_checked_results : Bool,
  publication : Bool,
  consumer : Bool,
  host_policy : Bool,
) -> Bool {
  @strategy.configure_captured_managed_identity_policy(
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
    publish_checked_results,
    publication,
    consumer,
    host_policy,
  )
}

///|
/// Common scheduler derivation. Connector implementations receive this exact
/// opaque obligation set and cannot substitute their own default profile.
#export_name("strategyHostManagedObligations")
pub fn strategy_host_managed_obligations(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> @execution.ManagedObligations raise NodeHostFailure {
  match
    @strategy.captured_next_managed_obligations(
      @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
      @host_driver.compute_host_max_entries(
        @builtin.configured_host_runtime(host),
      ),
    ) {
    Ok(value) => value
    Err(_) => raise InvalidCommand
  }
}

///|
#export_name("strategyHostManagedRequiresLogicalIdentity")
pub fn strategy_host_managed_requires_logical_identity(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> Bool raise NodeHostFailure {
  @execution.managed_obligations_require_logical_identity(
    strategy_host_managed_obligations(host),
  )
}

///|
#export_name("strategyHostRegistrationSelectionKey")
pub fn strategy_host_registration_selection_key(
  registration : @connector.CapabilityRegistration,
) -> String {
  @connector.capability_registration_selection_key(registration)
}

///|
/// Commit the common Host's registration-order-independent managed choice.
/// This is not execution start, reservation, or material access.
#export_name("strategyHostSelectManagedRegistration")
pub fn strategy_host_select_managed_registration(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  task : Int,
  registration : @connector.CapabilityRegistration,
) -> Bool {
  @strategy.select_captured_managed_registration(
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
    task,
    registration,
  ) is Ok(_)
}

///|
#export_name("strategyHostManagedOutputMatches")
pub fn strategy_host_managed_output_matches(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  task : Int,
  output : @execution.ManagedCompletedOutput[Int],
) -> Bool {
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(host),
  )
  guard @strategy.captured_task_target(run, task) is Some(target) else {
    return false
  }
  @strategy.captured_managed_task_output_matches(run, task, target, output)
}

///|
#export_name("strategyHostManagedInputMatchesMaterial")
pub fn strategy_host_managed_input_matches_material(
  input : @execution.ManagedProducerRead[Int],
  material : @execution.ManagedRetainedOutput[Int],
) -> Bool {
  @execution.managed_producer_read_matches_material(input, material)
}

///|
#export_name("strategyHostModules")
pub fn strategy_host_modules(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> Array[String] {
  @builtin.configured_compute_module_keys(@builtin.configured_host_modules(host))
}

///|
#export_name("strategyHostTask")
pub fn strategy_host_task(task : @host_driver.PreparedTaskDispatch) -> Int {
  @host_driver.prepared_task_index(task)
}

///|
#export_name("strategyHostTaskCapacity")
pub fn strategy_host_task_capacity(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  task : Int,
) -> Array[Int64] raise NodeHostFailure {
  guard
    @strategy.strategy_task_envelope(
      @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
      task,
    ) is Some(capacity)
  else {
    raise InvalidCommand
  }
  [capacity.retained_bytes, capacity.execution_bytes]
}

///|
#export_name("strategyHostRegistration")
pub fn strategy_host_registration(
  task : @host_driver.PreparedTaskDispatch,
) -> @connector.CapabilityRegistration? {
  Some(@host_driver.prepared_task_registration(task))
}



///|
#export_name("strategyHostTaskCompleted")
pub fn strategy_host_task_completed(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  task : Int,
) -> Bool {
  @strategy.captured_task_completed(@host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)), task)
}

///|
#export_name("strategyHostResident")
pub fn strategy_host_resident(task : @host_driver.PreparedTaskDispatch) -> Bool {
  strategy_host_resource_binding(task) is Some(_)
}

///|
#export_name("strategyHostRun")
pub fn strategy_host_run(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> @strategy.CapturedDAG {
  @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host))
}

///|
#export_name("strategyHostResourceBinding")
pub fn strategy_host_resource_binding(
  task : @host_driver.PreparedTaskDispatch,
) -> @connector.ResourceBinding? {
  @strategy.strategy_resident_profile(@host_driver.prepared_task_revision(task), @host_driver.prepared_task_index(task)).map(@strategy.resident_profile_resource_binding)
}

///|
#export_name("strategyHostResidentInputs")
pub fn strategy_host_resident_inputs(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  task : Int,
) -> Array[Array[Int64]] raise NodeHostFailure {
  guard @host_driver.compute_host_resident_inputs(@builtin.configured_host_runtime(host), task) is Some(inputs) else {
    raise InvalidCommand
  }
  inputs.map(input => {
    let (producer, bytes, entries, names) = input
    [producer.to_int64(), bytes, entries.to_int64(), names.to_int64()]
  })
}



///|
#export_name("strategyHostCount")
pub fn strategy_host_count(host : @builtin.ConfiguredComputeHost[@strategy.RunIssue]) -> Int {
  @strategy.graph_task_count(
    @strategy.captured_dag_graph(@host_driver.dispatch_driver_run(@builtin.configured_host_driver(host))),
  )
}

///|
#export_name("strategyHostProgramDefinitionCid")
pub fn strategy_host_program_definition_cid(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> String {
  @strategy.graph_program_definition_cid(
    @strategy.captured_dag_graph(
      @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
    ),
  )
}

///|
#export_name("strategyHostResultNames")
pub fn strategy_host_result_names(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> Array[String] {
  let graph = @strategy.captured_dag_graph(
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
  )
  Array::makei(@strategy.graph_result_count(graph), index =>
    @strategy.graph_result_name(graph, index).unwrap()
  )
}

///|
#export_name("strategyHostResultTasks")
pub fn strategy_host_result_tasks(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> Array[Int] {
  let graph = @strategy.captured_dag_graph(
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
  )
  Array::makei(@strategy.graph_result_count(graph), index =>
    @strategy.graph_result_task(graph, index).unwrap()
  )
}

///|
/// Complete Result Definition bodies sealed by the portable MoonBit contract
/// implementation from the exact checked graph inventory.
#export_name("strategyHostResultDefinitions")
pub fn strategy_host_result_definitions(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> Array[String] raise NodeHostFailure {
  let graph = @strategy.captured_dag_graph(
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
  )
  let program = @strategy.graph_program_definition_cid(graph)
  let definitions : Array[String] = []
  for index in 0..<@strategy.graph_result_count(graph) {
    let name = @strategy.graph_result_name(graph, index).unwrap()
    let definition = match
      @publication.prepare_result_definition(program, name) {
      Ok(value) => value
      Err(_) => raise InvalidCommand
    }
    definitions.push(
      match @publication.result_definition_json(definition) {
        Ok(value) => value
        Err(_) => raise InvalidCommand
      },
    )
  }
  definitions
}

///|
/// Admit and seal a bounded publication body in the portable contract owner.
/// The Node adapter supplies bytes and budgets; it does not define canonical
/// identity or contract validity.
#export_name("strategyPublicationSeal")
pub fn strategy_publication_seal(
  name : String,
  body_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @publication.PublicationContract raise NodeHostFailure {
  match
    @publication.seal_publication_contract(
      name,
      body_wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(_) => raise InvalidCommand
  }
}

///|
#export_name("strategyPublicationAdmit")
pub fn strategy_publication_admit(
  name : String,
  complete_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @publication.PublicationContract raise NodeHostFailure {
  match
    @publication.admit_publication_contract(
      name,
      complete_wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(_) => raise InvalidCommand
  }
}

///|
#export_name("strategyPublicationContractName")
pub fn strategy_publication_contract_name(
  contract : @publication.PublicationContract,
) -> String {
  @publication.publication_contract_name(contract)
}

///|
#export_name("strategyPublicationContractIdentityField")
pub fn strategy_publication_contract_identity_field(
  contract : @publication.PublicationContract,
) -> String {
  @publication.publication_contract_identity_field(contract)
}

///|
#export_name("strategyPublicationContractIdentity")
pub fn strategy_publication_contract_identity(
  contract : @publication.PublicationContract,
) -> String {
  @publication.publication_contract_identity(contract)
}

///|
#export_name("strategyPublicationContractJson")
pub fn strategy_publication_contract_json(
  contract : @publication.PublicationContract,
) -> String {
  @publication.publication_contract_json(contract)
}

///|
#export_name("strategyPublicationRecordTransition")
pub fn strategy_publication_record_transition(
  previous : @publication.PublicationContract?,
  next : @publication.PublicationContract,
  uncommitted_confirmed : Bool,
) -> Bool {
  @publication.validate_publication_record_transition(
    previous,
    next,
    uncommitted_confirmed,
  ) is Ok(_)
}

///|
#export_name("strategyPublicationRecordAllowsCommit")
pub fn strategy_publication_record_allows_commit(
  record : @publication.PublicationContract,
) -> Bool {
  @publication.publication_record_allows_commit(record)
}

///|
#export_name("strategyDeliveryRecordTransition")
pub fn strategy_delivery_record_transition(
  previous : @publication.PublicationContract?,
  next : @publication.PublicationContract,
) -> Bool {
  @publication.validate_delivery_record_transition(previous, next) is Ok(_)
}

///|
#export_name("strategyHostFinished")
pub fn strategy_host_finished(host : @builtin.ConfiguredComputeHost[@strategy.RunIssue]) -> Bool {
  let run = @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host))
  for task in 1..<strategy_host_count(host) {
    if !@strategy.captured_task_completed(run, task) {
      return false
    }
  }
  true
}

///|
#export_name("strategyHostStop")
pub fn strategy_host_stop(host : @builtin.ConfiguredComputeHost[@strategy.RunIssue]) -> Unit {
  @host_driver.stop_dispatch_driver(@builtin.configured_host_driver(host))
}

///|
#export_name("strategyHostCloseOutputs")
pub fn strategy_host_close_outputs(host : @builtin.ConfiguredComputeHost[@strategy.RunIssue]) -> Unit {
  let run = @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host))
  for task = strategy_host_count(host) - 1; task > 0; task = task - 1 {
    @strategy.close_captured_task_output(run, task)
  }
}

///|
#export_name("strategyHostOutput")
pub fn strategy_host_output(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  task : Int,
) -> @execution.CompletedOutput? {
  let run = @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host))
  @strategy.captured_task_target(run, task).bind(target => {
    @strategy.captured_task_output(run, task, target)
  })
}

///|
#export_name("strategyHostExplain")
pub fn strategy_host_explain(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  max_bytes : Int,
  max_nodes : Int,
) -> String raise NodeHostFailure {
  let excluded = match @host_driver.compute_host_exclusions(@builtin.configured_host_runtime(host), max_nodes) {
    Ok(value) => value
    Err(issue) => raise Diagnostics(issue)
  }
  match
    @strategy.explain_captured_strategy(
      @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
      max_bytes,
      max_nodes,
      excluded~,
    ) {
    Ok(value) => value
    Err(issue) => raise Encoding(issue)
  }
}

///|
#export_name("strategyHostUsage")
pub fn strategy_host_usage(host : @builtin.ConfiguredComputeHost[@strategy.RunIssue]) -> Array[Int64] {
  let usage = @resources.ledger_usage(
    @strategy.captured_dag_ledger(@host_driver.dispatch_driver_run(@builtin.configured_host_driver(host))),
  )
  [
    usage.planning_work.to_int64(),
    usage.attempts.to_int64(),
    usage.holdings.to_int64(),
    usage.transferred_bytes,
    usage.reserved_transfer_bytes,
    usage.held_bytes,
    usage.reserved_retention_bytes,
    usage.reserved_execution_bytes,
  ]
}

///|
/// Reserve one explicit representation transfer in the existing Run ledger.
/// Site discovery and binding are Host concerns; this handle owns only the
/// physical attempt, cumulative transfer, destination holding and cleanup.
#export_name("strategyHostTransferBegin")
pub fn strategy_host_transfer_begin(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  source_task : Int,
  transfer_bytes : Int64,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> @strategy.ManagedTransfer raise NodeHostFailure {
  match
    @strategy.begin_captured_managed_transfer(
      @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
      source_task,
      transfer_bytes,
      retained_bytes,
      execution_bytes,
    ) {
    Ok(value) => value
    Err(issue) => raise Execution(issue)
  }
}

///|
#export_name("strategyHostTransferCharge")
pub fn strategy_host_transfer_charge(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  transfer : @strategy.ManagedTransfer,
  bytes : Int64,
) -> Unit raise NodeHostFailure {
  match
    @strategy.charge_captured_managed_transfer(
      @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
      transfer,
      bytes,
    ) {
    Ok(_) => ()
    Err(issue) => raise Execution(@strategy.Physical(issue))
  }
}

///|
#export_name("strategyHostTransferSettle")
pub fn strategy_host_transfer_settle(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  transfer : @strategy.ManagedTransfer,
  confirmed : Bool,
) -> Unit raise NodeHostFailure {
  match
    @strategy.settle_captured_managed_transfer(
      @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
      transfer,
      confirmed,
    ) {
    Ok(_) => ()
    Err(issue) => raise Execution(@strategy.Physical(issue))
  }
}

///|
#export_name("strategyHostTransferComplete")
pub fn strategy_host_transfer_complete(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  transfer : @strategy.ManagedTransfer,
  retained_bytes : Int64,
) -> @strategy.ManagedTransferReceipt raise NodeHostFailure {
  match
    @strategy.complete_captured_managed_transfer(
      @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
      transfer,
      retained_bytes,
    ) {
    Ok(value) => value
    Err(issue) => raise Execution(issue)
  }
}

///|
#export_name("strategyHostTransferAbort")
pub fn strategy_host_transfer_abort(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  transfer : @strategy.ManagedTransfer,
  confirmed : Bool,
) -> Unit raise NodeHostFailure {
  match
    @strategy.abort_captured_managed_transfer(
      @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
      transfer,
      confirmed,
    ) {
    Ok(_) => ()
    Err(issue) => raise Execution(@strategy.Physical(issue))
  }
}

///|
#export_name("strategyHostTransferRelease")
pub fn strategy_host_transfer_release(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  receipt : @strategy.ManagedTransferReceipt,
) -> Bool raise NodeHostFailure {
  match
    @strategy.release_captured_managed_transfer(
      @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
      receipt,
    ) {
    Ok(value) => value
    Err(issue) => raise Execution(@strategy.Physical(issue))
  }
}

///|
#export_name("strategyHostTransferPending")
pub fn strategy_host_transfer_pending(
  transfer : @strategy.ManagedTransfer,
) -> Bool {
  @strategy.captured_managed_transfer_pending(transfer)
}

///|
#export_name("strategyHostTransferReceipt")
pub fn strategy_host_transfer_receipt(
  receipt : @strategy.ManagedTransferReceipt,
) -> Array[Int64] {
  let (transferred, retained) =
    @strategy.captured_managed_transfer_receipt_bytes(receipt)
  [
    @strategy.captured_managed_transfer_receipt_source(receipt).to_int64(),
    @strategy.captured_managed_transfer_receipt_attempt(receipt).to_int64(),
    transferred,
    retained,
    if @strategy.captured_managed_transfer_receipt_available(receipt) {
      1L
    } else {
      0L
    },
  ]
}

///|
#export_name("strategySiteCreate")
pub fn strategy_site_create(
  key : String,
  generation : Int,
  runtime_revision : String,
  max_concurrent_operations : Int,
  max_concurrent_transfers : Int,
  max_retained_bytes : Int64,
  max_execution_bytes : Int64,
) -> @site.ExecutionSite? {
  @site.create_site(
    key,
    generation,
    runtime_revision,
    max_concurrent_operations,
    max_concurrent_transfers,
    max_retained_bytes,
    max_execution_bytes,
  )
}

///|
#export_name("strategySiteAvailable")
pub fn strategy_site_available(site : @site.ExecutionSite) -> Bool {
  @site.site_available(site)
}

///|
#export_name("strategySiteRevoked")
pub fn strategy_site_revoked(site : @site.ExecutionSite) -> Bool {
  @site.site_revoked(site)
}

///|
#export_name("strategySiteCapacitySupports")
pub fn strategy_site_capacity_supports(
  site : @site.ExecutionSite,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Bool {
  @site.site_capacity_supports(site, retained_bytes, execution_bytes)
}

///|
#export_name("strategySiteBindingCurrent")
pub fn strategy_site_binding_current(
  site : @site.ExecutionSite,
  generation : Int,
  runtime_revision : String,
) -> Bool {
  @site.site_binding_current(site, generation, runtime_revision)
}

///|
#export_name("strategySiteStartOperation")
pub fn strategy_site_start_operation(
  site : @site.ExecutionSite,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> @site.SiteOperation? {
  @site.start_site_operation(site, retained_bytes, execution_bytes)
}

///|
#export_name("strategySiteOperationAvailable")
pub fn strategy_site_operation_available(
  operation : @site.SiteOperation,
) -> Bool {
  @site.site_operation_available(operation)
}

///|
#export_name("strategySiteSettleOperation")
pub fn strategy_site_settle_operation(operation : @site.SiteOperation) -> Bool {
  @site.settle_site_operation(operation)
}

///|
#export_name("strategySiteRetainOperationHolding")
pub fn strategy_site_retain_operation_holding(
  operation : @site.SiteOperation,
  bytes : Int64,
) -> @site.SiteHolding? {
  @site.retain_site_operation_holding(operation, bytes)
}

///|
#export_name("strategySiteStartTransfer")
pub fn strategy_site_start_transfer(
  source : @site.ExecutionSite,
  destination : @site.ExecutionSite,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> @site.SiteTransfer? {
  @site.start_site_transfer(
    source,
    destination,
    retained_bytes,
    execution_bytes,
  )
}

///|
#export_name("strategySiteTransferAvailable")
pub fn strategy_site_transfer_available(transfer : @site.SiteTransfer) -> Bool {
  @site.site_transfer_available(transfer)
}

///|
#export_name("strategySiteSettleTransferSource")
pub fn strategy_site_settle_transfer_source(
  transfer : @site.SiteTransfer,
) -> Bool {
  @site.settle_site_transfer_source(transfer)
}

///|
#export_name("strategySiteSettleTransferDestination")
pub fn strategy_site_settle_transfer_destination(
  transfer : @site.SiteTransfer,
) -> Bool {
  @site.settle_site_transfer_destination(transfer)
}

///|
#export_name("strategySiteRetainTransferHolding")
pub fn strategy_site_retain_transfer_holding(
  transfer : @site.SiteTransfer,
  bytes : Int64,
) -> @site.SiteHolding? {
  @site.retain_site_transfer_holding(transfer, bytes)
}

///|
#export_name("strategySiteRetainHolding")
pub fn strategy_site_retain_holding(
  site : @site.ExecutionSite,
  bytes : Int64,
) -> @site.SiteHolding? {
  @site.retain_site_holding(site, bytes)
}

///|
#export_name("strategySiteReleaseHolding")
pub fn strategy_site_release_holding(holding : @site.SiteHolding) -> Bool {
  @site.release_site_holding(holding)
}

///|
#export_name("strategySiteRetainCleanup")
pub fn strategy_site_retain_cleanup(
  site : @site.ExecutionSite,
) -> @site.SiteCleanup {
  @site.retain_site_cleanup(site)
}

///|
#export_name("strategySiteReleaseCleanup")
pub fn strategy_site_release_cleanup(cleanup : @site.SiteCleanup) -> Bool {
  @site.release_site_cleanup(cleanup)
}

///|
#export_name("strategySiteBeginTeardown")
pub fn strategy_site_begin_teardown(site : @site.ExecutionSite) -> Unit {
  @site.begin_site_teardown(site)
}

///|
#export_name("strategySiteRevoke")
pub fn strategy_site_revoke(site : @site.ExecutionSite) -> Unit {
  @site.revoke_site(site)
}

///|
#export_name("strategySiteStatus")
pub fn strategy_site_status(site : @site.ExecutionSite) -> Array[Int64] {
  @site.site_status(site)
}
