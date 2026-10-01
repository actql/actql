///|
/// Observation only: expected semantics are computed outside MoonBit from the
/// restricted specification domain. This helper never constructs expected rows.
fn relation_pipeline_columns(output : @execution.CompletedOutput) -> String {
  let names = Array::makei(@execution.completed_column_count(output), i => {
    query_oracle_quote(@execution.completed_column_name(output, i).unwrap())
  })
  "[" + names.join(",") + "]"
}

///|
fn relation_pipeline_rows(output : @execution.CompletedOutput) -> String {
  let rows = []
  for row in 0..<@execution.completed_row_count(output) {
    let cells = []
    for column in 0..<@execution.completed_column_count(output) {
      cells.push(
        match @execution.completed_cell(output, row, column) {
          Some(Number(n)) => n.to_string()
          Some(Null) => "null"
          _ => abort("pipeline observation outside numeric/null domain")
        },
      )
    }
    rows.push("[" + cells.join(",") + "]")
  }
  "[" + rows.join(",") + "]"
}

///|
fn relation_pipeline_projection(
  sequence : @execution.GeneratedSequence,
  output : @execution.CompletedOutput,
) -> String {
  match
    @execution.generated_sequence_step_at(
      sequence,
      @execution.generated_sequence_step_count(sequence) - 1,
    ) {
    Some(@lower.RowStep(kernel)) =>
      match @lower.kernel_body(kernel) {
        @lower.Select(fields) =>
          "[" +
          fields
          .map(field => query_oracle_quote(@schema.reference_name(field.output)))
          .join(",") +
          "]"
        _ => relation_pipeline_columns(output)
      }
    _ => relation_pipeline_columns(output)
  }
}

///|
fn relation_pipeline_wire(output : @execution.CompletedOutput) -> String {
  let rows = Array::makei(@execution.completed_row_count(output), row => {
    @execution.completed_output_row_wire(output, row, 10000, 1000, 10).unwrap()
  })
  "[" + rows.join(",") + "]"
}

///|
fn relation_pipeline_schema(schema : @schema.Schema) -> String {
  @execution.relation_schema_wire(
    @execution.identify_relation_schema(schema, {
      max_fields: 100,
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 10,
    }).unwrap(),
  )
}

///|
/// Observe the checked pipeline and selected kernels from the SAME sequence
/// supplied to the registered provider, not a separately checked request.
fn relation_pipeline_contracts(
  sequence : @execution.GeneratedSequence,
) -> String {
  let pipeline = @lower.pipeline(
    @lower.bound_preparation(@execution.generated_sequence_owner(sequence)),
  )
  let contracts = []
  for index in 0..<@execution.generated_sequence_step_count(sequence) {
    let kernel = match @execution.generated_sequence_step_at(sequence, index) {
      Some(@lower.RowStep(kernel)) => kernel
      _ => abort("pipeline evidence requires a selected row kernel")
    }
    let (route, projection) = match @lower.kernel_body(kernel) {
      @lower.Filter(_) => ("Filter", "null")
      @lower.Select(fields) =>
        (
          "Select",
          "[" +
          fields
          .map(field => {
            "{\"input\":" +
            query_oracle_quote(@schema.reference_name(field.input)) +
            ",\"output\":" +
            query_oracle_quote(@schema.reference_name(field.output)) +
            "}"
          })
          .join(",") +
          "]",
        )
      @lower.StableSort(_) => ("StableSort", "null")
      @lower.Limit(_, _, _) => ("Limit", "null")
      @lower.DistinctRows => ("DistinctRows", "null")
      _ => abort("unreviewed pipeline kernel")
    }
    contracts.push(
      "{\"index\":" +
      index.to_string() +
      ",\"route\":" +
      query_oracle_quote(route) +
      ",\"checked\":" +
      relation_pipeline_schema(
        @pipeline.schema_at(pipeline, Step(index)).unwrap(),
      ) +
      ",\"kernel\":" +
      relation_pipeline_schema(@lower.kernel_output_schema(kernel)) +
      ",\"projection\":" +
      projection +
      "}",
    )
  }
  "[" + contracts.join(",") + "]"
}

///|
fn relation_pipeline_provider(
  sequence : @execution.GeneratedSequence,
) -> @local_connector.ManagedProvider {
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let implementation = @local_connector.prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [sequence],
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
    1,
  ).unwrap()
  @local_connector.local_module_managed_provider(implementation, sequence).unwrap()
}

