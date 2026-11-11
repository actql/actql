///|
test "saved Model constructors share original restoration reservation without a new compiler or Run" {
  let (_, request, definition) = capture_recovery_originals()
  let input = [181]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let original = owner.capacity
  let before = @resources.ledger_usage(owner.ledger)
  let calls = Ref(0)
  let observed = Ref(true)
  for bodies in [["{\"saved\":true}"], ["{}", "{}", "{}"], ["{}", "{}", "{}"]] {
    let previous = @resources.ledger_usage(owner.ledger)
    reserve_request_model_recovery_materials(
      owner,
      input,
      request,
      definition,
      bodies.length(),
      index => {
        observed.val = observed.val && owner.phase == Selecting
        observed.val = observed.val &&
          reserve_request_model_recovery_materials(
            owner,
            input,
            request,
            definition,
            0,
            _ => "",
            0,
          )
          is Err(ForeignOriginal)
        calls.val += 1
        bodies[index]
      },
      bodies.length(),
    ).unwrap()
    let after = @resources.ledger_usage(owner.ledger)
    assert_true(
      after.reserved_retention_bytes > previous.reserved_retention_bytes,
    )
    assert_true(
      after.reserved_execution_bytes >= previous.reserved_execution_bytes,
    )
    assert_eq(after.live_reservations, before.live_reservations)
    assert_eq(after.attempts, before.attempts)
    assert_eq(after.transferred_bytes, before.transferred_bytes)
    assert_true(physical_equal(owner.capacity, original))
    assert_true(
      owner.program_capacity is None && owner.compiled_program is None,
    )
    assert_true(
      owner.program_compilation is None && owner.program_check is None,
    )
    assert_true(owner.phase == ModelRecovery)
  }
  assert_eq(calls.val, 7)
  assert_true(observed.val)
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
  assert_true(owner.phase == Closed)
}

///|
test "saved Model reservation rejects foreign pair and current refusal before reading another material" {
  let (_, request, definition) = capture_recovery_originals()
  let (_, foreign, foreign_definition) = capture_recovery_originals()
  let input = [182]
  let current = Ref(true)
  let owner = begin_request_preparation(
    request_parent_fixture(input, current=() => current.val),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_model_recovery_materials(
    owner,
    input,
    request,
    definition,
    1,
    _ => "{}",
    1,
  ).unwrap()
  let retained = @resources.ledger_usage(owner.ledger)
  let calls = Ref(0)
  for
    (selected_input, selected_request, selected_definition) in [
      ([182], request, definition),
      (input, foreign, definition),
      (input, request, foreign_definition),
    ] {
    assert_true(
      reserve_request_model_recovery_materials(
        owner,
        selected_input,
        selected_request,
        selected_definition,
        1,
        _ => {
          calls.val += 1
          "{}"
        },
        1,
      )
      is Err(ForeignOriginal),
    )
    assert_eq(@resources.ledger_usage(owner.ledger), retained)
  }
  current.val = false
  assert_true(
    reserve_request_model_recovery_materials(
      owner,
      input,
      request,
      definition,
      1,
      _ => {
        calls.val += 1
        "{}"
      },
      1,
    )
    is Err(Capacity(_)),
  )
  assert_eq(calls.val, 0)
  current.val = true
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}

///|
test "saved Model growth failure keeps original capacity and physical cleanup pending" {
  let (_, request, definition) = capture_recovery_originals()
  let input = [183]
  let pending = Ref(false)
  let owner = begin_request_preparation(
    request_parent_fixture(input, pending=() => pending.val),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_model_recovery_materials(
    owner,
    input,
    request,
    definition,
    1,
    _ => "{}",
    1,
  ).unwrap()
  let previous = @resources.ledger_usage(owner.ledger)
  assert_true(
    reserve_request_model_recovery_materials(
      owner,
      input,
      request,
      definition,
      1,
      _ => "x".repeat(1000000),
      1,
    )
    is Err(Capacity(_)),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), previous)
  pending.val = true
  assert_true(abort_request_preparation_after_cleanup(owner) is Err(_))
  assert_true(owner.phase == Retiring && owner.input is None)
  pending.val = false
  // A later empty callback cannot fabricate the original stop ACK.
  assert_true(abort_request_preparation_after_cleanup(owner) is Err(Initial(_)))
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}

///|
// Original checked compiler/Graph from the existing fixture, then a distinct
// physical-process Request parent. No compiler is entered by recovery here.
test "cold Model Scope binds the original recovery Request census and ledger without a replacement Run" {
  let f = request_serialized_model_fixture(serialized=false)
  let input = [188]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_model_recovery_materials(
    owner,
    input,
    f.request,
    f.definition,
    1,
    _ => "{}",
    1,
  ).unwrap()
  let original = owner.capacity
  let ledger = request_model_recovery_ledger(
    owner,
    input,
    f.request,
    f.definition,
  ).unwrap()
  assert_true(physical_equal(ledger, owner.ledger))
  let before = @resources.ledger_usage(ledger)
  let scopes = prepare_request_model_recovery_read_scopes(
    owner,
    input,
    f.request,
    f.definition,
    f.prepared,
    f.compiled,
    [f.graph],
    effect_model_plan_limits,
    [7L],
    [5L],
    20,
    20,
    20,
  ).unwrap()
  assert_eq(scopes.length(), 1)
  assert_true(physical_equal(owner.capacity, original))
  assert_true(owner.program_capacity is None && owner.compiled_program is None)
  assert_true(owner.program_compilation is None && owner.program_model is None)
  assert_true(owner.phase == ModelRecovery)
  let scope = scopes[0]
  let identity = @resources.preparation_capacity_inventory_original(
    original, input,
  ).unwrap()
  assert_true(
    @publication_host.client_model_read_scope_original_inventory(
      scope, ledger, identity,
    ),
  )
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.attempts, before.attempts)
  assert_eq(after.transferred_bytes, before.transferred_bytes)
  assert_eq(after.live_reservations, before.live_reservations)
  assert_true(after.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_false(
    @publication_host.client_compiled_run_infer_originals_match(f.compiled, []),
  )
  assert_false(
    @publication_host.client_compiled_run_infer_originals_match(f.compiled, [
      f.graph,
      f.graph,
    ]),
  )
  let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
  @publication_host.stop_client_model_read(read).unwrap()
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      f.compiled,
      f.definition,
      f.graph,
      true,
    ).unwrap(),
  )
  assert_true(
    @resources.preparation_capacity_working_usage_isolated(
      owner.capacity,
      input,
      ledger,
    ),
  )
  assert_false(
    @resources.preparation_capacity_working_usage_isolated(
      owner.capacity,
      [188],
      ledger,
    ),
  )
  assert_false(
    @resources.preparation_capacity_working_usage_isolated(
      owner.capacity,
      input,
      f.parent.ledger,
    ),
  )
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  abort_request_preparation_after_cleanup(f.parent).unwrap()
}

