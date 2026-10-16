///|
fn sequence_text_without_defaults(
  grouping : Bool,
  overlap : Bool,
  contiguity : Bool,
) -> String {
  let text = sequence_source_text()
  let text = if grouping { text } else { text.replace(old="by: [], ", new="") }
  let text = if overlap {
    text
  } else {
    text.replace(old=", overlap: 'disallow'", new="")
  }
  if contiguity {
    text
  } else {
    text.replace(old=", contiguity: 'adjacent'", new="")
  }
}

///|
test "SQL and AQL sequence omission reaches the same Common scope and author guards" {
  let expected = sequence_source_schema(sequence_source_control())
  for format in [@frontend.Sql, @frontend.Text] {
    for grouping in [false, true] {
      for overlap in [false, true] {
        for contiguity in [false, true] {
          let actual = @frontend.lower(
            sequence_text_without_defaults(grouping, overlap, contiguity),
            format,
            Some({ ..pair_context(), inputs: [], }),
          ).unwrap().program.unwrap()
          let fields = sequence_source_schema(actual)
          assert_eq(
            fields.map(field => field.name),
            expected.map(field => field.name),
          )
          for index in 0..<fields.length() {
            assert_eq(fields[index].presence, expected[index].presence)
            assert_true(
              @contract.type_equal(
                fields[index].contract,
                expected[index].contract,
                10000,
              ),
            )
          }
          let checked = match
            @check.check_parsed(
              actual,
              graph_event_environment(),
              None,
              check_limits(),
            ) {
            Checked(value) => value
            _ => fail("the original Common sequence contract must be checked")
          }
          let stage = @stage_results.stage_at(
            @check.checked_stage_results(checked),
            0,
          ).unwrap()
          let pipeline = @relation_results.pipeline(stage)
          let mut matches = 0
          for index in 0..<@pipeline.step_count(pipeline) {
            if @pipeline.step_at(pipeline, index).unwrap().operation
              is Sequence(operation) {
              matches += 1
              assert_eq(@relation.sequence_keys(operation).length(), 0)
              assert_eq(@relation.sequence_overlap(operation), Disallow)
              assert_eq(@relation.sequence_contiguity(operation), Adjacent)
              assert_eq(
                @relation.sequence_per_key_guard(operation),
                Some(Literal(2L)),
              )
              assert_eq(
                @relation.sequence_output_guard(operation),
                Some(Literal(2L)),
              )
            }
          }
          assert_eq(matches, 1)
        }
      }
    }
  }
}

///|
test "sequence shorthand does not default malformed explicit modes or required arguments" {
  let text = sequence_text_without_defaults(false, false, false)
  for format in [@frontend.Sql, @frontend.Text] {
    for
      invalid in [
        text.replace(old="within: 20", new="by: NULL, within: 20"),
        text.replace(old="within: 20", new="overlap: 'invented', within: 20"),
        text.replace(old="within: 20", new="contiguity: 3, within: 20"),
        text.replace(old="id: e.id, ", new=""),
        text.replace(old="time: e.occurred_ms, ", new=""),
        text.replace(old="within: 20, ", new=""),
      ] {
      assert_true(
        @frontend.lower(
          invalid,
          format,
          Some({ ..pair_context(), inputs: [], }),
        )
        is Err(_),
      )
    }
  }
}
