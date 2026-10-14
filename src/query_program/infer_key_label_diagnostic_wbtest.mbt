///|
test "omitted key label refusals retain each parser-owned INFER origin" {
  let text = "/*😀é*/\r\nFROM tickets |> INFER task INPUT (text) AS assessment"
  for script in [false, true] {
    let query = if script {
      @query.script_query(
        @query.parse_query_script(
          text,
          mapping_syntax_limits(),
          source_path="label-origin.sql",
        ).unwrap(),
      )
    } else {
      @query.parse_query(
        text,
        mapping_syntax_limits(),
        source_path="label-origin.sql",
      ).unwrap()
    }
    guard @query.operation_at(query, 0) is Some(Infer(clause)) else {
      fail("expected the original INFER")
    }
    let generated = @origin.range(
      @query.query_document(query),
      0,
      0,
      kind=Generated,
    ).unwrap()
    for
      (labels, keys, expected) in [
        ([], [], 0),
        ([("slot", "")], [], 1),
        ([("slot", "VaLuE")], [], 2),
        ([("slot", "OuTcOmE")], [], 2),
        ([("slot", "ID")], [("id", "earlier")], 3),
        ([("slot", "id")], [("other", "slot")], 4),
      ] {
      let refused = try {
        ignore(
          infer_prefix_key_label(
            { key_labels: labels, origin: clause.origin, },
            "slot",
            keys,
            { remaining_work: 1000, },
            generated,
          ),
        )
        false
      } catch {
        Abort(InferKeyLabel(issue, Some(origin))) => {
          let actual = match issue {
            MissingCorrespondence => 0
            EmptyOrAmbiguousLabel => 1
            ReservedRole => 2
            DuplicateLabel => 3
            DuplicateSlot => 4
          }
          assert_eq(actual, expected)
          let span = @origin.span(origin)
          assert_eq(span.source_path, "label-origin.sql")
          assert_eq(span.start_byte, 29)
          assert_eq(span.end_byte, 34)
          assert_eq(@origin.kind(origin), @origin.Authored)
          true
        }
        _ => false
      }
      assert_true(refused)
    }
    // An absent or ambiguous label on another slot is not adopted or refused.
    assert_eq(
      infer_prefix_key_label(
        {
          key_labels: [("unselected", ""), ("slot", "id")],
          origin: clause.origin,
        },
        "slot",
        [],
        { remaining_work: 1000, },
        generated,
      ),
      "id",
    )
  }
}
