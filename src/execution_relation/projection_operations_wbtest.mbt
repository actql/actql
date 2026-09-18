///|
fn checked_projection_operation(
  operation : @relation.Operation,
  schema : @schema.Schema,
  body : String,
) -> @lower.BoundPrepared {
  let source = match operation {
    @relation.Rename => "[{\"rename\":" + body + "}]"
    @relation.Drop => "[{\"drop\":" + body + "}]"
    _ => abort("projection fixture operation")
  }
  let checked = @pipeline.check(
    input_cursor(source),
    [("seed", schema)],
    None,
    Some(input_cursor("\"seed\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_nodes: 1000,
      max_text_bytes: 10000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 10000,
      max_identifier_bytes: 10000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "rename and drop preserve every directly admitted value domain and NULL" {
  let boolean = select_checked_contract(
    "{\"type\":\"boolean\",\"nullable\":false}",
  )
  let retained = @admitted.admit(boolean, input_cursor("true"), {
      max_nodes: 1,
      max_depth: 0,
      max_text_bytes: 0,
    }).unwrap().value
  let cases = [
    ("{\"type\":\"string\",\"nullable\":true}", "\"é\""),
    ("{\"type\":\"number\",\"nullable\":true}", "1"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":true}", "\"1.20\"",
    ),
    ("{\"type\":\"boolean\",\"nullable\":true}", "true"),
    (
      "{\"type\":\"timestamp\",\"nullable\":true}", "\"2000-02-29T12:30:00.000Z\"",
    ),
    ("{\"type\":\"date\",\"nullable\":true}", "\"0000-02-29\""),
    ("{\"type\":\"json\",\"nullable\":true}", "{\"z\":[1,null],\"a\":\"x\"}"),
    (
      "{\"type\":\"object\",\"nullable\":true,\"additional_properties\":false,\"fields\":{\"x\":{\"type\":\"string\",\"nullable\":false}}}",
      "{\"x\":\"v\"}",
    ),
    (
      "{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"number\",\"nullable\":true},\"max_items\":2}",
      "[1,null]",
    ),
    (
      "{\"type\":\"vector\",\"nullable\":true,\"dimensions\":2,\"element_type\":\"f32\"}",
      "[1,2]",
    ),
  ]
  for (contract_body, wire) in cases {
    let contract = select_checked_contract(contract_body)
    let schema = @schema.from_fields(
      [
        (@schema.Unqualified("input"), contract),
        (@schema.Unqualified("keep"), boolean),
      ],
      max_fields=2,
      max_name_bytes=100,
    ).unwrap()
    let value = @admitted.admit(contract, input_cursor(wire), {
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 1000,
      }).unwrap().value
    let null = @admitted.admit(contract, input_cursor("null"), {
        max_nodes: 1,
        max_depth: 0,
        max_text_bytes: 0,
      }).unwrap().value
    for
      (operation, body, name) in [
        (@relation.Rename, "{\"input\":\"renamed\"}", "renamed"),
        (@relation.Drop, "[\"keep\"]", "input"),
      ] {
      let prepared = checked_projection_operation(operation, schema, body)
      let input : CompletedTable = AdmittedTable({
        owner: prepared,
        id: @lower.input_id(@lower.bound_preparation(prepared), 0).unwrap(),
        names: ["input", "keep"],
        rows: [[value, retained], [null, retained]],
      })
      let result = evaluate_completed_body(
        PreparedBody(row_kernel(prepared, 0)),
        input,
        "projected",
        2,
        { remaining: 100000, max_frames: 100, },
        value_budget({
          max_nodes: 1000,
          max_text_bytes: 10000,
          max_depth: 10,
          max_work: 100000,
        }).unwrap(),
        { limit: 10000, live: 0, peak: 0, },
        None,
      ).unwrap()
      guard result is AdmittedTable(projected) else {
        fail("projection changed the admitted representation")
      }
      let mut index = -1
      for i = 0; i < projected.names.length(); i = i + 1 {
        if projected.names[i] == name {
          index = i
        }
      }
      assert_true(index >= 0)
      assert_true(physical_equal(projected.rows[0][index], value))
      assert_true(projected.rows[1][index] is @admitted.Null)
      assert_true(physical_equal(projected.owner, prepared))
    }
  }
}

///|
fn projection_operation_scale(count : Int, rename : Bool) -> Unit raise {
  let operation = if rename {
    ",{\"rename\":{\"a\":\"x\",\"b\":\"y\"}}"
  } else {
    ",{\"drop\":[\"b\"]}"
  }
  let owner = row_owner(operation)
  let template = row_capture(owner)
  let input = {
    ..template,
    rows: Array::makei(count, i => [Number(i.to_double()), Number(1.0)]),
  }
  let budget = logical_budget(
    {
      max_input_rows: count.to_int64(),
      max_value_bytes: 1000L,
      max_live_value_bytes: (count * 100).to_int64(),
      max_work: (count * 100).to_int64(),
    },
    1000,
    100,
    10,
  ).unwrap()
  let workspace = { limit: count * 10 + 100, live: 0, peak: 0, }
  let result = evaluate_rows_with_workspace(
    row_kernel(owner, 1),
    input,
    count,
    { remaining: count * 100 + 100, max_frames: 100, },
    value_budget({
      max_nodes: count * 10 + 100,
      max_text_bytes: count * 20 + 100,
      max_depth: 10,
      max_work: count * 20 + 100,
    }).unwrap(),
    workspace,
    ordered_budget=Some(budget),
  ).unwrap()
  assert_eq(result.rows.length(), count)
  assert_eq(result.names.length(), if rename { 2 } else { 1 })
  assert_true(budget.work < (count * 50 + 10).to_int64())
  assert_eq(budget.rows, count.to_int64())
  assert_eq(budget.live, 0L)
  assert_false(budget.failed)
  assert_true(workspace.peak < count * 10 + 10)
}

///|
test "rename and drop work stay linear in rows and retained width" {
  for count in [100, 1000, 10000] {
    projection_operation_scale(count, true)
    projection_operation_scale(count, false)
  }
}
