///|
test "refined Infer Filter executes its unchanged predicate on supplied admitted rows" {
  let source = input_cursor(
    (
      #|[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":false}},"rows":[{"id":"one","text":"input"}]},"as":"seed"},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"outcomes"},{"filter":{"eq":[{"field":"outcome"},{"literal":"ok"}]}},{"derive":{"risk":{"property":{"name":"risk","value":{"field":"value"}}}}}]
    ),
  )
  let checked = @pipeline.check_with_evidence(
    source,
    [],
    None,
    None,
    {
      max_steps: 100,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
    model_tasks=Some(infer_fixture_tasks()),
  ).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 10000,
      max_identifier_bytes: 10000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=10000,
  ).unwrap()
  let kernel = row_kernel(owner, 3)
  let schema = @lower.preparation_schema_at(
    @lower.bound_preparation(owner),
    Step(2),
  ).unwrap()
  let names = []
  for i in 0..<@schema.field_count(schema) {
    names.push(
      @schema.reference_name(@schema.field_at(schema, i).unwrap().name),
    )
  }
  // These are ordinary supplied row fixtures for the pure evaluator, not
  // fabricated Infer completions, publication evidence or model execution.
  let rows = []
  for outcome in ["ok", "failed:timeout"] {
    let row = []
    for name in names {
      let wire = match name {
        "id" => "\"one\""
        "outcome" => "\"" + outcome + "\""
        "value" =>
          if outcome == "ok" {
            "{\"reason\":null,\"risk\":\"low\"}"
          } else {
            "null"
          }
        _ => "null"
      }
      row.push(
        assertion_admitted_value(
          @schema.lookup_reference(schema, name).unwrap().contract,
          wire,
          "ordinary",
          Ref(true),
        ),
      )
    }
    rows.push(row)
  }
  let output = evaluate_rows(
    kernel,
    { owner, id: @lower.kernel_input(kernel), names, rows, },
    10,
    { remaining: 100000, max_frames: 100, },
    row_output(),
  ).unwrap()
  assert_eq(output.rows.length(), 1)
  assert_false(
    @schema.lookup_reference(@lower.kernel_output_schema(kernel), "value").unwrap().contract.nullable,
  )
  let derived = evaluate_rows(
    row_kernel(owner, 4),
    output,
    10,
    { remaining: 100000, max_frames: 100, },
    row_output(),
  ).unwrap()
  assert_eq(derived.rows.length(), 1)
  let risk = derived.names.search("risk").unwrap()
  assert_true(
    append_value_equal(
      derived.rows[0][risk],
      assertion_admitted_value(
        @contract.primitive(StringType, nullable=false),
        "\"low\"",
        "ordinary",
        Ref(true),
      ),
    ),
  )
}
