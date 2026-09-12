///|
// Shapes fixed in columnar-experiment.json. These are workload fixtures, not
// alternative semantic rules or a backend-specific source program.
priv enum NumericLayoutWorkload {
  NarrowProjection
  NullableProjection
  FullWidthAddition
  LowSelectivity
  HighSelectivity
} derive(Eq)

///|
fn numeric_layout_fixture(
  workload : NumericLayoutWorkload,
  count : Int,
) -> (GeneratedSequence, CapturedRows) raise {
  let width = 64
  let nullable = workload == NullableProjection
  let raw = Array::makei(count, i => {
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
        (if nullable {
          nullable_layout_cell(id, j)
        } else {
          (id + j).to_string()
        })
    }
    input_cursor(text + "}")
  })
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
  let fields = [
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
  for j = 2; j < width; j = j + 1 {
    fields.push(
      (
        @schema.Unqualified("p" + j.to_string()),
        if !nullable {
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
  let key = @evidence.declare_primary_key(
    input_cursor("[\"id\"]"),
    @carrier.relation(@carrier.typed_rows(schema)),
    { max_fields: width, max_name_bytes: 10000, },
  ).unwrap()
  let (program, expression_steps) = match workload {
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
  let owner = sort_input_owner(@pipeline.KeyedInput(key), program)
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
    let ordered = if nullable && step == 1 {
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
    contexts.push(
      prepare_runtime_fragment(
        request,
        test_fragment_contract(),
        material_demands(),
        registry_limits(),
        logical,
        ordered~,
      ).unwrap(),
    )
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
  let input = capture_input(
    owner,
    0,
    raw,
    max_rows=count,
    numeric_layout_limits(count).input_values,
  ).unwrap()
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
fn[T : RelationRows] verify_numeric_layout_output(
  table : T,
  workload : NumericLayoutWorkload,
  count : Int,
) -> Unit raise {
  let rows = match workload {
    NarrowProjection | NullableProjection | FullWidthAddition => 10
    LowSelectivity => count / 100
    HighSelectivity => count * 99 / 100
  }
  let (names, offsets) = match workload {
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
  }
  assert_eq(IndexedRows::row_count(table), rows)
  assert_eq(table.field_names(), names)
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
    ] {
    let (generated, input) = numeric_layout_fixture(workload, count)
    let rows = execute_generated_sequence(generated, [input], {
      rows: numeric_layout_limits(count),
      max_work: 100000000,
      max_frames: 100,
    }).unwrap()
    let slot = @lower.sequence_count(generated.sequence)
    verify_numeric_layout_output(
      rows.store.tables[slot].unwrap().table,
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
