///|
// Exercise premises independently: input identity, equality coverage, and an
// authored cardinality assertion. Expected witnesses come from the closed table,
// never from which generated witnesses an order consumer happens to select.
test "ordinary join key table covers independent identity and cardinality premises" {
  let row = schema()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  for kind in ["inner", "left", "full", "semi", "anti"] {
    for left_keyed in [false, true] {
      for right_keyed in [false, true] {
        for covered in [false, true] {
          for assertion in ["", "one_to_one", "one_to_many", "many_to_one"] {
            let lu = (covered && left_keyed) ||
              assertion == "one_to_one" ||
              assertion == "one_to_many"
            let ru = (covered && right_keyed) ||
              assertion == "one_to_one" ||
              assertion == "many_to_one"
            let expected : Array[Array[@schema.FieldName]] = []
            if left_keyed &&
              (
                kind == "semi" ||
                kind == "anti" ||
                ((kind == "inner" || kind == "left") && ru)
              ) {
              expected.push([Qualified(Left, "id")])
            }
            if right_keyed && kind == "inner" && lu {
              expected.push([Qualified(Right, "id")])
            }
            if kind == "inner" && !lu && !ru && left_keyed && right_keyed {
              expected.push([Qualified(Left, "id"), Qualified(Right, "id")])
            }
            let p = @pipeline_typing.check_with_evidence(
              cursor(
                "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"" +
                kind +
                "\",\"on\":\"" +
                (if covered { "id" } else { "amount" }) +
                "\"" +
                (if assertion == "" {
                  ""
                } else {
                  ",\"cardinality\":\"" + assertion + "\""
                }) +
                "}}]",
              ),
              [
                (
                  "l",
                  if left_keyed {
                    @pipeline_typing.KeyedInput(key)
                  } else {
                    @pipeline_typing.CarrierInput(carrier)
                  },
                ),
                (
                  "r",
                  if right_keyed {
                    @pipeline_typing.KeyedInput(key)
                  } else {
                    @pipeline_typing.CarrierInput(carrier)
                  },
                ),
              ],
              None,
              None,
              limits(),
            ).unwrap()
            let keys = @pipeline_typing.candidate_keys(p, Step(0)).unwrap()
            assert_eq(@evidence.key_witness_count(keys), expected.length())
            for i in 0..<expected.length() {
              let witness = @evidence.key_witness_at(keys, i).unwrap()
              assert_eq(
                @evidence.key_field_count(witness),
                expected[i].length(),
              )
              for j in 0..<expected[i].length() {
                let field = @evidence.key_field_at(witness, j).unwrap()
                assert_eq(field.name, expected[i][j])
                assert_false(field.contract.unwrap().nullable)
              }
              assert_true(
                @evidence.key_pending(witness).contains(ValidateKeyProducer),
              )
              let producer = @evidence.key_join_producer(witness).unwrap()
              assert_eq(@join.assertion(producer) is Some(_), assertion != "")
              for j in 0..<@evidence.key_join_dependency_count(witness) {
                let parent = @evidence.key_join_dependency_at(witness, j).unwrap()
                assert_true(
                  @evidence.key_pending(parent).contains(
                    ValidateWholeTupleUniquenessAfterInputNormalization,
                  ),
                )
              }
            }
          }
        }
      }
    }
  }
}
