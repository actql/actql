///|
/// Regenerated generated-fragment integrity. Runtime input obligations and
/// backend limits still have to be discharged before evaluating its kernel.
/// This is intentionally not an arbitrary saved-JSON execution entry.
priv struct CheckedFragment {
  candidate : FragmentCandidate
}

///|
pub(all) enum FragmentAdmissionIssue {
  InvalidContract
  Integrity
  Material(FragmentMaterialIssue)
  Artifact(RootArtifactIssue)
  Budget
}

///|
fn check_generated_fragment(
  candidate : FragmentCandidate,
  demand_limits : @lower.DemandLimits,
  budget : RegistryLimits,
) -> Result[CheckedFragment, FragmentAdmissionIssue] {
  if budget.max_body_bytes < 0 ||
    budget.max_body_nodes < 1 ||
    budget.max_body_depth < 0 {
    return Err(Budget)
  }
  if candidate.contract.cid != selected_fragment_contract_cid ||
    candidate.contract.relations.registry_cid != selected_registry_cid ||
    candidate.contract.relations.values_contract_cid !=
    selected_values_contract_cid {
    return Err(InvalidContract)
  }
  // Rebuild from the retained checked request, not cached graph/root bodies.
  let material = match
    prepare_fragment_material(
      candidate.material.request.request,
      demand_limits,
      budget,
      ordered=candidate.material.ordered.map(binding => {
        binding.node.params.contract
      }),
    ) {
    Ok(material) => material
    Err(issue) => return Err(Material(issue))
  }
  let rebuilt = match
    prepare_fragment_candidate(candidate.contract, material, budget) {
    Ok(rebuilt) => rebuilt
    Err(issue) => return Err(Artifact(issue))
  }
  try {
    let expected = @identity.stringify_value(
      rebuilt.artifact.value,
      budget.max_body_bytes,
      budget.max_body_nodes,
      budget.max_body_depth,
    )
    let claimed = @identity.stringify_value(
      candidate.artifact.value,
      budget.max_body_bytes,
      budget.max_body_nodes,
      budget.max_body_depth,
    )
    if candidate.artifact.cid != rebuilt.artifact.cid || claimed != expected {
      return Err(Integrity)
    }
    // Cached material used by the emitter must agree as well; matching a
    // remembered CID cannot conceal swapped graph/roots/request metadata.
    let projected = match
      prepare_fragment_candidate(candidate.contract, candidate.material, budget) {
      Ok(projected) => projected
      Err(issue) => return Err(Artifact(issue))
    }
    let projected_text = @identity.stringify_value(
      projected.artifact.value,
      budget.max_body_bytes,
      budget.max_body_nodes,
      budget.max_body_depth,
    )
    if projected_text != expected {
      return Err(Integrity)
    }
    // Keep only regenerated material so execution cannot inherit caller-held
    // preparation arrays, even inside this package.
    Ok({ candidate: rebuilt, })
  } catch {
    _ => Err(Budget)
  }
}
