///|
fn pool_input(nullable : Bool) -> @carrier.Carrier {
  let rows = @carrier.rows(
    [
      (
        Unqualified("record"),
        Some(@contract.primitive(NumberType, nullable=false)),
      ),
      (Unqualified("group"), Some(@contract.primitive(NumberType, nullable~))),
      (
        Unqualified("embedding"),
        Some(@contract.vector_contract(3, nullable=false).unwrap()),
      ),
      (Unqualified("member_count"), None),
    ],
    field_set=Open,
    max_fields=4,
    max_name_bytes=100,
  ).unwrap()
  @carrier.vectors(
    rows,
    ids=[Unqualified("record")],
    components=Unqualified("embedding"),
    max_identity_fields=1,
  ).unwrap()
}

///|
test "pool Vectors retains grouping values and aliases without physical ID substitution" {
  let input = pool_input(false)
  for reduction in ["mean", "sum", "max"] {
    let source = cursor(
      "{\"by\":[\"group\"],\"method\":\"" +
      reduction +
      "\",\"output_id\":\"group_id\"}",
    )
    let c = @vector_typing.check_pool_vectors(source, input, limits()).unwrap()
    guard @vector_typing.pooled_output(c) is @carrier.VectorValue(v) else {
      abort("pooled vectors")
    }
    assert_eq(
      @carrier.vector_identity_at(v, 0).unwrap().name,
      Unqualified("group_id"),
    )
    assert_eq(@carrier.vector_components(v).name, Unqualified("embedding"))
    assert_eq(@carrier.vector_dimensions(v), 3.0)
    let rows = @carrier.vector_records(v)
    assert_eq(@carrier.field_set(rows), Closed)
    assert_eq(@carrier.field_count(rows), 4)
    assert_true(
      @carrier.lookup(rows, Unqualified("group"))
      is Present({ contract: Some(_), .. }),
    )
    assert_true(@carrier.lookup(rows, Unqualified("record")) is Absent)
    assert_true(
      @carrier.lookup(rows, Unqualified("member_count"))
      is Present({ contract: Some({ shape: @contract.Number, .. }), .. }),
    )
    assert_true(
      indexed_obligation_copy(
        @vector_typing.pool_pending(c),
        @vector_typing.pool_pending_count(c),
        i => @vector_typing.pool_pending_at(c, i),
        (a, b) => a == b,
      ).contains(ValidatePoolMemberIdentityGlobally),
    )
    assert_true(
      indexed_obligation_copy(
        @vector_typing.pool_pending(c),
        @vector_typing.pool_pending_count(c),
        i => @vector_typing.pool_pending_at(c, i),
        (a, b) => a == b,
      ).contains(QuantizeBeforeAndAfterPoolFold),
    )
    let u = @vector_typing.pooled_usage(c)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
    }
    assert_true(
      @vector_typing.check_pool_vectors(source, input, exact) is Ok(_),
    )
    for
      cap in [
        { ..exact, max_work: u.work - 1, },
        { ..exact, max_nodes: u.nodes - 1, },
        { ..exact, max_text_bytes: u.text_bytes - 1, },
      ] {
      assert_true(
        @vector_typing.check_pool_vectors(source, input, cap)
        is Err({ kind: BudgetExceeded, .. }),
      )
    }
  }
}

///|
test "pool rejects invalid group identity and actual output collisions" {
  let source = cursor("{\"by\":[\"group\"],\"method\":\"mean\"}")
  assert_true(
    @vector_typing.check_pool_vectors(source, pool_input(true), limits())
    is Err({ kind: InvalidRole(_), .. }),
  )
  for
    text in [
      "{\"by\":[\"group\"],\"method\":\"mean\",\"output_id\":\"member_count\"}",
      "{\"by\":[\"group\"],\"method\":\"mean\",\"output_id\":\"embedding\"}", "{\"by\":[\"missing\"],\"method\":\"mean\"}",
      "{\"by\":[\"embedding\"],\"method\":\"mean\"}", "{\"by\":[\"group\"],\"method\":\"mean\",\"vector\":\"other\"}",
    ] {
    assert_true(
      @vector_typing.check_pool_vectors(
        cursor(text),
        pool_input(false),
        limits(),
      )
      is Err(_),
    )
  }
  let c = @vector_typing.check_pool_vectors(
    cursor("{\"by\":[\"group\"],\"method\":\"mean\",\"output_id\":\"group\"}"),
    pool_input(false),
    limits(),
  ).unwrap()
  guard @vector_typing.pooled_output(c) is @carrier.VectorValue(v) else {
    abort("vectors")
  }
  assert_eq(@carrier.field_count(@carrier.vector_records(v)), 3)
}
