///|
test "interval singleton matches retain left order even when output hides all keys" {
  let number = @contract.primitive(NumberType, nullable=false)
  let fields : Array[(@schema.FieldName, @contract.Contract)] = [
    (Unqualified("id"), number),
    (Unqualified("at"), number),
    (Unqualified("start"), number),
    (Unqualified("end"), number),
  ]
  let row = @schema.from_fields(fields, max_fields=4, max_name_bytes=30).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let seed = "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"at\":1}]},\"as\":\"seed\"}"
  for kind in ["inner", "left"] {
    for covered in [false, true] {
      for keyed in [false, true] {
        let source = cursor(
          "[" +
          seed +
          ",{\"interval_join\":{\"with\":\"r\",\"kind\":\"" +
          kind +
          "\",\"mode\":\"point_in_interval\",\"on\":[{\"left\":\"id\",\"right\":\"" +
          (if covered { "id" } else { "start" }) +
          "\"}],\"left\":{\"time\":\"at\"},\"right\":{\"start\":\"start\",\"end\":\"end\"},\"select\":{\"value\":\"left.at\"}}},{\"take\":1}]",
        )
        let inputs = [
          (
            "r",
            if keyed {
              @pipeline_typing.KeyedInput(key)
            } else {
              @pipeline_typing.CarrierInput(carrier)
            },
          ),
        ]
        let p = @pipeline_typing.check_with_evidence(
          source,
          inputs,
          None,
          None,
          limits(),
        ).unwrap()
        let evidence = @pipeline_typing.interval_join_evidence(p, 1).unwrap()
        assert_true(evidence.assertion is None)
        assert_true(evidence.left is None)
        assert_eq(evidence.right is Some(_), covered && keyed)
        assert_eq(
          evidence.cardinality,
          if covered && keyed {
            Some(@join.Cardinality::ManyToOne)
          } else {
            None
          },
        )
        assert_true(@pipeline_typing.join_evidence(p, 1) is None)
        assert_true(@pipeline_typing.interval_join_evidence(p, -1) is None)
        assert_true(@pipeline_typing.interval_join_evidence(p, 0) is None)
        assert_eq(
          @evidence.key_witness_count(
            @pipeline_typing.candidate_keys(p, Step(1)).unwrap(),
          ),
          0,
        )
        let order = @pipeline_typing.logical_order(p, Step(1))
        assert_eq(order is Some(_), covered && keyed)
        assert_eq(
          @pipeline_typing.take_order(p, 2) is Some(_),
          covered && keyed,
        )
        if order is Some(order) {
          assert_eq(@pipeline_typing.order_dependency_count(order), 1)
          assert_eq(
            @pipeline_typing.order_dependency_at(order, 0),
            Some(Step(0)),
          )
          let producer = @pipeline_typing.order_producer(order).unwrap()
          assert_eq(@pipeline_typing.input_occurrence_count(producer), 2)
          guard producer.operation is IntervalJoin(checked~, ..) else {
            fail("interval")
          }
          assert_true(
            @join.interval_pending_validations(checked).contains(
              ValidateIntervalEndpoints,
            ),
          )
          assert_true(
            physical_equal(
              @evidence.key_source(evidence.right.unwrap()),
              @evidence.key_source(key),
            ),
          )
          assert_true(
            @evidence.key_pending(evidence.right.unwrap()).contains(
              ValidateWholeTupleUniquenessAfterInputNormalization,
            ),
          )
          let foreign_row = @schema.from_fields(
            fields,
            max_fields=4,
            max_name_bytes=30,
          ).unwrap()
          let foreign = @evidence.declare_primary_key(
            cursor("[\"id\"]"),
            @carrier.relation(@carrier.typed_rows(foreign_row)),
            { max_fields: 1, max_name_bytes: 2, },
          ).unwrap()
          assert_true(
            @evidence.select_interval_join_key(
              checked,
              Right,
              Some(@evidence.singleton_key(foreign)),
              { max_work: 100, max_name_bytes: 100, },
            )
            is Err(_),
          )
          let owned = @pipeline_typing.produced_input(p, Step(1)).unwrap()
          let consumer = @pipeline_typing.check_with_evidence(
            cursor("[{\"take\":1}]"),
            [("rows", @pipeline_typing.ProducedInput(owned))],
            None,
            None,
            limits(),
          ).unwrap()
          assert_true(@pipeline_typing.take_order(consumer, 0) is Some(_))
        }
        let used = @pipeline_typing.usage(p)
        let exact = {
          ..limits(),
          max_work: used.work,
          max_text_bytes: used.text_bytes,
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
            max_work: used.work - 1,
          })
          is Err(_),
        )
        assert_true(
          @pipeline_typing.check_with_evidence(source, inputs, None, None, {
            ..exact,
            max_text_bytes: used.text_bytes - 1,
          })
          is Err(_),
        )
      }
    }
  }
}
