///|
/// Failures retain their construction stage; integrity admission cannot be
/// replaced by a caller's digest or omitted when configuring the runtime.
pub(all) enum RuntimeFragmentIssue {
  Material(FragmentMaterialIssue)
  Candidate(RootArtifactIssue)
  Admission(FragmentAdmissionIssue)
  Runtime(FragmentRuntimeIssue)
}

///|
/// Consumes a typed lowering request, not source JSON or a supplied AoA graph.
/// Each bounded construction has its own physical ceiling; these ceilings are
/// not a claim to measure the process heap or cumulative preparation work.
pub fn prepare_runtime_fragment(
  request : @lower.FragmentRequest,
  contract : FragmentContract,
  demands : @lower.DemandLimits,
  physical : RegistryLimits,
  logical : @lower.FragmentRowLimits,
  ordered? : RegisteredOrderedContract? = None,
) -> Result[FragmentRuntimeContext, RuntimeFragmentIssue] {
  let material = match
    prepare_fragment_material(request, demands, physical, ordered~) {
    Ok(material) => material
    Err(issue) => return Err(Material(issue))
  }
  let candidate = match
    prepare_fragment_candidate(contract, material, physical) {
    Ok(candidate) => candidate
    Err(issue) => return Err(Candidate(issue))
  }
  let checked = match check_generated_fragment(candidate, demands, physical) {
    Ok(checked) => checked
    Err(issue) => return Err(Admission(issue))
  }
  match prepare_fragment_runtime_context(checked, logical, physical) {
    Ok(context) => Ok(context)
    Err(issue) => Err(Runtime(issue))
  }
}
