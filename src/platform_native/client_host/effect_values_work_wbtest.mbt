///|
// Static phases only: no raw issue payload, row, wire, key or stack is emitted.
fn[T, E] effect_values_work_test_ok(
  value : Result[T, E],
  phase : String,
) -> T raise {
  match value {
    Ok(value) => value
    Err(_) => fail("effect-values fixture: " + phase)
  }
}

///|
fn effect_values_work_test_opened(
  value : Result[
    NativeClientEffectValuesWork,
    NativeClientEffectValuesWorkFailure,
  ],
) -> NativeClientEffectValuesWork raise {
  match value {
    Ok(work) => work
    Err(failure) => {
      let kind = match failure.issue {
        AuthorizationDenied => "AuthorizationDenied"
        ForeignMaterials => "ForeignMaterials"
        Configuration => "Configuration"
        OriginalRunNotCurrent => "OriginalRunNotCurrent"
        Unavailable => "Unavailable"
        Journal(_) => "Journal"
        Start(_) => "Start"
        Normalization(_) => "Normalization"
        Execution(_) => "Execution"
      }
      failure.close() |> ignore
      fail("effect-values Work: " + kind)
    }
  }
}

///|
// Admit the same bundled contract originals as the adjacent Values fixture.
// These are test inputs, not an installation, authority or funding supplier.
fn effect_values_work_test_bodies() -> (
  @local.ClientInstalledSequenceContracts,
  String,
  String?,
) {
  let assets = @host.client_local_product_assets()
  let values = assets.values
  let fragment = Some(assets.fragment)
  let installed = @local.prepare_installed_sequence_contracts(
    assets.registry,
    values,
    fragment,
    None,
  ).unwrap()
  (installed, values, fragment)
}

///|
fn effect_values_work_test_original(
  request : @host.ClientRequestIdentity,
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
) -> (
  @host.ClientEffectRunMaterials,
  @host.PreparedClientEffectRun,
  @strategy.CapturedEffectRunDAG,
) raise {
  let prepared = @host.client_effect_compilation_owner(allowed.compilation)
  let normalization = effect_values_work_test_ok(
    @host.issue_prepared_client_effect_normalization(prepared),
    "normalization.issue",
  )
  let issued = effect_values_work_test_ok(
    @host.issue_prepared_client_effect_normalization_materials(
      allowed,
      definition,
      normalization,
      request=Some(request),
    ),
    "normalization.materials",
  )
  let materials = effect_values_work_test_ok(
    @host.bind_prepared_client_effect_original_materials(
      allowed,
      definition,
      issued,
      request=Some(request),
    ),
    "materials.bind",
  )
  let bound = effect_values_work_test_ok(
    @host.bind_client_effect_compiled_run(prepared, allowed, definition),
    "compiled.bind",
  )
  let (installed, values, fragment) = effect_values_work_test_bodies()
  // An explicit Core test Ledger for this fresh Run, not normal Host funding.
  guard @local.client_effect_local_ledger_limits(
      prepared,
      installed,
      values,
      fragment,
      None,
    )
    is Some(capacity) else {
    fail("effect-values fixture: original capacity")
  }
  let captured = effect_values_work_test_ok(
    @host.open_prepared_source_free_client_effect_run(bound, capacity),
    "original.run.open",
  )
  (materials, bound, captured)
}

///|
fn effect_values_work_test_stop(
  captured : @strategy.CapturedEffectRunDAG,
) -> Unit {
  stop_unstarted_values_setup(@strategy.captured_effect_run_dag(captured))
}

