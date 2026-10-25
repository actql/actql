///|
// Same accepted original packet/material Owner as ordinary readonly restore.
// The fresh Core test Ledger is explicit; no normal Host funding is supplied.
fn submitted_effect_values_fixture(
  name : String,
) -> (
  NativeLocalHostConnection,
  NativeClientSubmissionReference,
  @host.ClientRequestIdentity,
  @host.ClientEffectRunMaterials,
  @host.PreparedClientEffectRun,
  @strategy.CapturedEffectRunDAG,
) raise {
  let (host, reference, request, _) = effect_original_restorable_host_fixture(
    name,
  )
  let materials = effect_values_work_test_ok(
    effect_original_restore_fixture_call(host, reference, request),
    "submitted.original.restore",
  )
  let (bound, captured) = submitted_effect_values_fixture_capture(materials)
  (host, reference, request, materials, bound, captured)
}

///|
fn submitted_effect_values_fixture_capture(
  materials : @host.ClientEffectRunMaterials,
) -> (@host.PreparedClientEffectRun, @strategy.CapturedEffectRunDAG) raise {
  let bound = effect_values_work_test_ok(
    @host.bind_client_effect_compiled_run(
      materials.prepared,
      materials.allowed,
      materials.run_definition,
    ),
    "submitted.original.bound",
  )
  let (installed, values, fragment) = effect_values_work_test_bodies()
  guard @local.client_effect_local_ledger_limits(
      materials.prepared,
      installed,
      values,
      fragment,
      None,
    )
    is Some(capacity) else {
    fail("submitted original test capacity unavailable")
  }
  let captured = effect_values_work_test_ok(
    @host.open_prepared_source_free_client_effect_run(bound, capacity),
    "submitted.original.capture",
  )
  (bound, captured)
}

///|
fn submitted_effect_values_fixture_open(
  host : NativeLocalHostConnection,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  materials : @host.ClientEffectRunMaterials,
  bound : @host.PreparedClientEffectRun,
  captured : @strategy.CapturedEffectRunDAG,
  epoch_clock? : () -> Double = () => 1003.0,
) -> Result[
  NativeClientSubmittedEffectValuesWork,
  NativeClientSubmittedEffectValuesWorkFailure,
] {
  let (installed, values, fragment) = effect_values_work_test_bodies()
  host.open_submitted_effect_values_work(
    epoch_test_crypto(),
    "operator",
    "cli",
    reference,
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
    epoch_clock,
  )
}

///|
fn submitted_effect_values_fixture_opened(
  result : Result[
    NativeClientSubmittedEffectValuesWork,
    NativeClientSubmittedEffectValuesWorkFailure,
  ],
) -> NativeClientSubmittedEffectValuesWork raise {
  match result {
    Ok(work) => work
    Err(failure) => {
      let phase = match failure.issue {
        Original(_) => "Original"
        Work(_) => "Work"
      }
      failure.close() |> ignore
      fail("submitted Effect Values: " + phase)
    }
  }
}

///|
test "Native submitted Effect Values joins the saved original packet before the original first start" {
  let (host, reference, request, materials, bound, captured) = submitted_effect_values_fixture(
    "submitted-effect-values-original",
  )
  let before = host.journal.retained(request).unwrap().unwrap()
  let submitted_before = host.journal
    .retained_submission(reference)
    .unwrap()
    .unwrap()
  let packet = before.effect_material_originals.unwrap()
  let work = submitted_effect_values_fixture_open(
      host, reference, request, materials, bound, captured,
    )
    |> submitted_effect_values_fixture_opened
  assert_true(physical_equal(work.run_for_capture().unwrap(), captured))
  let after = host.journal.retained(request).unwrap().unwrap()
  assert_true(after.physical_start_claimed)
  assert_false(after.cancellation_requested)
  assert_eq(after.effect_material_originals, Some(packet))
  let submitted_after = host.journal
    .retained_submission(reference)
    .unwrap()
    .unwrap()
  assert_eq(submitted_after.revision, submitted_before.revision)
  assert_eq(
    submitted_after.run_admission.unwrap().revision,
    submitted_before.run_admission.unwrap().revision,
  )
  let pins = @strategy.pin_captured_effect_sources(captured, 1).unwrap()
  assert_eq(@strategy.captured_effect_inputs_count(pins), 1)
  assert_true(@strategy.release_captured_effect_inputs(pins))
  assert_true(work.close())
  assert_eq(work.usage().held_bytes, 0L)
  host.close().unwrap()
}