///|
fn relation_pipeline_start(
  sequence : @execution.GeneratedSequence,
  reads : Array[@execution.ProducerRead],
) -> @local_connector.ManagedProviderExecution {
  @local_connector.start_managed_provider_with_execution(
    relation_pipeline_provider(sequence),
    sequence,
    reads,
    100,
    10000,
    compute_test_limits(),
  ).unwrap()
}

///|
/// Correspondence of the ACTUAL selected_binding_rows_execution delta adapter
/// with the cumulative kernel it invokes. This is not the semantic oracle.
fn relation_pipeline_child_reference(
  sequence : @execution.GeneratedSequence,
  first : @execution.ProducerRead,
) -> (Int64, Int, Int, String) raise {
  let owner = @execution.generated_sequence_owner(sequence)
  let children = []
  let mut previous = None
  let mut total = 0L
  let mut cancel_confirmed = 0
  let mut already_terminal = 0
  let stage_values = []
  for index in 0..<@execution.generated_sequence_step_count(sequence) {
    let selected = @execution.select_generated_sequence_step(
      sequence,
      @execution.generated_sequence_step_index_at(sequence, index).unwrap(),
    ).unwrap()
    let reads = if index == 0 {
      [first]
    } else {
      chain_evidence_inputs(sequence, index, previous)
    }
    let read = reads[0]
    let active = relation_pipeline_start(selected, reads)
    children.push(active)
    let limits = compute_test_limits()
    let control = @bounded.control()
    let kernel = @execution.start_bounded_binding_rows(
      control,
      selected,
      read,
      100,
      limits.rows.input_values,
      limits.rows.output_values,
      limits.max_work,
      limits.max_frames,
      limits.rows.operation_entries,
      10000,
    ).unwrap()
    let mut work = 0L
    let mut progress = 0L
    let mut done = false
    for _poll in 0..<100000 {
      if !done {
        let poll = @local_connector.advance_managed_provider(active, 1).unwrap()
        let expected = @execution.advance_bounded_binding_rows(kernel, 1).unwrap()
        match (poll, expected) {
          (
            @local_connector.Continue(progress=p, work=w),
            @execution.BoundedBindingRowsContinue(progress=kp, work=kw),
          ) => {
            assert_true(w >= 0L && w <= 1L)
            work += w
            progress += p
            assert_eq((progress, work), (kp, kw))
          }
          (
            @local_connector.Complete(output, progress=p, work=w),
            @execution.BoundedBindingRowsComplete(_, progress=kp, work=kw),
          ) => {
            work += w
            progress += p
            assert_eq((progress, work), (kp, kw))
            previous = Some(output)
            stage_values.push(
              "{\"columns\":" +
              relation_pipeline_projection(selected, output) +
              ",\"schemaColumns\":" +
              relation_pipeline_columns(output) +
              ",\"tableRows\":" +
              relation_pipeline_rows(output) +
              ",\"wireRows\":" +
              relation_pipeline_wire(output) +
              "}",
            )
            done = true
          }
          _ => fail("selected adapter differs from its cumulative kernel")
        }
      }
    }
    assert_true(done)
    assert_true(@execution.cleanup_bounded_binding_rows(kernel).unwrap())
    assert_true(@local_connector.advance_managed_provider(active, 1) is Err(_))
    total += work
    // Real child + selected adapter cancellation after an actual poll. Empty
    // input may already complete: seal that terminal, without inventing work.
    let cancelled = relation_pipeline_start(selected, reads)
    match @local_connector.advance_managed_provider(cancelled, 1).unwrap() {
      @local_connector.Continue(work=w, ..) => {
        assert_true(w >= 0L && w <= 1L)
        assert_true(@local_connector.cancel_managed_provider(cancelled))
        assert_true(
          @local_connector.advance_managed_provider(cancelled, 1).unwrap()
          is @local_connector.Stopped(progress=0L, work=0L),
        )
        cancel_confirmed += 1
      }
      @local_connector.Complete(_, ..) => already_terminal += 1
      _ => fail("cancellation probe failed before cancellation")
    }
    assert_true(@local_connector.managed_provider_stopped(cancelled))
    assert_true(
      @local_connector.advance_managed_provider(cancelled, 1) is Err(_),
    )
    assert_true(@local_connector.cleanup_managed_provider(cancelled).unwrap())
    assert_true(@local_connector.cleanup_managed_provider(cancelled).unwrap())
    // Checked owner/port, not a matching provider label.
    assert_true(
      @execution.producer_read_matches_operation_input(
        read,
        owner,
        @execution.generated_sequence_step_index_at(sequence, index).unwrap(),
        0,
      ),
    )
  }
  for index = children.length() - 1; index >= 0; index = index - 1 {
    assert_true(
      @local_connector.cleanup_managed_provider(children[index]).unwrap(),
    )
    assert_true(
      @local_connector.cleanup_managed_provider(children[index]).unwrap(),
    )
  }
  (
    total + (@execution.generated_sequence_step_count(sequence) - 1).to_int64(),
    cancel_confirmed,
    already_terminal,
    "[" + stage_values.join(",") + "]",
  )
}

