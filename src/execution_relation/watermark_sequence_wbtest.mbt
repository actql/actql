///|
fn watermark_owner(
  time_contract : String,
  rows : String,
  threshold : String,
  policy : String,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check(
    input_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\"," +
      "\"nullable\":false},\"time\":" +
      time_contract +
      "},\"rows\":" +
      rows +
      "},\"as\":\"seed\"},{\"watermark_rows\":{\"time\":\"time\"," +
      "\"late_policy\":\"" +
      policy +
      "\"," +
      threshold +
      "}}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn execute_watermark(
  owner : @lower.BoundPrepared,
  max_work? : Int = 100000,
) -> Result[CompletedSequence, SequenceRunIssue] raise {
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["watermark_1"],
    100000,
    10000,
  ).unwrap()
  execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work,
    max_frames: 100,
  })
}

///|
test "watermark preserves occurrence order for mark and drop policies" {
  let rows = "[{\"id\":1,\"time\":100},{\"id\":2,\"time\":80}," +
    "{\"id\":3,\"time\":95}]"
  for
    (threshold, policy, expected_ids, expected_late) in [
      ("\"watermark_ms\":90", "mark", [1.0, 2.0, 3.0], [false, true, false]),
      ("\"max_skew\":10", "drop", [1.0, 3.0], [false, false]),
    ] {
    let result = execute_watermark(
      watermark_owner(
        "{\"type\":\"number\",\"nullable\":false}", rows, threshold, policy,
      ),
    ).unwrap()
    let table = test_row_output(completed_output(result, Step(1)).unwrap())
    assert_eq(table.names, [
      "id", "time", "watermark_ms", "watermark_late", "watermark_decision",
    ])
    assert_eq(table.rows.length(), expected_ids.length())
    for index in 0..<table.rows.length() {
      assert_true(
        table.rows[index][0] is Number(id) && id == expected_ids[index],
      )
      assert_true(
        table.rows[index][3] is Boolean(late) && late == expected_late[index],
      )
      guard table.rows[index][4] is Text(decision) else {
        fail("watermark decision")
      }
      assert_eq(decision, if expected_late[index] { "mark" } else { "keep" })
      assert_true(table.rows[index][2] is Number(90.0))
    }
  }
}

///|
test "watermark timestamp comparisons use canonical epoch milliseconds" {
  let result = execute_watermark(
    watermark_owner(
      "{\"type\":\"timestamp\",\"nullable\":false}",
      "[{\"id\":1,\"time\":\"1970-01-01T00:00:00.100Z\"}," +
      "{\"id\":2,\"time\":\"1970-01-01T00:00:00.000Z\"}]",
      "\"watermark_ms\":50",
      "mark",
    ),
  ).unwrap()
  let table = test_row_output(completed_output(result, Step(1)).unwrap())
  assert_true(table.rows[0][3] is Boolean(false))
  assert_true(table.rows[1][3] is Boolean(true))
}

///|
test "watermark shares exact execution work and rejects invalid physical time" {
  let owner = watermark_owner(
    "{\"type\":\"number\",\"nullable\":false}", "[{\"id\":1,\"time\":100},{\"id\":2,\"time\":80}]",
    "\"max_skew\":10", "mark",
  )
  let sequence = prepared_sequence(owner)
  let control = { remaining: 100000, max_frames: 100, }
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    sequence,
    [],
    ["watermark_1"],
    run_limits(),
    control,
    fragments=Some([]),
  ).unwrap()
  assert_eq(
    test_row_output(completed_output(result, Step(1)).unwrap()).rows.length(),
    2,
  )
  let used = 100000 - control.remaining
  assert_true(execute_watermark(owner, max_work=used) is Ok(_))
  assert_true(execute_watermark(owner, max_work=used - 1) is Err(_))

  let invalid : Table = {
    owner,
    id: "values_0",
    names: ["id", "time"],
    rows: [[Number(1.0), Number(100.0)], [Number(2.0), Null]],
  }
  let workspace = { limit: 100, live: 0, peak: 0, }
  assert_true(
    evaluate_watermark_rows(
      row_kernel(owner, 1),
      invalid,
      "invalid",
      2,
      { remaining: 1000, max_frames: 10, },
      value_budget({
        max_nodes: 100,
        max_text_bytes: 1000,
        max_depth: 10,
        max_work: 1000,
      }).unwrap(),
      workspace,
    )
    is Err(WindowTime(1)),
  )
}