///|
test "Native submitted Effect Values refuses missing accepted packet and independent read or submit denial without backfill" {
  for (read, submit) in [(true, true), (false, true), (true, false)] {
    let (host, reference, _, request, allowed, definition, issued) = local_original_effect_material_fixture(
      "submitted-effect-values-legacy-" +
      read.to_string() +
      "-" +
      submit.to_string(),
      read,
      submit,
    )
    let materials = effect_values_work_test_ok(
      @host.bind_prepared_client_effect_original_materials(
        allowed,
        definition,
        issued,
        request=Some(request),
      ),
      "legacy.original.bind",
    )
    let (bound, captured) = submitted_effect_values_fixture_capture(materials)
    let before = run_record_body(
      host.journal.retained(request).unwrap().unwrap(),
    ).unwrap()
    let failure = submitted_effect_values_fixture_open(
      host, reference, request, materials, bound, captured,
    ).unwrap_err()
    let issue = native_client_submitted_effect_values_work_failure_issue(
      failure,
    )
    assert_true(
      if !submit {
        issue is Work(Journal(AuthorizationDenied))
      } else if !read {
        issue is Original(Journal(AuthorizationDenied))
      } else {
        issue is Original(Journal(MissingEffectMaterialOriginal))
      },
    )
    assert_true(failure.close())
    let after = host.journal.retained(request).unwrap().unwrap()
    assert_eq(run_record_body(after).unwrap(), before)
    assert_false(after.physical_start_claimed)
    assert_true(after.effect_material_originals is None)
    assert_eq(
      @resources.ledger_usage(
        @strategy.captured_dag_ledger(
          @strategy.captured_effect_run_dag(captured),
        ),
      ).attempts,
      0,
    )
    effect_values_work_test_stop(captured)
    host.close().unwrap()
  }
}

///|
test "Native submitted Effect Values rejects another nonce and foreign original selection without changing the accepted Run" {
  let (host, reference, request, materials, bound, captured) = submitted_effect_values_fixture(
    "submitted-effect-values-foreign-reference",
  )
  let before = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  let foreign = prepare_native_client_submission_reference(
    reference.epoch,
    "other-nonce",
  ).unwrap()
  let failure = submitted_effect_values_fixture_open(
    host, foreign, request, materials, bound, captured,
  ).unwrap_err()
  assert_true(failure.issue is Original(UnresolvedHistory))
  assert_true(failure.close())
  let failure = submitted_effect_values_fixture_open(
    host,
    reference,
    request,
    { ..materials, request: None, },
    bound,
    captured,
  ).unwrap_err()
  assert_true(failure.issue is Original(ChangedIntent))
  assert_true(failure.close())
  assert_eq(
    run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
    before,
  )
  assert_true(
    @strategy.captured_dag_strategy(@strategy.captured_effect_run_dag(captured))
    is None,
  )
  effect_values_work_test_stop(captured)
  host.close().unwrap()
}

///|
test "Native submitted Effect Values observes original packet loss after Compute and never fills it or repeats the claim" {
  let (host, reference, request, materials, bound, captured) = submitted_effect_values_fixture(
    "submitted-effect-values-lost-packet",
  )
  let lose : Ref[Bool] = Ref(false)
  let work = submitted_effect_values_fixture_open(
      host,
      reference,
      request,
      materials,
      bound,
      captured,
      epoch_clock=() => {
        if lose.val {
          lose.val = false
          // Deliberate loss in this new disposable DB only, not a production
          // transition or a post-accept repair. The original claim must survive.
          host.journal
          .transaction(() => {
            let record = host.journal.retained(request).unwrap().unwrap()
            host.journal
            .save({ ..record, effect_material_originals: None, })
            .map(_ => ())
          })
          .unwrap()
        }
        1003.0
      },
    )
    |> submitted_effect_values_fixture_opened
  lose.val = true
  assert_true(
    work.run_for_capture()
    is Err(Original(Journal(MissingEffectMaterialOriginal))),
  )
  let after = host.journal.retained(request).unwrap().unwrap()
  assert_true(after.physical_start_claimed)
  assert_true(after.effect_material_originals is None)
  assert_false(host.journal.claim_physical_start(request, true).unwrap())
  assert_true(work.close())
  host.close().unwrap()
}

///|
test "Native submitted Effect Values capture checks the original cleanup lifetime after its final clock callback" {
  let (host, reference, request, materials, bound, captured) = submitted_effect_values_fixture(
    "submitted-effect-values-clock-retirement",
  )
  let original : Ref[NativeClientSubmittedEffectValuesWork?] = Ref(None)
  let work = submitted_effect_values_fixture_open(
      host,
      reference,
      request,
      materials,
      bound,
      captured,
      epoch_clock=() => {
        if original.val is Some(work) {
          work.close() |> ignore
        }
        1003.0
      },
    )
    |> submitted_effect_values_fixture_opened
  original.val = Some(work)
  assert_true(work.run_for_capture() is Err(Work(Unavailable)))
  assert_true(work.close())
  original.val = None
  host.close().unwrap()
}

///|
// This pure priority check is not a successful current Host observation.
test "Native submitted Effect Values preserves original custody refusal while denying terminal Submit loss" {
  assert_true(
    submitted_effect_values_current_result(Err(Journal(CustodyLost)), false)
    is Err(Original(Journal(CustodyLost))),
  )
  assert_true(
    submitted_effect_values_current_result(
      Err(Journal(MissingEffectMaterialOriginal)),
      true,
    )
    is Err(Original(Journal(MissingEffectMaterialOriginal))),
  )
  assert_true(
    submitted_effect_values_current_result(Ok(()), false)
    is Err(Work(AuthorizationDenied)),
  )
}
