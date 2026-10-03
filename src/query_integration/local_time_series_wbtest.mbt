///|
fn local_time_series_owner(body : String) -> @lower.BoundPrepared {
  let checked = @pipeline.check(
    input_cursor("[{\"time_series\":" + body + ",\"as\":\"ticks\"}]"),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn local_time_series_generated(
  body : String,
) -> @execution.GeneratedSequence raise {
  compute_test_sequence(local_time_series_owner(body))
}

///|
fn local_time_series_provider(
  generated : @execution.GeneratedSequence,
) -> @local_connector.ManagedProvider {
  @local_tea_provider.time_series_provider(
    carrier_events_storage_limits(),
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
}

///|
fn local_time_series_program() -> String {
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":" +
  "{\"minimum\":{\"type\":\"number\",\"nullable\":false}}," +
  "\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":{" +
  "\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{" +
  "\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{" +
  "\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{" +
  "\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}},{" +
  "\"id\":\"series\",\"inputs\":{},\"steps\":[{" +
  "\"time_series\":{\"start\":\"1969-12-31T23:59:59.999Z\"," +
  "\"end\":\"1970-01-01T00:00:00.004Z\",\"step\":2}," +
  "\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":[\"time\"]}}},{\"id\":\"consumer_a\",\"inputs\":{" +
  "\"x\":{\"result\":{\"stage\":\"series\",\"result\":\"r\"}}}," +
  "\"steps\":[{\"select\":[\"time\"],\"as\":\"out\"}]," +
  "\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"time\"]}}},{" +
  "\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"series\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":[\"time\"],\"as\":\"out\"}],\"results\":{\"r\":{" +
  "\"from\":\"out\",\"fields\":[\"time\"]}}}],\"results\":{" +
  "\"source\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}"
}

///|
test "registered time-series provider emits a bounded UTC grid" {
  let generated = local_time_series_generated(
    "{\"start\":\"1969-12-31T23:59:59.999Z\",\"end\":\"1970-01-01T00:00:00.004Z\",\"step\":2}",
  )
  let provider = local_time_series_provider(generated)
  assert_true(@local_connector.managed_provider_accepts(provider, generated))
  assert_true(
    @local_connector.start_managed_provider_with_execution(
      provider,
      generated,
      [],
      2,
      1000,
      dispatch_test_limits().local_execution,
    )
    is Err(_),
  )
  let execution = @local_connector.start_managed_provider_with_execution(
    provider,
    generated,
    [],
    3,
    1000,
    dispatch_test_limits().local_execution,
  ).unwrap()
  let mut output = None
  let mut advances = 0
  while output is None {
    advances += 1
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_eq(work, 1L)
      @local_connector.Complete(value, work~, ..) => {
        assert_eq(work, 1L)
        output = Some(value)
      }
      @local_connector.CarrierComplete(_, ..) =>
        fail("time-series provider returned a Carrier output")
      @local_connector.Failed(_, ..) => fail("time-series provider failed")
      @local_connector.Stopped(..) => fail("time-series provider stopped")
    }
  }
  let completed = output.unwrap()
  assert_eq(advances, 4)
  assert_eq(@execution.completed_row_count(completed), 3)
  let expected_rows = [
    "1969-12-31T23:59:59.999Z", "1970-01-01T00:00:00.001Z", "1970-01-01T00:00:00.003Z",
  ]
  for row, expected in expected_rows {
    assert_true(
      @execution.completed_cell(completed, row, 0)
      is Some(@execution.Captured(@admitted.Timestamp(actual))) &&
      actual == expected,
    )
  }
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
  assert_true(@execution.completed_output_available(completed))
}

///|
test "time-series output value work admits exact and one-short limits" {
  // Each row costs one row node, four field-name bytes, one value node,
  // and 24 timestamp bytes: three rows require 3 * 30 work units.
  let generated = local_time_series_generated(
    "{\"start\":\"1969-12-31T23:59:59.999Z\",\"end\":\"1970-01-01T00:00:00.004Z\",\"step\":2}",
  )
  let capacity = @execution.generated_sequence_capacity(
    generated,
    dispatch_test_limits().local_execution,
    dispatch_test_limits().guards,
  ).unwrap()
  let accepted = @local_connector.start_managed_provider_with_execution(
    @local_tea_provider.time_series_provider(
      { ..carrier_events_storage_limits(), max_work: 90, },
      capacity,
    ),
    generated,
    [],
    3,
    1000,
    dispatch_test_limits().local_execution,
  ).unwrap()
  let mut completed = false
  for _ in 0..<4 {
    match @local_connector.advance_managed_provider(accepted, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_eq(work, 1L)
      @local_connector.Complete(value, work~, ..) => {
        assert_eq(work, 1L)
        assert_eq(@execution.completed_row_count(value), 3)
        completed = true
      }
      _ => fail("exact value-work ceiling rejected time series")
    }
  }
  assert_true(completed)
  assert_true(@local_connector.managed_provider_stopped(accepted))
  assert_true(
    @local_connector.cleanup_managed_provider(accepted).unwrap_or(false),
  )

  let rejected = @local_connector.start_managed_provider_with_execution(
    @local_tea_provider.time_series_provider(
      { ..carrier_events_storage_limits(), max_work: 89, },
      capacity,
    ),
    generated,
    [],
    3,
    1000,
    dispatch_test_limits().local_execution,
  ).unwrap()
  let mut failed = false
  for _ in 0..<4 {
    if !failed {
      match @local_connector.advance_managed_provider(rejected, 1).unwrap() {
        @local_connector.Continue(work~, ..) => assert_eq(work, 1L)
        @local_connector.Failed(_, ..) => failed = true
        @local_connector.Complete(_, ..) =>
          fail("one-short value-work ceiling published time series")
        _ => fail("one-short value-work ceiling did not fail")
      }
    }
  }
  assert_true(failed)
  assert_true(@local_connector.managed_provider_stopped(rejected))
  assert_true(
    @local_connector.cleanup_managed_provider(rejected).unwrap_or(false),
  )
}

///|
test "time-series control work admits exact and one-short limits" {
  // Three emitted rows and one finalization step require four work units.
  let generated = local_time_series_generated(
    "{\"start\":\"1969-12-31T23:59:59.999Z\",\"end\":\"1970-01-01T00:00:00.004Z\",\"step\":2}",
  )
  let provider = local_time_series_provider(generated)
  let limits = dispatch_test_limits().local_execution
  assert_true(
    @local_connector.start_managed_provider(provider, generated, [], 3, 1000)
    is Err(_),
  )
  assert_true(
    @local_connector.start_managed_provider_with_execution(
      provider,
      generated,
      [],
      3,
      1000,
      { ..limits, max_work: 3, },
    )
    is Err(_),
  )
  let execution = @local_connector.start_managed_provider_with_execution(
    provider,
    generated,
    [],
    3,
    1000,
    { ..limits, max_work: 4, },
  ).unwrap()
  let mut completed = false
  for _ in 0..<4 {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_eq(work, 1L)
      @local_connector.Complete(value, work~, ..) => {
        assert_eq(work, 1L)
        assert_eq(@execution.completed_row_count(value), 3)
        completed = true
      }
      _ => fail("exact control-work ceiling rejected time series")
    }
  }
  assert_true(completed)
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
}

///|
test "time-series schema workspace admits exact and one-short limits" {
  // The output schema has exactly one name entry; rows and value bytes have
  // separate ceilings on the same admitted builder.
  let generated = local_time_series_generated(
    "{\"start\":\"1969-12-31T23:59:59.999Z\",\"end\":\"1970-01-01T00:00:00.004Z\",\"step\":2}",
  )
  let capacity = @execution.generated_sequence_capacity(
    generated,
    dispatch_test_limits().local_execution,
    dispatch_test_limits().guards,
  ).unwrap()
  assert_true(
    @local_connector.start_managed_provider_with_execution(
      @local_tea_provider.time_series_provider(
        { ..carrier_events_storage_limits(), max_workspace_slots: 0, },
        capacity,
      ),
      generated,
      [],
      3,
      1000,
      dispatch_test_limits().local_execution,
    )
    is Err(_),
  )
  let execution = @local_connector.start_managed_provider_with_execution(
    @local_tea_provider.time_series_provider(
      { ..carrier_events_storage_limits(), max_workspace_slots: 1, },
      capacity,
    ),
    generated,
    [],
    3,
    1000,
    dispatch_test_limits().local_execution,
  ).unwrap()
  let mut completed = false
  for _ in 0..<4 {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_eq(work, 1L)
      @local_connector.Complete(value, work~, ..) => {
        assert_eq(work, 1L)
        assert_eq(@execution.completed_row_count(value), 3)
        completed = true
      }
      _ => fail("exact schema-workspace ceiling rejected time series")
    }
  }
  assert_true(completed)
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
}

///|
test "time-series cancellation stops before cleanup" {
  let generated = local_time_series_generated(
    "{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.050Z\",\"step\":1}",
  )
  let execution = @local_connector.start_managed_provider_with_execution(
    local_time_series_provider(generated),
    generated,
    [],
    10000,
    1000,
    dispatch_test_limits().local_execution,
  ).unwrap()
  assert_true(
    @local_connector.advance_managed_provider(execution, 1).unwrap()
    is @local_connector.Continue(progress=1L, work=1L),
  )
  assert_true(@local_connector.cancel_managed_provider(execution))
  assert_true(
    @local_connector.advance_managed_provider(execution, 1).unwrap()
    is @local_connector.Stopped(progress=0L, work=0L),
  )
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
}

///|
test "standard Host runs time series with two retained consumers" {
  let (run, issuer) = captured_graph_fixture(
    local_time_series_chain=true,
    managed_publication=true,
  )
  assert_true(
    @strategy.configure_captured_managed_identity_policy(
      run, true, false, false, false,
    ),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
  let cleanup_attempts = Ref(0)
  let provider = delayed_cleanup_provider(
    local_time_series_provider(sequences[0]),
    cleanup_attempts,
  )
  let modules = @builtin.configure_compute_modules(
    @host_driver.open_dispatch_driver(run),
    registry,
    1,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_local=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          sequences,
          managed_providers: [provider],
          managed_capacity: limits.capacity,
          execution: limits.local_execution,
          measurement: limits.guards,
          max_work: limits.candidate_work,
        },
        _ => @strategy.RunIssue::ForeignCandidate,
        _ => @strategy.RunIssue::ForeignCandidate,
      ),
    ),
  ).unwrap()
  let installed = @builtin.configured_local_module(modules).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_columns: 10,
      },
      row: {
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_text_bytes: 3000,
      },
      max_batch_bytes: 3000,
    },
    None,
  ).unwrap()

  let series_live = Ref(true)
  let series_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (series_ops, series) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    series_live,
    obligations=series_obligations,
  )
  let rows = local_managed_test_rows(series_ops)
  assert_eq(cleanup_attempts.val, 1)
  assert_true(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes >
    0L,
  )
  assert_eq(rows, [
    "{\"time\":\"1969-12-31T23:59:59.999Z\"}", "{\"time\":\"1970-01-01T00:00:00.001Z\"}",
    "{\"time\":\"1970-01-01T00:00:00.003Z\"}",
  ])
  let requirements = @execution.managed_obligations_identities(
    series_obligations,
  )
  let published = requirements.filter(requirement => {
    requirement.domain == @execution.LogicalRelation &&
    requirement.subject == @execution.NamedResult
  })
  assert_eq(published.length(), 1)
  assert_eq(
    @execution.managed_completed_identity_requirement_status(
      series,
      published[0],
    ),
    Some(
      @execution.EstablishedSourceRetained(
        @execution.logical_relation_canonical_contract_cid(),
        "sha256:b5f7795bc6be00983b9a047815c5d6530a4ffad599d496a6304e692eb94f0392",
      ),
    ),
  )
  assert_true(
    @execution.managed_completed_deadline_satisfied(
      series,
      @execution.BeforePublication,
    ),
  )

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    2,
    [series],
    [rows],
    2,
    first_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    3,
    [series],
    [rows],
    3,
    second_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  assert_eq(local_managed_test_rows(first_ops), rows)
  assert_eq(local_managed_test_rows(second_ops), rows)

  first_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(series))

  second_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  series_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (series_ops.close)()
  assert_true((series_ops.cleanup_refresh)())
  assert_eq(cleanup_attempts.val, 2)
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}
