///|
fn effect_serialization_prefix_fixture(
  preserve? : Bool = false,
) -> @publication_host.PreparedClientEffectComputation raise {
  let (_, environment, limits) = local_effect_export_fixture()
  let document =
    #|{"version":"actql/0.1","id":"effect-prefix-original-input","stages":[{"id":"capture","inputs":{},"steps":[{"values":{"schema":{"value":{"type":"number","nullable":false}},"rows":[{"value":2},{"value":1}]},"as":"original"}],"results":{"out":{"from":"original","fields":["value"]}}},{"id":"save","inputs":{"original":{"result":{"stage":"capture","result":"out"}}},"steps":[{"filter":"value > 0"},{"select":["value"]},{"assert_rows":{"unique_by":["value"]}},{"serialize":{"format":"jsonl","fields":["value"],"order_by":[{"value":"asc"}],"name":"out.jsonl","bounds":{"max_rows":2,"max_bytes":32}},"as":"attachment"},{"derive":{"value":"row_count"}},{"select":["value"],"as":"statistics"}],"results":{"out":{"from":"statistics","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"published":{"from":{"stage":"save","result":"out"}}}}
  let document = if preserve {
    document.replace(
      old="{\"serialize\":{\"format\":\"jsonl\",\"fields\":[\"value\"],\"order_by\":[{\"value\":\"asc\"}]",
      new="{\"sort\":[{\"value\":\"desc\"}]},{\"serialize\":{\"format\":\"jsonl\",\"fields\":[\"value\"],\"preserve_order\":true",
    )
  } else {
    document
  }
  match
    @publication_host.prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      limits,
    ) {
    Ok(value) => value
    Err(Candidate(Computation(issue))) => raise issue
    Err(Syntax(_)) => fail("Effect serialization fixture syntax failed")
    Err(Candidate(_)) =>
      fail("Effect serialization fixture candidate binding failed")
    Err(Mapping(_)) => fail("Effect serialization fixture mapping failed")
    Err(Static(_)) => fail("Effect serialization fixture static Effect failed")
    Err(Stage(_)) =>
      fail("Effect serialization fixture Stage preparation failed")
    Err(Graph(_)) =>
      fail("Effect serialization fixture Graph preparation failed")
    Err(TargetSelection(_)) =>
      fail("Effect serialization fixture target selection failed")
    Err(RequestValuePolicies(_)) =>
      fail("Effect serialization fixture request value policies failed")
    Err(RequestValuePolicyConstruction) =>
      fail(
        "Effect serialization fixture request value policy construction failed",
      )
  }
}

///|
fn effect_prefix_complete(
  execution : @local_connector.ManagedProviderExecution,
  quantum : Int,
) -> @execution.CompletedOutput raise {
  for _ in 0..<10000 {
    match
      @local_connector.advance_managed_provider(execution, quantum).unwrap() {
      Complete(output, ..) => return output
      Continue(..) => ()
      _ => fail("Original bounded Effect prefix did not complete")
    }
  }
  fail("Original bounded Effect prefix exceeded its diagnostic deadline")
}

