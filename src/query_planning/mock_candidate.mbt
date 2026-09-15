///|
pub fn mock_acquisition_candidate(
  registration : @connector.CapabilityRegistration,
  requirement : QueryRequirement,
  offer : QueryOffer,
) -> Result[PreparedAcquisition[QueryOffer], QueryPlanningIssue] {
  if !physical_equal(requirement.material.owner, offer.owner) {
    return Err(ForeignQuery(0))
  }
  bind_acquisition_candidate(
    registration,
    requirement,
    offer,
    offer.duration,
    offer.quantities,
  )
}

///|
/// Preserve the common selection reason when entering the existing mock driver;
/// do not run a second, mock-only comparison after Host selection.
pub fn mock_acquisition_strategy(
  choice : AcquisitionChoice,
  prepared : PreparedAcquisition[QueryOffer],
) -> QueryStrategy? {
  acquisition_choice_payload(choice, prepared).map(offer => {
    offer,
    choice: choice.reason,
  })
}
