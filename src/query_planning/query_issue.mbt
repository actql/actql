///|
pub(all) enum QueryPlanningIssue {
  InvalidLimits
  PlanningLimit
  NegativeQuantity
  ForeignQuery(Int)
  ForeignCapability(Int)
  AcquisitionUnsupported
  CapabilityClosed
  Cost(@cost.CostIssue)
}
