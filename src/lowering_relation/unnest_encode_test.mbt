///|
fn unnest_owner(body : String) -> @lowering_relation.BoundPrepared {
  let row = @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
      ),
      (
        @schema.Unqualified("items"),
        @contract.array_contract(
          @contract.primitive(NumberType, nullable=true),
          nullable=true,
          max_items=Some(2L),
        ).unwrap(),
      ),
    ],
    max_fields=2,
    max_name_bytes=7,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let checked = @pipeline.check_with_evidence(
    cursor("[{\"unnest\":" + body + "}]"),
    [("rows", @pipeline.KeyedInput(key))],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "unnest lowers its normalized outer and explicit index contract" {
  let owner = unnest_owner(
    "{\"column\":\"items\",\"as\":\"item\",\"with_index\":\"position\",\"outer\":true}",
  )
  let exact = { ..sequence_limits(), max_bindings: 3, max_name_bytes: 17, }
  let sequence = match @lowering_relation.prepare_sequence(owner, exact) {
    Ok(value) => value
    Err(
      @lowering_relation.KernelFailure(
        _,
        @lowering_relation.KernelBudgetExceeded
      )
    ) => fail("kernel budget")
    Err(
      @lowering_relation.KernelFailure(
        _,
        @lowering_relation.InvalidKernelWiring
      )
    ) => fail("kernel wiring")
    Err(_) => fail("sequence preparation")
  }
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.RowStep(kernel)) else {
    fail("unnest")
  }
  assert_eq(
    @lowering_relation.kernel_unnest(kernel),
    Some(
      (@schema.Unqualified("items"), "item", Some("position"), true, Some(2L)),
    ),
  )
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_kernel_node(kernel, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"id\":\"unnest_0\",\"in\":[\"input_0\"],\"op\":\"REL.unnest\",\"params\":{\"as\":\"item\",\"column\":\"items\",\"outer\":true,\"with_index\":\"position\"}}",
  )
  for
    limited in [
      { ..exact, max_bindings: 2, },
      { ..exact, max_name_bytes: 16, },
      { ..exact, expressions: { ..exact.expressions, max_work: 2, }, },
    ] {
    assert_true(
      @lowering_relation.prepare_sequence(owner, limited)
      is Err(
        @lowering_relation.KernelFailure(
          0,
          @lowering_relation.KernelBudgetExceeded
        )
      ),
    )
  }
}

///|
test "unnest omits an absent index and normalizes omitted outer to false" {
  let sequence = match
    @lowering_relation.prepare_sequence(
      unnest_owner("{\"column\":\"items\",\"as\":\"item\"}"),
      sequence_limits(),
    ) {
    Ok(value) => value
    Err(
      @lowering_relation.KernelFailure(
        _,
        @lowering_relation.KernelBudgetExceeded
      )
    ) => fail("kernel budget")
    Err(
      @lowering_relation.KernelFailure(
        _,
        @lowering_relation.InvalidKernelWiring
      )
    ) => fail("kernel wiring")
    Err(_) => fail("sequence preparation")
  }
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.RowStep(kernel)) else {
    fail("unnest")
  }
  assert_eq(
    @lowering_relation.kernel_unnest(kernel),
    Some((@schema.Unqualified("items"), "item", None, false, Some(2L))),
  )
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_kernel_node(kernel, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"id\":\"unnest_0\",\"in\":[\"input_0\"],\"op\":\"REL.unnest\",\"params\":{\"as\":\"item\",\"column\":\"items\",\"outer\":false}}",
  )
}