///|
fn relation_pipeline_observe(
  id : String,
  source : String,
  steps : String,
  correspondence : Bool,
) -> Unit raise {
  println("ACTQL_PIPELINE_CASE:" + query_oracle_quote(id))
  // Despite the historical fixture name, this constructs a checked Values
  // producer and exact ProducedInput; it invokes no DuckDB evaluator or SQL.
  let input = duckdb_fixed_values(source, steps~)
  let sequence = task_test_generated(@execution.producer_read_receiver(input))
  assert_true(@execution.generated_sequence_step_count(sequence) > 0)
  let pipeline = @lower.pipeline(
    @lower.bound_preparation(@execution.generated_sequence_owner(sequence)),
  )
  let order = @pipeline.logical_order(
    pipeline,
    Step(@execution.generated_sequence_step_count(sequence) - 1),
  ).unwrap()
  assert_true(@pipeline.order_key_completion(order) is None)
  let origin = match @pipeline.order_origin(order) {
    Input(i) => "input:" + i.to_string()
    Step(i) => "step:" + i.to_string()
  }
  let active = relation_pipeline_start(sequence, [input])
  let mut work = 0L
  let mut output = None
  let mut terminal = false
  for _poll in 0..<100000 {
    if !terminal {
      match @local_connector.advance_managed_provider(active, 1).unwrap() {
        @local_connector.Continue(work=w, ..) => {
          assert_true(w >= 0L && w <= 1L)
          work += w
        }
        @local_connector.Complete(value, work=w, ..) => {
          work += w
          output = Some(value)
          terminal = true
        }
        @local_connector.Failed(_, work=w, ..) => {
          work += w
          terminal = true
        }
        _ => fail("success domain unexpectedly stopped")
      }
    }
  }
  assert_true(terminal)
  let (kind, columns, schema_columns, rows, wire) = match output {
    Some(value) =>
      (
        "complete",
        relation_pipeline_projection(sequence, value),
        relation_pipeline_columns(value),
        relation_pipeline_rows(value),
        relation_pipeline_wire(value),
      )
    None => ("failed", "[]", "[]", "[]", "[]")
  }
  let witnesses = if correspondence {
    let (reference, cancelled, already, stage_values) = relation_pipeline_child_reference(
      sequence, input,
    )
    assert_eq(work, reference)
    ",\"referenceWork\":" +
    reference.to_string() +
    ",\"cancelConfirmedChildren\":" +
    cancelled.to_string() +
    ",\"alreadyTerminalChildren\":" +
    already.to_string() +
    ",\"stageValues\":" +
    stage_values
  } else {
    ""
  }
  assert_true(@local_connector.managed_provider_stopped(active))
  assert_true(@local_connector.advance_managed_provider(active, 1) is Err(_))
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  println(
    "ACTQL_PIPELINE:" +
    "{\"id\":" +
    query_oracle_quote(id) +
    ",\"source\":" +
    query_oracle_quote(source) +
    ",\"steps\":" +
    query_oracle_quote(steps) +
    ",\"stepCount\":" +
    @execution.generated_sequence_step_count(sequence).to_string() +
    ",\"contracts\":" +
    relation_pipeline_contracts(sequence) +
    ",\"orderOrigin\":" +
    query_oracle_quote(origin) +
    ",\"checked\":true,\"registered\":true,\"kind\":" +
    query_oracle_quote(kind) +
    ",\"columns\":" +
    columns +
    ",\"rows\":" +
    rows +
    ",\"schemaColumns\":" +
    schema_columns +
    ",\"wireRows\":" +
    wire +
    ",\"work\":" +
    work.to_string() +
    ",\"correspondence\":" +
    correspondence.to_string() +
    witnesses +
    "}",
  )
}
