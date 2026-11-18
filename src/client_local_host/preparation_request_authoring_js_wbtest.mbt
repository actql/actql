///|
fn authoring_request_fixture(
  note : String,
  current? : () -> Bool = () => true,
) -> (ClientRequestPreparation[Array[Int]], Array[Int]) raise {
  let document = request_default_document_fixture(1, 0).replace(
    old="\"id\":\"default-document\"",
    new="\"id\":\"default-document\",\"meta\":{\"note\":\"" + note + "\"}",
  )
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input, current~),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_snapshot(
    parent,
    input,
    document.length().to_int64() + 128L,
    12L,
  ).unwrap()
  let (environment, publication) = request_query_publication_fixture()
  prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(document, "json"),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  assert_eq(
    finish_request_checked_computation(parent, input, environment, publication).unwrap(),
    Pure,
  )
  prepare_request_program_normalization(parent, input).unwrap() |> ignore
  (parent, input)
}

///|
test "same Request authoring retains original metadata before Plan and rejects equal-CID foreign proof" {
  let (parent, input) = authoring_request_fixture("original")
  let prepared = parent.compiled_program.unwrap()
  let original = prepare_request_program_authoring_context(parent, input).unwrap()
  assert_true(
    physical_equal(
      original,
      prepare_request_program_authoring_context(parent, input).unwrap(),
    ),
  )
  let evidence = @publication_host.prepared_client_authoring_context_evidence(
    prepared, original, 1000000, 100000, 64,
  ).unwrap()
  let wire = @publication.run_evidence_value_json(evidence)
  assert_true(wire.contains("\"meta\":{\"note\":\"original\"}"))
  let (foreign, _other) = authoring_request_fixture("changed")
  let replacement = foreign.compiled_program.unwrap()
  assert_eq(
    @publication_host.prepared_client_identity(prepared),
    @publication_host.prepared_client_identity(replacement),
  )
  assert_true(
    @publication_host.prepared_client_authoring_context_evidence(
      replacement, original, 1000000, 100000, 64,
    )
    is Err(ForeignOriginal),
  )
  let borrow = borrow_request_program_plan_input(parent, input).unwrap()
  assert_true(
    prepare_request_program_authoring_context(parent, input)
    is Err(Preparation(WrongPhase)),
  )
  @resources.return_preparation_body_borrow(borrow).unwrap() |> ignore
  abort_request_preparation_after_cleanup(parent).unwrap()
  abort_request_preparation_after_cleanup(foreign).unwrap()
  assert_true(parent.program_authoring is None)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(foreign.ledger).live_reservations, 0)
}

///|
test "authoring grow and cached result fence current reentry before constructor" {
  let current = Ref(true)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (parent, input) = authoring_request_fixture("current", current=() => {
    if action.val is Some(run) {
      run()
    }
    current.val
  })
  let reentry = Ref(false)
  action.val = Some(() => {
    action.val = None
    reentry.val = prepare_request_program_authoring_context(parent, input)
      is Err(Preparation(WrongPhase)) &&
      abort_request_preparation_after_cleanup(parent) is Err(WrongPhase)
  })
  let original = prepare_request_program_authoring_context(parent, input).unwrap()
  assert_true(reentry.val)
  current.val = false
  assert_true(
    prepare_request_program_authoring_context(parent, input)
    is Err(Preparation(Capacity(_))),
  )
  assert_true(
    parent.program_authoring.unwrap().result is Some(Ok(value)) &&
    physical_equal(original, value),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "authoring exact fixed control versus one-short admits no variable constructor" {
  // Independent closed inventory:80H*16 +128R*8 +160W*8 =3584.
  assert_eq(request_authoring_control_bytes(), 3584L)
  for short in [1L, 0L] {
    let (parent, input) = normalization_request_control_fixture()
    prepare_request_program_normalization(parent, input).unwrap() |> ignore
    let usage = @resources.ledger_usage(parent.ledger)
    let limits = @resources.ledger_limits(parent.ledger)
    let free = limits.execution_bytes - usage.reserved_execution_bytes
    let pressure = @resources.reserve_capacity(
      parent.ledger,
      0L,
      free - 3584L + short,
    ).unwrap()
    assert_true(
      prepare_request_program_authoring_context(parent, input)
      is Err(Preparation(Capacity(_))),
    )
    if short == 1L {
      assert_true(parent.program_authoring is None)
    } else {
      let state = parent.program_authoring.unwrap()
      assert_true(state.inventory is Some(_) && state.preparation is None)
    }
    @resources.settle_capacity(parent.ledger, pressure).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "authoring output refusal retains same partial collection until original cleanup" {
  let (parent, input) = authoring_request_fixture("partial")
  // Fixture-only quantity observation sets pressure; it grants nothing. The
  // actual product continuation below still admits every constructor itself.
  let (geometry, _) = @publication_host.observe_client_authoring_collection_geometry(
    parent.compiled_program.unwrap(),
    1000000L,
  )
  let (_, collection) = request_authoring_collection_extents(geometry.unwrap()).unwrap()
  let usage = @resources.ledger_usage(parent.ledger)
  let free = @resources.ledger_limits(parent.ledger).execution_bytes -
    usage.reserved_execution_bytes
  let pressure = @resources.reserve_capacity(
    parent.ledger,
    0L,
    free - 3584L - collection,
  ).unwrap()
  assert_true(
    prepare_request_program_authoring_context(parent, input)
    is Err(Preparation(Capacity(_))),
  )
  {
    let state = parent.program_authoring.unwrap()
    assert_true(state.preparation is Some(_) && state.construction is Some(_))
    let partial = state.preparation.unwrap()
    assert_true(
      @publication_host.prepared_client_authoring_context_evidence(
        parent.compiled_program.unwrap(),
        partial,
        1000000,
        100000,
        64,
      )
      is Err(Encoding),
    )
    assert_true(
      prepare_request_program_authoring_context(parent, input)
      is Err(Preparation(Capacity(_))),
    )
    assert_true(
      physical_equal(
        partial,
        parent.program_authoring.unwrap().preparation.unwrap(),
      ),
    )
  }
  @resources.settle_capacity(parent.ledger, pressure).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(parent.program_authoring is None)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
