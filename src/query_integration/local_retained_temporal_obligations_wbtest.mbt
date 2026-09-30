///|
priv enum RetainedTemporalFixture {
  Series
  Interval
  AsOf
}

///|
fn check_retained_temporal_offer(kind : RetainedTemporalFixture) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_time_series_chain=kind is Series,
    local_values_interval_chain=kind is Interval,
    local_values_asof_chain=kind is AsOf,
  )
  let task = if kind is Series { 1 } else { 3 }
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let generated = dispatch_test_generated(run)
  let capacity = @execution.generated_sequence_capacity(
    generated[task - 1],
    limits.local_execution,
    limits.guards,
  ).unwrap()
  let provider = match kind {
    Series =>
      @local_tea_provider.time_series_provider(
        carrier_events_storage_limits(),
        capacity,
      )
    Interval =>
      @local_tea_provider.interval_join_provider(
        carrier_events_storage_limits(),
        capacity,
      )
    AsOf =>
      @local_tea_provider.asof_join_provider(
        carrier_events_storage_limits(),
        capacity,
      )
  }
  for registered in [false, true] {
    let installed = @local_driver.prepare_local_dispatch_module(
      @host_driver.open_dispatch_driver(run),
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      generated,
      limits.local_execution,
      limits.guards,
      limits.candidate_work,
      managed_providers=if registered { [provider] } else { [] },
    ).unwrap()
    let wire = {
      ..retained_attempt_wire_limits(),
      max_bytes: 10000,
      max_columns: 10,
    }
    @local_driver.configure_local_retained_inputs(
      installed,
      {
        max_rows: 100,
        values: limits.local_execution.rows.input_values,
        wire,
        row: {
          max_bytes: 10000,
          max_nodes: 1000,
          max_depth: 10,
          max_text_bytes: 1000,
        },
        max_batch_bytes: 1024,
      },
      None,
    ).unwrap()
    @local_driver.configure_local_retained_output(
      installed,
      {
        max_rows: 100,
        values: limits.local_execution.rows.output_values,
        wire,
        max_batch_bytes: 1024,
      },
      None,
    ).unwrap()
    let implementation = @local_connector.prepare_local_compute_module(
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      generated,
      limits.local_execution,
      limits.guards,
      limits.candidate_work,
      generated.length(),
      managed_providers=if registered { [provider] } else { [] },
    ).unwrap()
    let step = @execution.generated_sequence_step_index_at(
      generated[task - 1],
      0,
    ).unwrap()
    let check = match kind {
      Series => @local_connector.TimeSeries
      Interval => @local_connector.IntervalJoin
      AsOf => @local_connector.AsOfJoin
    }
    let wrong_check = if kind is Series {
      @local_connector.IntervalJoin
    } else {
      @local_connector.TimeSeries
    }
    assert_false(
      @local_connector.local_module_bounded_temporal_relation_obligation(
        implementation,
        task - 1,
        step + 1,
        check,
      ),
    )
    assert_false(
      @local_connector.local_module_bounded_temporal_relation_obligation(
        implementation,
        task - 1,
        step,
        wrong_check,
      ),
    )
    assert_eq(
      @local_connector.local_module_bounded_temporal_relation_obligation(
        implementation,
        task - 1,
        step,
        check,
      ),
      registered,
    )
    assert_eq(
      @local_driver.local_dispatch_rejection(installed, task),
      if registered {
        None
      } else {
        Some("unsupported_execution_obligation")
      },
    )
  }
  @strategy.stop_captured_dag(run)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "retained time series requires its registered bounded provider" {
  check_retained_temporal_offer(Series)
}

///|
test "retained interval join requires its registered bounded provider" {
  check_retained_temporal_offer(Interval)
}

///|
test "retained as-of join requires its registered bounded provider" {
  check_retained_temporal_offer(AsOf)
}
