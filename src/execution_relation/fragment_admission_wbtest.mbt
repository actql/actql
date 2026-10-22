///|
fn admission_candidate(value : String) -> FragmentCandidate raise {
  let material = prepare_fragment_material(
    artifact_request("{\"literal\":" + value + "}", 10L),
    material_demands(),
    registry_limits(),
  ).unwrap()
  prepare_fragment_candidate(
    test_fragment_contract(),
    material,
    registry_limits(),
  ).unwrap()
}

///|
test "generated fragment rechecks complete value and retains only regenerated material" {
  let candidate = admission_candidate("7")
  let checked = check_generated_fragment(
    candidate,
    material_demands(),
    registry_limits(),
  ).unwrap()
  assert_eq(checked.candidate.artifact.cid, candidate.artifact.cid)
  assert_false(physical_equal(checked.candidate.material, candidate.material))
  assert_true(
    physical_equal(
      checked.candidate.material.request.request,
      candidate.material.request.request,
    ),
  )
  let other = admission_candidate("8")
  let forged_digest = {
    ..candidate,
    artifact: { ..candidate.artifact, cid: other.artifact.cid, },
  }
  assert_true(
    check_generated_fragment(
      forged_digest,
      material_demands(),
      registry_limits(),
    )
    is Err(Integrity),
  )
  // A correctly hashed but unrelated body cannot be combined with this owner.
  assert_true(
    check_generated_fragment(
      { ..candidate, artifact: other.artifact, },
      material_demands(),
      registry_limits(),
    )
    is Err(Integrity),
  )
  // Altering cached projection must not hide behind the correct stored body.
  assert_true(
    check_generated_fragment(
      {
        ..candidate,
        material: { ..candidate.material, graph: other.material.graph, },
      },
      material_demands(),
      registry_limits(),
    )
    is Err(Integrity),
  )
  assert_true(
    check_generated_fragment(
      {
        ..candidate,
        material: { ..candidate.material, roots: other.material.roots, },
      },
      material_demands(),
      registry_limits(),
    )
    is Err(Integrity),
  )
  let false_contract = {
    ..candidate.contract,
    cid: "sha256:0000000000000000000000000000000000000000000000000000000000000000",
  }
  assert_true(
    check_generated_fragment(
      { ..candidate, contract: false_contract, },
      material_demands(),
      registry_limits(),
    )
    is Err(InvalidContract),
  )
  assert_true(
    check_generated_fragment(candidate, material_demands(), {
      ..registry_limits(),
      max_body_bytes: 1,
    })
    is Err(_),
  )
  assert_true(
    check_generated_fragment(
      candidate,
      { ..material_demands(), max_roots: 0, },
      registry_limits(),
    )
    is Err(Material(_)),
  )
  candidate.material.roots.clear()
  assert_eq(checked.candidate.material.roots.length(), 1)
  assert_true(
    check_generated_fragment(candidate, material_demands(), registry_limits())
    is Err(Integrity),
  )
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
