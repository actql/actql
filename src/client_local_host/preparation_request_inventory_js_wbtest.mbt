///|
test "Request initial census is already owned before snapshot without a Model execution grant" {
  let input = [1]
  let policy = client_local_resource_policy()
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    policy,
  ).unwrap()
  let identity = @resources.preparation_capacity_inventory_original(
    owner.capacity,
    input,
  ).unwrap()
  let (r, e) = client_request_preparation_control_capacity(policy).unwrap()
  assert_eq(e, 0L)
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 1)
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_retention_bytes, r)
  assert_false(@resources.original_ledger_inventory_available(identity))
  assert_true(
    @resources.claim_original_ledger_run_binding(identity, owner.ledger)
    is Err(@resources.InvalidBootstrap),
  )
  let (headers, refs, words) = request_preparation_inventory_slots
  assert_eq((headers, refs, words), (19L, 28L, 21L))
  // Independent pinned tariff arithmetic: 19*16+28*8+21*8 =696.
  // This is logical Resource control backing, not heap/RSS.
  assert_eq(
    @execution.preparation_representation_cost({
      record_headers: headers,
      reference_slots: refs,
      scalar_words: words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }),
    Some(696L),
  )
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}

///|
test "Request IO census uses the existing original borrower quota and keeps consumed work on retirement" {
  let input = [1]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let children : Array[@resources.PreparationIo] = []
  for _ in 0..<6 {
    children.push(
      @resources.begin_preparation_io(owner.capacity, input, 0L).unwrap(),
    )
  }
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 7)
  assert_eq(@resources.ledger_usage(owner.ledger).attempts, 6)
  assert_true(
    @resources.begin_preparation_io(owner.capacity, input, 0L)
    is Err(@resources.InvalidExtent),
  )
  for original in children {
    // Explicit logical Resource cleanup ports only; no physical Source/IO
    // was created by this component and no Host cleanup ACK is claimed.
    @resources.finish_preparation_io_after_cleanup(original).unwrap()
  }
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).attempts, 6)
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}

///|
test "actual ordinary Request constructor retires only unused census metadata on the same compiler and reservation" {
  let (owner, input, prepared) = request_program_body_fixture()
  let identity = @resources.preparation_capacity_inventory_original(
    owner.program_capacity.unwrap(),
    input,
  ).unwrap()
  prepare_request_program_module_body(
    owner,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  let holder = borrow_request_program_preparation(owner).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "early-census-ordinary",
  ).unwrap()
  let before = request_preparation_accounting(owner)
  let run = begin_request_program_managed_run(owner, request).unwrap()
  assert_false(@resources.original_ledger_inventory_available(identity))
  assert_eq(request_preparation_accounting(owner), before)
  assert_true(
    @resources.preparation_body_borrow_value(holder) is Some(original) &&
    physical_equal(original, prepared),
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}

///|
test "ordinary Effect purpose uses explicit checked Infer inventory instead of single-selector absence" {
  let (parent, input, prepared) = request_effect_compile_fixture()
  let ordinary = @publication_host.prepared_client_effect_composed_infer_occurrences(
    prepared,
  )
  assert_true(ordinary is Some(values) && values.is_empty())
  assert_true(installed_managed_owner_shape_supported(Effect(prepared), false))
  assert_false(installed_managed_owner_shape_supported(Effect(prepared), true))
  abort_request_preparation_after_cleanup(parent).unwrap()
  let (model, _, _, _) = effect_model_plan_inputs()
  let selected = @publication_host.prepared_client_effect_composed_infer_occurrences(
    model,
  )
  assert_true(selected is Some(values) && values.length() == 1)
  assert_false(installed_managed_owner_shape_supported(Effect(model), false))
  assert_true(installed_managed_owner_shape_supported(Effect(model), true))
  // No unknown/single-selector None is asserted to mean zero here. General
  // multiple-Model ordinary execution remains outside this component.
  ignore(input)
}
