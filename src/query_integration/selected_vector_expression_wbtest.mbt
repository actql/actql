///|
test "registered VecA provider runs selected scalar steps at their original coordinates" {
  for prefix in [false, true] {
    let source = direct_vector_expression_source_owner()
    let owner = direct_vector_expression_owner(source, prefix~)
    let source_output = direct_nearest_relation_output(source)
    let original_read = direct_vector_expression_read(
      owner, source, source_output,
    )
    let whole = task_test_generated(owner)
    let limits = dispatch_test_limits()
    let step = if prefix { 1 } else { 0 }
    let input = if prefix {
      let selected = @execution.select_generated_sequence_step(whole, 0).unwrap()
      let active = @execution.start_bounded_binding_rows(
        @bounded.control(),
        selected,
        original_read,
        10,
        limits.local_execution.rows.input_values,
        limits.local_execution.rows.output_values,
        limits.local_execution.max_work,
        limits.local_execution.max_frames,
        limits.local_execution.rows.operation_entries,
        1000,
      ).unwrap()
      let mut completed = None
      for _ in 0..<1000 {
        if completed is Some(_) {
          break
        }
        match @execution.advance_bounded_binding_rows(active, 1).unwrap() {
          @execution.BoundedBindingRowsComplete(output, ..) =>
            completed = Some(output)
          @execution.BoundedBindingRowsContinue(..) => ()
          _ => fail("the original projection prefix did not complete")
        }
      }
      let output = completed.unwrap()
      assert_true(@execution.cleanup_bounded_binding_rows(active).unwrap())
      @execution.prepare_producer_read(
        owner,
        @execution.bind_completed_operation_input(owner, step, 0, owner, output).unwrap(),
        1000,
        10000,
      ).unwrap()
    } else {
      original_read
    }
    assert_true(
      @execution.producer_read_matches_operation_input(input, owner, step, 0),
    )
    let selected = @execution.select_generated_sequence_step(whole, step).unwrap()
    let provider = @local_veca_provider.provider(
      carrier_vectors_storage_limits(),
      4096L,
      @execution.generated_sequence_capacity(
        selected,
        limits.local_execution,
        limits.guards,
      ).unwrap(),
    )
    let active = @local_connector.start_managed_provider_with_execution(
      provider,
      selected,
      [input],
      10,
      1000,
      limits.local_execution,
    ).unwrap()
    let mut completed = None
    for _ in 0..<1000 {
      if completed is Some(_) {
        break
      }
      match @local_connector.advance_managed_provider(active, 1).unwrap() {
        @local_connector.Complete(output, work~, ..) => {
          assert_true(work <= 1L)
          completed = Some(output)
        }
        @local_connector.Continue(work~, ..) => assert_true(work <= 1L)
        _ => fail("the selected scalar expression did not complete")
      }
    }
    let output = completed.unwrap()
    let schema = @pipeline.schema_at(
      @lower.pipeline(@lower.bound_preparation(owner)),
      @pipeline.Step(step),
    ).unwrap()
    let mut score = -1
    let mut joined = -1
    for column in 0..<@schema.field_count(schema) {
      let name = @schema.reference_name(
        @schema.field_at(schema, column).unwrap().name,
      )
      if name == "score" {
        score = column
      }
      if name == "joined" {
        joined = column
      }
    }
    assert_eq(@execution.completed_row_count(output), 2)
    assert_true(
      @execution.completed_cell(output, 0, score) is Some(Number(11.0)),
    )
    assert_true(
      @execution.completed_cell(output, 1, score) is Some(Number(11.0)),
    )
    assert_true(
      @execution.completed_cell(output, 0, joined)
      is Some(Captured(@admitted.Vector(value))) &&
      @admitted.element_count(value) == 4,
    )
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
    assert_true(@execution.completed_output_available(source_output))
    let cancelled = @local_connector.start_managed_provider_with_execution(
      provider,
      selected,
      [input],
      10,
      1000,
      limits.local_execution,
    ).unwrap()
    assert_true(
      @local_connector.advance_managed_provider(cancelled, 1).unwrap()
      is @local_connector.Continue(..),
    )
    assert_true(@local_connector.cancel_managed_provider(cancelled))
    assert_true(
      @local_connector.advance_managed_provider(cancelled, 1).unwrap()
      is @local_connector.Stopped(..),
    )
    assert_true(@local_connector.cleanup_managed_provider(cancelled).unwrap())
    if prefix {
      let wrong_port = @local_connector.start_managed_provider_with_execution(
        provider,
        selected,
        [original_read],
        10,
        1000,
        limits.local_execution,
      ).unwrap()
      assert_true(
        @local_connector.advance_managed_provider(wrong_port, 1).unwrap()
        is @local_connector.Failed(_, ..),
      )
      assert_true(
        @local_connector.cleanup_managed_provider(wrong_port).unwrap(),
      )
    }
  }
}
