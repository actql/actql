///|
fn egress_fixture_observation() -> @publication_host.ClientInferEgressObservation {
  {
    classification: @environment.Public,
    region: "fixture-region",
    provider_retention: false,
    training_use: false,
  }
}

///|
test "egress admission rejects incompatible observations before any work" {
  let observed = egress_fixture_observation()
  for
    (observation, expected) in [
      (None, @publication_host.MissingObservation),
      (
        Some({ ..observed, classification: @environment.Unknown, }),
        @publication_host.UnknownClassification,
      ),
      (
        Some({ ..observed, classification: @environment.Restricted, }),
        @publication_host.ClassificationDenied,
      ),
      (
        Some({ ..observed, region: "other-region", }),
        @publication_host.RegionDenied,
      ),
      (
        Some({ ..observed, provider_retention: true, }),
        @publication_host.RetentionDenied,
      ),
      (
        Some({ ..observed, training_use: true, }),
        @publication_host.TrainingDenied,
      ),
    ] {
    let calls = Ref(0)
    let active = contract_capacity_start(calls, 2, 133072L)
    let execution = @publication_host.client_infer_plan_graph_execution_contract(
      active.plan.unwrap(),
    )
    assert_true(
      @publication_host.admit_prepared_client_infer_egress(
        active.prepared.unwrap(),
        2,
        execution,
        () => observation,
      )
      is Err(actual) &&
      actual == expected,
    )
    assert_eq(active.work, 0L)
    assert_eq(calls.val, 0)
    assert_true(cancel(active))
    assert_true(fixture_finish(active) is Stopped(_))
    assert_true(cleanup(active).unwrap())
  }
}

///|
test "egress admission binds the exact prepared owner and selected contract" {
  let calls = Ref(0)
  let active = contract_capacity_start(calls, 2, 133072L)
  let execution = @publication_host.client_infer_plan_graph_execution_contract(
    active.plan.unwrap(),
  )
  let admission = @publication_host.admit_prepared_client_infer_egress(
    active.prepared.unwrap(),
    2,
    execution,
    () => Some(egress_fixture_observation()),
  ).unwrap()
  let foreign = contract_capacity_start(calls, 2, 133072L)
  assert_true(
    bind_egress_admission(foreign, admission)
    is Err(Model(@model.Egress(@publication_host.ForeignOwner))),
  )
  bind_egress_admission(active, admission).unwrap()
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_eq(calls.val, 2)
  assert_true(cleanup(active).unwrap())
  assert_true(cancel(foreign))
  assert_true(fixture_finish(foreign) is Stopped(_))
  assert_true(cleanup(foreign).unwrap())
}

///|
test "changed egress after physical preparation refuses dispatch and releases reservations" {
  let calls = Ref(0)
  let active = contract_capacity_start(calls, 2, 133072L)
  let events = []
  physical_preflight_fixture(active, events)
  let observed = Ref(Some(egress_fixture_observation()))
  let execution = @publication_host.client_infer_plan_graph_execution_contract(
    active.plan.unwrap(),
  )
  let admission = @publication_host.admit_prepared_client_infer_egress(
    active.prepared.unwrap(),
    2,
    execution,
    () => observed.val,
  ).unwrap()
  bind_egress_admission(active, admission).unwrap()
  let mut last_work = 0L
  for _ in 0..<2000 {
    guard advance(active, 1).unwrap() is Continue(work~) else {
      abort("dispatch must not precede physical preflight completion")
    }
    last_work = work
    if events.length() == 8 {
      break
    }
  }
  assert_eq(events.length(), 8)
  assert_eq(calls.val, 0)
  observed.val = Some({
    ..egress_fixture_observation(),
    region: "changed-region",
  })
  assert_true(
    fixture_finish(active, initial_work=last_work)
    is Failed(Model(@model.Egress(@publication_host.ChangedObservation)), ..),
  )
  assert_true(acquire_output(active) is None)
  assert_true(acquire_capture(active) is None)
  assert_eq(calls.val, 0)
  let model = active.model.unwrap()
  assert_eq(@model.model_execution_quantity_usage(model).uncertain.tokens, 0L)
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(@model.model_execution_quantity_usage(model).reserved.tokens, 0L)
  let resources = @model.model_execution_resource_usage(model)
  assert_eq(resources.reserved_transfer_bytes, 0L)
  assert_eq(resources.reserved_execution_bytes, 0L)
  assert_eq(resources.reserved_retention_bytes, 0L)
  assert_eq(calls.val, 0)
}
