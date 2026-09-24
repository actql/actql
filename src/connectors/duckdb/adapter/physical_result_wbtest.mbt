///|
fn result_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 10,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 10,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn result_schema() -> @schema.Schema {
  @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(@contract.NumberType, nullable=false),
      ),
      (
        @schema.Unqualified("label"),
        @contract.primitive(@contract.StringType, nullable=true),
      ),
    ],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
}

///|
fn result_limits() -> PhysicalResultLimits {
  { max_rows: 100, max_cells: 200, max_nodes: 200, max_text_bytes: 1000, }
}

///|
test "native record guard counts keys and canonical escaping not raw transport text" {
  // {"id":1,"label":"a\n"} occupies 22 canonical UTF-8 bytes.
  for ceiling in [21, 22] {
    let result = prepare_physical_result(
      result_schema(),
      [("id", Float64), ("label", Varchar)],
      result_limits(),
      100,
    ).unwrap()
    let budget : NativeValueBudget = {
      guards: { max_value_bytes: ceiling, max_output_rows: 1, },
      work: 2,
      bytes: 22,
      nodes: 3,
      depth: 1,
    }
    let accepted = admit_physical_chunk(result, 1, [
      result_cursor("[\"3ff0000000000000\"]"),
      result_cursor("[\"a\\n\"]"),
    ]).unwrap()
    let measured = measure_native_record(budget, accepted, 0)
    if ceiling == 22 {
      assert_true(measured is Ok(_))
    } else {
      assert_true(measured is Err(ValueBytes))
    }
    assert_eq((budget.work, budget.bytes, budget.nodes), (0, 0, 0))
  }
}

///|
test "encoded output progress carries the exact record measurement" {
  let result = prepare_physical_result(
    result_schema(),
    [("id", Float64), ("label", Varchar)],
    result_limits(),
    100,
  ).unwrap()
  let accepted = admit_physical_chunk(result, 2, [
    result_cursor("[\"3ff0000000000000\",\"4000000000000000\"]"),
    result_cursor("[\"a\\n\",\"日本語\"]"),
  ]).unwrap()
  let cached : NativeValueBudget = {
    guards: { max_value_bytes: 100, max_output_rows: 2, },
    work: 6,
    bytes: 100,
    nodes: 20,
    depth: 1,
  }
  let ordinary : NativeValueBudget = {
    guards: { max_value_bytes: 100, max_output_rows: 2, },
    work: 6,
    bytes: 100,
    nodes: 20,
    depth: 1,
  }
  let writer = @encode.hashing_writer(1000, 100, 10)
  @encode.begin_array(writer)
  for row in 0..<2 {
    let previous = @encode.writer_progress(writer)
    @encode.begin_object(writer)
    // Output order is allowed to differ from schema-order measurement.
    @encode.key(writer, "label")
    @admitted.emit_wire_value(
      physical_batch_cell(accepted, row, 1).unwrap().value,
      writer,
    )
    @encode.key(writer, "id")
    @admitted.emit_wire_value(
      physical_batch_cell(accepted, row, 0).unwrap().value,
      writer,
    )
    @encode.end_object(writer)
    assert_true(
      charge_native_encoded_record(
        cached,
        2,
        previous,
        @encode.writer_progress(writer),
        row > 0,
      ),
    )
    ordinary.work -= 1
    measure_native_record(ordinary, accepted, row).unwrap()
  }
  assert_eq(
    (cached.work, cached.bytes, cached.nodes),
    (ordinary.work, ordinary.bytes, ordinary.nodes),
  )
  @encode.end_array(writer)
  @encode.finish_hash_metrics(writer) |> ignore
}

///|
test "encoded output guard falls back at a failing record ceiling" {
  let budget : NativeValueBudget = {
    guards: { max_value_bytes: 21, max_output_rows: 1, },
    work: 3,
    bytes: 22,
    nodes: 3,
    depth: 1,
  }
  assert_false(
    charge_native_encoded_record(budget, 2, (1, 1, 1), (23, 4, 2), false),
  )
  assert_eq((budget.work, budget.bytes, budget.nodes), (3, 22, 3))
}

///|
test "physical chunks retain schema order and charge scalar usage across chunks" {
  let result = prepare_physical_result(
    result_schema(),
    [("label", Varchar), ("id", Float64)],
    result_limits(),
    34,
  ).unwrap()
  let first = admit_physical_chunk(result, 2, [
    result_cursor("[\"日本語\",null]"),
    result_cursor("[\"4008000000000000\",\"4000000000000000\"]"),
  ]).unwrap()
  assert_eq(physical_batch_rows(first), 2)
  assert_true(physical_equal(physical_batch_owner(first), result))
  assert_true(
    physical_batch_cell(first, 0, 0).unwrap().value is @admitted.Number(3),
  )
  assert_true(
    physical_batch_cell(first, 0, 1).unwrap().value
    is @admitted.Text("日本語"),
  )
  assert_true(physical_batch_cell(first, 1, 1).unwrap().value is @admitted.Null)
  assert_eq(physical_result_usage(result), (2, 4, 4, 9))
  let second = admit_physical_chunk(result, 1, [
    result_cursor("[\"x\"]"),
    result_cursor("[\"3ff0000000000000\"]"),
  ]).unwrap()
  assert_true(
    physical_batch_cell(second, 0, 0).unwrap().value is @admitted.Number(1),
  )
  assert_eq(physical_result_usage(result), (3, 6, 6, 10))
  assert_true(physical_batch_cell(first, 2, 0) is None)
  assert_true(physical_batch_cell(first, 0, -1) is None)
}