///|
test "Native original source-free Effect Work claims and computes once on the same Run and retains capture custody" {
  println("effect-values fixture: acceptance.begin")
  let (database, journal, request, allowed, definition) = accepted_effect_work_fixture(
    "effect-values-original-once",
  )
  println("effect-values fixture: acceptance.complete")
  let (materials, bound, captured) = effect_values_work_test_original(
    request, allowed, definition,
  )
  let (installed, values, fragment) = effect_values_work_test_bodies()
  let work = open_native_client_effect_values_work(
      journal,
      request,
      materials,
      bound,
      captured,
      installed,
      values,
      fragment,
      None,
      64,
      1000,
      () => "2026-10-15T00:00:00.000Z",
      () => true,
    )
    |> effect_values_work_test_opened
  assert_true(physical_equal(work.run_for_capture().unwrap(), captured))
  let dag = @strategy.captured_effect_run_dag(captured)
  assert_true(@strategy.captured_task_completed(dag, 0))
  let record = journal.retained(request).unwrap().unwrap()
  assert_true(record.physical_start_claimed)
  assert_false(record.cancellation_requested)
  assert_true(record.checkpoint is None)
  let pins = @strategy.pin_captured_effect_sources(captured, 1).unwrap()
  assert_eq(@strategy.captured_effect_inputs_count(pins), 1)
  let input = @strategy.captured_effect_input_at(pins, 0).unwrap()
  assert_true(
    @strategy.captured_any_result_borrow_matches_managed(
      @strategy.captured_effect_input_borrow(input),
      work.execution.completed_output(),
    ),
  )
  let original_body = run_record_body(record).unwrap()
  let repeat = open_native_client_effect_values_work(
    journal,
    request,
    materials,
    bound,
    captured,
    installed,
    values,
    fragment,
    None,
    64,
    1000,
    () => "2026-10-15T00:00:00.000Z",
    () => true,
  ).unwrap_err()
  assert_true(
    native_client_effect_values_work_failure_issue(repeat)
    is Start(NeedsOriginalReconciliation),
  )
  assert_true(repeat.close())
  assert_eq(
    run_record_body(journal.retained(request).unwrap().unwrap()).unwrap(),
    original_body,
  )
  assert_true(@strategy.release_captured_effect_inputs(pins))
  assert_true(work.close())
  assert_true(work.close())
  assert_true(work.run_for_capture() is Err(Unavailable))
  assert_eq(work.usage().held_bytes, 0L)
  assert_eq(work.usage().reserved_execution_bytes, 0L)
  database.close_checked().unwrap()
}

///|
test "Native Effect Values refuses missing normalization and expired original before any start" {
  for missing in [true, false] {
    let (database, journal, request, allowed, definition) = accepted_effect_work_fixture(
      "effect-values-original-refusal-" + missing.to_string(),
    )
    let (original, bound, captured) = effect_values_work_test_original(
      request, allowed, definition,
    )
    let materials = if missing {
      { ..original, normalization: None, }
    } else {
      original
    }
    let (installed, values, fragment) = effect_values_work_test_bodies()
    let failure = open_native_client_effect_values_work(
      journal,
      request,
      materials,
      bound,
      captured,
      installed,
      values,
      fragment,
      None,
      64,
      1000,
      () => "2099-01-01T00:00:00.000Z",
      () => true,
    ).unwrap_err()
    assert_true(
      if missing {
        native_client_effect_values_work_failure_issue(failure)
        is Normalization(MissingOriginalJournal)
      } else {
        native_client_effect_values_work_failure_issue(failure)
        is OriginalRunNotCurrent
      },
    )
    assert_true(failure.close())
    assert_false(
      journal.retained(request).unwrap().unwrap().physical_start_claimed,
    )
    assert_eq(
      @resources.ledger_usage(
        @strategy.captured_dag_ledger(
          @strategy.captured_effect_run_dag(captured),
        ),
      ).attempts,
      0,
    )
    effect_values_work_test_stop(captured)
    database.close_checked().unwrap()
  }
}

///|
test "Native Effect Values refuses foreign opaque Run without stopping or claiming either original" {
  let (database, journal, request, allowed, definition) = accepted_effect_work_fixture(
    "effect-values-foreign-first",
  )
  let (second, other_journal, other_request, other_allowed, other_definition) = accepted_effect_work_fixture(
    "effect-values-foreign-second",
  )
  let (materials, bound, captured) = effect_values_work_test_original(
    request, allowed, definition,
  )
  let (_, _, foreign) = effect_values_work_test_original(
    other_request, other_allowed, other_definition,
  )
  let (installed, values, fragment) = effect_values_work_test_bodies()
  // Equal public Run bytes cannot replace the first nominal binding.
  let rebound = effect_values_work_test_ok(
    @host.bind_client_effect_compiled_run(
      materials.prepared,
      allowed,
      definition,
    ),
    "same-bytes.rebound",
  )
  for
    (selected_bound, selected_captured) in [
      (bound, foreign),
      (rebound, captured),
    ] {
    let failure = open_native_client_effect_values_work(
      journal,
      request,
      materials,
      selected_bound,
      selected_captured,
      installed,
      values,
      fragment,
      None,
      64,
      1000,
      () => "2026-10-15T00:00:00.000Z",
      () => true,
    ).unwrap_err()
    assert_true(
      native_client_effect_values_work_failure_issue(failure)
      is ForeignMaterials,
    )
    assert_true(failure.close())
  }
  assert_false(
    journal.retained(request).unwrap().unwrap().physical_start_claimed,
  )
  assert_false(
    other_journal.retained(other_request).unwrap().unwrap().physical_start_claimed,
  )
  for run in [captured, foreign] {
    let dag = @strategy.captured_effect_run_dag(run)
    assert_eq(@strategy.next_captured_task(dag), Some(0))
    assert_true(@strategy.captured_dag_strategy(dag) is None)
    effect_values_work_test_stop(run)
  }
  database.close_checked().unwrap()
  second.close_checked().unwrap()
}

