///|
// Exact first-service authored input shape. The logical selector is the
// existing Task alias; physical OpenAI binding/funding is a separate gate.
// This census executes only the checked prefix and mapped-row preparation.
let first_m1_input_program : String =
  #|{"version":"actql/0.1","id":"infer-prefix","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true}},"rows":[{"id":"a","text":"hello"}]},"as":"input"},{"assert_rows":{"unique_by":["id"]},"as":"unique"},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"captured"}],"results":{"captured":{"from":"captured","fields":["id","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"captured"}}}}

///|
fn first_m1_checked_value_wire(value : @admitted.CheckedValue) -> String raise {
  let writer = @encode.writer(100, 10, 5)
  @admitted.emit_checked_wire_value(value, writer)
  @encode.finish(writer)
}

///|
test "first M1 fixed input census preserves all rows keys mapped values and cleanup" {
  assert_eq(first_m1_input_program, infer_fixture_program)
  let prepared = fixture_prepared(source=first_m1_input_program)
  // Existing independent common prefix helper, quantum1 and finite2000.
  // It obtains actual CompletedOutput/PreparedInferRows, not reported rows.
  let (input, rows, scope, fixed_request_cid) = call_identity_fixture(prepared)
  let completed = @input.client_infer_completed_input(input).unwrap()
  assert_true(
    @relation.prepared_infer_rows_matches_completed_input(rows, completed),
  )
  assert_eq(@relation.completed_row_count(completed), 1)
  assert_eq(@relation.prepared_infer_rows_count(rows), 1)
  assert_eq(@relation.completed_column_count(completed), 2)
  assert_eq(@relation.completed_column_name(completed, 0), Some("id"))
  assert_eq(@relation.completed_column_name(completed, 1), Some("text"))
  assert_true(
    @relation.completed_cell(completed, 0, 0) is Some(@relation.Text("a")),
  )
  assert_true(
    @relation.completed_cell(completed, 0, 1) is Some(@relation.Text("hello")),
  )
  // Every key and mapped field is read from the original checked getters.
  // Neither request4096 nor selected mask can substitute for all-R custody.
  let key = @relation.prepared_infer_rows_key(rows, 0, 0).unwrap()
  let value = @relation.prepared_infer_rows_value(rows, 0, 0).unwrap()
  assert_true(key.value is @admitted.Text("a"))
  assert_true(value.value is @admitted.Text("hello"))
  assert_true(@relation.prepared_infer_rows_key(rows, 0, 1) is None)
  assert_true(@relation.prepared_infer_rows_value(rows, 0, 1) is None)
  let key_wire = first_m1_checked_value_wire(key)
  let value_wire = first_m1_checked_value_wire(value)
  assert_eq(key_wire, "\"a\"")
  assert_eq(value_wire, "\"hello\"")
  assert_eq(@utf8.encode(key_wire).length(), 3)
  assert_eq(@utf8.encode(value_wire).length(), 7)
  assert_true(
    @publication_host.client_infer_call_scope_matches_rows(
      scope, rows, fixed_request_cid,
    ),
  )
  println(
    "M1_INPUT_CENSUS all_rows=1 key_components=1 mapped_fields=1 columns=id,text key_wire_bytes=3 value_wire_bytes=7 provider_calls=0",
  )
  assert_true(@input.cleanup_client_infer_input(input).unwrap())
  assert_true(@relation.prepared_infer_rows_key(rows, 0, 0) is None)
  assert_true(@relation.prepared_infer_rows_value(rows, 0, 0) is None)
  // These escaped typed scalar observations remain DATA; this is no heap,
  // GC, numerical profile, original-read grant or Model-send assertion.
  assert_eq(first_m1_checked_value_wire(key), "\"a\"")
  assert_eq(first_m1_checked_value_wire(value), "\"hello\"")
}
