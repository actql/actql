///|
test "runtime preparation never bypasses fragment admission or declared ordered limits" {
  let sequence = prepared_sequence(
    row_owner(",{\"derive\":[{\"old\":\"a\"},{\"a\":\"old + 1\"}]}"),
  )
  let context = ordered_sequence_fragment_context(sequence, 10000L)
  let candidate = context.fragment.candidate
  let request = candidate.material.request.request
  let ordered = candidate.material.ordered.unwrap().node.params.contract
  let build = fn(contract, physical, logical, extension) {
    prepare_runtime_fragment(
      request,
      contract,
      material_demands(),
      physical,
      logical,
      ordered=extension,
    )
  }
  assert_true(
    build(candidate.contract, registry_limits(), context.limits, None)
    is Err(Material(OrderedContractRequired)),
  )
  assert_true(
    build(
      { ..candidate.contract, cid: "sha256:wrong", },
      registry_limits(),
      context.limits,
      Some(ordered),
    )
    is Err(Admission(InvalidContract)),
  )
  assert_true(
    build(
      candidate.contract,
      registry_limits(),
      { ..context.limits, max_work: 10001L, },
      Some(ordered),
    )
    is Err(Runtime(ExceedsRequest)),
  )
  assert_true(
    build(
      candidate.contract,
      { ..registry_limits(), max_body_bytes: 0, },
      context.limits,
      Some(ordered),
    )
    is Err(Material(_)),
  )
  let rebuilt = build(
    candidate.contract,
    registry_limits(),
    context.limits,
    Some(ordered),
  ).unwrap()
  assert_eq(rebuilt.fragment.candidate.artifact.cid, candidate.artifact.cid)
  assert_true(physical_equal(rebuilt.kernel, context.kernel))
}

///|
test "wide compiler codec keeps the complete measured Fragment above its runtime floor" {
  let sequence = prepared_sequence(
    row_owner(",{\"derive\":[{\"old\":\"a\"},{\"a\":\"old + 1\"}]}"),
  )
  let original = ordered_sequence_fragment_context(sequence, 10000L)
  let candidate = original.fragment.candidate
  let request = candidate.material.request.request
  let ordered = candidate.material.ordered.unwrap().node.params.contract
  let wide = {
    ..registry_limits(),
    max_body_bytes: 2000000,
    max_body_nodes: 2000000,
  }
  let legacy = prepare_runtime_fragment(
    request,
    candidate.contract,
    material_demands(),
    wide,
    original.limits,
    ordered=Some(ordered),
  ).unwrap()
  assert_eq(legacy.physical.max_body_bytes, wide.max_body_bytes)
  assert_eq(legacy.physical.max_body_nodes, wide.max_body_nodes)
  assert_eq(legacy.physical.max_body_depth, wide.max_body_depth)
  let runtime = prepare_runtime_fragment(
    request,
    candidate.contract,
    material_demands(),
    wide,
    original.limits,
    ordered=Some(ordered),
    runtime_body_floor=Some({
      max_body_bytes: 100,
      max_body_nodes: 10,
      max_body_depth: wide.max_body_depth,
    }),
  ).unwrap()
  let measured = runtime.fragment.candidate.artifact
  assert_true(measured.bytes > 100 && measured.nodes > 10)
  assert_eq(runtime.physical.max_body_bytes, measured.bytes)
  assert_eq(runtime.physical.max_body_nodes, measured.nodes)
  assert_eq(runtime.physical.max_body_depth, wide.max_body_depth)
  assert_eq(measured.cid, legacy.fragment.candidate.artifact.cid)
  assert_true(physical_equal(runtime.kernel, original.kernel))
  assert_true(
    physical_equal(runtime.fragment.candidate.material.request.request, request),
  )
  assert_eq(runtime.limits.max_work, original.limits.max_work)
  assert_eq(runtime.limits.max_value_bytes, original.limits.max_value_bytes)
  assert_eq(
    runtime.limits.max_live_value_bytes,
    original.limits.max_live_value_bytes,
  )
  assert_true(
    prepare_runtime_fragment(
      request,
      candidate.contract,
      material_demands(),
      wide,
      original.limits,
      ordered=Some(ordered),
      runtime_body_floor=Some({ ..wide, max_body_nodes: -1, }),
    )
    is Err(Runtime(InvalidLimits)),
  )
}
