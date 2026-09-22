///|
fn select_checked_contract(body : String) -> @contract.Contract {
  @contract.read_checked(input_cursor(body), {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }).unwrap()
}

///|
fn select_projection(
  schema : @schema.Schema,
  body : String,
) -> @lower.PreparedProjection {
  let checked = @relation.check(Select, input_cursor(body), schema, None, {
    max_work: 10000,
    max_nodes: 1000,
    max_text_bytes: 10000,
    max_tokens: 1000,
    max_depth: 100,
  }).unwrap()
  @lower.prepare_projection(checked).unwrap()
}

///|
test "select preserves every relation value domain and NULL" {
  let owner = capture_fixture()
  let cases = [
    ("{\"type\":\"string\",\"nullable\":true}", "\"é\"", "ordinary"),
    ("{\"type\":\"number\",\"nullable\":true}", "1", "ordinary"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":true}", "\"1.20\"",
      "ordinary",
    ),
    ("{\"type\":\"boolean\",\"nullable\":true}", "true", "ordinary"),
    (
      "{\"type\":\"timestamp\",\"nullable\":true}", "\"2000-02-29T12:30:00.000Z\"",
      "ordinary",
    ),
    ("{\"type\":\"date\",\"nullable\":true}", "\"0000-02-29\"", "ordinary"),
    (
      "{\"type\":\"json\",\"nullable\":true}", "{\"z\":[1,null],\"a\":\"x\"}", "ordinary",
    ),
    (
      "{\"type\":\"object\",\"nullable\":true,\"additional_properties\":false,\"fields\":{\"x\":{\"type\":\"string\",\"nullable\":false}}}",
      "{\"x\":\"v\"}", "ordinary",
    ),
    (
      "{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"number\",\"nullable\":true},\"max_items\":2}",
      "[1,null]", "ordinary",
    ),
    (
      "{\"type\":\"vector\",\"nullable\":true,\"dimensions\":2,\"element_type\":\"f32\"}",
      "[1,2]", "ordinary",
    ),
    (
      "{\"type\":\"resource_ref\",\"nullable\":true,\"resource_kind\":\"mail/message\"}",
      "", "resource",
    ),
    (
      "{\"type\":\"artifact_ref\",\"nullable\":true,\"media_type\":\"application/json\"}",
      "", "artifact",
    ),
  ]
  for (contract_body, wire, kind) in cases {
    let contract = select_checked_contract(contract_body)
    let schema = @schema.from_fields(
      [(@schema.Unqualified("input"), contract)],
      max_fields=1,
      max_name_bytes=100,
    ).unwrap()
    let live = Ref(true)
    let value = match kind {
      "resource" =>
        issued_resource_value(
          contract, "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
          live,
        ).value
      "artifact" => issued_artifact_value(contract, live).value
      _ =>
        @admitted.admit(contract, input_cursor(wire), {
          max_nodes: 100,
          max_depth: 10,
          max_text_bytes: 1000,
        }).unwrap().value
    }
    let null = @admitted.admit(contract, input_cursor("null"), {
        max_nodes: 1,
        max_depth: 0,
        max_text_bytes: 0,
      }).unwrap().value
    let table : CompletedTable = AdmittedTable({
      owner,
      id: "source",
      names: ["input"],
      rows: [[value], [null]],
    })
    let result = evaluate_completed_body(
      Projection(select_projection(schema, "[{\"output\":\"input\"}]")),
      table,
      "selected",
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
      fail("select changed the admitted representation")
    }
    assert_eq(projected.names, ["output"])
    assert_eq(projected.rows.length(), 2)
    assert_true(physical_equal(projected.rows[0][0], value))
    assert_true(projected.rows[1][0] is @admitted.Null)
    assert_true(physical_equal(projected.owner, owner))
    live.val = false
  }
}

