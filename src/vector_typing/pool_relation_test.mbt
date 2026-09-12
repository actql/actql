///|
fn keyed_pool_input(primary : String, open : Bool) -> @evidence.KeyedRelation {
  let rows = @carrier.rows(
    [
      (
        Unqualified("code"),
        Some(@contract.primitive(StringType, nullable=false)),
      ),
      (
        Unqualified("number"),
        Some(@contract.primitive(NumberType, nullable=false)),
      ),
      (
        Unqualified("group"),
        Some(@contract.primitive(StringType, nullable=false)),
      ),
      (
        Unqualified("embedding"),
        Some(@contract.vector_contract(2, nullable=false).unwrap()),
      ),
    ],
    field_set=if open { Open } else { Closed },
    max_fields=4,
    max_name_bytes=100,
  ).unwrap()
  @evidence.declare_primary_key(cursor(primary), @carrier.relation(rows), {
    max_fields: 4,
    max_name_bytes: 100,
  }).unwrap()
}

///|
test "pool selection skips ineligible keys before choosing among alternatives" {
  let reference = @contract.read_checked(
    cursor(
      "{\"type\":\"resource_ref\",\"resource_kind\":\"file\",\"nullable\":false}",
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  for early in [None, Some(reference)] {
    let input = @carrier.relation(
      @carrier.rows(
        [
          (Unqualified("a"), early),
          (
            Unqualified("code"),
            Some(@contract.primitive(StringType, nullable=false)),
          ),
          (
            Unqualified("embedding"),
            Some(@contract.vector_contract(2, nullable=false).unwrap()),
          ),
        ],
        field_set=Closed,
        max_fields=3,
        max_name_bytes=100,
      ).unwrap(),
    )
    let a = @evidence.declare_primary_key(cursor("[\"a\"]"), input, {
      max_fields: 1,
      max_name_bytes: 10,
    }).unwrap()
    let code = @evidence.declare_primary_key(cursor("[\"code\"]"), input, {
      max_fields: 1,
      max_name_bytes: 10,
    }).unwrap()
    let source = cursor(
      "{\"by\":[\"code\"],\"vector\":\"embedding\",\"method\":\"sum\"}",
    )
    for witnesses in [[a, code], [code, a]] {
      let set = @evidence.collect_keys(source, input, witnesses, {
        max_keys: 2,
        max_work: 100,
        max_name_bytes: 100,
      }).unwrap()
      let c = @vector_typing.check_pool_keys(source, set, limits()).unwrap()
      assert_true(!@vector_typing.pool_encodes_member_key(c))
      assert_eq(
        @evidence.key_field_at(
          @vector_typing.pool_key_declaration(c).unwrap(),
          0,
        ).unwrap().name,
        Unqualified("code"),
      )
    }
    for witnesses in [[], [a]] {
      let set = @evidence.collect_keys(source, input, witnesses, {
        max_keys: 2,
        max_work: 100,
        max_name_bytes: 100,
      }).unwrap()
      assert_true(
        @vector_typing.check_pool_keys(source, set, limits())
        is Err({ kind: MissingEligiblePoolKey, .. }),
      )
    }
  }
}

///|
test "Relation pooling retains input assertions and distinct member completion paths" {
  let source = cursor(
    "{\"by\":[\"group\"],\"vector\":\"embedding\",\"method\":\"mean\"}",
  )
  for primary in ["[\"code\"]", "[\"number\"]", "[\"number\",\"code\"]"] {
    let key = keyed_pool_input(primary, false)
    let c = @vector_typing.check_pool_relation(source, key, limits()).unwrap()
    let encoded = primary != "[\"code\"]"
    assert_eq(@vector_typing.pool_encodes_member_key(c), encoded)
    assert_true(@vector_typing.pool_key_declaration(c) is Some(_))
    if primary == "[\"number\",\"code\"]" {
      let selected = @vector_typing.pool_key_declaration(c).unwrap()
      assert_eq(
        @evidence.key_field_at(selected, 0).unwrap().name,
        Unqualified("code"),
      )
      assert_eq(
        @evidence.declared_key_field_at(selected, 0).unwrap().name,
        Unqualified("number"),
      )
    }
    let pending = indexed_obligation_copy(
      @vector_typing.pool_pending(c),
      @vector_typing.pool_pending_count(c),
      i => @vector_typing.pool_pending_at(c, i),
      (a, b) => a == b,
    )
    assert_true(
      pending.contains(
        ValidateDeclaredPoolKey(
          ValidateWholeTupleUniquenessAfterInputNormalization,
        ),
      ),
    )
    assert_eq(pending.contains(EncodePoolMemberKeyByScalarLengths), encoded)
    assert_eq(pending.contains(OrderPoolMembersByEncodedIdentity), encoded)
    assert_eq(pending.contains(OrderPoolMembersByIdentity), !encoded)
    guard @vector_typing.pooled_output(c) is @carrier.VectorValue(v) else {
      abort("vectors")
    }
    assert_eq(
      @carrier.vector_identity_at(v, 0).unwrap().name,
      Unqualified("group"),
    )
    assert_true(
      @carrier.lookup(
        @carrier.vector_records(v),
        Unqualified("__actql_vector_record_id"),
      )
      is Absent,
    )
    let u = @vector_typing.pooled_usage(c)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
    }
    assert_true(@vector_typing.check_pool_relation(source, key, exact) is Ok(_))
    for
      cap in [
        { ..exact, max_work: u.work - 1, },
        { ..exact, max_nodes: u.nodes - 1, },
        { ..exact, max_text_bytes: u.text_bytes - 1, },
      ] {
      assert_true(
        @vector_typing.check_pool_relation(source, key, cap)
        is Err({ kind: BudgetExceeded, .. }),
      )
    }
  }
}

///|
test "Relation pooling requires known scalar key types and explicit component role" {
  let source = cursor(
    "{\"by\":[\"group\"],\"vector\":\"embedding\",\"method\":\"sum\"}",
  )
  let key = keyed_pool_input("[\"code\"]", true)
  assert_true(
    @vector_typing.check_pool_relation(source, key, limits()) is Ok(_),
  )
  let composite = keyed_pool_input("[\"number\",\"code\"]", true)
  assert_true(
    @vector_typing.check_pool_relation(source, composite, limits())
    is Err({ kind: UnknownOutputFields, .. }),
  )
  let unknown = @evidence.declare_primary_key(
    cursor("[\"id\"]"),
    @carrier.relation(@carrier.unknown_rows()),
    { max_fields: 1, max_name_bytes: 2, },
  ).unwrap()
  assert_true(
    @vector_typing.check_pool_relation(source, unknown, limits())
    is Err({ kind: MissingEligiblePoolKey, .. }),
  )
  assert_true(
    @vector_typing.check_pool_relation(
      cursor("{\"by\":[\"group\"],\"method\":\"sum\"}"),
      key,
      limits(),
    )
    is Err(_),
  )
}
