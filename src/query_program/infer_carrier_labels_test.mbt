///|
test "omitted INFER key retains a scoped hidden rename through row watermark" {
  let environment = infer_member_environment()
  let context = infer_input_field_context(environment)
  let prefix = "FROM tickets |> EXTEND 10 AS event_time |> SET id = secret |> ASSERT UNIQUE BY (id) |> RENAME id AS stable_id |> SET stable_id = 'same' |> RENAME stable_id AS replacement_id |> AS current |> watermark_rows(time: event_time, late_policy: 'mark', watermark_ms: 0)"
  let checked = check_shorthand_identity_program(
    compile_infer_defaults(
      prefix +
      " |> INFER `model-task:risk-score.v1` INPUT (text) KEEP (text) AS assessment",
      context,
      true,
    ).unwrap(),
    environment,
  )
  let key = infer_defaults_checked_input_key(checked)
  guard key.shape is @contract.Object(fields) else {
    fail("expected the original hidden scalar key")
  }
  assert_eq(@contract.field_count(fields), 1)
  assert_eq(@contract.field_at(fields, 0).unwrap().name, "stable_id")
  assert_true(
    @contract.type_equal(
      infer_defaults_object_field(key, "stable_id"),
      @contract.primitive(@contract.StringType, nullable=false),
      10000,
    ),
  )
  // Carrying its identity label does not restore the retired row/range lookup.
  assert_true(
    compile_infer_defaults(
      prefix + " |> SELECT current.stable_id",
      context,
      true,
    )
    is Err(_),
  )
}
