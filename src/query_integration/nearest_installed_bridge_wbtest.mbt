///|
// Independent component control for the original installed declaration. This
// does not replay a public Run or use observed product values as expectations.
test "selected nearest bridge retains original f32 string key and nullable payload" {
  let limits = {
    max_steps: 10,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_depth: 100,
  }
  let source = direct_nearest_bind(
    @pipeline.check(
      input_cursor(
        "[{\"values\":{\"schema\":{\"embedding\":{\"type\":\"vector\",\"element_type\":\"f32\",\"dimensions\":2,\"nullable\":false},\"note\":{\"type\":\"string\",\"nullable\":true},\"request_id\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"embedding\":[1,0],\"note\":null,\"request_id\":\"q1\"}]},\"as\":\"rows\"}]",
      ),
      [], None, None, limits,
    ).unwrap(),
  )
  let owner = direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"from\":\"rows\",\"select\":[\"embedding\",\"note\",\"request_id\"],\"as\":\"selected\"},{\"from\":\"selected\",\"to_vectors\":{\"id\":\"request_id\",\"vector\":\"embedding\"}}]",
      ),
      [("rows", @pipeline.ProducedInput(@pipeline.produced_input(
        @lower.pipeline(@lower.bound_preparation(source)), @pipeline.Step(0),
      ).unwrap()))],
      None, None, limits,
    ).unwrap(),
  )
  let source_output = direct_nearest_relation_output(source)
  let read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source, source_output).unwrap(),
    1000, 10000,
  ).unwrap()
  let generated = task_test_generated(owner)
  let dispatch = dispatch_test_limits()
  let selected = @execution.select_generated_sequence_step(generated, 0).unwrap()
  let selection = @execution.start_bounded_binding_rows(
    @bounded.control(), selected, read, 10,
    dispatch.local_execution.rows.input_values,
    dispatch.local_execution.rows.output_values,
    dispatch.local_execution.max_work,
    dispatch.local_execution.max_frames,
    dispatch.local_execution.rows.operation_entries, 1000,
  ).unwrap()
  let mut selected_output = None
  for _ in 0..<1000 {
    if selected_output is Some(_) { break }
    match @execution.advance_bounded_binding_rows(selection, 1).unwrap() {
      @execution.BoundedBindingRowsContinue(..) => ()
      @execution.BoundedBindingRowsComplete(output, ..) => selected_output = Some(output)
      @execution.BoundedBindingRowsFailed(issue, ..) => raise issue
      _ => fail("original selected projection did not complete")
    }
  }
  let selected_output = selected_output.unwrap()
  assert_eq(@execution.completed_row_count(selected_output), 1)
  assert_true(@execution.cleanup_bounded_binding_rows(selection).unwrap())
  let selected_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_operation_input(owner, 1, 0, owner, selected_output).unwrap(),
    1000, 10000,
  ).unwrap()
  let bridge = @execution.select_generated_sequence_step(generated, 1).unwrap()
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(), 4096L,
    @execution.generated_sequence_capacity(bridge, dispatch.local_execution, dispatch.guards).unwrap(),
  )
  let active = @local_connector.start_managed_provider_with_execution(
    provider, bridge, [selected_read], 10, 1000, dispatch.local_execution,
  ).unwrap()
  let mut material = None
  for _ in 0..<1000 {
    if material is Some(_) { break }
    match @local_connector.advance_managed_provider(active, 1).unwrap() {
      @local_connector.Continue(..) => ()
      @local_connector.CarrierComplete(output, ..) => material = Some(output)
      @local_connector.Failed(issue, ..) => raise issue
      _ => fail("original selected rows-to-vectors bridge did not complete")
    }
  }
  let material = material.unwrap()
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_true(@execution.completed_output_available(source_output))
  assert_true(@carrier_runtime.reclaim_material(material))
}
