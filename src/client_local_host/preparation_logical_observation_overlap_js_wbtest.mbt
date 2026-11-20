///|
// Actual same-owner Node preparation/compilation/adoption and Resource loans.
// The physical input/module backing is the existing component fixture port;
// no ordinary installed Host, delivery, Journal ACK or Saved is claimed here.
test "ordinary manager admission registry dispatch and Host holders coexist with logical capture" {
  let (parent, input, prepared) = request_program_body_fixture()
  // Ordinary manager's construction input, retained while its actual Plan is
  // completed. It is neither another body nor a borrowed numerical allowance.
  let manager = borrow_request_program_plan_input(parent, input).unwrap()
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  let handler = @resources.borrow_preparation_body_sibling(manager).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "ordinary-observation-overlap",
  ).unwrap()
  // Node adoption itself issues its distinct admission and Run field holders.
  let run = begin_request_program_managed_run(parent, request).unwrap()
  let dispatch = @resources.borrow_preparation_body_sibling(handler).unwrap()
  let host = borrow_installed_managed_dispatch_preparation(
      run, prepared, request,
    )
    .unwrap()
    .unwrap()
  for holder in [manager, handler, dispatch, host] {
    assert_true(
      @resources.preparation_body_borrow_value(holder) is Some(original) &&
      physical_equal(original, prepared),
    )
  }
  let artifact = installed_managed_run_compilation_original(run, prepared).unwrap()
  let compiled = match artifact {
    Values(value) =>
      @publication_host.issue_client_values_compiled_run(
        prepared,
        value,
        "sha256:" + "a".repeat(64),
        "sha256:" + "b".repeat(64),
        "2099-01-01T00:00:00.000Z",
      ).unwrap()
    Tasks(value) =>
      @publication_host.issue_client_task_compiled_run(
        prepared,
        value,
        "sha256:" + "a".repeat(64),
        "sha256:" + "b".repeat(64),
        "2099-01-01T00:00:00.000Z",
      ).unwrap()
    Effects(_) => fail("the ordinary Pure component became Effectful")
  }
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "observation-overlap-component", "same-original-run", "2026-11-19T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  // The Journal's actual typed payload ACK drops strings, not the existing
  // explanation borrower. It now coexists with the logical observer below.
  let explanation = capture_installed_managed_run_explanation(
    run, prepared, compiled, definition, 65536, 8192, 64,
  ).unwrap()
  acknowledge_installed_original_explanation_capture(explanation).unwrap()
  assert_true(explanation.plan_view is None && explanation.facts is None)
  assert_true(explanation.original is Some(_))
  let limits = @resources.ledger_limits(parent.ledger)
  let observation = prepare_installed_logical_observation(
    run, prepared, compiled, definition, 65536, 8192, 64,
  ).unwrap()
  assert_true(
    @resources.preparation_body_borrow_value(observation.cleanup.holder)
    is Some(original) &&
    physical_equal(original, prepared),
  )
  // All eight necessary roles still hold the SAME preparation. The next
  // unrelated sibling remains refused; no owner or byte/work policy widened.
  assert_true(
    @resources.borrow_preparation_body_sibling(host) is Err(InvalidExtent),
  )
  assert_eq(@resources.ledger_limits(parent.ledger), limits)
  return_installed_logical_observation(observation).unwrap() |> ignore
  assert_true(
    observation.original is None && observation.cleanup.original is None,
  )
  // Returning the actual capture frees its one slot, without retiring or
  // refunding the manager/handler/dispatch/Host's still-live originals.
  let next = @resources.borrow_preparation_body_sibling(host).unwrap()
  assert_true(
    @resources.preparation_body_borrow_value(next) is Some(original) &&
    physical_equal(original, prepared),
  )
  @resources.return_preparation_body_borrow(next).unwrap() |> ignore
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(
    @resources.ledger_usage(parent.ledger).reserved_retention_bytes > 0L,
  )
  return_installed_original_explanation_capture(explanation).unwrap() |> ignore
  for holder in [host, dispatch, handler, manager] {
    @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  }
  retire_installed_managed_run(run).unwrap()
  let closed = @resources.ledger_usage(parent.ledger)
  assert_eq(closed.live_reservations, 0)
  assert_eq(closed.reserved_retention_bytes, 0L)
  assert_eq(closed.reserved_execution_bytes, 0L)
}