///|
test "Effect Content prefix consumes the original DAG input and ordered completion without another Program" {
  let prepared = effect_serialization_prefix_fixture()
  let (registry, values, fragment, ordered) = acquired_serialization_contracts()
  let graph = @strategy.checked_effect_computation_graph(
    @publication_host.prepared_client_effect_computation_graph(prepared),
  )
  assert_eq(@strategy.graph_task_count(graph), 2)
  assert_eq(
    @publication_host.prepared_client_effect_serialization_occurrences(prepared),
    [(1, 3)],
  )
  let full = @client_local_host.prepare_client_effect_local_sequences(
    prepared, registry, values, fragment, ordered,
  ).unwrap()
  let prefix = @client_local_host.prepare_client_effect_serialization_prefix(
    prepared, 1, 3, registry, values, fragment, ordered,
  ).unwrap()
  let owner = @strategy.graph_task_owner(graph, 1).unwrap()
  assert_true(
    physical_equal(@execution.generated_sequence_owner(prefix), owner),
  )
  assert_true(
    physical_equal(@execution.generated_sequence_owner(full[1]), owner),
  )
  assert_true(
    @execution.generated_sequence_step_at(full[1], 3)
    is Some(@lower.SerializationBoundary(3)),
  )
  let barrier = @publication_host.prepare_client_effect_serialization(
    prepared,
    1,
    3,
    max_work=10000,
  ).unwrap()
  assert_true(physical_equal(@lower.serialization_owner(barrier), owner))
  let dispatch = dispatch_test_limits()
  assert_true(
    @local_connector.local_bounded_relation_provider(
      dispatch.local_execution,
      dispatch.guards,
      full[1],
    )
    is None,
  )
  let source_provider = @local_connector.local_bounded_relation_provider(
    dispatch.local_execution,
    dispatch.guards,
    full[0],
  ).unwrap()
  let source = @local_connector.start_managed_provider_with_execution(
    source_provider,
    full[0],
    [],
    100,
    10000,
    dispatch.local_execution,
  ).unwrap()
  let input_live = Ref(true)
  let original = @execution.restrict_completed_output(
    effect_prefix_complete(source, 1),
    () => input_live.val,
  )
  let bound = @execution.bind_completed_input(
    owner,
    0,
    @execution.generated_sequence_owner(full[0]),
    original,
  ).unwrap()
  let read = @execution.prepare_producer_read(owner, bound, 10000, 10000).unwrap()
  let provider = @local_connector.local_bounded_relation_provider(
    dispatch.local_execution,
    dispatch.guards,
    prefix,
  ).unwrap()
  assert_true(
    @local_connector.managed_provider_capacity(provider, prefix) is Some(_),
  )
  let child = @local_connector.start_managed_provider_with_execution(
    provider,
    prefix,
    [read],
    100,
    10000,
    dispatch.local_execution,
  ).unwrap()
  let output = effect_prefix_complete(child, 1)
  // A compiler-owned private sort is not the Content metadata output. Its
  // existing sort witness verifies the exact original owner and coordinate;
  // ordinary Stage port/provenance APIs must not promote it to public output.
  assert_false(
    @execution.completed_output_matches_port(output, owner, @pipeline.Step(3)),
  )
  let foreign_prepared = effect_serialization_prefix_fixture()
  let foreign = @strategy.graph_task_owner(
    @strategy.checked_effect_computation_graph(
      @publication_host.prepared_client_effect_computation_graph(
        foreign_prepared,
      ),
    ),
    1,
  ).unwrap()
  assert_false(
    @execution.completed_output_matches_port(output, foreign, @pipeline.Step(3)),
  )
  assert_true(
    @execution.bind_completed_input(owner, 0, foreign, original) is Err(_),
  )
  assert_false(
    @execution.completed_output_matches_serialization_sort(
      output,
      @publication_host.prepare_client_effect_serialization(
        foreign_prepared,
        1,
        3,
        max_work=10000,
      ).unwrap(),
    ),
  )
  assert_true(
    @execution.completed_output_matches_serialization_sort(output, barrier),
  )
  assert_eq(
    @execution.completed_output_row_wire(output, 0, 1000, 100, 10).unwrap(),
    "{\"value\":1}",
  )
  assert_eq(
    @execution.completed_output_row_wire(output, 1, 1000, 100, 10).unwrap(),
    "{\"value\":2}",
  )
  assert_true(
    @local_connector.managed_provider_cumulative_work(child).unwrap() > 0L,
  )
  assert_true(@local_connector.cleanup_managed_provider(child).unwrap())
  // Prefix cleanup never reclaims the borrowed original producer.
  assert_true(@execution.completed_output_available(original))
  assert_true(@execution.producer_read_available(read))
  // A separate diagnostic attempt stops after positive work. It borrows the
  // same live producer rather than creating or acquiring another Source.
  let cancelled = @local_connector.start_managed_provider_with_execution(
    provider,
    prefix,
    [read],
    100,
    10000,
    dispatch.local_execution,
  ).unwrap()
  assert_true(
    @local_connector.advance_managed_provider(cancelled, 1).unwrap()
    is Continue(..),
  )
  let work_before_stop = @local_connector.managed_provider_cumulative_work(
    cancelled,
  ).unwrap()
  assert_true(work_before_stop > 0L)
  assert_true(@local_connector.cancel_managed_provider(cancelled))
  let mut stopped = false
  for _ in 0..<10000 {
    match @local_connector.advance_managed_provider(cancelled, 1).unwrap() {
      Stopped(..) => {
        stopped = true
        break
      }
      Continue(..) => ()
      _ =>
        fail(
          "Cancelled Effect prefix published a result or lost stop responsibility",
        )
    }
  }
  assert_true(stopped)
  assert_true(
    @local_connector.managed_provider_cumulative_work(cancelled).unwrap() >=
    work_before_stop,
  )
  assert_true(@local_connector.cleanup_managed_provider(cancelled).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(cancelled).unwrap())
  assert_true(@execution.producer_read_available(read))
  assert_true(@local_connector.cleanup_managed_provider(source).unwrap())
  // Source scratch cleanup does not revoke transferred output custody.
  assert_true(@execution.producer_read_available(read))
  input_live.val = false
  assert_false(@execution.producer_read_available(read))
  assert_true(
    @client_local_host.prepare_client_effect_serialization_prefix(
      prepared, 0, 3, registry, values, fragment, ordered,
    )
    is None,
  )
  assert_true(
    @client_local_host.prepare_client_effect_serialization_prefix(
      prepared, 1, 2, registry, values, fragment, ordered,
    )
    is None,
  )
}
