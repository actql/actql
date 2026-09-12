///|
fn layout_producer_case(
  count : Int,
) -> (GeneratedSequence, BoundProducerInput) raise {
  let (source, input) = numeric_layout_fixture(
    NarrowProjection,
    count,
    producer_seed=true,
  )
  let completed = execute_generated_sequence(source, [input], {
    rows: numeric_layout_limits(count),
    max_work: 100000000,
    max_frames: 100,
  }).unwrap()
  let owner = @lower.sequence_owner(source.sequence)
  let output = completed_output(completed, Step(0)).unwrap()
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(owner)),
    @pipeline.Step(0),
  ).unwrap()
  let receiver = sort_input_owner(
    @pipeline.ProducedInput(producer),
    "[{\"select\":[\"id\",\"p2\"],\"as\":\"narrow\"},{\"derive\":{\"next\":\"p2 + 1\"},\"from\":\"seed\",\"as\":\"wide\"}]",
  )
  let sequence = @lower.prepare_sequence(receiver, {
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
  let pipeline = @lower.prepare_fragment_pipeline(sequence, 1, {
    max_roots: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
  }).unwrap()
  let request = @lower.prepare_fragment_request(
    pipeline,
    count.to_int64(),
    100000L,
  ).unwrap()
  let context = prepare_runtime_fragment(
    request,
    test_fragment_contract(),
    material_demands(),
    registry_limits(),
    {
      max_input_rows: count.to_int64(),
      max_value_bytes: 100000L,
      max_live_value_bytes: 10000000L,
      max_work: 100000000L,
    },
  ).unwrap()
  let retained = Array::makei(2, step => {
    @lower.node_id(
      @lower.node_at(@lower.bound_preparation(receiver), step).unwrap(),
    )
  })
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [context],
    retained,
    100000,
    10000,
  ).unwrap()
  (generated, bind_completed_input(receiver, 0, owner, output).unwrap())
}

///|
fn[T : RelationRows] verify_layout_producer_case(
  narrow : T,
  wide : T,
  count : Int,
) -> Unit raise {
  assert_eq(narrow.field_names(), ["id", "p2"])
  assert_eq(IndexedRows::row_count(narrow), count)
  assert_eq(IndexedRows::row_count(wide), count)
  let names = ["id", "k"]
  let offsets = [0, -1]
  // Independent canonical source-name order, resolved once before observation.
  for leading in 1..<10 {
    if leading >= 2 {
      names.push("p" + leading.to_string())
      offsets.push(leading)
    }
    for trailing in 0..<10 {
      let j = leading * 10 + trailing
      if j < 64 {
        names.push("p" + j.to_string())
        offsets.push(j)
      }
    }
  }
  names.push("next")
  offsets.push(3)
  assert_eq(wide.field_names(), names)
  for row = 0; row < count; row = row + 1 {
    let id = count - row
    assert_true(
      IndexedRows::read_cell(narrow, row, 0) is Number(n) && n == id.to_double(),
    )
    assert_true(
      IndexedRows::read_cell(narrow, row, 1) is Number(n) &&
      n == (id + 2).to_double(),
    )
    for column = 0; column < 65; column = column + 1 {
      let expected = if offsets[column] == -1 {
        (id - 1) / 4
      } else {
        id + offsets[column]
      }
      assert_true(
        IndexedRows::read_cell(wide, row, column) is Number(n) &&
        n == expected.to_double(),
      )
    }
  }
}

///|
test "fixed producer workload retains both narrow and full width branches" {
  let count = 1000
  let (generated, bound) = layout_producer_case(count)
  let limits = numeric_layout_limits(count)
  let completed = execute_generated_sequence(
    generated,
    [],
    { rows: limits, max_work: 100000000, max_frames: 100, },
    produced=[bound],
  ).unwrap()
  verify_layout_producer_case(
    completed_output(completed, Step(0)).unwrap().table,
    completed_output(completed, Step(1)).unwrap().table,
    count,
  )
  for candidate in [ValueColumns, TypedColumns] {
    let ledger = layout_ledger(100000000, 100000000, 100000000)
    let physical = {
      ..layout_allocation(100000000, 100000000, 100000000),
      ledger: Some(ledger),
    }
    let control = { remaining: 100000000, max_frames: 100, }
    let invocation = prepare_sequence_with_importers(
      generated.contracts,
      generated.sequence,
      [],
      generated.retained_ids,
      limits,
      control,
      fn(_captured) { Err(InvalidRows) },
      fn(produced, id, output) {
        import_layout_producer(
          produced, id, candidate, limits, control, output, physical,
        )
      },
      release_table=fn(table : LayoutRelation) {
        release_layout_columns(table.storage)
      },
      produced=[bound],
      fragments=Some(generated.contexts),
      ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
    ).unwrap()
    run_sequence_with_backend(invocation, fn(_captured) { Err(InvalidRows) }, fn(
      kernel,
      input,
      logical,
    ) {
      evaluate_layout_kernel(
        kernel,
        input,
        count,
        control,
        invocation.output_budget,
        { limit: limits.operation_entries, live: 0, peak: 0, },
        physical,
        logical,
      )
    }).unwrap()
    assert_true(invocation.store.tables[0] is None)
    verify_layout_producer_case(
      invocation.store.tables[1].unwrap().table,
      invocation.store.tables[2].unwrap().table,
      count,
    )
    clear_table_store(invocation.store)
    assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
    // Output cleanup must not invalidate the independently owned producer result.
    assert_eq(bound.output.table.rows.length(), count)
    assert_true(bound.output.table.rows[0][0] is Number(1000))
  }
}
