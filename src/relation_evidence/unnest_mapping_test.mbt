///|
test "unnest mapping preserves admission, producer ownership and transfer charges" {
  for bound in [None, Some(0L), Some(1L), Some(2L)] {
    let make_parent = () => {
      let schema = @row.from_fields(
        [
          (Unqualified("id"), @contract.primitive(NumberType, nullable=false)),
          (
            Unqualified("items"),
            @contract.array_contract(
              @contract.primitive(NumberType, nullable=true),
              nullable=true,
              max_items=bound,
            ).unwrap(),
          ),
        ],
        max_fields=2,
        max_name_bytes=20,
      ).unwrap()
      key(@carrier.relation(@carrier.typed_rows(schema)), "[\"id\"]")
    }
    let parent = make_parent()
    for outer in [false, true] {
      for indexed in [false, true] {
        let body = "{\"column\":\"items\",\"as\":\"item\",\"outer\":" +
          outer.to_string() +
          (if indexed { ",\"with_index\":\"ix\"" } else { "" }) +
          "}"
        let op = checked(Unnest, body, parent)
        let extended = !outer && indexed
        let retained = extended || (outer && bound is Some(0L | 1L))
        // Independent accounting for one parent component and one alias:
        // witness + output fields + (component + alias + copied fields/aliases/producer).
        let caps : @relation_evidence.TransferLimits = {
          max_work: 1 +
          @row.field_count(@relation.output_schema(op)) +
          (if retained { 5 } else { 0 }),
          max_name_bytes: if extended {
            4
          } else if retained {
            2
          } else {
            0
          },
        }
        let result = @relation_evidence.transfer_unary(parent, op, caps).unwrap()
        assert_eq(result.work, caps.max_work)
        assert_eq(result.name_bytes, caps.max_name_bytes)
        assert_eq(result.key is Some(_), retained)
        if result.key is Some(next) {
          assert_true(
            physical_equal(
              @relation_evidence.key_unnest_input(next).unwrap(),
              parent,
            ),
          )
          assert_eq(
            @relation_evidence.key_field_count(next),
            if extended {
              2
            } else {
              1
            },
          )
          assert_true(
            @relation_evidence.key_pending(next).contains(ValidateKeyProducer),
          )
        }
        assert_true(
          @relation_evidence.transfer_unary(parent, op, {
            ..caps,
            max_work: caps.max_work - 1,
          })
          is Err({ kind: LimitExceeded, .. }),
        )
        if caps.max_name_bytes > 0 {
          assert_true(
            @relation_evidence.transfer_unary(parent, op, {
              ..caps,
              max_name_bytes: caps.max_name_bytes - 1,
            })
            is Err({ kind: LimitExceeded, .. }),
          )
        }
        // Equal field contracts from a fresh admission are not the same owner,
        // including operations whose mapping intentionally forgets all keys.
        assert_true(
          @relation_evidence.transfer_unary(
            parent,
            checked(Unnest, body, make_parent()),
            caps,
          )
          is Err({ kind: InputContractMismatch, .. }),
        )
      }
    }
  }
}
