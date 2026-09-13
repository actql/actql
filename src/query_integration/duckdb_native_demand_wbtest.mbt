///|
fn native_demand_physical() -> @execution.FixedInputGuardMeasureLimits {
  { max_work: 10000, max_bytes: 100000, max_nodes: 10000, max_depth: 100, }
}

///|
fn demand_receiving(
  supplied? : String = "{\"minimum\":1}",
  filter? : String = "id > $minimum",
  ceiling? : Int = 100,
  input_rows? : Int = 3,
  input? : String = "[\"4008000000000000\",\"3ff0000000000000\",\"4000000000000000\"]",
  output_rows? : Int = 2,
  output? : String = "[\"4008000000000000\",\"4000000000000000\"]",
) -> @duckdb.NativeReceiving {
  let (_, owner) = query_sequence_fixture(
    filter~,
    supplied~,
    parameters="{\"minimum\":{\"type\":\"number\",\"nullable\":true}}",
  )
  let query = @duckdb.compile_native_filter_select(
    owner,
    "main",
    "records",
    native_compile_limits(),
  ).unwrap()
  let value = @duckdb.prepare_native_receiving(
    @duckdb.prepare_native_scan(query, 1, 1000).unwrap(),
    { max_rows: 100, max_cells: 100, max_nodes: 100, max_text_bytes: 1000, },
    1000,
    { max_value_bytes: ceiling, max_output_rows: 100, },
    native_demand_physical(),
  ).unwrap()
  receiving_metadata(value)
  for
    (role, rows, cells) in [
      (@duckdb.ValidationScan, input_rows, input),
      (@duckdb.NativeResult, output_rows, output),
    ] {
    let port = @duckdb.begin_native_receipt(value, role, [
      ("id", @duckdb.Float64),
    ]).unwrap()
    @duckdb.accept_native_receipt_chunk(value, port, rows, [input_cursor(cells)]).unwrap()
    @duckdb.finish_native_receipt(value, port).unwrap()
  }
  value
}

///|
test "native exact demanded measurements use owned operands and result counts without Local replay" {
  let value = demand_receiving()
  let exact : @execution.FixedInputGuardMeasureLimits = {
    max_work: 4,
    max_bytes: 4,
    max_nodes: 4,
    max_depth: 0,
  }
  let measured = @duckdb.measure_native_demand(value, exact).unwrap()
  let usage = @duckdb.native_demand_usage(measured)
  assert_eq(usage.rows, 3)
  assert_eq(usage.field_bytes, 3L)
  assert_true(usage.rhs_bytes is Some(1))
  assert_eq((usage.true_rows, usage.false_rows, usage.null_rows), (2, 1, 0))
  assert_eq(usage.predicate_bytes, 13L)
  assert_eq(
    (usage.physical_work, usage.physical_bytes, usage.physical_nodes),
    (4, 4, 4),
  )
  assert_true(@duckdb.native_demand_matches(measured, value))
  assert_false(@duckdb.native_demand_matches(measured, demand_receiving()))
  for
    limits in [
      { ..exact, max_work: 3, },
      { ..exact, max_bytes: 3, },
      { ..exact, max_nodes: 3, },
    ] {
    let short = demand_receiving()
    assert_true(
      @duckdb.measure_native_demand(short, limits) is Err(Operand(2, false, _)),
    )
    assert_false(@duckdb.native_receiving_has_both(short))
    assert_true(
      @duckdb.measure_native_demand(short, exact) is Err(InvalidState),
    )
  }
  @duckdb.abort_native_receiving(value)
  assert_false(@duckdb.native_demand_matches(measured, value))
}

