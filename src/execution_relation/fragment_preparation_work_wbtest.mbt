///|
test "fresh fragment preparation builds each unchanged stage once" {
  let request = admission_candidate("7").material.request.request
  let counts = [0, 0]
  let materials : Array[FragmentMaterial] = []
  let candidates : Array[FragmentCandidate] = []
  let context = prepare_runtime_fragment_owned(
    request,
    test_fragment_contract(),
    material_demands(),
    registry_limits(),
    {
      max_input_rows: 10L,
      max_value_bytes: 1000L,
      max_live_value_bytes: 10000L,
      max_work: 100000L,
    },
    None,
    material_builder=fn(request, demands, physical, ordered) {
      counts[0] += 1
      let result = prepare_fragment_material(
        request,
        demands,
        physical,
        ordered~,
      )
      if result is Ok(value) {
        materials.push(value)
      }
      result
    },
    candidate_builder=fn(contract, material, physical) {
      counts[1] += 1
      let result = prepare_fragment_candidate(contract, material, physical)
      if result is Ok(value) {
        candidates.push(value)
      }
      result
    },
  ).unwrap()
  println(
    "fragment preparation stages: material=" +
    counts[0].to_string() +
    " candidate=" +
    counts[1].to_string() +
    " cid=" +
    context.fragment.candidate.artifact.cid,
  )
  assert_eq(counts, [1, 1])
  assert_true(physical_equal(context.fragment.candidate, candidates[0]))
  assert_true(physical_equal(context.fragment.candidate.material, materials[0]))
  // This is regression correspondence with the existing full checker, not an
  // independent canonical-identity oracle or an arbitrary JSON execution port.
  let rechecked = check_generated_fragment(
    context.fragment.candidate,
    material_demands(),
    registry_limits(),
  ).unwrap()
  assert_eq(
    rechecked.candidate.artifact.cid,
    context.fragment.candidate.artifact.cid,
  )
  assert_eq(
    @identity.stringify_value(
      rechecked.candidate.artifact.value,
      10000,
      10000,
      100,
    ),
    @identity.stringify_value(
      context.fragment.candidate.artifact.value,
      10000,
      10000,
      100,
    ),
  )
  assert_false(physical_equal(rechecked.candidate.material, materials[0]))
}

///|
test "fresh fragment preparation applies selected bounds to retained envelope metrics" {
  let request = admission_candidate("7").material.request.request
  let physical = registry_limits()
  assert_true(
    prepare_runtime_fragment_owned(
      request,
      test_fragment_contract(),
      material_demands(),
      physical,
      {
        max_input_rows: 10L,
        max_value_bytes: 1000L,
        max_live_value_bytes: 10000L,
        max_work: 100000L,
      },
      None,
      candidate_builder=fn(contract, material, bounds) {
        let candidate = prepare_fragment_candidate(contract, material, bounds).unwrap()
        Ok({
          ..candidate,
          artifact: { ..candidate.artifact, bytes: bounds.max_body_bytes + 1, },
        })
      },
    )
    is Err(Candidate(OutputLimit)),
  )
}
