///|
pub fn mock_acquisition_candidate(
  registration : @connector.CapabilityRegistration,
  requirement : @planning.QueryRequirement,
  offer : QueryOffer,
) -> Result[
  @planning.PreparedAcquisition[QueryOffer],
  @planning.QueryPlanningIssue,
] {
  if !physical_equal(
      @planning.query_material_owner(
        @planning.query_requirement_material(requirement),
      ),
      offer.owner,
    ) {
    return Err(ForeignQuery(0))
  }
  @planning.bind_acquisition_candidate(
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
  choice : @planning.AcquisitionChoice,
  prepared : @planning.PreparedAcquisition[QueryOffer],
) -> QueryStrategy? {
  @planning.acquisition_choice_payload(choice, prepared).map(offer => {
    offer,
    choice: @planning.acquisition_choice_reason(choice),
  })
}
