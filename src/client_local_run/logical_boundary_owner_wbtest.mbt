///|
// Actual configured Compute/Run callers and registered Local kernels. Account
// and physical start remain the existing explicit component ports; this does
// not claim installed Host backing, disclosure authority or public capability.
test "Compute boundary owner returns an independent original fork after real work" {
  let original = plan(
    prepared(@input.Program(boundary_single_operation_program)),
    "compute-logical-owner",
  )
  let root = source_free_root()
  let host = source_free_shared_host(original, root).unwrap()
  let run = local_compute_run(host)
  let facts = @host.capture_client_structural_explanation_original(
    original.compiled,
    original.prepared,
    1000000,
    100000,
    100,
  ).unwrap()
  let unarmed = @resources.ledger_usage(root)
  assert_true(
    read_local_compute_logical_boundary(host, facts, Before, 1000)
    is Err(NoCurrentBoundary),
  )
  assert_eq(@resources.ledger_usage(root), unarmed)
  prepare_local_compute_task_boundaries(host).unwrap() |> ignore
  assert_true(
    read_local_compute_logical_boundary(host, facts, Before, 1000)
    is Err(NoCurrentBoundary),
  )
  let operations = boundary_test_start(host)
  // The synchronous managed start consumed its activation grant. This caller
  // cannot invent a Before boundary after work has already entered.
  assert_true(
    read_local_compute_logical_boundary(host, facts, Before, 1000)
    is Err(NoCurrentBoundary),
  )
  let available = Ref(true)
  boundary_test_finish(operations, available)
  let before_read = @resources.ledger_usage(root).live_reservations
  guard read_local_compute_logical_boundary(host, facts, Settled, 1000).unwrap()
    is Projected(before) else {
    fail("missing actual Compute boundary")
  }
  // The temporary base read was returned; only this independent logical fork
  // remains in addition to the unchanged actual task/setup reservations.
  assert_eq(@resources.ledger_usage(root).live_reservations, before_read + 1)
  let key_wire = @host.client_logical_task_boundary_key_json(
    before,
    original.compiled,
    original.prepared,
    4096,
    128,
    16,
  ).unwrap()
  let key = @publication.parse_interactive_run_control_shape(
    "logical_step_key", key_wire, 4096, 128, 16,
  ).unwrap()
  assert_true(
    @identity.object_field(key, "stage_ordinal") is Some(@identity.Number(0)),
  )
  guard @identity.object_field(key, "compiled_plan_cid")
    is Some(@identity.String(plan_id)) else {
    fail("missing original compiled Plan identity")
  }
  assert_eq(
    plan_id,
    @publication.publication_contract_identity(original.compiled.plan),
  )
  guard read_local_compute_logical_boundary(host, facts, Settled, 1000).unwrap()
    is Projected(settled) else {
    fail("missing actual settled Compute boundary")
  }
  @host.return_client_logical_task_boundary(before).unwrap()
  assert_false(
    @host.client_logical_task_boundary_current(
      before,
      original.compiled,
      original.prepared,
    ),
  )
  assert_true(
    @host.client_logical_task_boundary_current(
      settled,
      original.compiled,
      original.prepared,
    ),
  )
  @host.return_client_logical_task_boundary(settled).unwrap()
  @host.return_client_logical_task_boundary(settled).unwrap()
  boundary_test_close(host, operations, available)
  assert_false(@strategy.captured_task_boundary_cleanup_pending(run))
}

///|
test "Compute boundary owner refuses foreign originals and unfunded read without consuming current boundary" {
  let original = plan(
    prepared(@input.Program(boundary_single_operation_program)),
    "compute-logical-refusals",
  )
  let foreign = plan(
    prepared(@input.Program(boundary_single_operation_program)),
    "compute-logical-foreign",
  )
  let root = source_free_root()
  let host = source_free_shared_host(original, root).unwrap()
  let facts = @host.capture_client_structural_explanation_original(
    original.compiled,
    original.prepared,
    1000000,
    100000,
    100,
  ).unwrap()
  let foreign_facts = @host.capture_client_structural_explanation_original(
    foreign.compiled,
    foreign.prepared,
    1000000,
    100000,
    100,
  ).unwrap()
  prepare_local_compute_task_boundaries(host).unwrap() |> ignore
  let operations = boundary_test_start(host)
  let available = Ref(true)
  boundary_test_finish(operations, available)
  let usage = @resources.ledger_usage(root)
  assert_true(
    read_local_compute_logical_boundary(host, foreign_facts, Settled, 1000)
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(root), usage)
  let limits = @resources.ledger_limits(root)
  let occupied = @resources.reserve_capacity(
    root,
    limits.retained_bytes - usage.reserved_retention_bytes - usage.held_bytes,
    limits.execution_bytes - usage.reserved_execution_bytes,
  ).unwrap()
  let full = @resources.ledger_usage(root)
  assert_true(
    read_local_compute_logical_boundary(host, facts, Settled, 1000) is Err(_),
  )
  assert_eq(
    @resources.ledger_usage(root).live_reservations,
    full.live_reservations,
  )
  @resources.settle_capacity(root, occupied).unwrap()
  guard read_local_compute_logical_boundary(host, facts, Settled, 1000).unwrap()
    is Projected(boundary) else {
    fail("original boundary was consumed by a refused read")
  }
  @host.return_client_logical_task_boundary(boundary).unwrap()
  boundary_test_close(host, operations, available)
}
