///|
fn unpivot_owner() -> @lowering_relation.BoundPrepared {
  let row = @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
      ),
      (
        @schema.Unqualified("jan"),
        @contract.primitive(NumberType, nullable=true),
      ),
      (
        @schema.Unqualified("feb"),
        @contract.primitive(NumberType, nullable=true),
      ),
    ],
    max_fields=3,
    max_name_bytes=8,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let checked = @pipeline.check_with_evidence(
    cursor(
      "[{\"unpivot\":{\"columns\":[\"jan\",\"feb\",\"jan\"],\"keep\":[\"id\",\"jan\"],\"name_column\":\"metric\",\"value_column\":\"amount\"}}]",
    ),
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
test "unpivot lowers repeated columns and overlapping kept fields exactly" {
  let owner = unpivot_owner()
  let exact = { ..sequence_limits(), max_bindings: 7, max_name_bytes: 26, }
  let sequence = @lowering_relation.prepare_sequence(owner, exact).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.RowStep(kernel)) else {
    fail("unpivot")
  }
  assert_eq(@lowering_relation.kernel_unpivot_column_count(kernel), 3)
  assert_eq(@lowering_relation.kernel_unpivot_keep_count(kernel), 2)
  assert_eq(
    @lowering_relation.kernel_unpivot_outputs(kernel),
    Some(("metric", "amount")),
  )
  assert_eq(
    @lowering_relation.kernel_unpivot_column_at(kernel, 0),
    Some(@schema.Unqualified("jan")),
  )
  assert_eq(
    @lowering_relation.kernel_unpivot_column_at(kernel, 2),
    Some(@schema.Unqualified("jan")),
  )
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_kernel_node(kernel, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"id\":\"unpivot_0\",\"in\":[\"input_0\"],\"op\":\"REL.unpivot\",\"params\":{\"columns\":[\"jan\",\"feb\",\"jan\"],\"keep\":[\"id\",\"jan\"],\"name_column\":\"metric\",\"value_column\":\"amount\"}}",
  )
  for
    limited in [
      { ..exact, max_bindings: 6, },
      { ..exact, max_name_bytes: 25, },
      { ..exact, expressions: { ..exact.expressions, max_work: 6, }, },
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
