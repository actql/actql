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
