// Exact physical capture ownership tests. Registered provider fixtures do
// not stand in for Native Source acquisition or public Cloud acceptance.

///|
test "acquired task output refuses an equal capture outside its original Run holding" {
  let original = retained_transfer_run()
  let (input, dispatch, sequence, program, current, codec) = retained_source_setup(
    run=Some(original),
  )
  let releases = Ref(0)
  let capture = fn() {
    let live = Ref(true)
    let physical = register_native_remote_standard_physical_source(
      input.physical,
      () => live.val,
      (max_bytes, emit) => {
        let row = b"{\"id\":3}"
        let mut offset = 0
        while offset < row.length() {
          let count = Int::min(max_bytes, row.length() - offset)
          match
            emit(
              0,
              Bytes::from_array(
                Array::makei(count, index => row[offset + index]),
              ),
            ) {
            Ok(_) => ()
            Err(issue) => return Err(issue)
          }
          offset += count
        }
        Ok(())
      },
      () => {
        releases.val += 1
        live.val = false
        true
      },
    )
    acquire_native_remote_retained_physical_source(
      input,
      physical,
      dispatch,
      codec,
      sequence,
      program,
      retained_source_limits(),
      current,
    ).unwrap()
  }
  let first = capture()
  let second = capture()
  let first_source = native_remote_standard_transfer_captured_source(first)
  let second_source = native_remote_standard_transfer_captured_source(second)
  let run = @publication_host.open_prepared_captured_client_run(
    original.0,
    first_source,
    {
      planning_work: 10000,
      attempts: 10,
      holdings: 10,
      transfer_bytes: 1000000L,
      retained_bytes: 1000000L,
      execution_bytes: 1000000L,
    },
  ).unwrap()
  assert_eq(
    @strategy.graph_result_task(@strategy.captured_dag_graph(run), 0),
    Some(1),
  )
  assert_true(@strategy.captured_task_source_matches(run, 0, first_source))
  // Same checked preparation and equal row bytes are not the same holding.
  assert_true(
    @publication_host.prepared_client_captured_task_source_matches(
      original.0,
      second_source,
      0,
    ),
  )
  assert_false(@strategy.captured_task_source_matches(run, 0, second_source))
  let limits : @publication_host.PublicationOutputExportLimits = {
    max_result_fields: 10,
    max_result_mapping_work: 100,
    max_result_order_work: 100,
    max_result_workspace_entries: 100,
    max_rows: 100,
    values: retained_source_limits().values,
    payload_wire: {
      max_columns: 10,
      max_order_work: 100,
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 20,
    },
    logical_wire: {
      max_columns: 10,
      max_order_work: 100,
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 20,
    },
    schema: {
      max_fields: 10,
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 20,
    },
    max_batch_bytes: 64,
  }
  assert_true(
    @publication_host.prepare_acquired_task_publication_export(
      run, 0, second_source, limits,
    )
    is Err(@publication_host.Output(@execution.ForeignMaterial)),
  )
  for task in [-1, 1] {
    assert_true(
      @publication_host.prepare_acquired_task_publication_export(
        run, task, first_source, limits,
      )
      is Err(@publication_host.Output(@execution.ForeignMaterial)),
    )
  }
  assert_true(
    prepare_native_remote_standard_acquired_task_owner(run, 0, second_source, () => {
      true
    })
    is Err(InvalidConfiguration),
  )
  let output_export = @publication_host.prepare_acquired_task_publication_export(
    run, 0, first_source, limits,
  ).unwrap()
  let mut text = ""
  while output_export.next().unwrap() is Some(chunk) {
    text += chunk
  }
  text += output_export.finish().unwrap()
  assert_eq(text, "[{\"id\":3}]")
  output_export.cancel()
  let owner = prepare_native_remote_standard_acquired_task_owner(
    run,
    0,
    first_source,
    () => finish_native_remote_standard_transfer_source(first),
  ).unwrap()
  assert_eq(releases.val, 0)
  assert_true(owner.release())
  assert_true(owner.release())
  assert_eq(releases.val, 1)
  assert_true(@query.captured_source_available(second_source))
  assert_true(finish_native_remote_standard_transfer_source(second))
  assert_eq(releases.val, 2)
}
