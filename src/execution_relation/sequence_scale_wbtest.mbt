///|
// Closed-form expectations: unique id is N-i, rank is either 1 or N-i.
// No reference engine or product comparator computes expected survivors.
fn sequence_scale(count : Int, width : Int, same : Bool) -> Unit raise {
  let numeric = @contract.read_checked(
    input_cursor("{\"type\":\"number\",\"nullable\":false}"),
    { max_nodes: 10, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let fields = [
    (@schema.Unqualified("id"), numeric),
    (@schema.Unqualified("k"), numeric),
  ]
  for j = 2; j < width; j = j + 1 {
    fields.push((@schema.Unqualified("p" + j.to_string()), numeric))
  }
  let schema = @schema.from_fields(
    fields,
    max_fields=width,
    max_name_bytes=10000,
  ).unwrap()
  let key = @evidence.declare_primary_key(
    input_cursor("[\"id\"]"),
    @carrier.relation(@carrier.typed_rows(schema)),
    { max_fields: width, max_name_bytes: 10000, },
  ).unwrap()
  let owner = sort_input_owner(
    @pipeline.KeyedInput(key),
    "[{\"rename\":{\"k\":\"rank\"}},{\"drop\":[]},{\"sort\":[{\"id\":\"asc\"}],\"as\":\"ordered\"},{\"select\":[\"rank\"]},{\"distinct\":true},{\"take\":10},{\"from\":\"ordered\",\"dedupe_rows\":{\"by\":[\"rank\"],\"order_by\":[{\"id\":\"asc\"}]}},{\"sort\":[{\"id\":\"asc\"}]},{\"take\":10}]",
  )
  let sequence = @lower.prepare_sequence(owner, {
    max_steps: 100,
    max_rows: count,
    max_cells: count * width,
    max_bindings: 1000,
    max_name_bytes: 100000,
    expressions: {
      max_nodes: 10000,
      max_work: 1000000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 100000,
    },
  }).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["limit_5", "limit_8"],
    1000000,
    100000,
  ).unwrap()
  let raw = Array::makei(count, i => {
    let id = count - i
    let mut text = "{\"id\":" +
      id.to_string() +
      ",\"k\":" +
      (if same { 1 } else { id }).to_string()
    for j = 2; j < width; j = j + 1 {
      text += ",\"p" + j.to_string() + "\":" + (id + j).to_string()
    }
    input_cursor(text + "}")
  })
  let value_limits : ValueLimits = {
    max_nodes: 20000000,
    max_text_bytes: 100000000,
    max_depth: 100,
    max_work: 100000000,
  }
  let input = capture_input(owner, 0, raw, max_rows=count, value_limits).unwrap()
  let complete = execute_generated_sequence(generated, [input], {
    rows: {
      max_rows: count,
      metadata_entries: 100000,
      retained_entries: 20000000,
      operation_entries: 20000000,
      input_values: value_limits,
      output_values: value_limits,
    },
    max_work: 100000000,
    max_frames: 100,
  }).unwrap()
  let unique = completed_output(complete, Step(5)).unwrap().table
  let chosen = completed_output(complete, Step(8)).unwrap().table
  let expected = if same { 1 } else { 10 }
  assert_eq(unique.rows.length(), expected)
  assert_eq(chosen.rows.length(), expected)
  let positions : Map[String, Int] = Map([])
  for i = 0; i < chosen.names.length(); i = i + 1 {
    positions[chosen.names[i]] = i
  }
  let id_at = positions.get("id").unwrap()
  let rank_at = positions.get("rank").unwrap()
  assert_eq(chosen.names.length(), width)
  for i = 0; i < expected; i = i + 1 {
    assert_true(unique.rows[i][0] is Number(n) && n == (i + 1).to_double())
    assert_true(chosen.rows[i][id_at] is Number(n) && n == (i + 1).to_double())
    assert_true(
      chosen.rows[i][rank_at] is Number(n) && n == (i + 1).to_double(),
    )
    for j = 2; j < width; j = j + 1 {
      let at = positions.get("p" + j.to_string()).unwrap()
      assert_true(
        chosen.rows[i][at] is Number(n) && n == (i + 1 + j).to_double(),
      )
    }
  }
  // Retained outputs do not keep the alias source/intermediate tables alive.
  assert_true(completed_output(complete, Input(0)) is None)
  for i = 0; i < 9; i = i + 1 {
    if i != 5 && i != 8 {
      assert_true(completed_output(complete, Step(i)) is None)
    }
  }
}

///|
test "scale 100 narrow same" {
  sequence_scale(100, 2, true)
}

///|
test "scale 100 narrow different" {
  sequence_scale(100, 2, false)
}

///|
test "scale 100 wide same" {
  sequence_scale(100, 64, true)
}

///|
test "scale 100 wide different" {
  sequence_scale(100, 64, false)
}

///|
test "scale 1000 narrow same" {
  sequence_scale(1000, 2, true)
}

///|
test "scale 1000 narrow different" {
  sequence_scale(1000, 2, false)
}

///|
test "scale 1000 wide same" {
  sequence_scale(1000, 64, true)
}

///|
test "scale 1000 wide different" {
  sequence_scale(1000, 64, false)
}

///|
test "scale 10000 narrow same" {
  sequence_scale(10000, 2, true)
}

///|
test "scale 10000 narrow different" {
  sequence_scale(10000, 2, false)
}

///|
test "scale 10000 wide same" {
  sequence_scale(10000, 64, true)
}

///|
test "scale 10000 wide different" {
  sequence_scale(10000, 64, false)
}

///|
test "shadowed derive fields flow through filter rename sort dedupe and selection" {
  let owner = sort_seed(
    ",{\"derive\":[{\"id\":\"0 - id\"}]},{\"filter\":\"id < 0\"},{\"rename\":{\"id\":\"rank\"}},{\"sort\":[{\"rank\":\"asc\"}]},{\"dedupe_rows\":{\"by\":[\"k\"],\"order_by\":[{\"rank\":\"asc\"}]}},{\"sort\":[{\"rank\":\"asc\"}]},{\"take\":1}",
  )
  let sequence = prepared_sequence(owner)
  let contexts = [
    ordered_sequence_fragment_context(
      sequence,
      100000L,
      limits=Some({
        max_input_rows: 3L,
        max_value_bytes: 1000L,
        max_live_value_bytes: 10000L,
        max_work: 100000L,
      }),
    ),
    sequence_fragment_context(sequence, 2, 3L),
  ]
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    contexts,
    ["sort_4", "limit_7"],
    100000,
    10000,
  ).unwrap()
  for _i = 0; _i < 2; _i = _i + 1 {
    let complete = execute_generated_sequence(generated, [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    }).unwrap()
    let result = completed_output(complete, Step(7)).unwrap()
    assert_eq(completed_row_count(result), 1)
    // rename retains the original id column's physical position.
    assert_eq(completed_column_name(result, 0), Some("rank"))
    assert_true(completed_cell(result, 0, 0) is Some(Number(-3)))
    assert_eq(
      completed_row_count(completed_output(complete, Step(4)).unwrap()),
      3,
    )
  }
}
