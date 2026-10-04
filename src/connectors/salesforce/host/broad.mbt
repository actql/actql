///|
/// Physical-cost selection belongs to the Host assembly, not the provider's
/// query interpretation. A selected candidate still grants no I/O authority.
pub fn salesforce_broad_candidate(
  registration : @connector.CapabilityRegistration,
  preparation : SalesforceBroadPreparation,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : @connector.QueryQuantities,
  max_entries : Int,
) -> Result[
  @planning.PreparedAcquisition[SalesforceBroadPreparation],
  @planning.QueryPlanningIssue,
] {
  let duration = match @cost.assess_serial(8, estimates, max_entries) {
    Ok(value) => value
    Err(issue) => return Err(Cost(issue))
  }
  @planning.bind_acquisition_candidate(
    registration,
    salesforce_broad_requirement(preparation),
    preparation,
    duration,
    quantities,
  )
}

///|
struct SalesforceBroadHostConfiguration {
  contracts : @planning.QueryEvidenceContracts
  requirement : @planning.QueryRequirement
  choice : @planning.AcquisitionChoice
  candidate : @planning.PreparedAcquisition[SalesforceBroadPreparation]
  limits : SalesforceBroadCompletionLimits
}

///|
struct SalesforceBroadHostRun {
  configuration : SalesforceBroadHostConfiguration
  issuer : SalesforceBroadIssuer
  attempt : SalesforceBroadAttempt
  mut closed : Bool
  mut physical : SalesforceBroadPhysical?
}

///|
priv struct SalesforceBroadPhysical {
  ledger : @resources.Ledger
  reservation : @resources.Reservation
  mut holding : @resources.Holding?
  mut dag : (@strategy.CapturedDAG, Int)?
}

///|
pub(all) enum SalesforceBroadHostIssue {
  InvalidState
  Physical(@resources.LedgerIssue)
  Evidence(SalesforceEvidenceIssue)
  Consumer(@query.CapturedSourceIssue)
  Binding(SalesforceEvidenceIssue)
}

///|
/// Keep the selected checked requirement, candidate, and evidence contracts
/// together. Physical transport and its verifier are supplied only at start.
pub fn configure_salesforce_broad_host(
  contracts : @planning.QueryEvidenceContracts,
  requirement : @planning.QueryRequirement,
  choice : @planning.AcquisitionChoice,
  candidate : @planning.PreparedAcquisition[SalesforceBroadPreparation],
  limits : SalesforceBroadCompletionLimits,
) -> SalesforceBroadHostConfiguration {
  { contracts, requirement, choice, candidate, limits, }
}

