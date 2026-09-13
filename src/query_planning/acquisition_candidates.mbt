///|
/// Realization binding for Host dispatch, not a new semantic acquisition kind.
/// The common comparison code never branches on this payload.
pub enum AcquisitionBinding {
  Mock(QueryOffer)
  DuckDBBroad(DuckDBQueryPreparation)
}

///|
struct AcquisitionCandidate {
  requirement : QueryRequirement
  binding : AcquisitionBinding
  duration : @cost.DurationEstimate
  quantities : QueryQuantities
}

///|
struct AcquisitionChoice {
  candidate : AcquisitionCandidate
  reason : @cost.CostChoice
}

///|
pub enum AcquisitionSelection {
  Proposed(AcquisitionChoice)
  Deferred
  NoCandidates
}

///|
pub fn mock_acquisition_candidate(
  requirement : QueryRequirement,
  offer : QueryOffer,
) -> Result[AcquisitionCandidate, QueryPlanningIssue] {
  if !physical_equal(requirement.material.owner, offer.owner) {
    return Err(ForeignQuery(0))
  }
  Ok({
    requirement,
    binding: Mock(offer),
    duration: offer.duration,
    quantities: offer.quantities,
  })
}

///|
/// Disjoint serial scopes for broad acquisition; setup includes catalog and
/// read-transaction work. The SQL scan, receipt transport and Local residual
/// must not hide one another's costs. Missing estimates remain unknown.
pub(all) enum DuckDBBroadWork {
  SessionAndCatalog
  SourceScan
  ReceiptTransfer
  ReceiptConversion
  LocalResidual
  ObservationCapture
  Retention
  Cleanup
} derive(Eq, Debug)

///|
pub fn duckdb_broad_work_at(index : Int) -> DuckDBBroadWork? {
  match index {
    0 => Some(SessionAndCatalog)
    1 => Some(SourceScan)
    2 => Some(ReceiptTransfer)
    3 => Some(ReceiptConversion)
    4 => Some(LocalResidual)
    5 => Some(ObservationCapture)
    6 => Some(Retention)
    7 => Some(Cleanup)
    _ => None
  }
}

///|
pub fn duckdb_broad_candidate(
  prepared : DuckDBQueryPreparation,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : QueryQuantities,
  max_entries : Int,
) -> Result[AcquisitionCandidate, QueryPlanningIssue] {
  if !valid_quantity(quantities.transfer_bytes) ||
    !valid_quantity(quantities.retained_bytes) ||
    !valid_quantity(quantities.money_units) {
    return Err(NegativeQuantity)
  }
  @cost.assess_serial(8, estimates, max_entries)
  .map_err(issue => Cost(issue))
  .map(duration => {
    requirement: prepared.requirement,
    binding: DuckDBBroad(prepared),
    duration,
    quantities,
  })
}

///|
/// Cost proposal only: source authorization, execution, retention and capture
/// remain pending. No I/O or fallback is performed. All candidates belong to
/// the exact same requirement, not just an equal canonical CID.
pub fn choose_acquisition_candidate(
  requirement : QueryRequirement,
  candidates : Array[AcquisitionCandidate],
  host_priority : Array[Int]?,
  max_entries : Int,
) -> Result[AcquisitionSelection, QueryPlanningIssue] {
  if max_entries < 0 {
    return Err(InvalidLimits)
  }
  if candidates.length() > max_entries {
    return Err(PlanningLimit)
  }
  let durations = []
  for i in 0..<candidates.length() {
    if !physical_equal(candidates[i].requirement, requirement) {
      return Err(ForeignQuery(i))
    }
    durations.push(candidates[i].duration)
  }
  @cost.choose_serial(
    durations,
    host_priority,
    max_entries - candidates.length(),
  )
  .map_err(issue => Cost(issue))
  .map(reason => {
    match reason {
      NoCandidates => NoCandidates
      Deferred => Deferred
      EstimatedFastest(index, _) | HostPreferred(index) =>
        Proposed({ candidate: candidates[index], reason, })
    }
  })
}

///|
pub fn acquisition_choice_candidate(
  choice : AcquisitionChoice,
) -> AcquisitionCandidate {
  choice.candidate
}

///|
pub fn acquisition_choice_reason(
  choice : AcquisitionChoice,
) -> @cost.CostChoice {
  choice.reason
}

///|
pub fn acquisition_candidate_binding(
  candidate : AcquisitionCandidate,
) -> AcquisitionBinding {
  candidate.binding
}

///|
pub fn acquisition_candidate_duration(
  candidate : AcquisitionCandidate,
) -> @cost.DurationEstimate {
  candidate.duration
}

///|
pub fn acquisition_candidate_quantities(
  candidate : AcquisitionCandidate,
) -> QueryQuantities {
  candidate.quantities
}
