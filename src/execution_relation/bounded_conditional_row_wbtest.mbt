///|
fn bounded_conditional_fixture(
  step_work : Int,
  workspace : Int,
  values : ValueLimits,
) -> ConditionalRowPreparation {
  let schema = conditional_row_test_schema()
  let id_contract = @schema.presence_field_contract(
    @schema.presence_field_at(schema, 0).unwrap(),
  )
  let p_contract = @schema.presence_field_contract(
    @schema.presence_field_at(schema, 1).unwrap(),
  )
  let id = @admitted.checked_number_value(1.0, id_contract).unwrap()
  let p = @admitted.admit(p_contract, input_cursor("7"), {
    max_nodes: 2,
    max_text_bytes: 0,
    max_depth: 1,
  }).unwrap()
  let cells = [Some(id), Some(p)]
  start_conditional_row_preparation(schema, values, step_work, workspace, column => {
    cells.get(column)
  }).unwrap()
}

///|
test "bounded conditional row charges exact value and step limits" {
  let active = bounded_conditional_fixture(8, 3, conditional_row_test_values())
  assert_true(conditional_row_preparation_value(active) is None)
  let mut completed = None
  for _ in 0..<8 {
    match advance_conditional_row_preparation(active, 1).unwrap() {
      ConditionalRowContinue(..) => ()
      ConditionalRowComplete(row, ..) => {
        completed = Some(row)
        break
      }
      _ => fail("bounded conditional row did not complete")
    }
  }
  let row = completed.unwrap()
  assert_eq(conditional_row_usage(row), { nodes: 3, text_bytes: 3, work: 6, })
  let shared = conditional_relation_row(row)
  assert_true(
    physical_equal(
      relation_row_schema(shared),
      @schema.conditional_relation_schema(active.state.builder.schema),
    ),
  )
  assert_eq(relation_row_usage(shared), conditional_row_usage(row))
  let independent = copy_relation_row(shared, conditional_row_test_values()).unwrap()
  assert_true(conditional_row_preparation_value(active) is Some(_))
  let writer = @encode.writer(128, 16, 4)
  emit_conditional_row(row, writer)
  assert_eq(@encode.finish(writer), "{\"id\":1,\"p\":7}")
  assert_true(cleanup_conditional_row_preparation(active).unwrap())
  assert_true(conditional_row_preparation_value(active) is None)
  assert_eq(active.state.workspace.live, 0)
  assert_true(
    relation_row_cell(independent, 1) is Ok(Present(@admitted.Number(7))),
  )
  for
    (step_work, workspace, values) in [
      (7, 3, conditional_row_test_values()),
      (8, 2, conditional_row_test_values()),
      (8, 3, { ..conditional_row_test_values(), max_work: 5, }),
    ] {
    let rejected = bounded_conditional_fixture(step_work, workspace, values)
    let mut limited = false
    for _ in 0..<9 {
      match advance_conditional_row_preparation(rejected, 1).unwrap() {
        ConditionalRowContinue(..) => ()
        ConditionalRowFailed(Limit, ..) => {
          limited = true
          break
        }
        _ => fail("one-short conditional row completed")
      }
    }
    assert_true(limited)
    assert_true(conditional_row_preparation_value(rejected) is None)
    assert_true(cleanup_conditional_row_preparation(rejected).unwrap())
    assert_eq(rejected.state.workspace.live, 0)
  }
  let schema = conditional_row_test_schema()
  assert_true(
    start_conditional_row_preparation(
      schema,
      { ..conditional_row_test_values(), max_nodes: 2, },
      8,
      3,
      _ => None,
    )
    is Err(Limit),
  )
}

///|
test "bounded conditional row cancellation keeps partial cells private" {
  let active = bounded_conditional_fixture(8, 3, conditional_row_test_values())
  for _ in 0..<4 {
    assert_true(
      advance_conditional_row_preparation(active, 1).unwrap()
      is ConditionalRowContinue(..),
    )
  }
  assert_true(active.state.builder.cells.length() > 0)
  assert_true(cancel_conditional_row_preparation(active))
  assert_true(
    advance_conditional_row_preparation(active, 1).unwrap()
    is ConditionalRowStopped(..),
  )
  assert_true(conditional_row_preparation_value(active) is None)
  assert_true(cleanup_conditional_row_preparation(active).unwrap())
  assert_true(active.state.builder.cells.is_empty())
  assert_eq(active.state.workspace.live, 0)
}

