///|
test "set operators retain only left key evidence even with a wider output contract" {
  let number = @contract.primitive(NumberType, nullable=false)
  let left_schema = @schema.from_fields(
    [(Unqualified("id"), number)],
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  let left = @carrier.relation(@carrier.typed_rows(left_schema))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), left, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  for op in ["except", "intersect"] {
    for duplicates in ["all", "distinct"] {
      for wider in [false, true] {
        let right_schema = @schema.from_fields(
          [(Unqualified("id"), @contract.with_nullability(number, wider))],
          max_fields=1,
          max_name_bytes=2,
        ).unwrap()
        for keyed in [false, true] {
          let inputs = [
            (
              "l",
              if keyed {
                @pipeline_typing.KeyedInput(key)
              } else {
                @pipeline_typing.CarrierInput(left)
              },
            ),
            (
              "r",
              if wider {
                @pipeline_typing.CarrierInput(
                  @carrier.relation(@carrier.typed_rows(right_schema)),
                )
              } else {
                @pipeline_typing.KeyedInput(key)
              },
            ),
          ]
          let source = cursor(
            "[{\"" +
            op +
            "\":{\"with\":\"r\",\"duplicates\":\"" +
            duplicates +
            "\"},\"from\":\"l\"},{\"sort\":[{\"id\":\"desc\"}]}]",
          )
          let p = @pipeline_typing.check_with_evidence(
            source,
            inputs,
            None,
            None,
            limits(),
          ).unwrap()
          assert_eq(
            @pipeline_typing.candidate_key(p, Step(0)) is Some(_),
            keyed,
          )
          assert_eq(
            @pipeline_typing.logical_order(p, Step(1)) is Some(_),
            keyed,
          )
          assert_eq(
            @schema.lookup(
              @pipeline_typing.schema_at(p, Step(0)).unwrap(),
              Unqualified("id"),
            ).unwrap().nullable,
            wider,
          )
          if keyed {
            let retained = @pipeline_typing.candidate_key(p, Step(0)).unwrap()
            assert_eq(
              @evidence.key_pending(retained),
              @evidence.key_pending(key),
            )
            assert_true(
              !@evidence.key_field_at(retained, 0).unwrap().contract.unwrap().nullable,
            )
            let completion = @pipeline_typing.order_sort_completion(
              @pipeline_typing.logical_order(p, Step(1)).unwrap(),
            ).unwrap()
            assert_eq(@pipeline_typing.sort_completion_count(completion), 0)
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
            @pipeline_typing.check_with_evidence(
              source,
              inputs,
              None,
              None,
              exact,
            )
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
    }
  }
}

///|
test "set key transfer rejects keys attached to a different left schema" {
  let rows = @carrier.relation(@carrier.typed_rows(schema()))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), rows, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let p = @pipeline_typing.check_carriers(
    cursor("[{\"except\":{\"with\":\"rows\",\"duplicates\":\"all\"}}]"),
    [("rows", rows)],
    None,
    None,
    limits(),
  ).unwrap()
  guard @pipeline_typing.step_at(p, 0).unwrap().operation
    is @pipeline_typing.Set(checked~, ..) else {
    abort("expected set")
  }
  let set = @evidence.singleton_key(key)
  assert_eq(
    @evidence.transfer_set_keys(set, checked, {
      max_work: 2,
      max_name_bytes: 0,
    }).unwrap().work,
    2,
  )
  assert_eq(
    @evidence.transfer_set_keys(set, checked, {
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
    @evidence.transfer_set_keys(@evidence.singleton_key(other), checked, {
      max_work: 2,
      max_name_bytes: 0,
    }).unwrap_err().kind,
    InputContractMismatch,
  )
}
