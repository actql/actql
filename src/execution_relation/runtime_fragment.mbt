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
  prepare_runtime_fragment_owned(
    request, contract, demands, physical, logical, ordered,
  )
}

///|
// Fixed production constructors; package-private ports expose actual stage
// work to focused regressions without a global counter or a public callback.
fn prepare_runtime_fragment_owned(
  request : @lower.FragmentRequest,
  contract : FragmentContract,
  demands : @lower.DemandLimits,
  physical : RegistryLimits,
  logical : @lower.FragmentRowLimits,
  ordered : RegisteredOrderedContract?,
  material_builder? : (
    @lower.FragmentRequest,
    @lower.DemandLimits,
    RegistryLimits,
    RegisteredOrderedContract?,
  ) -> Result[FragmentMaterial, FragmentMaterialIssue] = fn(
    request,
    demands,
    physical,
    ordered,
  ) {
    prepare_fragment_material(request, demands, physical, ordered~)
  },
  candidate_builder? : (FragmentContract, FragmentMaterial, RegistryLimits) -> Result[
    FragmentCandidate,
    RootArtifactIssue,
  ] = prepare_fragment_candidate,
) -> Result[FragmentRuntimeContext, RuntimeFragmentIssue] {
  let material = match material_builder(request, demands, physical, ordered) {
    Ok(material) => material
    Err(issue) => return Err(Material(issue))
  }
  let candidate = match candidate_builder(contract, material, physical) {
    Ok(candidate) => candidate
    Err(issue) => return Err(Candidate(issue))
  }
  // Read the completed envelope's measured extent; never emit or hash it
  // again to enforce this operation's selected physical bounds.
  if candidate.artifact.bytes > physical.max_body_bytes ||
    candidate.artifact.nodes > physical.max_body_nodes {
    return Err(Candidate(OutputLimit))
  }
  if contract.cid != selected_fragment_contract_cid ||
    contract.relations.registry_cid != selected_registry_cid ||
    contract.relations.values_contract_cid != selected_values_contract_cid {
    return Err(Admission(InvalidContract))
  }
  // These are the completed facts from this operation's fixed private
  // constructors, under the same request, demands and physical limits. No
  // supplied candidate or application callback enters the production path.
  // Keep the full separate-candidate checker for independently supplied or
  // altered material; a remembered CID alone never selects this constructor.
  let checked : CheckedFragment = { candidate, }
  match prepare_fragment_runtime_context(checked, logical, physical) {
    Ok(context) => Ok(context)
    Err(issue) => Err(Runtime(issue))
  }
}