///|
test "bounded conditional rows distinguish absence from explicit null" {
  let schema = conditional_row_test_schema()
  let id_contract = @schema.presence_field_contract(
    @schema.presence_field_at(schema, 0).unwrap(),
  )
  let p_contract = @schema.presence_field_contract(
    @schema.presence_field_at(schema, 1).unwrap(),
  )
  let id = @admitted.checked_number_value(1.0, id_contract).unwrap()
  let null = @admitted.admit(p_contract, input_cursor("null"), {
    max_nodes: 1,
    max_text_bytes: 0,
    max_depth: 1,
  }).unwrap()
  for
    (cell, expected) in [
      (None, "{\"id\":1}"),
      (Some(null), "{\"id\":1,\"p\":null}"),
    ] {
    let active = start_conditional_row_preparation(
      schema,
      conditional_row_test_values(),
      8,
      3,
      column => if column == 0 { Some(Some(id)) } else { Some(cell) },
    ).unwrap()
    let mut completed = None
    for _ in 0..<8 {
      match advance_conditional_row_preparation(active, 1).unwrap() {
        ConditionalRowContinue(..) => ()
        ConditionalRowComplete(row, ..) => {
          completed = Some(row)
          break
        }
        _ => fail("conditional presence failed")
      }
    }
    let row = completed.unwrap()
    let canonical = admit_relation_row(
      @schema.conditional_relation_schema(schema),
      [Some(id), cell],
      conditional_row_test_values(),
    ).unwrap()
    assert_eq(
      relation_row_usage(conditional_relation_row(row)),
      relation_row_usage(canonical),
    )
    let writer = @encode.writer(128, 16, 4)
    emit_conditional_row(row, writer)
    assert_eq(@encode.finish(writer), expected)
    if cell is None {
      assert_true(conditional_row_cell(row, 1) is Some(None))
    } else {
      assert_true(conditional_row_cell(row, 1) is Some(Some(@admitted.Null)))
    }
    assert_true(cleanup_conditional_row_preparation(active).unwrap())
  }
  let missing = start_conditional_row_preparation(
    schema,
    conditional_row_test_values(),
    8,
    3,
    _ => Some(None),
  ).unwrap()
  assert_true(
    advance_conditional_row_preparation(missing, 1).unwrap()
    is ConditionalRowFailed(MissingRequired(0), ..),
  )
  assert_true(conditional_row_preparation_value(missing) is None)
  assert_true(cleanup_conditional_row_preparation(missing).unwrap())
  assert_eq(missing.state.workspace.live, 0)
}

///|
test "bounded conditional row rechecks compatible definition values" {
  let schema = conditional_row_test_schema()
  let id_contract = @schema.presence_field_contract(
    @schema.presence_field_at(schema, 0).unwrap(),
  )
  let id = @admitted.checked_number_value(1.0, id_contract).unwrap()
  let narrow = @contract.primitive(NumberType, nullable=false)
  let p = @admitted.checked_number_value(7.0, narrow).unwrap()
  let cells = [Some(id), Some(p)]
  let active = start_conditional_row_preparation(
    schema,
    conditional_row_test_values(),
    10,
    3,
    column => cells.get(column),
  ).unwrap()
  let mut completed = None
  for _ in 0..<10 {
    match advance_conditional_row_preparation(active, 1).unwrap() {
      ConditionalRowContinue(..) => ()
      ConditionalRowComplete(row, ..) => {
        completed = Some(row)
        break
      }
      _ => fail("compatible definition value was rejected")
    }
  }
  let row = completed.unwrap()
  assert_eq(conditional_row_usage(row), { nodes: 3, text_bytes: 3, work: 6, })
  assert_true(conditional_row_cell(row, 1) is Some(Some(@admitted.Number(7.0))))
  assert_true(cleanup_conditional_row_preparation(active).unwrap())
  let too_short = start_conditional_row_preparation(
    schema,
    conditional_row_test_values(),
    9,
    3,
    column => cells.get(column),
  ).unwrap()
  let mut limited = false
  for _ in 0..<10 {
    match advance_conditional_row_preparation(too_short, 1).unwrap() {
      ConditionalRowContinue(..) => ()
      ConditionalRowFailed(Limit, ..) => {
        limited = true
        break
      }
      _ => fail("one-short recheck completed")
    }
  }
  assert_true(limited)
  assert_true(cleanup_conditional_row_preparation(too_short).unwrap())
  let cancelled = start_conditional_row_preparation(
    schema,
    conditional_row_test_values(),
    10,
    3,
    column => cells.get(column),
  ).unwrap()
  for _ in 0..<4 {
    assert_true(
      advance_conditional_row_preparation(cancelled, 1).unwrap()
      is ConditionalRowContinue(..),
    )
  }
  assert_true(cancelled.state.admission is Some(_))
  assert_true(cancel_conditional_row_preparation(cancelled))
  assert_true(
    advance_conditional_row_preparation(cancelled, 1).unwrap()
    is ConditionalRowStopped(..),
  )
  assert_true(conditional_row_preparation_value(cancelled) is None)
  assert_true(cleanup_conditional_row_preparation(cancelled).unwrap())
  assert_true(cancelled.state.admission is None)
  assert_eq(cancelled.state.workspace.live, 0)
  let text_contract = @contract.primitive(StringType, nullable=false)
  let invalid = @admitted.checked_text_value("bad", text_contract).unwrap()
  let foreign = [Some(id), Some(invalid)]
  let rejected = start_conditional_row_preparation(
    schema,
    conditional_row_test_values(),
    10,
    3,
    column => foreign.get(column),
  ).unwrap()
  let mut mismatch = false
  for _ in 0..<10 {
    match advance_conditional_row_preparation(rejected, 1).unwrap() {
      ConditionalRowContinue(..) => ()
      ConditionalRowFailed(ForeignValue(1), ..) => {
        mismatch = true
        break
      }
      _ => fail("incompatible definition value completed")
    }
  }
  assert_true(mismatch)
  assert_true(cleanup_conditional_row_preparation(rejected).unwrap())
}

