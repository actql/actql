///|
fn ordered_candidate_fixture() -> FragmentCandidate raise {
  let sequence = prepared_sequence(
    row_owner(",{\"derive\":[{\"old\":\"a\"},{\"a\":\"old + 1\"}]}"),
  )
  let context = execution_for(sequence, 10000L).contexts[0]
  let pipeline = @lower.prepare_fragment_pipeline(sequence, 1, {
    max_roots: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
  }).unwrap()
  let request = @lower.prepare_fragment_request(
    pipeline,
    10L,
    1000L,
    row_limits=Some(context.limits),
  ).unwrap()
  assert_true(
    prepare_fragment_material(request, material_demands(), registry_limits())
    is Err(OrderedContractRequired),
  )
  let material = prepare_fragment_material(
    request,
    material_demands(),
    registry_limits(),
    ordered=Some(context.params.contract),
  ).unwrap()
  prepare_fragment_candidate(
    test_fragment_contract(),
    material,
    registry_limits(),
  ).unwrap()
}

///|
test "ordered request generates complete fragment and regenerates all evidence at admission" {
  let candidate = ordered_candidate_fixture()
  let checked = check_generated_fragment(
    candidate,
    material_demands(),
    registry_limits(),
  ).unwrap()
  guard checked.candidate.material.ordered is Some(binding) else {
    fail("ordered")
  }
  assert_eq(
    binding.node.graph.cid,
    "sha256:45961666ce15c01a481fc383d390b4b1f86b152d0fb918bf4ccc69aeb4733755",
  )
  let text = @identity.stringify_value(
    checked.candidate.artifact.value,
    100000,
    10000,
    100,
  )
  assert_true(text.contains("\"row_kernel_evidence\""))
  assert_true(text.contains("\"row_kernel_limits\""))
  assert_true(text.contains(binding.artifact.cid))
  assert_true(text.contains(binding.links.limits.cid))
  assert_eq(checked.candidate.material.roots.length(), 2)
  for i = 0; i < 2; i = i + 1 {
    assert_eq(
      checked.candidate.material.roots[i].cid,
      binding.links.slots[i].root.cid,
    )
  }
  let out = @encode.writer(100000, 10000, 100)
  emit_fragment_candidate(checked.candidate, registry_limits(), out)
  let body = @json.parse(@encode.finish(out))
  guard body is Object(fields) else { fail("fragment") }
  assert_true(
    fields.get("fragment_cid") is Some(String(cid)) &&
    cid == candidate.artifact.cid,
  )
  fields.remove("fragment_cid") |> ignore
  let preimage = @identity.from_json(body, 10000, 100, 100000)
  assert_eq(
    @identity.cid_value(preimage, 100000, 10000, 100),
    candidate.artifact.cid,
  )
  candidate.material.roots.clear()
  assert_eq(checked.candidate.material.roots.length(), 2)
}

///|
test "ordered fragment rejects missing or tampered cached evidence despite retained candidate digest" {
  let candidate = ordered_candidate_fixture()
  let missing = {
    ..candidate,
    material: { ..candidate.material, ordered: None, },
  }
  assert_true(
    check_generated_fragment(missing, material_demands(), registry_limits())
    is Err(Material(OrderedContractRequired)),
  )
  guard candidate.material.ordered is Some(binding) else { fail("binding") }
  let altered = {
    ..binding,
    artifact: { ..binding.artifact, cid: binding.node.graph.cid, },
  }
  let wrong = {
    ..candidate,
    material: { ..candidate.material, ordered: Some(altered), },
  }
  assert_true(
    check_generated_fragment(wrong, material_demands(), registry_limits())
    is Err(Integrity),
  )
  assert_true(
    prepare_fragment_material(
      candidate.material.request.request,
      material_demands(),
      { ..registry_limits(), max_body_bytes: 1000, },
      ordered=Some(binding.node.params.contract),
    )
    is Err(_),
  )
}
