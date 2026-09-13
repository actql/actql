///|
/// Static coverage requirement anchored to the checked Unit definition.
/// This is neither a wire attestation nor an observed completeness claim.
pub struct UnitCompletenessRequirement {
  unit_definition_cid : String
  requirement : @pipeline.CompletenessRequirement
}

///|
pub fn unit_completeness_requirement(
  program : CheckedProgram,
  unit_index : Int,
  target : @pipeline.Target,
) -> UnitCompletenessRequirement? {
  guard program.units.get(unit_index) is Some(unit) &&
    @pipeline.completeness_requirement(unit.pipeline, target)
    is Some(requirement) else {
    return None
  }
  Some({ unit_definition_cid: unit.definition_cid, requirement, })
}
