///|
/// Read only the six contract references selected by the original capture
/// Owner. Measurement is not an additional hold or authority. In particular,
/// the physical encrypted-body reservation does not fund these heap facts.
pub fn ResidentEffectCaptureCustody::original_computation_representation_extent(
  self : ResidentEffectCaptureCustody,
  max_nodes : Int,
  max_depth : Int,
  max_utf16_units : Int,
) -> Result[
  Array[@publication.PublicationRepresentationExtent],
  ResidentEffectCaptureCustodyIssue,
] {
  guard !self.released &&
    @resources.reservation_open(self.reservation) &&
    self.original is Some(funded) &&
    !funded.physical_cleanup_confirmed &&
    @resources.capacity_reservation_open(funded.reservation) &&
    funded.evidence is Some(original) else {
    return Err(Unavailable)
  }
  let facts = []
  for
    contract in [
      original.run,
      original.invocation,
      original.definition,
      original.artifact,
      original.manifest,
      original.receipt,
    ] {
    match
      @publication.publication_contract_representation_extent(
        contract, max_nodes, max_depth, max_utf16_units,
      ) {
      Ok(value) => facts.push(value)
      Err(_) => return Err(Binding(@publication.EvidenceEncoding))
    }
  }
  Ok(facts)
}
