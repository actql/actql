///|
test "original parity SQL 72 and 73 reach terminal Content input with the checked two rows" {
  // The parity corpus SQL is fixed independently of the expected output.
  let cases = [
    (
      (
        #|WITH r AS (SELECT 2 AS id UNION ALL SELECT 1) FROM r |> SERIALIZE FORMAT JSONL ORDER BY id OPTIONS (name = 'rows.jsonl')
      ),
      false,
    ),
    (
      (
        #|WITH r AS (SELECT 2 AS id UNION ALL SELECT 1) FROM r |> SERIALIZE FORMAT JSONL ORDER BY id OPTIONS (name = 'rows.jsonl', max_rows = 1)
      ),
      true,
    ),
  ]
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let manifests = request_program_module_manifests()
  let (environment, publication) = request_query_publication_fixture()
  for (sql, row_guard) in cases {
    let (parent, input) = native_driver_parent(sql)
    assert_eq(
      prepare_request_native_query_computation(
        parent,
        input,
        sql,
        @frontend.Sql,
        native_json_reader,
        environment,
        publication,
        [],
        @publication_host.client_standard_program_preparation_limits(),
        @publication_host.client_standard_effect_computation_limits(),
      ).unwrap(),
      Pure,
    )
    let prepared = parent.compiled_program.unwrap()
    let compilation_limits = request_program_compilation_limits(parent, input).unwrap()
    let holder = borrow_request_content_plan_input(parent, input).unwrap()
    guard @publication_host.prepared_client_serialization_occurrences(prepared)
      is [(task, step)] else {
      fail("the original SQL must have one checked serialization occurrence")
    }
    let graph = prepare_request_serialization_graph(
      parent,
      input,
      task,
      step,
      "sha256:" + @sha.hex(@utf8.encode(assets.result_policy)),
      assets.result_policy,
      16,
      128,
      true,
      contracts,
      manifests~,
      compilation_limits~,
    ).unwrap()
    let compilation = prepare_request_serialization_compilation(
      parent,
      input,
      graph,
      contracts,
      manifests~,
      compilation_limits~,
    ).unwrap()
    let authority = "sha256:" + "a".repeat(64)
    let compiled = @publication_host.issue_client_task_compiled_run(
      prepared,
      compilation,
      authority,
      "sha256:" + "b".repeat(64),
      "2099-01-01T00:00:00.000Z",
    ).unwrap()
    let definition = @publication_host.issue_client_compiled_run_definition(
      compiled, "parity-terminal-sql", "original", "2026-11-27T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
    ).unwrap()
    let request = @publication_host.prepare_source_free_client_request_identity(
      prepared, authority, "original-parity-terminal-sql",
    ).unwrap()
    let selected = prepare_request_terminal_serialization_plan(
      parent, input, request, compiled, definition,
    ).unwrap()
    complete_request_serialization_preparation(parent, input, selected).unwrap()
    assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
    let run = begin_request_content_managed_run(parent, request).unwrap()
    let (_, prefix, demand) = start_installed_managed_terminal_serialization(
      run, request, compiled, definition,
    ).unwrap()
    let mut completed = None
    for _ in 0..<1000 {
      match advance_client_serialization_prefix(prefix, 1).unwrap() {
        @local.Complete(output, ..) => {
          completed = Some(output)
          break
        }
        @local.Continue(..) | @local.Waiting(..) | @local.Settling(_, ..) => ()
        _ =>
          fail(
            "the original terminal prefix refused before binding Content input",
          )
      }
    }
    let output = completed.unwrap()
    assert_eq(@execution.completed_row_count(output), 2)
    let encoder = @publication_host.start_client_serialization_encoder(
      graph.barrier,
      max_rows=demand.generation_rows,
      max_bytes=demand.limits.generation_bytes,
      max_value_nodes=demand.limits.generation_nodes,
      max_value_depth=demand.limits.generation_depth,
      max_frames=demand.limits.generation_frames,
    ).unwrap()
    let unavailable = @execution.restrict_completed_output(output, () => false)
    assert_true(
      @publication_host.bind_client_serialization_completed_input(
        graph.barrier,
        unavailable,
        encoder,
      )
      is Err(InputUnavailable),
    )
    let bound = @publication_host.bind_client_serialization_completed_input(
      graph.barrier,
      output,
      encoder,
    )
    if row_guard {
      assert_eq(demand.generation_rows, 1)
      assert_true(bound is Err(RowLimit))
      @publication.cancel_content_byte_encoder(encoder)
    } else {
      let selected = bound.unwrap()
      assert_eq(@publication_host.client_serialization_input_rows(selected), 2)
      let body = StringBuilder()
      for row in -1..<2 {
        if row >= 0 {
          @publication_host.start_client_serialization_input_row(selected, row).unwrap()
        }
        let mut ready = false
        for _ in 0..<1000 {
          match @publication.advance_content_bytes(encoder, 7) {
            ContentBytesContinue(piece, ..) => body.write_string(piece)
            ContentBytesReady(piece, ..) => {
              body.write_string(piece)
              ready = true
              break
            }
            ContentBytesFailed(_, ..) =>
              fail("the original ordered JSONL must encode")
          }
        }
        assert_true(ready)
      }
      let generated = @publication.finish_content_bytes(encoder).unwrap()
      assert_eq(body.to_string(), "{\"id\":1}\n{\"id\":2}\n")
      assert_eq((generated.row_count, generated.size_bytes), (2, 18))
      assert_eq(
        generated.content_cid,
        "sha256:c63f6dd68b68601e7315ea40d28bc34e55379e4fa65f82b1d32228429aeafcde",
      )
    }
    assert_true(cleanup_installed_managed_terminal_serialization(run).unwrap())
    retire_installed_managed_run(run).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}
