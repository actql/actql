///|
fn params_for(tail : String) -> OrderedParams raise {
  let sequence = prepared_sequence(row_owner(tail))
  guard @lower.sequence_step(sequence, 1) is Some(@lower.RowStep(kernel)) else {
    fail("kernel")
  }
  let refs = @lower.prepare_ordered_references(kernel, {
    max_references: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let registered = admit_ordered_contract(
    registered_relation_contracts(),
    registered_ordered(),
    registry_limits(),
  ).unwrap()
  prepare_ordered_params(registered, refs)
}

///|
test "ordered contract admission validates the body not an asserted digest" {
  let selected = registered_relation_contracts()
  let body = registered_ordered()
  let limits = registry_limits()
  let registered = admit_ordered_contract(selected, body, limits).unwrap()
  assert_eq(
    registered.cid,
    "sha256:90f5a71e31aa6a60c1961b7039a87f3a2849c4a793aaba3d776a166176fc28b9",
  )
  assert_true(physical_equal(registered.relation, selected))
  assert_true(
    admit_ordered_contract(selected, registered_values(), limits)
    is Err(OrderedContractMismatch),
  )
  for
    cap in [
      { ..limits, max_body_bytes: 0, },
      { ..limits, max_body_nodes: 0, },
      { ..limits, max_body_depth: 0, },
    ] {
    assert_true(
      admit_ordered_contract(selected, body, cap)
      is Err(OrderedContractBodyLimit),
    )
  }
  assert_true(
    admit_ordered_contract(selected, body, { ..limits, max_body_bytes: -1, })
    is Err(InvalidOrderedContractLimits),
  )
}

///|
test "ordered params join bindings references and pin from one retained kernel" {
  let params = params_for(",{\"derive\":[{\"old\":\"a\"},{\"a\":\"old + 1\"}]}")
  let writer = @encode.writer(100000, 10000, 100)
  emit_ordered_params(params, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"bindings\":[{\"expr\":{\"body\":\"a\",\"op\":\"field\"},\"name\":\"old\"},{\"expr\":{\"body\":[{\"body\":\"old\",\"op\":\"field\"},{\"body\":1,\"op\":\"literal\"}],\"op\":\"add\"},\"name\":\"a\"}],\"references\":[{\"at\":\"/bindings/0/expr\",\"target\":{\"input_field\":\"a\"}},{\"at\":\"/bindings/1/expr/body/0\",\"target\":{\"prior_slot\":0}}],\"row_kernel_contract_cid\":\"sha256:90f5a71e31aa6a60c1961b7039a87f3a2849c4a793aaba3d776a166176fc28b9\"}",
  )
  assert_true(
    physical_equal(ordered_params_registry(params), params.contract.relation),
  )
  assert_true(
    physical_equal(
      ordered_params_kernel(params),
      @lower.ordered_reference_kernel(params.references),
    ),
  )
  let other = params_for(",{\"derive\":[{\"old\":\"b\"},{\"a\":\"old + 1\"}]}")
  assert_false(
    physical_equal(ordered_params_kernel(params), ordered_params_kernel(other)),
  )
  // Exposed binding views are detached; mutating one cannot mismatch evidence.
  guard @lower.kernel_body(ordered_params_kernel(params))
    is @lower.OrderedBindings(bindings) else {
    fail("ordered")
  }
  bindings.clear()
  let again = @encode.writer(100000, 10000, 100)
  emit_ordered_params(params, again)
  assert_true(@encode.finish(again).contains("\"old\""))
}

///|
test "ordered params output budget spans bindings and references atomically" {
  let params = params_for(",{\"derive\":[{\"x\":\"a + b\"}]}")
  let large = @encode.writer(100000, 10000, 100)
  emit_ordered_params(params, large)
  let expected = @encode.finish(large)
  let exact = @encode.writer(expected.length(), 10000, 100)
  emit_ordered_params(params, exact)
  assert_eq(@encode.finish(exact), expected)
  let short = @encode.writer(expected.length() - 1, 10000, 100)
  assert_true(
    try {
      emit_ordered_params(params, short)
      false
    } catch {
      @encode.OutputLimit => true
      _ => false
    },
  )
  assert_true(
    try {
      let _ = @encode.finish(short)
      false
    } catch {
      _ => true
    },
  )
}
