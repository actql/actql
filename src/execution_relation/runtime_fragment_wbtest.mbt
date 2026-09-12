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