///|
test "long conditional text yields between charged chunks" {
  let contract = @contract.primitive(StringType, nullable=false)
  let schema = @schema.from_conditional_fields(
    [(Unqualified("payload"), contract, @schema.Required)],
    max_fields=1,
    max_name_bytes=7,
  ).unwrap()
  let text = "x".repeat(200)
  let checked = @admitted.admit(contract, input_cursor("\"" + text + "\""), {
    max_nodes: 2,
    max_text_bytes: 200,
    max_depth: 1,
  }).unwrap()
  let limits : ValueLimits = {
    max_nodes: 2,
    max_text_bytes: 207,
    max_depth: 2,
    max_work: 209,
  }
  let active = start_conditional_row_preparation(schema, limits, 16, 2, column => {
    if column == 0 {
      Some(Some(checked))
    } else {
      None
    }
  }).unwrap()
  let mut polls = 0
  let mut completed = None
  for _ in 0..<16 {
    polls += 1
    match advance_conditional_row_preparation(active, 1).unwrap() {
      ConditionalRowContinue(..) => ()
      ConditionalRowComplete(row, ..) => {
        completed = Some(row)
        break
      }
      _ => fail("long text did not complete")
    }
  }
  assert_true(polls > 6)
  assert_eq(conditional_row_usage(completed.unwrap()), {
    nodes: 2,
    text_bytes: 207,
    work: 209,
  })
  assert_true(cleanup_conditional_row_preparation(active).unwrap())
  let cancelled = start_conditional_row_preparation(schema, limits, 16, 2, column => {
    if column == 0 {
      Some(Some(checked))
    } else {
      None
    }
  }).unwrap()
  for _ in 0..<5 {
    assert_true(
      advance_conditional_row_preparation(cancelled, 1).unwrap()
      is ConditionalRowContinue(..),
    )
  }
  assert_true(cancel_conditional_row_preparation(cancelled))
  assert_true(
    advance_conditional_row_preparation(cancelled, 1).unwrap()
    is ConditionalRowStopped(..),
  )
  assert_true(cleanup_conditional_row_preparation(cancelled).unwrap())
  assert_eq(cancelled.state.workspace.live, 0)
  let one_short = start_conditional_row_preparation(
    schema,
    { ..limits, max_text_bytes: 206, },
    16,
    2,
    column => if column == 0 { Some(Some(checked)) } else { None },
  ).unwrap()
  let mut limited = false
  for _ in 0..<16 {
    match advance_conditional_row_preparation(one_short, 1).unwrap() {
      ConditionalRowContinue(..) => ()
      ConditionalRowFailed(Limit, ..) => {
        limited = true
        break
      }
      _ => fail("one-short long text completed")
    }
  }
  assert_true(limited)
  assert_true(cleanup_conditional_row_preparation(one_short).unwrap())
}