///|
/// Trusted Host bootstrap installs a verifier for the exact physical owner.
pub fn start_salesforce_broad_host(
  configuration : SalesforceBroadHostConfiguration,
  nonce : String,
  verify : (SalesforceBroadAttempt) -> Bool,
) -> Result[SalesforceBroadHostRun, SalesforceBroadHostIssue] {
  let issuer = match
    prepare_salesforce_broad_issuer(
      configuration.contracts,
      configuration.requirement,
      nonce,
      128,
      verify,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  let attempt = match
    prepare_issued_salesforce_broad_attempt(
      issuer,
      configuration.choice,
      configuration.candidate,
    ) {
    Ok(value) => value
    Err(issue) => {
      close_salesforce_broad_issuer(issuer)
      return Err(Evidence(issue))
    }
  }
  Ok({ configuration, issuer, attempt, closed: false, physical: None, })
}

///|
pub fn salesforce_broad_retained_capacity(
  configuration : SalesforceBroadHostConfiguration,
) -> Int64 {
  configuration.limits.retention.retained_wire_bytes.to_int64()
}

///|
pub fn salesforce_broad_execution_capacity(
  configuration : SalesforceBroadHostConfiguration,
) -> Int64 {
  let limits = configuration.limits
  (limits.retention.received_wire_bytes +
  limits.retention.retained_wire_bytes +
  limits.records.max_bytes +
  limits.capture.max_bytes).to_int64()
}

///|
pub fn start_accounted_salesforce_broad_host(
  configuration : SalesforceBroadHostConfiguration,
  nonce : String,
  verify : (SalesforceBroadAttempt) -> Bool,
  ledger : @resources.Ledger,
  transfer_bytes : Int64,
  execution_scratch : Int64,
) -> Result[SalesforceBroadHostRun, SalesforceBroadHostIssue] {
  if transfer_bytes < 0L ||
    execution_scratch < 0L ||
    execution_scratch >
    9223372036854775807L - salesforce_broad_execution_capacity(configuration) {
    return Err(Physical(InvalidLimits))
  }
  let run = match start_salesforce_broad_host(configuration, nonce, verify) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let reservation = match
    @resources.reserve_attempt(
      ledger,
      transfer_bytes,
      salesforce_broad_retained_capacity(configuration),
      salesforce_broad_execution_capacity(configuration) + execution_scratch,
    ) {
    Ok(value) => value
    Err(issue) => {
      close_salesforce_broad_host(run)
      return Err(Physical(issue))
    }
  }
  run.physical = Some({ ledger, reservation, holding: None, dag: None, })
  Ok(run)
}

///|
pub fn charge_salesforce_broad_page(
  run : SalesforceBroadHostRun,
  bytes : Int64,
) -> Result[Unit, SalesforceBroadHostIssue] {
  if run.closed {
    return Err(InvalidState)
  }
  if run.physical is Some(physical) {
    @resources.charge_transfer(physical.ledger, physical.reservation, bytes).map_err(issue => {
        Physical(issue)
      },
    )
  } else {
    Ok(())
  }
}

///|
pub fn retain_salesforce_broad_capture(
  capture : SalesforceBroadSourceCapture,
) -> Result[Unit, SalesforceBroadHostIssue] {
  let run = capture.run
  guard !run.closed &&
    run.physical is Some(physical) &&
    physical.holding is None else {
    return Err(InvalidState)
  }
  let bytes = capture.observation.records.retention.measured.retained_bytes.to_int64()
  let holding = match
    @resources.retain_allocation(physical.ledger, physical.reservation, bytes) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  physical.holding = Some(holding)
  @resources.settle_reservation(physical.ledger, physical.reservation).map_err(issue => {
    Physical(issue)
  })
}

///|
pub fn retain_salesforce_broad_capture_task(
  capture : SalesforceBroadSourceCapture,
  dag : @strategy.CapturedDAG,
  task : Int,
) -> Result[Unit, SalesforceBroadHostIssue] {
  let run = capture.run
  guard !run.closed &&
    run.physical is Some(physical) &&
    physical.holding is Some(holding) &&
    physical.dag is None &&
    physical_equal(physical.ledger, @strategy.captured_dag_ledger(dag)) &&
    @strategy.captured_task_source_matches(dag, task, capture.source) else {
    return Err(Physical(ForeignOwner))
  }
  match
    @strategy.retain_captured_task_allocation(dag, task, holding, release_confirmed=fn() {
      run.closed
    }) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  physical.dag = Some((dag, task))
  physical.holding = None
  Ok(())
}

///|
pub fn close_accounted_salesforce_broad_host(
  run : SalesforceBroadHostRun,
) -> Result[Unit, SalesforceBroadHostIssue] {
  guard run.physical is Some(physical) else { return Err(InvalidState) }
  close_salesforce_broad_host(run)
  if physical.dag is Some((dag, task)) {
    @strategy.close_captured_task_output(dag, task)
    @strategy.refresh_captured_retention(dag)
  }
  if physical.holding is Some(holding) {
    match @resources.release_allocation(physical.ledger, holding) {
      Ok(_) => physical.holding = None
      Err(issue) => return Err(Physical(issue))
    }
  }
  if @resources.reservation_open(physical.reservation) {
    @resources.settle_reservation(physical.ledger, physical.reservation).map_err(issue => {
        Physical(issue)
      },
    )
  } else {
    Ok(())
  }
}

///|
pub fn salesforce_broad_host_attempt(
  run : SalesforceBroadHostRun,
) -> SalesforceBroadAttempt {
  run.attempt
}

///|
pub fn complete_salesforce_broad_host(
  run : SalesforceBroadHostRun,
) -> Result[SalesforceBroadObservation, SalesforceBroadHostIssue] {
  if run.closed {
    return Err(InvalidState)
  }
  complete_salesforce_broad_capture(
    run.issuer,
    run.attempt,
    run.configuration.limits,
  ).map_err(issue => Evidence(issue))
}

///|
pub fn salesforce_broad_host_source(
  run : SalesforceBroadHostRun,
  observation : SalesforceBroadObservation,
) -> Result[@query.CapturedInputSource, SalesforceBroadHostIssue] {
  if run.closed {
    return Err(InvalidState)
  }
  salesforce_broad_captured_source(run.issuer, run.attempt, observation).map_err(issue => {
      Consumer(issue)
    },
  )
}

///|
pub fn bind_salesforce_broad_host_input(
  run : SalesforceBroadHostRun,
  observation : SalesforceBroadObservation,
  receiver : @lower.BoundPrepared,
  input_index : Int,
) -> Result[@execution.BoundProducerInput, SalesforceBroadHostIssue] {
  if run.closed {
    return Err(InvalidState)
  }
  let producer = @query.query_sequence_owner(
    @planning.query_material_owner(
      @planning.query_requirement_material(run.configuration.requirement),
    ),
  )
  bind_captured_salesforce_broad_input(
    run.issuer,
    run.attempt,
    observation,
    receiver,
    input_index,
    producer,
  ).map_err(issue => Binding(issue))
}

///|
pub fn abort_salesforce_broad_host(run : SalesforceBroadHostRun) -> Unit {
  abort_salesforce_broad_attempt(run.attempt)
}

///|
pub fn close_salesforce_broad_host(run : SalesforceBroadHostRun) -> Unit {
  if !run.closed {
    abort_salesforce_broad_host(run)
    close_salesforce_broad_issuer(run.issuer)
    run.closed = true
  }
}
