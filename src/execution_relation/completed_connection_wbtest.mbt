///|
// Only kernel/storage selection is experimental. Admission, the operation
// driver, final success construction and downstream execution are production.
fn test_typed_completion(
  generated : GeneratedSequence,
  width : Int,
) -> CompletedSequence {
  try_typed_completion(generated, width, run_limits()).unwrap()
}

///|
fn try_typed_completion(
  generated : GeneratedSequence,
  width : Int,
  limits : SequenceRunLimits,
  mutate_original? : Bool = false,
) -> Result[CompletedSequence, SequenceRunIssue] {
  let control = { remaining: 1000000, max_frames: 100, }
  let invocation = match
    prepare_physical_sequence(
      generated.contracts,
      generated.sequence,
      [],
      generated.retained_ids,
      limits,
      control,
      [],
      Some(generated.contexts),
      { contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
    ) {
    Ok(invocation) => invocation
    Err(issue) => return Err(issue)
  }
  run_completed_sequence_backend(
    invocation,
    captured => {
      table_from_capture_bounded(captured, control, {
        limit: limits.operation_entries,
        live: 0,
        peak: 0,
      }).map(table => RowTable(table))
    },
    fn(kernel, input, logical) {
      if @relation.operation(@lower.kernel_checked(kernel)) != Derive {
        return evaluate_completed_rows(
          kernel,
          input,
          limits.max_rows,
          control,
          invocation.output_budget,
          { limit: limits.operation_entries, live: 0, peak: 0, },
          logical,
        )
      }
      guard input is RowTable(table) else { return Err(InvalidRows) }
      let slots = { limit: limits.operation_entries, live: 0, peak: 0, }
      let plan = match ext_prepare_batch(kernel, control, slots) {
        Ok(Some(plan)) => plan
        Ok(None) => return Err(InvalidRows)
        Err(e) => return Err(e)
      }
      guard logical is Some(logical) else {
        return Err(MissingOrderedResourceContext)
      }
      let ledger : LayoutLedger = {
        slots,
        bytes: { limit: 1000000, live: 0, peak: 0, },
        work: control,
        traffic: None,
      }
      let source : LayoutRelation = {
        candidate: RowLayout,
        owner: table.owner,
        id: table.id,
        names: table.names,
        storage: {
          body: RowArrays(table.rows),
          width: table.names.length(),
          count: table.rows.length(),
          selection: None,
          owned_selection: None,
        },
      }
      let physical : LayoutAllocation = {
        slots,
        bytes: ledger.bytes,
        work: control,
        ledger: Some(ledger),
      }
      let result = match
        ext_run_batch(
          plan,
          source,
          width,
          logical,
          physical,
          { chunks: 0, selected: 0, rejected: 0, },
          output_values=invocation.output_budget,
        ) {
        Err(e) => return Err(e)
        Ok(storage) => storage
      }
      let seal = fn() -> Result[CompletedTable, RowIssue] {
        guard result.body is OwnedColumnArrays(buffers) else {
          return Err(InvalidRows)
        }
        if !reserve_slots(slots, buffers.length()) ||
          !reserve_slots(slots, plan.names.length()) ||
          !spend_control(control, plan.names.length()) {
          return Err(RowLimit)
        }
        let columns : Array[CompletedNumberColumn] = []
        for buffer in buffers {
          guard buffer.value is Some(Numeric(values, valid)) else {
            return Err(InvalidRows)
          }
          // Seal by copying typed buffers, while the original leases remain
          // retained and charged. No Array[Value] row matrix is constructed.
          if !reserve_slots(slots, values.length()) ||
            !reserve_slots(slots, valid.length()) ||
            !spend_control(control, values.length()) ||
            !spend_control(control, valid.length()) {
            return Err(RowLimit)
          }
          columns.push({
            values: FixedArray::makei(values.length(), i => values[i]),
            valid: FixedArray::makei(valid.length(), i => valid[i]),
          })
        }
        let node = @lower.node_at(
          @lower.bound_preparation(table.owner),
          @lower.kernel_step(kernel),
        ).unwrap()
        Ok(
          NumberTable({
            owner: table.owner,
            id: @lower.node_id(node),
            names: plan.names.copy(),
            columns,
            count: result.count,
            selection: None,
          }),
        )
      }
      let copied = seal()
      if mutate_original && copied is Ok(_) {
        // Adversarial whitebox mutation of the original input and transient
        // builder buffers after sealing. Neither is a public completion API.
        if table.rows.length() > 0 && table.names.length() > 0 {
          table.rows[0][0] = Number(999)
        }
        if result.body is OwnedColumnArrays(buffers) {
          for buffer in buffers {
            if buffer.value is Some(Numeric(values, valid)) &&
              values.length() > 0 {
              values[0] = 999
              valid[0] = 0
            }
          }
        }
      }
      release_layout_columns(result)
      copied
    },
    store => PhysicalStore(store),
  )
}

///|
test "typed derive crosses product completion binding projection sort and completion" {
  let owner = row_owner(",{\"derive\":[{\"a\":\"a + 1\"}]}")
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [ordered_sequence_fragment_context(sequence, 1000L)],
    ["derive_1"],
    100000,
    10000,
  ).unwrap()
  let receiver_pipeline = @pipeline.check_with_evidence(
    input_cursor("[{\"select\":[\"a\"]},{\"sort\":[{\"a\":\"asc\"}]}]"),
    [
      (
        "prior",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(owner)),
            Step(1),
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(input_cursor("\"prior\"")),
    {
      max_steps: 100,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let receiver = @lower.bind_parameters(
    @lower.prepare(receiver_pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let consumer = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["select_0", "sort_1"],
    100000,
    10000,
  ).unwrap()
  for width in [1, 7, 1000] {
    let producer = test_typed_completion(generated, width)
    let source = completed_output(producer, Step(1)).unwrap()
    assert_true(source.table is NumberTable(_))
    let bound = bind_completed_input(receiver, 0, owner, source).unwrap()
    let rebound = @lower.bind_parameters(
      @lower.bound_preparation(owner),
      None,
      max_parameters=0,
      max_name_bytes=0,
    ).unwrap()
    assert_true(
      bind_completed_input(receiver, 0, rebound, source)
      is Err(ProducerBindingMismatch),
    )
    assert_true(
      execute_generated_sequence(
        consumer,
        [],
        { rows: run_limits(), max_work: 0, max_frames: 100, },
        produced=[bound],
      )
      is Err(_),
    )
    // A failed consumer has no completion handle; it cannot poison the
    // successful producer or spend a later consumer's fresh counters.
    assert_true(completed_cell(source, 0, 0) is Some(Number(2)))
    let completion = execute_generated_sequence(
      consumer,
      [],
      { rows: run_limits(), max_work: 100000, max_frames: 100, },
      produced=[bound],
    ).unwrap()
    assert_true(completion.store is PhysicalStore(_))
    let selected = completed_output(completion, Step(0)).unwrap()
    let sorted = completed_output(completion, Step(1)).unwrap()
    assert_true(selected.table is NumberTable(_))
    assert_true(sorted.table is NumberTable(_))
    guard selected.table is NumberTable(selected_buffers) else {
      fail("typed projection")
    }
    guard sorted.table is NumberTable(sorted_buffers) else {
      fail("typed sort")
    }
    assert_true(
      physical_equal(
        selected_buffers.columns[0].values,
        sorted_buffers.columns[0].values,
      ),
    )
    let second = execute_generated_sequence(
      consumer,
      [],
      { rows: run_limits(), max_work: 100000, max_frames: 100, },
      produced=[bound],
    ).unwrap()
    assert_true(
      completed_cell(completed_output(second, Step(1)).unwrap(), 0, 0)
      is Some(Number(1)),
    )
    assert_eq(completed_row_count(sorted), 2)
    assert_eq(completed_column_count(sorted), 1)
    assert_eq(completed_column_name(sorted, 0), Some("a"))
    assert_true(completed_cell(selected, 0, 0) is Some(Number(2)))
    assert_true(completed_cell(sorted, 0, 0) is Some(Number(1)))
    assert_true(completed_cell(sorted, 1, 0) is Some(Number(2)))
    assert_true(completed_cell(source, 0, 0) is Some(Number(2)))
    assert_true(completed_cell(sorted, -1, 0) is None)
    assert_true(completed_cell(sorted, 2, 0) is None)
    assert_true(completed_cell(sorted, 0, 1) is None)
  }
}
