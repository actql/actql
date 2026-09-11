///|
test "set pipeline bounds cover independent literal multiplicities and preserve left order" {
  for operation in ["except", "intersect"] {
    for duplicates in ["all", "distinct"] {
      for left in 0..<4 {
        for right in 0..<4 {
          let source = cursor(
            "[" +
            count_values(left, "l") +
            "," +
            count_values(right, "r") +
            ",{\"" +
            operation +
            "\":{\"with\":\"r\",\"duplicates\":\"" +
            duplicates +
            "\"},\"from\":\"l\"},{\"select\":[\"id\"]}]",
          )
          let p = @pipeline_typing.check_carriers(
            source,
            [],
            None,
            None,
            limits(),
          ).unwrap()
          let step = @pipeline_typing.step_at(p, 2).unwrap()
          assert_eq(
            @pipeline_typing.input_occurrences(step).map(e => (e.role, e.target)),
            [
              (@pipeline_typing.Left, @pipeline_typing.Step(0)),
              (@pipeline_typing.Right, @pipeline_typing.Step(1)),
            ],
          )
          // Fixtures contain each integer in [0,n) exactly once. Enumerate
          // complete-row equality independently instead of reading a count rule.
          let mut actual = 0
          for value in 0..<left {
            let mut found = false
            for candidate in 0..<right {
              if value == candidate {
                found = true
              }
            }
            if (operation == "except" && !found) ||
              (operation == "intersect" && found) {
              actual += 1
            }
          }
          for index in [2, 3] {
            let bound = @pipeline_typing.row_count(p, Step(index)).unwrap()
            assert_true(bound.upper >= actual.to_int64())
            assert_true(bound.upper <= left.to_int64())
            if bound.exact {
              assert_eq(bound.upper, actual.to_int64())
            }
            assert_true(
              @pipeline_typing.logical_order(p, Step(index)) is Some(_),
            )
          }
          guard step.operation is @pipeline_typing.Set(checked~, ..) else {
            abort("set expected")
          }
          assert_true(
            @set.pending_validations(checked).contains(CompareCompleteTypedRows),
          )
          assert_true(
            @set.pending_validations(checked).contains(
              PreserveEarliestLeftOccurrences,
            ),
          )
          assert_true(
            @set.pending_validations(checked).contains(
              ResolveComparisonResources,
            ),
          )
          let u = @pipeline_typing.usage(p)
          let exact = {
            ..limits(),
            max_work: u.work,
            max_nodes: u.nodes,
            max_text_bytes: u.text_bytes,
            max_tokens: u.tokens,
          }
          assert_true(
            @pipeline_typing.check_carriers(source, [], None, None, exact)
            is Ok(_),
          )
          for
            cap in [
              { ..exact, max_work: u.work - 1, },
              { ..exact, max_nodes: u.nodes - 1, },
              { ..exact, max_text_bytes: u.text_bytes - 1, },
            ] {
            assert_true(
              @pipeline_typing.check_carriers(source, [], None, None, cap)
              is Err(_),
            )
          }
        }
      }
    }
  }
}
