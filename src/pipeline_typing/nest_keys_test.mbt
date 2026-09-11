///|
test "nest preserves parent keys independently of child keys" {
  let rows = @carrier.relation(@carrier.typed_rows(schema()))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), rows, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  for keyed in [false, true] {
    let inputs = [
      (
        "parent",
        if keyed {
          @pipeline_typing.KeyedInput(key)
        } else {
          @pipeline_typing.CarrierInput(rows)
        },
      ),
      ("child", @pipeline_typing.KeyedInput(key)),
    ]
    let source = cursor(
      "[{\"select\":[{\"a\":\"id\"},{\"b\":\"id\"},\"amount\"],\"from\":\"parent\"},{\"nest\":{\"with\":\"child\",\"on\":[{\"left\":\"a\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"amount\"]}},{\"drop\":[\"a\"]},{\"sort\":[{\"b\":\"desc\"}]}]",
    )
    let p = @pipeline_typing.check_with_evidence(
      source,
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    assert_eq(@pipeline_typing.candidate_key(p, Step(1)) is Some(_), keyed)
    assert_eq(@pipeline_typing.logical_order(p, Step(3)) is Some(_), keyed)
    if keyed {
      let retained = @pipeline_typing.candidate_key(p, Step(1)).unwrap()
      assert_eq(@evidence.key_alias_count(retained, 0), 2)
      assert_eq(@evidence.key_pending(retained), @evidence.key_pending(key))
      assert_eq(
        @evidence.declared_key_field_at(retained, 0).unwrap().name,
        Unqualified("id"),
      )
      assert_eq(
        @evidence.key_field_at(
          @pipeline_typing.candidate_key(p, Step(2)).unwrap(),
          0,
        ).unwrap().name,
        Unqualified("b"),
      )
    }
    let u = @pipeline_typing.usage(p)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_text_bytes: u.text_bytes,
      max_nodes: u.nodes,
      max_tokens: u.tokens,
    }
    assert_true(
      @pipeline_typing.check_with_evidence(source, inputs, None, None, exact)
      is Ok(_),
    )
    assert_true(
      @pipeline_typing.check_with_evidence(source, inputs, None, None, {
        ..exact,
        max_work: u.work - 1,
      })
      is Err(_),
    )
  }
}

///|
test "nest transfer validates the exact parent and inclusive copying budget" {
  let rows = @carrier.relation(@carrier.typed_rows(schema()))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), rows, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"nest\":{\"with\":\"rows\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"amount\"]}}]",
    ),
    [("rows", rows)],
    None,
    None,
    limits(),
  ).unwrap()
  guard @pipeline_typing.step_at(p, 0).unwrap().operation
    is @pipeline_typing.Nest(checked~, ..) else {
    abort("expected nest")
  }
  let set = @evidence.singleton_key(key)
  let t = @evidence.transfer_nest_keys(set, checked, {
    max_work: 2,
    max_name_bytes: 0,
  }).unwrap()
  assert_eq(t.work, 2)
  assert_eq(t.name_bytes, 0)
  assert_eq(@evidence.key_witness_count(t.keys), 1)
  assert_eq(
    @evidence.transfer_nest_keys(set, checked, {
      max_work: 1,
      max_name_bytes: 0,
    }).unwrap_err().kind,
    LimitExceeded,
  )
  let other = @evidence.declare_primary_key(
    cursor("[\"id\"]"),
    @carrier.relation(@carrier.typed_rows(schema())),
    { max_fields: 1, max_name_bytes: 2, },
  ).unwrap()
  assert_eq(
    @evidence.transfer_nest_keys(@evidence.singleton_key(other), checked, {
      max_work: 2,
      max_name_bytes: 0,
    }).unwrap_err().kind,
    InputContractMismatch,
  )
}
