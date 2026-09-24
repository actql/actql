///|
/// Physical-cost selection belongs to the Host assembly, not the provider's
/// query interpretation. A selected candidate still grants no I/O authority.
pub fn salesforce_broad_candidate(
  registration : @connector.CapabilityRegistration,
  preparation : @salesforce.SalesforceBroadPreparation,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : @connector.QueryQuantities,
  max_entries : Int,
) -> Result[
  @planning.PreparedAcquisition[@salesforce.SalesforceBroadPreparation],
  @planning.QueryPlanningIssue,
] {
  let duration = match @cost.assess_serial(8, estimates, max_entries) {
    Ok(value) => value
    Err(issue) => return Err(Cost(issue))
  }
  @planning.bind_acquisition_candidate(
    registration,
    @salesforce.salesforce_broad_requirement(preparation),
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
  candidate : @planning.PreparedAcquisition[
    @salesforce.SalesforceBroadPreparation,
  ]
  limits : @salesforce.SalesforceBroadCompletionLimits
}

///|
struct SalesforceBroadHostRun {
  configuration : SalesforceBroadHostConfiguration
  issuer : @salesforce.SalesforceBroadIssuer
  attempt : @salesforce.SalesforceBroadAttempt
  mut closed : Bool
}

///|
pub(all) enum SalesforceBroadHostIssue {
  InvalidState
  Evidence(@salesforce.SalesforceEvidenceIssue)
  Consumer(@query.CapturedSourceIssue)
  Binding(@salesforce.SalesforceEvidenceIssue)
}

///|
/// Keep the selected checked requirement, candidate, and evidence contracts
/// together. Physical transport and its verifier are supplied only at start.
pub fn configure_salesforce_broad_host(
  contracts : @planning.QueryEvidenceContracts,
  requirement : @planning.QueryRequirement,
  choice : @planning.AcquisitionChoice,
  candidate : @planning.PreparedAcquisition[
    @salesforce.SalesforceBroadPreparation,
  ],
  limits : @salesforce.SalesforceBroadCompletionLimits,
) -> SalesforceBroadHostConfiguration {
  { contracts, requirement, choice, candidate, limits, }
}

///|
/// Trusted Host bootstrap installs a verifier for the exact physical owner.
pub fn start_salesforce_broad_host(
  configuration : SalesforceBroadHostConfiguration,
  nonce : String,
  verify : (@salesforce.SalesforceBroadAttempt) -> Bool,
) -> Result[SalesforceBroadHostRun, SalesforceBroadHostIssue] {
  let issuer = match
    @salesforce.prepare_salesforce_broad_issuer(
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
    @salesforce.prepare_issued_salesforce_broad_attempt(
      issuer,
      configuration.choice,
      configuration.candidate,
    ) {
    Ok(value) => value
    Err(issue) => {
      @salesforce.close_salesforce_broad_issuer(issuer)
      return Err(Evidence(issue))
    }
  }
  Ok({ configuration, issuer, attempt, closed: false, })
}

///|
pub fn salesforce_broad_host_attempt(
  run : SalesforceBroadHostRun,
) -> @salesforce.SalesforceBroadAttempt {
  run.attempt
}

///|
pub fn complete_salesforce_broad_host(
  run : SalesforceBroadHostRun,
) -> Result[@salesforce.SalesforceBroadObservation, SalesforceBroadHostIssue] {
  if run.closed {
    return Err(InvalidState)
  }
  @salesforce.complete_salesforce_broad_capture(
    run.issuer,
    run.attempt,
    run.configuration.limits,
  ).map_err(issue => Evidence(issue))
}

///|
pub fn salesforce_broad_host_source(
  run : SalesforceBroadHostRun,
  observation : @salesforce.SalesforceBroadObservation,
) -> Result[@query.CapturedInputSource, SalesforceBroadHostIssue] {
  if run.closed {
    return Err(InvalidState)
  }
  @salesforce.salesforce_broad_captured_source(
    run.issuer,
    run.attempt,
    observation,
  ).map_err(issue => Consumer(issue))
}

///|
pub fn bind_salesforce_broad_host_input(
  run : SalesforceBroadHostRun,
  observation : @salesforce.SalesforceBroadObservation,
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
  @salesforce.bind_captured_salesforce_broad_input(
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
  @salesforce.abort_salesforce_broad_attempt(run.attempt)
}

///|
pub fn close_salesforce_broad_host(run : SalesforceBroadHostRun) -> Unit {
  if !run.closed {
    abort_salesforce_broad_host(run)
    @salesforce.close_salesforce_broad_issuer(run.issuer)
    run.closed = true
  }
}