///|
test "Native Effect Values rechecks cancellation admitted by its clock callback before Compute" {
  let (database, journal, request, allowed, definition) = accepted_effect_work_fixture(
    "effect-values-clock-cancel",
  )
  let (materials, bound, captured) = effect_values_work_test_original(
    request, allowed, definition,
  )
  let (installed, values, fragment) = effect_values_work_test_bodies()
  let failure = open_native_client_effect_values_work(
    journal,
    request,
    materials,
    bound,
    captured,
    installed,
    values,
    fragment,
    None,
    64,
    1000,
    () => {
      journal
      .transaction(() => {
        let record = journal.retained(request).unwrap().unwrap()
        journal.save({ ..record, cancellation_requested: true, }).map(_ => ())
      })
      .unwrap()
      "2026-10-15T00:00:00.000Z"
    },
    () => true,
  ).unwrap_err()
  assert_true(
    native_client_effect_values_work_failure_issue(failure) is Start(_),
  )
  assert_true(failure.close())
  assert_eq(
    @resources.ledger_usage(
      @strategy.captured_dag_ledger(@strategy.captured_effect_run_dag(captured)),
    ).attempts,
    0,
  )
  assert_true(
    journal.retained(request).unwrap().unwrap().cancellation_requested,
  )
  effect_values_work_test_stop(captured)
  database.close_checked().unwrap()
}

///|
test "Native Effect Values uses adopted current Submit independently of Source read and refuses denial" {
  for submit in [false, true] {
    let (host, request, allowed, definition, _) = local_effect_source_authority_fixture(
      "effect-values-real-authority-" + submit.to_string(),
      submit,
      false,
    )
    let (materials, bound, captured) = effect_values_work_test_original(
      request, allowed, definition,
    )
    let (installed, values, fragment) = effect_values_work_test_bodies()
    let opened = host.open_effect_values_work(
      epoch_test_crypto(),
      "operator",
      "cli",
      request,
      materials,
      bound,
      captured,
      installed,
      values,
      fragment,
      None,
      64,
      1000,
      () => "2026-10-15T00:00:00.000Z",
    )
    if submit {
      let work = effect_values_work_test_opened(opened)
      assert_true(physical_equal(work.run_for_capture().unwrap(), captured))
      host.close().unwrap()
      assert_true(work.run_for_capture() is Err(_))
      assert_true(work.close())
    } else {
      let failure = opened.unwrap_err()
      assert_true(
        native_client_effect_values_work_failure_issue(failure)
        is Journal(AuthorizationDenied),
      )
      assert_true(failure.close())
      effect_values_work_test_stop(captured)
      host.close().unwrap()
    }
  }
}

///|
test "Native Effect Values terminal capture fence observes cleanup performed inside current callback" {
  let (database, journal, request, allowed, definition) = accepted_effect_work_fixture(
    "effect-values-terminal-lifetime",
  )
  let (materials, bound, captured) = effect_values_work_test_original(
    request, allowed, definition,
  )
  let (installed, values, fragment) = effect_values_work_test_bodies()
  let retained : Ref[NativeClientEffectValuesWork?] = { val: None, }
  let work = open_native_client_effect_values_work(
      journal,
      request,
      materials,
      bound,
      captured,
      installed,
      values,
      fragment,
      None,
      64,
      1000,
      () => "2026-10-15T00:00:00.000Z",
      () => {
        if retained.val is Some(work) {
          work.close() |> ignore
        }
        true
      },
    )
    |> effect_values_work_test_opened
  retained.val = Some(work)
  assert_true(work.run_for_capture() is Err(Unavailable))
  assert_true(work.close())
  retained.val = None
  database.close_checked().unwrap()
}
