///|
let native_driver_program : String =
  #|{"version":"actql/0.1","id":"native-driver","params":{"n":{"type":"number","default":7}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"id":1,"label":"日本語😀"}]},"as":"seed"},{"derive":{"value":"id + $n"},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","label","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}

///|
fn native_driver_parent(
  text : String,
) -> (ClientRequestPreparation[Array[Int]], Array[Int]) {
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  // Conservative actual-capture envelope for this component. The distinct
  // Node manager case observes the SDK's own supplied snapshot quantities.
  reserve_request_snapshot(
    parent,
    input,
    text.length().to_int64() + 32L,
    text.length().to_int64() + 32L,
  ).unwrap()
  (parent, input)
}

///|
test "normal Native driver keeps original supplied Parameters Text compiler module and Run" {
  let (environment, publication) = request_query_publication_fixture()
  for supplied in [false, true] {
    let (parent, input) = native_driver_parent(native_driver_program)
    assert_eq(
      prepare_request_native_computation(
        parent,
        input,
        request_native_test_value(native_driver_program),
        native_json_reader,
        environment,
        publication,
        [],
        @publication_host.client_standard_program_preparation_limits(),
        @publication_host.client_standard_effect_computation_limits(),
        supplied=if supplied {
          Some(request_native_test_value("{\"n\":9}"))
        } else {
          None
        },
      ).unwrap(),
      Pure,
    )
    let prepared = parent.compiled_program.unwrap()
    let cursor = request_preparation_parameters_original(parent, input).unwrap()
    if supplied {
      assert_true(cursor is Some(_))
    } else {
      assert_true(cursor is None)
    }
    let before = @resources.ledger_usage(parent.ledger)
    assert_true(
      prepare_request_native_computation(
        parent,
        input,
        request_native_test_value(native_driver_program),
        native_json_reader,
        environment,
        publication,
        [],
        @publication_host.client_standard_program_preparation_limits(),
        @publication_host.client_standard_effect_computation_limits(),
      )
      is Err(Preparation(WrongPhase)),
    )
    assert_eq(@resources.ledger_usage(parent.ledger), before)
    prepare_request_program_module_body(
      parent,
      input,
      request_program_module_contracts(),
      retained_output=true,
      provider_factory=_ => [],
    ).unwrap()
    let holder = borrow_request_program_preparation(parent).unwrap()
    assert_true(
      physical_equal(
        @resources.preparation_body_borrow_value(holder).unwrap(),
        prepared,
      ),
    )
    let plan = parent.program_source_free.unwrap()
    let request = @publication_host.prepare_source_free_client_request_identity(
      prepared,
      "sha256:" + "a".repeat(64),
      "native-driver",
    ).unwrap()
    let run = begin_request_program_managed_run(parent, request).unwrap()
    let setup = open_installed_managed_source_free_host(
        run,
        prepared,
        request,
        plan.installed_contracts,
        plan.values_body,
        plan.fragment_body,
        plan.ordered_body,
        true,
      )
      .unwrap()
      .unwrap()
    let output = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
      true
    }).unwrap()
    assert_eq(
      output.rows().unwrap(),
      if supplied {
        ["{\"id\":1,\"label\":\"日本語😀\",\"value\":10}"]
      } else {
        ["{\"id\":1,\"label\":\"日本語😀\",\"value\":8}"]
      },
    )
    assert_true(output.close())
    assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
    @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
    retire_installed_managed_run(run).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "normal Native driver preserves the original typed rejected check and pending parent cleanup" {
  let (environment, publication) = request_query_publication_fixture()
  let text = request_check_wire.replace(old="\"take\":1", new="\"take\":-1")
  let (parent, input) = native_driver_parent(text)
  assert_true(
    prepare_request_native_computation(
      parent,
      input,
      request_native_test_value(text),
      native_json_reader,
      environment,
      publication,
      [],
      @publication_host.client_standard_program_preparation_limits(),
      @publication_host.client_standard_effect_computation_limits(),
    )
    is Err(CheckOutcome(_)),
  )
  assert_true(parent.compiled_program is None && parent.compiled_effect is None)
  let work = @resources.ledger_usage(parent.ledger).planning_work
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).planning_work, work)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "normal Native driver keeps the original Effect branch and its native Parameter cursor" {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let text =
    #|{"version":"actql/0.1","id":"native-effect","params":{"n":{"type":"number","default":7}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"derive":{"amount":"id + $n"},"as":"changed"}],"results":{"rows":{"from":"changed","fields":["id","amount"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"amount"}}}}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  let (parent, input) = native_driver_parent(text)
  assert_eq(
    prepare_request_native_computation(
      parent,
      input,
      request_native_test_value(text),
      native_json_reader,
      environment,
      publication,
      [],
      @publication_host.client_standard_program_preparation_limits(),
      @publication_host.client_standard_effect_computation_limits(),
      supplied=Some(request_native_test_value("{\"n\":9}")),
    ).unwrap(),
    Effect,
  )
  let cursor = request_preparation_parameters_original(parent, input)
    .unwrap()
    .unwrap()
  assert_true(physical_equal(cursor, parent.native_parameters.unwrap()))
  assert_true(
    parent.compiled_effect is Some(_) && parent.compiled_program is None,
  )
  let holder = borrow_request_effect_plan_input(parent, input).unwrap()
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(holder).unwrap(),
      parent.compiled_effect.unwrap(),
    ),
  )
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
  )
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
