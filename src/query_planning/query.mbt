///|
/// The two bounded mock realizations, not a classification of Connector kinds.
pub(all) enum QueryRealization {
  NativeQuery
  BroadWithResidual
} derive(Eq, Debug)

///|
/// Disjoint accounting scopes INSIDE an acquisition realization. These are not
/// independently approved semantic units or streaming physical task edges.
pub(all) enum QueryWork {
  SourceQuery
  SourceScan
  CompletedReceiptTransfer
  ReceiptConversion
  LocalResidual
  ObservationCapture
  OutputRetention
  Cleanup
} derive(Eq, Debug)

///|
/// Host-private tasks. Only the completed query output crosses the first edge;
/// source receipt/residual scheduling stays inside RealizeQuery.
pub(all) enum QueryTask {
  RealizeQuery
  CaptureObservation
} derive(Eq, Debug)

///|
/// Non-time quantities remain separate and do not become hard bounds. The
/// money unit is Host-context-specific; it is never added to bytes or latency.
pub(all) struct QueryQuantities {
  transfer_bytes : Int64?
  retained_bytes : Int64?
  money_units : Int64?
}

///|
/// Immutable planning data. All shared requirements remain pending: a cost
/// choice is not authority, execution evidence, capture or a runnable Plan.
struct QueryOffer {
  owner : @query.QuerySequence
  realization : QueryRealization
  duration : @cost.DurationEstimate
  quantities : QueryQuantities
}

///|
pub(all) enum QueryPlanningIssue {
  InvalidLimits
  PlanningLimit
  NegativeQuantity
  ForeignQuery(Int)
  Cost(@cost.CostIssue)
}

///|
/// A proposed PhysicalStrategy, still subject to current runtime admission.
/// No Connector is dispatched and no semantic identity is generated here.
struct QueryStrategy {
  offer : QueryOffer
  choice : @cost.CostChoice
}

///|
pub enum QuerySelection {
  Proposed(QueryStrategy)
  Deferred
  NoCandidates
}

///|
pub fn query_work_count(realization : QueryRealization) -> Int {
  match realization {
    NativeQuery => 6
    BroadWithResidual => 7
  }
}

///|
pub fn query_work_at(realization : QueryRealization, index : Int) -> QueryWork? {
  match (realization, index) {
    (NativeQuery, 0) => Some(SourceQuery)
    (BroadWithResidual, 0) => Some(SourceScan)
    (_, 1) => Some(CompletedReceiptTransfer)
    (_, 2) => Some(ReceiptConversion)
    (BroadWithResidual, 3) => Some(LocalResidual)
    (NativeQuery, 3) | (BroadWithResidual, 4) => Some(ObservationCapture)
    (NativeQuery, 4) | (BroadWithResidual, 5) => Some(OutputRetention)
    (NativeQuery, 5) | (BroadWithResidual, 6) => Some(Cleanup)
    _ => None
  }
}

///|
fn valid_quantity(value : Int64?) -> Bool {
  match value {
    None => true
    Some(n) => n >= 0L
  }
}

///|
/// Offer only the two known mock implementations of an already checked local
/// query. NativeQuery means complete source-side query semantics, not a weak
/// prefilter. No caller-supplied coverage/completion boolean is accepted.
/// Estimates can bundle disjoint work, but cannot omit known residual/capture/
/// retention costs and still claim a complete estimate. Missing costs are unknown.
pub fn offer_mock_query(
  owner : @query.QuerySequence,
  realization : QueryRealization,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : QueryQuantities,
  max_entries : Int,
) -> Result[QueryOffer, QueryPlanningIssue] {
  if max_entries < 0 {
    return Err(InvalidLimits)
  }
  if !valid_quantity(quantities.transfer_bytes) ||
    !valid_quantity(quantities.retained_bytes) ||
    !valid_quantity(quantities.money_units) {
    return Err(NegativeQuantity)
  }
  match
    @cost.assess_serial(query_work_count(realization), estimates, max_entries) {
    Ok(duration) => Ok({ owner, realization, duration, quantities, })
    Err(issue) => Err(Cost(issue))
  }
}

///|
/// Candidate indices and Host priority are physical addresses only. The exact
/// same prepared query owns every offer, irrespective of cost/registration order.
pub fn choose_query_strategy(
  owner : @query.QuerySequence,
  offers : Array[QueryOffer],
  host_priority : Array[Int]?,
  max_entries : Int,
) -> Result[QuerySelection, QueryPlanningIssue] {
  if max_entries < 0 {
    return Err(InvalidLimits)
  }
  // Charge candidate references before constructing the duration inventory.
  if offers.length() > max_entries {
    return Err(PlanningLimit)
  }
  let durations = []
  for i in 0..<offers.length() {
    if !physical_equal(offers[i].owner, owner) {
      return Err(ForeignQuery(i))
    }
    durations.push(offers[i].duration)
  }
  match
    @cost.choose_serial(durations, host_priority, max_entries - offers.length()) {
    Err(issue) => Err(Cost(issue))
    Ok(choice) =>
      match choice {
        NoCandidates => Ok(NoCandidates)
        Deferred => Ok(Deferred)
        EstimatedFastest(index, _) | HostPreferred(index) =>
          Ok(Proposed({ offer: offers[index], choice, }))
      }
  }
}

///|
pub fn query_offer_realization(v : QueryOffer) -> QueryRealization {
  v.realization
}

///|
pub fn query_offer_duration(v : QueryOffer) -> @cost.DurationEstimate {
  v.duration
}

///|
pub fn query_offer_quantities(v : QueryOffer) -> QueryQuantities {
  v.quantities
}

///|
pub fn query_strategy_offer(v : QueryStrategy) -> QueryOffer {
  v.offer
}

///|
pub fn query_strategy_choice(v : QueryStrategy) -> @cost.CostChoice {
  v.choice
}

///|
pub fn query_strategy_owner(v : QueryStrategy) -> @query.QuerySequence {
  v.offer.owner
}

///|
pub fn query_strategy_task_count(_v : QueryStrategy) -> Int {
  2
}

///|
pub fn query_strategy_task_at(_v : QueryStrategy, index : Int) -> QueryTask? {
  match index {
    0 => Some(RealizeQuery)
    1 => Some(CaptureObservation)
    _ => None
  }
}

///|
pub fn query_strategy_pending_count(v : QueryStrategy) -> Int {
  @acquisition.query_acquisition_requirement_count(
    @query.query_sequence_requirement(v.offer.owner),
  )
}

///|
pub fn query_strategy_pending_at(
  v : QueryStrategy,
  index : Int,
) -> @acquisition.QueryAcquisitionRequirement? {
  @acquisition.query_acquisition_requirement_at(
    @query.query_sequence_requirement(v.offer.owner),
    index,
  )
}
