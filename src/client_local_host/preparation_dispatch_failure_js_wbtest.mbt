///|
fn original_dispatch_failure_fixture(
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  ClientInstalledManagedRun,
  ClientOriginalExplanationCapture,
  @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) raise {
  let (parent, run, prepared, compiled, definition) = original_explanation_capture_fixture(
    current~,
  )
  let capture = capture_installed_managed_run_explanation(
    run, prepared, compiled, definition, 65536, 8192, 64,
  ).unwrap()
  let plan = run.source_free_preparation.unwrap()
  let host = open_installed_managed_source_free_host(
      run,
      prepared,
      run.request,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
      true,
    )
    .unwrap()
    .unwrap()
  (parent, run, capture, host)
}

///|
fn original_dispatch_reject(
  parent : ClientRequestPreparation[Array[Int]],
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> Unit raise {
  let usage = @resources.ledger_usage(parent.ledger)
  let limits = @resources.ledger_limits(parent.ledger)
  // Real same-Ledger pressure at the actual adaptive selection. Release only
  // this fixture's pressure afterwards; the report remains that original
  // refusal, never a later ledger sample or a manufactured policy failure.
  let pressure = @resources.reserve_capacity(
    parent.ledger,
    0L,
    limits.execution_bytes - usage.reserved_execution_bytes,
  ).unwrap()
  let result = @host_driver.prepare_next_compute_task(
    @builtin.configured_host_runtime(host),
    (),
  )
  assert_true(result is Err(Estimate(NoStrategy)))
  @resources.settle_capacity(parent.ledger, pressure).unwrap() |> ignore
}

///|
#external
priv type OriginalDispatchLoader

///|
#module("node:module")
extern "js" fn original_dispatch_loader(url : String) -> OriginalDispatchLoader = "createRequire"

///|
extern "js" fn original_dispatch_test_url() -> String =
  #|() => import.meta.url

///|
extern "js" fn original_dispatch_imported_consumer(
  loader : OriginalDispatchLoader,
  original : (
    String,
    String,
    Int,
    Int,
    Bool,
    Bool,
    Array[(Int, String?)],
    String,
  )?,
) -> Bool =
  #|(load, original) => {
  #| const {rememberOriginalDispatchFailure: remember, originalDispatchFailureSnapshot: read} = load('../../../../../adapters/host-common/dispatch-failure-observation.mjs');
  #| const error = new Error('same-original-dispatch');
  #| remember(error, original);
  #| const first = read(error), second = read(error);
  #| return first !== undefined && first === second && Object.isFrozen(first) &&
  #|   first.primaryDiagnostic.kind === 'no_strategy' &&
  #|   first.primaryDiagnostic.decision === 'unavailable' &&
  #|   first.primaryDiagnostic.candidateCount === 'unavailable' &&
  #|   first.primaryDiagnostic.assessments.some(a => a.rejection === 'execution_limit') &&
  #|   read(new Error('copied')) === undefined;
  #| }

///|
test "original adaptive refusal projects bounded same-owner DATA after payload ACK and imported JS consumes actual tuple" {
  let (parent, run, capture, host) = original_dispatch_failure_fixture()
  acknowledge_installed_original_explanation_capture(capture).unwrap()
  assert_true(capture.plan_view is None && capture.facts is None)
  assert_true(capture.original is Some(_))
  assert_eq(
    observe_installed_original_dispatch_failure(capture, host),
    Ok(None),
  )
  assert_false(capture.dispatch_failure_observed)
  original_dispatch_reject(parent, host)
  let before = @resources.preparation_body_borrow_reserved_extents(
    capture.holder,
  ).unwrap()
  let original = observe_installed_original_dispatch_failure(capture, host).unwrap()
  let view = original.unwrap()
  assert_eq(view.0, "adaptive_dispatch")
  assert_eq(view.1, "no_strategy")
  assert_eq(view.7, "unavailable")
  assert_true(view.6.length() <= 8)
  assert_eq(view.5, view.3 > 8)
  let captured = run.source_free_captured.unwrap()
  assert_eq(view.3, @strategy.strategy_report_count(captured))
  for index = 0; index < view.6.length(); index = index + 1 {
    let assessment = @strategy.strategy_report_at(captured, index).unwrap()
    assert_eq(view.6[index].0, assessment.position)
    assert_eq(
      view.6[index].1,
      @strategy.strategy_assessment_rejection_code(assessment),
    )
  }
  // Independent adopted H16/R8/W8 census: fixed H12/R17/W12=424,
  // per-item H3/R5/W3=112; this includes both original and Node DATA arrays.
  let expected = 424L + 112L * view.6.length().to_int64()
  let after = @resources.preparation_body_borrow_reserved_extents(
    capture.holder,
  ).unwrap()
  assert_eq(after, (before.0 + expected, before.1 + expected))
  assert_true(
    original_dispatch_imported_consumer(
      original_dispatch_loader(original_dispatch_test_url()),
      original,
    ),
  )
  assert_eq(
    observe_installed_original_dispatch_failure(capture, host),
    Ok(None),
  )
  assert_eq(
    @resources.preparation_body_borrow_reserved_extents(capture.holder),
    Ok(after),
  )
  assert_true(
    @host_driver.prepare_next_compute_task(
      @builtin.configured_host_runtime(host),
      (),
    )
    is Err(Estimate(NoStrategy)),
  )
  return_installed_original_explanation_capture(capture).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "original failure observation refuses foreign current retired and one-short without retry or refund" {
  for one_short in [false, true] {
    let current = Ref(true)
    let (parent, run, capture, host) = original_dispatch_failure_fixture(current=() => {
      current.val
    })
    let (foreign_parent, foreign_run, foreign_capture, foreign_host) = original_dispatch_failure_fixture()
    original_dispatch_reject(parent, host)
    assert_eq(
      observe_installed_original_dispatch_failure(capture, foreign_host),
      Ok(None),
    )
    assert_false(capture.dispatch_failure_observed)
    let holder = capture.holder
    let before = @resources.preparation_body_borrow_reserved_extents(holder).unwrap()
    let count = Int::min(
      8,
      @strategy.strategy_report_count(run.source_free_captured.unwrap()),
    )
    let extra = 424L + 112L * count.to_int64()
    let mut pressure = None
    if one_short {
      let usage = @resources.ledger_usage(parent.ledger)
      let limits = @resources.ledger_limits(parent.ledger)
      pressure = Some(
        @resources.reserve_capacity(
          parent.ledger,
          0L,
          limits.execution_bytes - usage.reserved_execution_bytes - extra + 1L,
        ).unwrap(),
      )
    } else {
      current.val = false
    }
    assert_true(
      observe_installed_original_dispatch_failure(capture, host) is Err(_),
    )
    assert_true(capture.dispatch_failure_observed)
    assert_eq(
      @resources.preparation_body_borrow_reserved_extents(holder),
      Ok(before),
    )
    current.val = true
    if pressure is Some(value) {
      @resources.settle_capacity(parent.ledger, value).unwrap() |> ignore
    }
    assert_eq(
      observe_installed_original_dispatch_failure(capture, host),
      Ok(None),
    )
    return_installed_original_explanation_capture(capture).unwrap() |> ignore
    assert_eq(
      observe_installed_original_dispatch_failure(capture, host),
      Ok(None),
    )
    retire_installed_managed_run(run).unwrap()
    @strategy.stop_captured_dag(foreign_run.source_free_captured.unwrap())
    return_installed_original_explanation_capture(foreign_capture).unwrap()
    |> ignore
    retire_installed_managed_run(foreign_run).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    assert_eq(
      @resources.ledger_usage(foreign_parent.ledger).live_reservations,
      0,
    )
  }
}