///|
test "saved material geometry keeps long text distinct from original Value slots" {
  let observe = (text : String) => {
    let cursor = @decode.admit_raw_json(
      @json.parse(text),
      {
        start_byte: 0,
        end_byte: text.length(),
        start_line: 1,
        start_column: 1,
        end_line: 1,
        end_column: text.length() + 1,
        source_path: "<original-material>",
      },
      {
        max_nodes: 20,
        max_depth: 4,
        max_string_bytes: 20000,
        max_total_string_bytes: 20000,
      },
    ).unwrap()
    cursor
  }
  let short = "{\"program\":\"x\"}"
  let long = "{\"program\":\"" + "x".repeat(10000) + "\"}"
  let short_cursor = observe(short)
  let long_cursor = observe(long)
  let a = @decode.observe_subtree_construction_geometry(short_cursor)
  let b = @decode.observe_subtree_construction_geometry(long_cursor)
  assert_eq(a.nodes, 2)
  assert_eq(b.nodes, 2)
  assert_eq(b.total_utf16 - a.total_utf16, 9999L)
  let old_a = request_model_recovery_capacity(short.length().to_int64() * 3L, 1).unwrap()
  let old_b = request_model_recovery_capacity(long.length().to_int64() * 3L, 1).unwrap()
  let new_a = request_model_recovery_material_capacity(
    short,
    a,
    @decode.admission_usage(short_cursor).depth,
    1,
  ).unwrap()
  let new_b = request_model_recovery_material_capacity(
    long,
    b,
    @decode.admission_usage(long_cursor).depth,
    1,
  ).unwrap()
  // Six original decoded-text roles and four canonical-wire roles grow;
  // neither Value-slot nor cursor-depth quantity changes with Text length.
  assert_eq(
    @execution.execution_capacity_retained_bytes(new_b) -
    @execution.execution_capacity_retained_bytes(new_a),
    9999L * (3L * 6L * 8L + 3L * 4L * 8L),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(new_b) <
    @execution.execution_capacity_retained_bytes(old_b),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(old_b) >
    @execution.execution_capacity_retained_bytes(old_a),
  )
  assert_true(
    request_model_recovery_material_capacity(
      long,
      b,
      @decode.admission_usage(long_cursor).depth,
      -1,
    )
    is None,
  )
  assert_true(request_model_recovery_capacity(-1L, 1) is None)
}

///|
test "saved structured Program quote uses original constructor inventory not literal text length" {
  let limits = @publication_host.client_standard_program_preparation_limits().checking.input
  let prefix = "{\"version\":\"actql/0.1\",\"id\":\"recovery-original\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"text\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"text\":\""
  let suffix = "\"}]},\"as\":\"seed\"}],\"results\":{\"rows\":{\"from\":\"seed\",\"fields\":[\"text\"]}}}],\"results\":{\"rows\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  let observe = (literal : String) => {
    let input = @syntax.parse_program_input(prefix + literal + suffix, limits).unwrap()
    let cursor = @syntax.program_input_cursor(input)
    let (inventory, spent) = @syntax.observe_program_constructor_inventory(
      cursor,
      @syntax.program_constructor_inspection_work_bound(input),
    )
    (inventory.unwrap(), @decode.admission_usage(cursor).depth, spent)
  }
  let (short, depth, short_work) = observe("x")
  let (long, long_depth, long_work) = observe("x".repeat(10000))
  assert_eq(short.retained, long.retained)
  assert_eq(depth, long_depth)
  assert_eq(short_work, long_work)
  let a = request_model_recovery_program_capacity(short, depth).unwrap()
  let b = request_model_recovery_program_capacity(long, long_depth).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(a),
    @execution.execution_capacity_retained_bytes(b),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(a),
    @execution.execution_capacity_execution_bytes(b),
  )
  // These borrowed original literals remain backed by the Source index;
  // the Program decoder allocates no additional Value forest for their text.
  assert_true(@execution.execution_capacity_retained_bytes(a) > 0L)
  assert_true(request_model_recovery_program_capacity(short, -1) is None)
}
