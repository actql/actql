///|
fn property_node_row_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 100,
      max_nodes: 20,
      max_depth: 5,
    }).unwrap(),
    {
      max_nodes: 20,
      max_depth: 5,
      max_string_bytes: 100,
      max_total_string_bytes: 100,
    },
  ).unwrap()
}

///|
fn property_node_row_fixture() -> (
  @projection.CheckedPropertyNodeRows,
  @storage.Storage,
) {
  let key = @contract.primitive(@contract.NumberType, nullable=false)
  let property = @contract.primitive(@contract.NumberType, nullable=true)
  let a = @carrier.property_node_definition(
    "A",
    [key],
    @carrier.rows(
      [(@schema.Unqualified("p"), Some(property))],
      field_set=@carrier.Closed,
      max_fields=1,
      max_name_bytes=1,
    ).unwrap(),
    [],
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  let b = @carrier.property_node_definition(
    "B",
    [key],
    @carrier.rows([], field_set=@carrier.Closed, max_fields=0, max_name_bytes=0).unwrap(),
    [],
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  let c = @carrier.property_node_definition(
    "C",
    [key],
    @carrier.rows(
      [
        (
          @schema.Unqualified("p"),
          Some(@contract.primitive(@contract.NumberType, nullable=false)),
        ),
      ],
      field_set=@carrier.Closed,
      max_fields=1,
      max_name_bytes=1,
    ).unwrap(),
    [],
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  let graph = @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [a, b, c],
    [],
    max_definitions=3,
    max_contract_work=100,
  ).unwrap()
  let plan = @projection.check_property_node_rows(
    property_node_row_cursor("true"),
    graph,
    { max_work: 100, max_nodes: 10, max_text_bytes: 10, max_depth: 5, },
  ).unwrap()
  let builder = @storage.prepare(graph, @storage.DeclaredNodes, {
    max_input_rows: 3,
    max_nodes: 3,
    max_edges: 0,
    max_value_bytes: 1000,
    max_total_value_bytes: 2000,
    max_retained_value_bytes: 2000,
    max_value_nodes: 100,
    max_value_depth: 10,
    max_contract_work: 100,
    max_work: 1000,
    max_workspace_slots: 100,
  }).unwrap()
  @storage.append_property_node(
    builder,
    0,
    [@value.checked_number_value(1.0, key).unwrap()],
    [@value.checked_null_value(property).unwrap()],
  ).unwrap()
  @storage.append_property_node(
    builder,
    1,
    [@value.checked_number_value(2.0, key).unwrap()],
    [],
  ).unwrap()
  @storage.append_property_node(
    builder,
    2,
    [@value.checked_number_value(3.0, key).unwrap()],
    [
      @value.checked_number_value(
        7.0,
        @contract.primitive(@contract.NumberType, nullable=false),
      ).unwrap(),
    ],
  ).unwrap()
  (plan, @storage.finish(builder).unwrap())
}

///|
fn property_node_row_values() -> @execution.ValueLimits {
  { max_nodes: 100, max_text_bytes: 1000, max_depth: 12, max_work: 1000, }
}

///|
test "property node row admits exact step work and workspace and refuses one short" {
  let (plan, storage) = property_node_row_fixture()
  // One checked Graph identity object and a present NULL property traverse
  // 46 bounded read, recheck, name/value-measure and finalization steps. The
  // row holds two cells plus one active traversal frame at peak.
  for
    (step_work, workspace, expected) in [
      (46, 3, true),
      (45, 3, false),
      (46, 2, false),
    ] {
    let active = start_property_node_row_read(
      plan,
      0,
      () => true,
      () => @storage.node_definition_index(storage, 0),
      () => @storage.node_identity(storage, 0),
      property => @storage.node_property(storage, 0, property),
      property_node_row_values(),
      step_work,
      workspace,
    ).unwrap()
    let mut complete = false
    let mut limited = false
    let mut observed_work = 0L
    for _ in 0..<50 {
      match advance_property_node_row(active, 1).unwrap() {
        PropertyNodeRowContinue(work~) => {
          assert_true(work >= observed_work)
          observed_work = work
        }
        PropertyNodeRowComplete(_, work~) => {
          observed_work = work
          complete = true
          break
        }
        PropertyNodeRowFailed(Row(@execution.Limit), work~) => {
          observed_work = work
          limited = true
          break
        }
        _ => fail("unexpected boundary result")
      }
    }
    assert_eq(complete, expected)
    assert_eq(limited, !expected)
    if expected {
      assert_eq(observed_work, 46L)
    } else {
      assert_true(
        @execution.conditional_row_preparation_value(active.row) is None,
      )
    }
    assert_true(cleanup_property_node_row(active).unwrap())
  }
}

///|
test "property Graph node rows preserve absent and present null through bounded construction" {
  let (plan, storage) = property_node_row_fixture()
  let expected = [
    "{\"id\":{\"definition\":\"A\",\"domain\":\"sha256:" +
    "0".repeat(64) +
    "\",\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]},\"p\":null}",
    "{\"id\":{\"definition\":\"B\",\"domain\":\"sha256:" +
    "0".repeat(64) +
    "\",\"key\":[2],\"key_types\":[{\"kind\":\"number\"}]}}",
    "{\"id\":{\"definition\":\"C\",\"domain\":\"sha256:" +
    "0".repeat(64) +
    "\",\"key\":[3],\"key_types\":[{\"kind\":\"number\"}]},\"p\":7}",
  ]
  for index in 0..<3 {
    let active = start_property_node_row_read(
      plan,
      index,
      () => true,
      () => @storage.node_definition_index(storage, index),
      () => @storage.node_identity(storage, index),
      property => @storage.node_property(storage, index, property),
      property_node_row_values(),
      100,
      100,
    ).unwrap()
    let mut completed = None
    for _ in 0..<100 {
      match advance_property_node_row(active, 1).unwrap() {
        PropertyNodeRowContinue(..) => ()
        PropertyNodeRowComplete(row, ..) => {
          completed = Some(row)
          break
        }
        _ => fail("Graph node row did not complete")
      }
    }
    let row = completed.unwrap()
    let writer = @encode.writer(1000, 100, 12)
    @execution.emit_conditional_row(row, writer)
    assert_eq(@encode.finish(writer), expected[index])
    if index == 0 {
      assert_true(
        @execution.conditional_row_cell(row, 1) is Some(Some(@value.Null)),
      )
    } else if index == 1 {
      assert_true(@execution.conditional_row_cell(row, 1) is Some(None))
    } else {
      assert_true(
        @execution.conditional_row_cell(row, 1)
        is Some(Some(@value.Number(7.0))),
      )
    }
    assert_true(cleanup_property_node_row(active).unwrap())
  }
  let invalid = start_property_node_row_read(
    plan,
    3,
    () => true,
    () => Some(3),
    () => None,
    _ => None,
    property_node_row_values(),
    100,
    100,
  )
  assert_true(invalid is Err(InvalidNode))
}

///|
test "property Graph node row cancellation does not publish partial content" {
  let (plan, storage) = property_node_row_fixture()
  let active = start_property_node_row_read(
    plan,
    0,
    () => true,
    () => @storage.node_definition_index(storage, 0),
    () => @storage.node_identity(storage, 0),
    property => @storage.node_property(storage, 0, property),
    property_node_row_values(),
    100,
    100,
  ).unwrap()
  assert_true(
    advance_property_node_row(active, 1).unwrap() is PropertyNodeRowContinue(..),
  )
  assert_true(cancel_property_node_row(active))
  assert_true(
    advance_property_node_row(active, 1).unwrap() is PropertyNodeRowStopped(..),
  )
  assert_true(@execution.conditional_row_preparation_value(active.row) is None)
  assert_true(cleanup_property_node_row(active).unwrap())
  assert_true(cleanup_property_node_row(active).unwrap())
  assert_true(active.available is None)
}

///|
test "property Graph node row loses access before completion without leaking output" {
  let (plan, storage) = property_node_row_fixture()
  let live = Ref(true)
  let active = start_property_node_row_read(
    plan,
    0,
    () => live.val,
    () => @storage.node_definition_index(storage, 0),
    () => @storage.node_identity(storage, 0),
    property => @storage.node_property(storage, 0, property),
    property_node_row_values(),
    100,
    100,
  ).unwrap()
  assert_true(
    advance_property_node_row(active, 1).unwrap() is PropertyNodeRowContinue(..),
  )
  live.val = false
  assert_true(advance_property_node_row(active, 1) is Err(InputUnavailable))
  assert_true(@execution.conditional_row_preparation_value(active.row) is None)
  assert_true(cleanup_property_node_row(active).unwrap())
  assert_true(active.available is None)
}