///|
test "empty physical results still reject unsupported mismatched and duplicate fields" {
  assert_true(
    prepare_physical_result(
      result_schema(),
      [("id", Varchar), ("label", Varchar)],
      result_limits(),
      100,
    )
    is Err(FieldType(0, TypeMismatch)),
  )
  assert_true(
    prepare_physical_result(
      result_schema(),
      [("id", Float64), ("id", Float64)],
      result_limits(),
      100,
    )
    is Err(SchemaMismatch),
  )
  assert_true(
    prepare_physical_result(
      result_schema(),
      [("id", Float64), ("unknown", Varchar)],
      result_limits(),
      100,
    )
    is Err(SchemaMismatch),
  )
  assert_true(
    prepare_physical_result(
      result_schema(),
      [("id", Float64), ("label", Varchar)],
      result_limits(),
      33,
    )
    is Err(MetadataLimit),
  )
  let result = prepare_physical_result(
    result_schema(),
    [("id", Float64), ("label", Varchar)],
    result_limits(),
    34,
  ).unwrap()
  assert_eq(
    physical_batch_rows(
      admit_physical_chunk(result, 0, [result_cursor("[]"), result_cursor("[]")]).unwrap(),
    ),
    0,
  )
  assert_eq(physical_result_usage(result), (0, 0, 0, 0))
}

///|
test "physical chunk resource limits are cumulative and failures are terminal" {
  for
    (limits, second_ok) in [
      ({ ..result_limits(), max_rows: 2, }, true),
      ({ ..result_limits(), max_rows: 1, }, false),
      ({ ..result_limits(), max_cells: 4, }, true),
      ({ ..result_limits(), max_cells: 3, }, false),
      ({ ..result_limits(), max_nodes: 4, }, true),
      ({ ..result_limits(), max_nodes: 3, }, false),
      ({ ..result_limits(), max_text_bytes: 2, }, true),
      ({ ..result_limits(), max_text_bytes: 1, }, false),
    ] {
    let result = prepare_physical_result(
      result_schema(),
      [("id", Float64), ("label", Varchar)],
      limits,
      34,
    ).unwrap()
    let columns = [
      result_cursor("[\"3ff0000000000000\"]"),
      result_cursor("[\"x\"]"),
    ]
    assert_true(admit_physical_chunk(result, 1, columns) is Ok(_))
    assert_eq(admit_physical_chunk(result, 1, columns) is Ok(_), second_ok)
    if !second_ok {
      assert_true(
        admit_physical_chunk(result, 0, [
          result_cursor("[]"),
          result_cursor("[]"),
        ])
        is Err(Terminal),
      )
    }
  }
}

///|
test "physical failures report global row and logical column not transport column" {
  let result = prepare_physical_result(
    result_schema(),
    [("label", Varchar), ("id", Float64)],
    result_limits(),
    34,
  ).unwrap()
  admit_physical_chunk(result, 1, [
    result_cursor("[null]"),
    result_cursor("[\"3ff0000000000000\"]"),
  ]).unwrap()
  |> ignore
  assert_true(
    admit_physical_chunk(result, 1, [
      result_cursor("[false]"),
      result_cursor("[\"7ff0000000000000\"]"),
    ])
    is Err(Cell(1, 0, _)),
  )
  assert_true(admit_physical_chunk(result, 0, []) is Err(Terminal))
  let cancelled = prepare_physical_result(
    result_schema(),
    [("label", Varchar), ("id", Float64)],
    result_limits(),
    34,
  ).unwrap()
  cancel_physical_result(cancelled)
  assert_true(admit_physical_chunk(cancelled, 0, []) is Err(Terminal))
}

///|
test "chunk widths preserve cumulative usage and the first invalid cell" {
  for width in [1, 7, 1000] {
    let result = prepare_physical_result(
      result_schema(),
      [("label", Varchar), ("id", Float64)],
      result_limits(),
      34,
    ).unwrap()
    let mut start = 0
    let mut failed = false
    while start < 15 {
      let length = if width < 15 - start { width } else { 15 - start }
      let labels = StringBuilder()
      let numbers = StringBuilder()
      labels.write_string("[")
      numbers.write_string("[")
      for offset in 0..<length {
        if offset > 0 {
          labels.write_string(",")
          numbers.write_string(",")
        }
        labels.write_string("\"x\"")
        numbers.write_string(
          if start + offset == 7 {
            "\"7ff0000000000000\""
          } else {
            "\"3ff0000000000000\""
          },
        )
      }
      labels.write_string("]")
      numbers.write_string("]")
      match
        admit_physical_chunk(result, length, [
          result_cursor(labels.to_string()),
          result_cursor(numbers.to_string()),
        ]) {
        Ok(_) => ()
        Err(issue) => {
          assert_true(issue is Cell(7, 0, _))
          failed = true
          break
        }
      }
      start += length
    }
    assert_true(failed)
    let (_, _, nodes, bytes) = physical_result_usage(result)
    assert_eq(nodes, 14)
    assert_eq(bytes, 7)
  }
}
