///|
// Shapes fixed in columnar-experiment.json. These are workload fixtures, not
// alternative semantic rules or a backend-specific source program.
priv enum NumericLayoutWorkload {
  NarrowProjection
  NullableProjection
  FullWidthAddition
  LowSelectivity
  HighSelectivity
  ShortText
  LongText
  DecimalTemporal
  NestedSmallResult
  ZeroColumns
  ConditionalFrames
  OrderedFrames
  LongFrames
} derive(Eq)

///|
fn numeric_layout_fixture(
  workload : NumericLayoutWorkload,
  count : Int,
  producer_seed? : Bool = false,
  timings? : Array[Double]? = None,
) -> (GeneratedSequence, CapturedRows) raise {
  let fixture_clock = @bench.monotonic_clock_start()
  let textual = workload == ShortText || workload == LongText
  let temporal = workload == DecimalTemporal
  let nested = workload == NestedSmallResult
  let zero = workload == ZeroColumns
  let frames = workload == ConditionalFrames ||
    workload == OrderedFrames ||
    workload == LongFrames
  let width = if zero {
    0
  } else if frames {
    2
  } else if textual || temporal || nested {
    8
  } else {
    64
  }
  let payload = layout_text_payload(workload)
  let nullable = workload == NullableProjection
  let raw = Array::makei(count, i => {
    if zero {
      return input_cursor("{}")
    }
    let id = count - i
    let mut text = "{\"id\":" +
      id.to_string() +
      ",\"k\":" +
      (if nullable {
        nullable_layout_cell(id, 1)
      } else {
        ((id - 1) / 4).to_string()
      })
    for j = 2; j < width; j = j + 1 {
      text += ",\"p" +
        j.to_string() +
        "\":" +
        (if nested {
          let branches = Array::makei(8, branch => {
            let leaves = Array::makei(8, leaf => {
              (id + j + branch * 8 + leaf).to_string()
            })
            "[" + leaves.join(",") + "]"
          })
          "[" + branches.join(",") + "]"
        } else if temporal && j >= 2 && j <= 4 {
          "\"" + layout_temporal_cell(id, j) + "\""
        } else if textual {
          "\"" + payload + "\""
        } else if nullable {
          nullable_layout_cell(id, j)
        } else {
          (id + j).to_string()
        })
    }
    input_cursor(text + "}")
  })
  if timings is Some(phases) {
    phases.push(@bench.monotonic_clock_end(fixture_clock))
  }
  let prepare_clock = @bench.monotonic_clock_start()
  let numeric = @contract.read_checked(
    input_cursor("{\"type\":\"number\",\"nullable\":false}"),
    { max_nodes: 10, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let nullable_number = @contract.read_checked(
    input_cursor("{\"type\":\"number\",\"nullable\":true}"),
    { max_nodes: 10, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let nullable_boolean = @contract.read_checked(
    input_cursor("{\"type\":\"boolean\",\"nullable\":true}"),
    { max_nodes: 10, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let text_contract = @contract.read_checked(
    input_cursor("{\"type\":\"string\",\"nullable\":false}"),
    { max_nodes: 10, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let temporal_contracts = [
    "{\"type\":\"decimal\",\"nullable\":false,\"precision\":38,\"scale\":2}", "{\"type\":\"date\",\"nullable\":false}",
    "{\"type\":\"timestamp\",\"nullable\":false}",
  ].map(text => {
    @contract.read_checked(input_cursor(text), {
      max_nodes: 10,
      max_depth: 10,
      max_text_bytes: 100,
    }).unwrap()
  })
  let nested_contract = @contract.read_checked(
    input_cursor(
      "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}}",
    ),
    { max_nodes: 20, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let fields = if zero {
    []
  } else {
    [
      (@schema.Unqualified("id"), numeric),
      (
        @schema.Unqualified("k"),
        if nullable {
          nullable_boolean
        } else {
          numeric
        },
      ),
    ]
  }
  for j = 2; j < width; j = j + 1 {
    fields.push(
      (
        @schema.Unqualified("p" + j.to_string()),
        if nested {
          nested_contract
        } else if temporal && j >= 2 && j <= 4 {
          temporal_contracts[j - 2]
        } else if textual {
          text_contract
        } else if !nullable {
          numeric
        } else if j % 2 == 0 {
          nullable_number
        } else {
          nullable_boolean
        },
      ),
    )
  }
  let schema = @schema.from_fields(
    fields,
    max_fields=width,
    max_name_bytes=10000,
  ).unwrap()
  let input_contract = if zero {
    @pipeline.CarrierInput(@carrier.relation(@carrier.typed_rows(schema)))
  } else {
    let key = @evidence.declare_primary_key(
      input_cursor("[\"id\"]"),
      @carrier.relation(@carrier.typed_rows(schema)),
      { max_fields: width, max_name_bytes: 10000, },
    ).unwrap()
    @pipeline.KeyedInput(key)
  }
  let (program, expression_steps) = match workload {
    ConditionalFrames =>
      (
        "[{\"derive\":{\"x\":\"if(id % 2 = 0, CASE WHEN k >= 0 THEN id + 1 ELSE 1 / 0 END, CASE WHEN id > 0 THEN id + 2 ELSE 1 / 0 END)\"}}]",
        [0],
      )
    OrderedFrames => {
      let bindings = Array::makei(8, i => {
        if i == 0 {
          "{\"k\":\"id + 1\"}"
        } else {
          let prior = if i == 1 { "k" } else { "x" + (i - 1).to_string() }
          "{\"x" + i.to_string() + "\":\"" + prior + " + 1\"}"
        }
      })
      ("[{\"derive\":[" + bindings.join(",") + "]}]", [0])
    }
    LongFrames =>
      (
        "[{\"derive\":{\"x\":\"id" + Array::make(64, " + 1").join("") + "\"}}]",
        [0],
      )
    ZeroColumns => ("[{\"drop\":[]},{\"sort\":[]}]", [])
    NestedSmallResult =>
      (
        "[{\"filter\":\"id > 0\"},{\"sort\":[{\"id\":\"asc\"}]},{\"take\":1}]",
        [0],
      )
    DecimalTemporal =>
      (
        "[{\"rename\":{\"id\":\"rank\"}},{\"sort\":[{\"p3\":\"asc\"},{\"p4\":\"asc\"},{\"p2\":\"asc\"}]},{\"dedupe_rows\":{\"by\":[\"k\",\"k\"],\"order_by\":[{\"rank\":\"asc\"}]}},{\"take\":10}]",
        [],
      )
    ShortText | LongText =>
      (
        "[{\"derive\":{\"copy\":\"p2\"}},{\"sort\":[{\"k\":\"asc\"}]},{\"distinct\":[\"k\",\"copy\"]},{\"take\":10}]",
        [0],
      )
    NullableProjection =>
      (
        "[{\"select\":[\"id\",\"p2\"]},{\"derive\":[{\"old\":\"p2\"},{\"p2\":\"coalesce(old, 0) > 0\"}]},{\"filter\":\"id > 0\"},{\"sort\":[{\"id\":\"asc\"}]},{\"take\":10}]",
        [1, 2],
      )
    NarrowProjection =>
      (
        "[{\"select\":[\"id\",\"p2\"]},{\"derive\":{\"next\":\"p2 + 1\"}},{\"filter\":\"next > 0\"},{\"sort\":[{\"id\":\"asc\"}]},{\"take\":10}]",
        [1, 2],
      )
    FullWidthAddition =>
      (
        "[{\"derive\":{\"a\":\"p2 + 1\",\"b\":\"p3 + 1\"}},{\"sort\":[{\"k\":\"asc\"}]},{\"take\":10}]",
        [0],
      )
    LowSelectivity | HighSelectivity => {
      let selected = if workload == LowSelectivity {
        count / 100
      } else {
        count * 99 / 100
      }
      (
        "[{\"derive\":{\"next\":\"id + 1\"}},{\"filter\":\"id <= " +
        selected.to_string() +
        "\"},{\"sort\":[{\"id\":\"asc\"}]},{\"select\":[\"id\",\"next\"]}]",
        [0, 1],
      )
    }
  }
  let (program, expression_steps) = if producer_seed {
    ("[{\"rename\":{}}]", [])
  } else {
    (program, expression_steps)
  }
  let owner = if frames {
    // Supplementary deep-expression workloads need a larger preparation
    // envelope than the small sort fixture. Identical on both revisions;
    // execution limits below are unchanged.
    let check = @pipeline.check_with_evidence(
      input_cursor(program),
      [("seed", input_contract)],
      None,
      Some(input_cursor("\"seed\"")),
      {
        max_steps: 100,
        max_work: 100000,
        max_text_bytes: 10000,
        max_nodes: 10000,
        max_tokens: 10000,
        max_depth: 1000,
      },
    )
    @lower.bind_parameters(
      @lower.prepare(check.unwrap(), {
        max_nodes: 1000,
        max_references: 1000,
        max_work: 100000,
        max_identifier_bytes: 10000,
      }).unwrap(),
      None,
      max_parameters=0,
      max_name_bytes=0,
    ).unwrap()
  } else {
    sort_input_owner(input_contract, program)
  }
  let sequence = @lower.prepare_sequence(owner, {
    max_steps: 100,
    max_rows: count,
    max_cells: count * 66,
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
  let contexts = []
  for step in expression_steps {
    let pipeline = @lower.prepare_fragment_pipeline(sequence, step, {
      max_roots: 100,
      max_pointer_bytes: 10000,
      max_work: 100000,
    }).unwrap()
    let logical : @lower.FragmentRowLimits = {
      max_input_rows: count.to_int64(),
      max_value_bytes: 100000L,
      max_live_value_bytes: 10000000L,
      max_work: 100000000L,
    }
    let ordered = if (nullable && step == 1) || workload == OrderedFrames {
      Some(
        admit_ordered_contract(
          registered_relation_contracts(),
          registered_ordered(),
          registry_limits(),
        ).unwrap(),
      )
    } else {
      None
    }
    let request = @lower.prepare_fragment_request(
      pipeline,
      count.to_int64(),
      100000L,
      row_limits=if ordered is Some(_) { Some(logical) } else { None },
    ).unwrap()
    let runtime = prepare_runtime_fragment(
      request,
      test_fragment_contract(),
      material_demands(),
      if frames {
        { ..registry_limits(), max_body_depth: 1000, }
      } else {
        registry_limits()
      },
      logical,
      ordered~,
    )
    contexts.push(runtime.unwrap())
  }
  let last = @lower.sequence_count(sequence) - 1
  let id = @lower.node_id(
    @lower.node_at(@lower.bound_preparation(owner), last).unwrap(),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    contexts,
    [id],
    1000000,
    100000,
  ).unwrap()
  if timings is Some(phases) {
    phases.push(@bench.monotonic_clock_end(prepare_clock))
  }
  let capture_clock = @bench.monotonic_clock_start()
  let input = capture_input(
    owner,
    0,
    raw,
    max_rows=count,
    numeric_layout_limits(count).input_values,
  ).unwrap()
  if timings is Some(phases) {
    phases.push(@bench.monotonic_clock_end(capture_clock))
  }
  (generated, input)
}

///|
fn numeric_layout_limits(count : Int) -> SequenceRunLimits {
  let values : ValueLimits = {
    max_nodes: 20000000,
    max_text_bytes: 100000000,
    max_depth: 100,
    max_work: 100000000,
  }
  {
    max_rows: count,
    metadata_entries: 100000,
    retained_entries: 20000000,
    operation_entries: 20000000,
    input_values: values,
    output_values: values,
  }
}

///|
fn nullable_layout_cell(id : Int, column : Int) -> String {
  if (id + column) % 3 == 0 {
    "null"
  } else if column % 2 == 0 {
    (id + column).to_string()
  } else {
    ((id + column) % 2 == 0).to_string()
  }
}

///|
fn layout_text_payload(workload : NumericLayoutWorkload) -> String {
  if workload != ShortText && workload != LongText {
    return ""
  }
  let size = if workload == ShortText { 8 } else { 1024 }
  let mut text = "é"
  for _i = 1; _i < size; _i = _i + 1 {
    text += "x"
  }
  text
}

///|
fn layout_temporal_cell(id : Int, column : Int) -> String {
  match column {
    2 =>
      "12345678901234567890123456789012345." +
      (if id % 2 == 0 { "02" } else { "01" })
    3 => "2026-01-" + (if id % 3 == 0 { "02" } else { "01" })
    4 => "2026-01-01T00:00:00." + (if id % 5 == 0 { "002Z" } else { "001Z" })
    _ => ""
  }
}

///|
fn[T : RelationRows] verify_numeric_layout_output(
  table : T,
  workload : NumericLayoutWorkload,
  count : Int,
) -> Unit raise {
  let rows = match workload {
    ConditionalFrames | OrderedFrames | LongFrames => count
    ZeroColumns => count
    NestedSmallResult => 1
    NarrowProjection
    | NullableProjection
    | FullWidthAddition
    | ShortText
    | LongText
    | DecimalTemporal => 10
    LowSelectivity => count / 100
    HighSelectivity => count * 99 / 100
  }
  let (names, offsets) = match workload {
    ConditionalFrames | LongFrames => (["id", "k", "x"], [])
    OrderedFrames => (["id", "k", "x1", "x2", "x3", "x4", "x5", "x6", "x7"], [])
    ZeroColumns => ([], [])
    NestedSmallResult => (["id", "k", "p2", "p3", "p4", "p5", "p6", "p7"], [])
    NarrowProjection => (["id", "p2", "next"], [0, 2, 3])
    NullableProjection => (["id", "p2", "old"], [0, 2, 2])
    FullWidthAddition => {
      let names = ["id", "k"]
      let offsets = [0, -1]
      // Canonical source schema uses lexical field order: p10 precedes p2.
      // Construct that expectation from decimal digits, not the tested sorter.
      for leading = 1; leading < 10; leading = leading + 1 {
        if leading >= 2 {
          names.push("p" + leading.to_string())
          offsets.push(leading)
        }
        for trailing = 0; trailing < 10; trailing = trailing + 1 {
          let j = leading * 10 + trailing
          if j < 64 {
            names.push("p" + j.to_string())
            offsets.push(j)
          }
        }
      }
      names.push("a")
      names.push("b")
      offsets.push(3)
      offsets.push(4)
      (names, offsets)
    }
    LowSelectivity | HighSelectivity => (["id", "next"], [0, 1])
    ShortText | LongText => (["k", "copy"], [0, 0])
    DecimalTemporal => (["rank", "k", "p2", "p3", "p4", "p5", "p6", "p7"], [])
  }
  assert_eq(IndexedRows::row_count(table), rows)
  assert_eq(table.field_names(), names)
  if workload == ConditionalFrames ||
    workload == OrderedFrames ||
    workload == LongFrames {
    for row in 0..<count {
      let id = count - row
      if workload == OrderedFrames {
        for column in 0..<9 {
          assert_true(
            IndexedRows::read_cell(table, row, column) is Number(n) &&
            n == (id + column).to_double(),
          )
        }
        continue
      }
      let delta = if workload == OrderedFrames {
        8
      } else if workload == LongFrames {
        64
      } else if id % 2 == 0 {
        1
      } else {
        2
      }
      assert_true(
        IndexedRows::read_cell(table, row, 0) is Number(n) &&
        n == id.to_double(),
      )
      assert_true(
        IndexedRows::read_cell(table, row, 1) is Number(n) &&
        n == ((id - 1) / 4).to_double(),
      )
      assert_true(
        IndexedRows::read_cell(table, row, 2) is Number(n) &&
        n == (id + delta).to_double(),
      )
    }
    return
  }
  if workload == ZeroColumns {
    for row in 0..<count {
      assert_eq(IndexedRows::row_width(table, row), 0)
    }
    return
  }
  if workload == NestedSmallResult {
    assert_true(IndexedRows::read_cell(table, 0, 0) is Number(1))
    assert_true(IndexedRows::read_cell(table, 0, 1) is Number(0))
    for column = 2; column < 8; column = column + 1 {
      guard IndexedRows::read_cell(table, 0, column)
        is Captured(@admitted.Array(branches)) else {
        fail("nested root")
      }
      assert_eq(@admitted.element_count(branches), 8)
      for branch = 0; branch < 8; branch = branch + 1 {
        guard @admitted.element_at(branches, branch)
          is Some(@admitted.Array(leaves)) else {
          fail("nested branch")
        }
        assert_eq(@admitted.element_count(leaves), 8)
        for leaf = 0; leaf < 8; leaf = leaf + 1 {
          assert_true(
            @admitted.element_at(leaves, leaf) is Some(@admitted.Number(n)) &&
            n == (1 + column + branch * 8 + leaf).to_double(),
          )
        }
      }
    }
    return
  }
  if workload == DecimalTemporal {
    assert_eq(count, 1000)
    // Repeated numeric keys compare in authored tuple order, not CID order.
    let groups = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
    for row = 0; row < rows; row = row + 1 {
      let id = groups[row] * 4 + 1
      assert_true(
        IndexedRows::read_cell(table, row, 0) is Number(n) &&
        n == id.to_double(),
      )
      assert_true(
        IndexedRows::read_cell(table, row, 1) is Number(n) &&
        n == groups[row].to_double(),
      )
      guard IndexedRows::read_cell(table, row, 2)
        is Captured(@admitted.Decimal(d)) else {
        fail("decimal payload")
      }
      assert_eq(d.coefficient, "1234567890123456789012345678901234501")
      assert_eq(d.precision, 38)
      assert_eq(d.scale, 2)
      assert_true(
        IndexedRows::read_cell(table, row, 3) is Captured(@admitted.Date(s)) &&
        s == layout_temporal_cell(id, 3),
      )
      assert_true(
        IndexedRows::read_cell(table, row, 4)
        is Captured(@admitted.Timestamp(s)) &&
        s == layout_temporal_cell(id, 4),
      )
      for column = 5; column < 8; column = column + 1 {
        assert_true(
          IndexedRows::read_cell(table, row, column) is Number(n) &&
          n == (id + column).to_double(),
        )
      }
    }
    return
  }
  if workload == ShortText || workload == LongText {
    let payload = layout_text_payload(workload)
    assert_eq(payload.length(), if workload == ShortText { 8 } else { 1024 })
    for row = 0; row < rows; row = row + 1 {
      assert_true(
        IndexedRows::read_cell(table, row, 0) is Number(n) &&
        n == row.to_double(),
      )
      assert_true(
        IndexedRows::read_cell(table, row, 1) is Text(s) && s == payload,
      )
    }
    return
  }
  // Closed-form source values and survivors; no tested comparator or sort
  // output is used to generate the expectations.
  for row = 0; row < rows; row = row + 1 {
    let id = row + 1
    for column = 0; column < names.length(); column = column + 1 {
      if workload == NullableProjection && column != 0 {
        let missing = (id + 2) % 3 == 0
        let value = IndexedRows::read_cell(table, row, column)
        if column == 1 {
          assert_true(value is Boolean(b) && b == !missing)
        } else if missing {
          assert_true(value is Null)
        } else {
          assert_true(value is Number(n) && n == (id + 2).to_double())
        }
        continue
      }
      let expected = if offsets[column] == -1 {
        (id - 1) / 4
      } else {
        id + offsets[column]
      }
      assert_true(
        IndexedRows::read_cell(table, row, column) is Number(n) &&
        n == expected.to_double(),
      )
    }
  }
}

///|
test "fixed numeric workload shapes share source and contracts across all layouts" {
  let count = 1000
  for
    workload in [
      NarrowProjection,
      NullableProjection,
      FullWidthAddition,
      LowSelectivity,
      HighSelectivity,
      ShortText,
      LongText,
      DecimalTemporal,
      NestedSmallResult,
      ZeroColumns,
    ] {
    let (generated, input) = numeric_layout_fixture(workload, count)
    let rows = execute_generated_sequence(generated, [input], {
      rows: numeric_layout_limits(count),
      max_work: 100000000,
      max_frames: 100,
    }).unwrap()
    let slot = @lower.sequence_count(generated.sequence)
    verify_numeric_layout_output(
      test_row_store(rows).tables[slot].unwrap().table,
      workload,
      count,
    )
    for candidate in [ValueColumns, TypedColumns] {
      let ledger = layout_ledger(100000000, 100000000, 100000000)
      let physical = {
        ..layout_allocation(100000000, 100000000, 100000000),
        ledger: Some(ledger),
      }
      let source = retain_layout_capture(input, ledger).unwrap()
      let control = { remaining: 100000000, max_frames: 100, }
      let limits = numeric_layout_limits(count)
      let invocation = prepare_sequence_with_importers(
        generated.contracts,
        generated.sequence,
        [input],
        generated.retained_ids,
        limits,
        control,
        fn(captured) {
          if !physical_equal(captured, input) {
            return Err(InvalidRows)
          }
          import_layout_capture_columns(source, candidate, physical)
        },
        fn(_bound, _id, _output) { Err(InvalidRows) },
        release_table=fn(table : LayoutRelation) {
          release_layout_columns(table.storage)
        },
        produced=[],
        fragments=Some(generated.contexts),
        ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
      ).unwrap()
      run_sequence_with_backend(
        invocation,
        fn(_captured) { Err(InvalidRows) },
        fn(kernel, table, logical) {
          evaluate_layout_kernel(
            kernel,
            table,
            count,
            control,
            invocation.output_budget,
            { limit: limits.operation_entries, live: 0, peak: 0, },
            physical,
            logical,
          )
        },
      ).unwrap()
      verify_numeric_layout_output(
        invocation.store.tables[slot].unwrap().table,
        workload,
        count,
      )
      if workload == NestedSmallResult {
        let storage = invocation.store.tables[slot].unwrap().table.storage
        assert_eq(storage.count, 1)
        guard storage.body is OwnedColumnArrays(columns) else {
          fail("owned nested columns")
        }
        // One survivor still retains full backing columns, not one physical row.
        for column = 2; column < 8; column = column + 1 {
          guard columns[column].value is Some(Generic(buffer)) else {
            fail("nested generic backing")
          }
          assert_eq(buffer.length(), count)
        }
      }
      if workload == NullableProjection {
        let storage = invocation.store.tables[slot].unwrap().table.storage
        guard storage.body is OwnedColumnArrays(columns) else {
          fail("owned columns")
        }
        if candidate == TypedColumns {
          assert_true(columns[0].value is Some(Numeric(_, _)))
          assert_true(columns[1].value is Some(Flags(_, _)))
          assert_true(columns[2].value is Some(Numeric(_, _)))
        } else {
          for column in columns {
            assert_true(column.value is Some(Generic(_)))
          }
        }
      }
      clear_table_store(invocation.store)
      release_owned_layout_buffer(ledger, source).unwrap()
      assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
    }
  }
}