///|
test "select resolves qualified fields and keeps authored projection order" {
  let owner = capture_fixture()
  let number = select_checked_contract(
    "{\"type\":\"number\",\"nullable\":false}",
  )
  let text = select_checked_contract("{\"type\":\"string\",\"nullable\":false}")
  let schema = @schema.from_fields(
    [
      (@schema.Qualified(Left, "id"), number),
      (@schema.Qualified(Right, "label"), text),
    ],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let left = @admitted.admit(number, input_cursor("1"), {
      max_nodes: 1,
      max_depth: 0,
      max_text_bytes: 0,
    }).unwrap().value
  let right = @admitted.admit(text, input_cursor("\"r\""), {
      max_nodes: 1,
      max_depth: 0,
      max_text_bytes: 1,
    }).unwrap().value
  let selected = evaluate_completed_body(
    Projection(
      select_projection(
        schema, "[{\"right_value\":\"right.label\"},{\"left_value\":\"left.id\"}]",
      ),
    ),
    AdmittedTable({
      owner,
      id: "joined",
      names: ["left.id", "right.label"],
      rows: [[left, right]],
    }),
    "selected",
    1,
    { remaining: 10000, max_frames: 100, },
    value_budget({
      max_nodes: 10,
      max_text_bytes: 100,
      max_depth: 2,
      max_work: 100,
    }).unwrap(),
    { limit: 100, live: 0, peak: 0, },
    None,
  ).unwrap()
  guard selected is AdmittedTable(table) else {
    fail("select changed the admitted representation")
  }
  assert_eq(table.names, ["right_value", "left_value"])
  assert_true(table.rows[0][0] is @admitted.Text("r"))
  assert_true(table.rows[0][1] is @admitted.Number(1.0))
}

///|
fn select_scale_sample(
  rows : Int,
  width : Int,
  selected : Int,
) -> (Int, Int) raise {
  let owner = capture_fixture()
  let number = select_checked_contract(
    "{\"type\":\"number\",\"nullable\":false}",
  )
  let fields = Array::makei(width, i => {
    (@schema.Unqualified("f" + i.to_string()), number)
  })
  let schema = @schema.from_fields(
    fields,
    max_fields=width,
    max_name_bytes=width * 16,
  ).unwrap()
  let projection = Array::makei(selected, i => {
    "\"f" + (width - i - 1).to_string() + "\""
  })
  let number_value = @admitted.admit(number, input_cursor("1"), {
      max_nodes: 1,
      max_depth: 0,
      max_text_bytes: 0,
    }).unwrap().value
  let input = AdmittedTable({
    owner,
    id: "source",
    names: Array::makei(width, i => "f" + i.to_string()),
    rows: Array::makei(rows, _ => Array::make(width, number_value)),
  })
  let maximum = 100000000
  let control = { remaining: maximum, max_frames: 100, }
  let workspace = row_workspace(100000000)
  let result = evaluate_completed_body(
    Projection(select_projection(schema, "[" + projection.join(",") + "]")),
    input,
    "selected",
    rows,
    control,
    value_budget({
      max_nodes: 10000000,
      max_text_bytes: 10000000,
      max_depth: 10,
      max_work: 100000000,
    }).unwrap(),
    workspace,
    None,
  ).unwrap()
  assert_eq(IndexedRows::row_count(result), rows)
  assert_eq(IndexedRows::column_count(result), selected)
  (maximum - control.remaining, workspace.peak)
}

///|
test "select work and retained slots scale with rows and projected width" {
  let small = select_scale_sample(8, 8, 4)
  let rows = select_scale_sample(64, 8, 4)
  let width = select_scale_sample(8, 64, 32)

  // Fixed logical-work and retained-slot diagnostics for the indexed
  // projection path. The row sample grows by 8x; the projected-width sample
  // grows by 8x without introducing a second scan of the unselected columns.
  assert_eq(small, (120, 180))
  assert_eq(rows, (624, 1244))
  assert_eq(width, (1022, 1272))

  assert_true(rows.0 > small.0)
  assert_true(rows.1 > small.1)
  assert_true(rows.0 < small.0 * 9)
  assert_true(rows.1 < small.1 * 9)

  assert_true(width.0 > small.0)
  assert_true(width.1 > small.1)
  assert_true(width.0 < small.0 * 9)
  assert_true(width.1 < small.1 * 9)
}
