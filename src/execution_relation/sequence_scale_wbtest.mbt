///|
// Closed-form expectations: unique id is N-i, rank is either 1 or N-i.
// No reference engine or product comparator computes expected survivors.
fn sequence_scale(
  count : Int,
  width : Int,
  same : Bool,
  profile? : Bool = false,
  candidate? : LayoutCandidate = RowLayout,
) -> Unit raise {
  let total_clock = @bench.monotonic_clock_start()
  let (phases, counters) = measure_legacy_layout(count, width, same, candidate)
  // Only numeric measurements escape the inner scope. Includes clearing stores
  // and disposing fixture/input/output owners, not just the five phase clocks.
  let total_us = @bench.monotonic_clock_end(total_clock)
  if profile {
    println(
      "{\"kind\":\"layout-sample\",\"candidate\":\"" +
      (match candidate {
        RowLayout => "A"
        ValueColumns => "B"
        TypedColumns => "C"
      }) +
      "\",\"rows\":" +
      count.to_string() +
      ",\"columns\":" +
      width.to_string() +
      ",\"same_keys\":" +
      same.to_string() +
      ",\"disposal_included\":true,\"phases_us\":" +
      phases.to_json().stringify() +
      ",\"end_to_end_us\":" +
      total_us.to_string() +
      ",\"retained_slots\":" +
      counters[0].to_string() +
      ",\"peak_retained_slots\":" +
      counters[1].to_string() +
      ",\"control_remaining\":" +
      counters[2].to_string() +
      ",\"owned_buffer_slots\":" +
      (if candidate == RowLayout { "null" } else { counters[3].to_string() }) +
      ",\"peak_owned_buffer_slots\":" +
      (if candidate == RowLayout { "null" } else { counters[4].to_string() }) +
      ",\"owned_typed_bytes\":" +
      (if candidate == RowLayout { "null" } else { counters[5].to_string() }) +
      ",\"peak_owned_typed_bytes\":" +
      (if candidate == RowLayout { "null" } else { counters[6].to_string() }) +
      "}",
    )
  }
}

///|
fn measure_legacy_layout(
  count : Int,
  width : Int,
  same : Bool,
  candidate : LayoutCandidate,
) -> (Array[Double], Array[Int]) raise {
  let phases = []
  let (generated, input) = legacy_layout_fixture(count, width, same, phases)
  let fixture_us = phases[0]
  let prepare_us = phases[1]
  let capture_us = phases[2]
  let import_clock = @bench.monotonic_clock_start()
  let value_limits = numeric_layout_limits(count).input_values
  if candidate != RowLayout {
    return profile_column_sequence(
      generated, input, candidate, count, width, same, value_limits, import_clock,
      fixture_us, prepare_us, capture_us,
    )
  }
  let invocation = prepare_sequence_invocation(
    generated.contracts,
    generated.sequence,
    [input],
    generated.retained_ids,
    numeric_layout_limits(count),
    { remaining: 100000000, max_frames: 100, },
    produced=[],
    fragments=Some(generated.contexts),
    ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
  ).unwrap()
  let import_us = capture_us + @bench.monotonic_clock_end(import_clock)
  let execute_clock = @bench.monotonic_clock_start()
  let complete = run_sequence_invocation(invocation).unwrap()
  let execute_us = @bench.monotonic_clock_end(execute_clock)
  let observe_clock = @bench.monotonic_clock_start()
  verify_legacy_layout_store(complete.store, width, same)
  let observe_us = @bench.monotonic_clock_end(observe_clock)
  let counters = [
    complete.store.workspace.live,
    complete.store.workspace.peak,
    invocation.control.remaining,
    0,
    0,
    0,
    0,
  ]
  clear_table_store(complete.store)
  assert_true(complete.store.tables.all(table => table is None))
  ([fixture_us, prepare_us, import_us, execute_us, observe_us], counters)
}

///|
fn legacy_layout_fixture(
  count : Int,
  width : Int,
  same : Bool,
  phases : Array[Double],
) -> (GeneratedSequence, CapturedRows) raise {
  let fixture_clock = @bench.monotonic_clock_start()
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
  phases.push(@bench.monotonic_clock_end(fixture_clock))
  let prepare_clock = @bench.monotonic_clock_start()
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
  phases.push(@bench.monotonic_clock_end(prepare_clock))
  let import_clock = @bench.monotonic_clock_start()
  let value_limits : ValueLimits = {
    max_nodes: 20000000,
    max_text_bytes: 100000000,
    max_depth: 100,
    max_work: 100000000,
  }
  let input = capture_input(owner, 0, raw, max_rows=count, value_limits).unwrap()
  phases.push(@bench.monotonic_clock_end(import_clock))
  (generated, input)
}

///|
fn[T : RelationRows] verify_legacy_layout_store(
  store : TableStore[T],
  width : Int,
  same : Bool,
) -> Unit raise {
  let unique = store.tables[6].unwrap().table
  let chosen = store.tables[9].unwrap().table
  let names = RelationRows::field_names(chosen)
  let expected = if same { 1 } else { 10 }
  assert_eq(IndexedRows::row_count(unique), expected)
  assert_eq(IndexedRows::column_count(unique), 1)
  assert_eq(RelationRows::field_names(unique), ["rank"])
  assert_eq(IndexedRows::row_count(chosen), expected)
  let positions : Map[String, Int] = Map([])
  for i = 0; i < names.length(); i = i + 1 {
    positions[names[i]] = i
  }
  let id_at = positions.get("id").unwrap()
  let rank_at = positions.get("rank").unwrap()
  assert_eq(names.length(), width)
  for i = 0; i < expected; i = i + 1 {
    assert_true(
      IndexedRows::read_cell(unique, i, 0) is Number(n) &&
      n == (i + 1).to_double(),
    )
    assert_true(
      IndexedRows::read_cell(chosen, i, id_at) is Number(n) &&
      n == (i + 1).to_double(),
    )
    assert_true(
      IndexedRows::read_cell(chosen, i, rank_at) is Number(n) &&
      n == (i + 1).to_double(),
    )
    for j = 2; j < width; j = j + 1 {
      let at = positions.get("p" + j.to_string()).unwrap()
      assert_true(
        IndexedRows::read_cell(chosen, i, at) is Number(n) &&
        n == (i + 1 + j).to_double(),
      )
    }
  }
  // Retained outputs do not keep the alias source/intermediate tables alive.
  for slot = 0; slot < store.tables.length(); slot = slot + 1 {
    if slot != 6 && slot != 9 {
      assert_true(store.tables[slot] is None)
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