///|
test "native demanded RHS size respects equality literal Parameter and empty input" {
  for filter in ["id > $minimum", "id > 123456789"] {
    for ceiling in [8, 9] {
      let value = demand_receiving(
        filter~,
        ceiling~,
        supplied="{\"minimum\":123456789}",
        input_rows=1,
        input="[\"3ff0000000000000\"]",
        output_rows=0,
        output="[]",
      )
      let result = @duckdb.measure_native_demand(
        value,
        native_demand_physical(),
      )
      if ceiling == 8 {
        assert_true(result is Err(Operand(0, true, ValueBytes)))
        assert_false(@duckdb.native_receiving_has_both(value))
      } else {
        let usage = @duckdb.native_demand_usage(result.unwrap())
        assert_true(usage.rhs_bytes is Some(9))
        assert_eq(
          (usage.true_rows, usage.false_rows, usage.null_rows),
          (0, 1, 0),
        )
        assert_eq(usage.predicate_bytes, 5L)
      }
    }
    let empty = demand_receiving(
      filter~,
      ceiling=0,
      supplied="{\"minimum\":123456789}",
      input_rows=0,
      input="[]",
      output_rows=0,
      output="[]",
    )
    let usage = @duckdb.native_demand_usage(
      @duckdb.measure_native_demand(empty, {
        max_work: 0,
        max_bytes: 0,
        max_nodes: 0,
        max_depth: 0,
      }).unwrap(),
    )
    assert_eq(usage.rows, 0)
    assert_true(usage.rhs_bytes is None)
    assert_eq(usage.predicate_bytes, 0L)
  }
}

///|
test "NULL RHS has exact NULL roots and impossible native counts cannot yield demand evidence" {
  let value = demand_receiving(
    supplied="{\"minimum\":null}",
    output_rows=0,
    output="[]",
  )
  let usage = @duckdb.native_demand_usage(
    @duckdb.measure_native_demand(value, native_demand_physical()).unwrap(),
  )
  assert_true(usage.rhs_bytes is Some(4))
  assert_eq((usage.true_rows, usage.false_rows, usage.null_rows), (0, 0, 3))
  assert_eq(usage.predicate_bytes, 12L)
  let wrong = demand_receiving(supplied="{\"minimum\":null}")
  assert_true(
    @duckdb.measure_native_demand(wrong, native_demand_physical())
    is Err(InvalidResultCount),
  )
  assert_false(@duckdb.native_receiving_has_both(wrong))
}

///|
test "nullable boolean demand counts are independent of chunk width and preserve duplicates" {
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @value_contract.primitive(@value_contract.BooleanType, nullable=true),
      ),
    ],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let pipeline = @pipeline.check(
    input_cursor("[{\"filter\":\"id = false\"},{\"select\":[\"id\"]}]"),
    [("fixed", schema)],
    None,
    None,
    {
      max_steps: 2,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let query = @duckdb.compile_native_filter_select(
    owner,
    "main",
    "records",
    native_compile_limits(),
  ).unwrap()
  let scan = @duckdb.prepare_native_scan(query, 1, 1000).unwrap()
  for width in [1, 7, 1000] {
    let value = @duckdb.prepare_native_receiving(
      scan,
      { max_rows: 10, max_cells: 10, max_nodes: 10, max_text_bytes: 1000, },
      100,
      { max_value_bytes: 12, max_output_rows: 2, },
      native_demand_physical(),
    ).unwrap()
    receiving_metadata(value)
    let port = @duckdb.begin_native_receipt(value, @duckdb.ValidationScan, [
      ("id", @duckdb.Boolean),
    ]).unwrap()
    let cells = ["null", "true", "false", "false"]
    let mut start = 0
    while start < cells.length() {
      let end = (start + width).min(cells.length())
      let text = "[" + cells[start:end].to_owned().join(",") + "]"
      @duckdb.accept_native_receipt_chunk(value, port, end - start, [
        input_cursor(text),
      ]).unwrap()
      start = end
    }
    @duckdb.finish_native_receipt(value, port).unwrap()
    let result = @duckdb.begin_native_receipt(value, @duckdb.NativeResult, [
      ("id", @duckdb.Boolean),
    ]).unwrap()
    @duckdb.accept_native_receipt_chunk(value, result, 2, [
      input_cursor("[false,false]"),
    ]).unwrap()
    @duckdb.finish_native_receipt(value, result).unwrap()
    let usage = @duckdb.native_demand_usage(
      @duckdb.measure_native_demand(value, {
        max_work: 5,
        max_bytes: 23,
        max_nodes: 5,
        max_depth: 0,
      }).unwrap(),
    )
    assert_eq(usage.field_bytes, 18L)
    assert_true(usage.rhs_bytes is Some(5))
    assert_eq((usage.true_rows, usage.false_rows, usage.null_rows), (2, 1, 1))
    assert_eq(usage.predicate_bytes, 17L)
    assert_eq(
      (usage.physical_work, usage.physical_bytes, usage.physical_nodes),
      (5, 23, 5),
    )
  }
}
