///|
fn values_filter_capacity_prepared(
  count : Int,
  filtered : Bool,
  maximum : Int,
) -> @publication_host.PreparedClientProgram {
  let assets = @publication_host.client_local_product_assets()
  let body = @json.parse(assets.environment) catch {
    _ => abort("bundled Environment JSON invalid")
  }
  guard body is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(cid)) else {
    abort("bundled Environment identity missing")
  }
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let rows = Array::makei(count, id => "{\"id\":" + id.to_string() + "}").join(
    ",",
  )
  let program = "{\"version\":\"actql/0.1\",\"id\":\"values-filter-capacity\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"input\",\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
    rows +
    "]}}" +
    (if filtered {
      ",{\"from\":\"input\",\"filter\":\"id >= 50\",\"as\":\"filtered\"}"
    } else {
      ""
    }) +
    "],\"results\":{\"rows\":{\"from\":\"" +
    (if filtered { "filtered" } else { "input" }) +
    "\",\"fields\":[\"id\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  let prepared = @publication_host.prepare_effect_free_client_program(
    program,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  @publication_host.with_prepared_client_values_row_limit(prepared, maximum).unwrap()
}

///|
fn values_filter_capacity_cleanup(
  active : @local.ManagedProviderExecution,
) -> Unit raise {
  assert_true(@local.managed_provider_stopped(active))
  for _ in 0..<512 {
    match @local.cleanup_managed_provider(active) {
      Ok(true) => return
      Ok(false) => ()
      Err(_) => fail("original managed provider cleanup failed")
    }
  }
  fail("original managed provider cleanup did not finish within bounded slices")
}

///|
fn values_filter_capacity_execute(count : Int, filtered : Bool) -> Unit raise {
  let prepared = values_filter_capacity_prepared(count, filtered, 2000)
  let assets = @publication_host.client_local_product_assets()
  let asset_contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let sequences = prepare_client_local_sequences(
    prepared,
    asset_contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_eq(sequences.length(), 1)
  let (_, execution, measurement) = client_local_execution_limits(max_rows=2000)
  let provider = @local.local_bounded_relation_provider(
    execution,
    measurement,
    sequences[0],
  ).unwrap()
  let active = @local.start_managed_provider_with_execution(
    provider,
    sequences[0],
    [],
    2000,
    10000,
    execution,
  ).unwrap()
  let mut result : Result[
    @execution.CompletedOutput,
    @connector.FixedComputeIssue,
  ]? = None
  let mut prior_work = 0L
  for _ in 0..<100000 {
    let poll = @local.advance_managed_provider(active, 64).unwrap()
    let (work, terminal) = match poll {
      @local.Continue(work~, ..) | @local.Waiting(work~, ..) => (work, false)
      @local.Settling(_, work~, ..) => (work, false)
      @local.Complete(output, work~, ..) => {
        result = Some(Ok(output))
        (work, true)
      }
      @local.Failed(issue, work~, ..) => {
        result = Some(Err(issue))
        (work, true)
      }
      @local.Stopped(work~, ..) => {
        values_filter_capacity_cleanup(active)
        fail("unexpected cancellation")
        (work, true)
      }
      @local.CarrierComplete(_, ..) => {
        values_filter_capacity_cleanup(active)
        fail("unexpected Carrier output")
        (0L, true)
      }
    }
    assert_true(work >= 0L)
    prior_work += work
    assert_true(prior_work <= execution.max_work.to_int64())
    if terminal {
      break
    }
  }
  match result {
    Some(Ok(output)) => {
      let start = if filtered { 50 } else { 0 }
      assert_eq(@execution.completed_row_count(output), count - start)
      for index in 0..<(count - start) {
        assert_eq(
          @execution.completed_output_row_wire(output, index, 1000, 10, 3).unwrap(),
          "{\"id\":" + (start + index).to_string() + "}",
        )
      }
      values_filter_capacity_cleanup(active)
    }
    Some(
      Err(
        @connector.Execution(
          @execution.Rows(1, @execution.LogicalRows(@execution.InputRowLimit))
        )
      )
    ) => {
      values_filter_capacity_cleanup(active)
      fail(
        "first typed refusal: Execution(Rows(1, LogicalRows(InputRowLimit)))",
      )
    }
    Some(Err(_)) => {
      values_filter_capacity_cleanup(active)
      fail("unexpected first typed managed execution issue")
    }
    None => {
      @local.cancel_managed_provider(active) |> ignore
      fail("bounded provider did not reach a terminal result")
    }
  }
}

///|
test "admitted Values row capacity reaches direct and filtered managed execution" {
  for count in [100, 500, 1000] {
    values_filter_capacity_execute(count, false)
    values_filter_capacity_execute(count, true)
  }
}

///|
test "Values filter keeps exact and one-short row profile admission" {
  let assets = @publication_host.client_local_product_assets()
  let asset_contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  for count in [100, 500, 1000] {
    let prepared = values_filter_capacity_prepared(count, true, count)
    assert_true(
      prepare_client_local_sequences(
        prepared,
        asset_contracts,
        assets.values,
        Some(assets.fragment),
        assets.ordered,
      )
      is Some(_),
    )
    let short = @publication_host.with_prepared_client_values_row_limit(
      prepared,
      count - 1,
    ).unwrap()
    assert_true(
      prepare_client_local_sequences(
        short,
        asset_contracts,
        assets.values,
        Some(assets.fragment),
        assets.ordered,
      )
      is None,
    )
    // Positive row policy is independent of actual demand and resource bounds.
    assert_true(
      @publication_host.with_prepared_client_values_row_limit(prepared, 10001)
      is Some(_),
    )
    for invalid in [-1, 0] {
      assert_true(
        @publication_host.with_prepared_client_values_row_limit(
          prepared, invalid,
        )
        is None,
      )
    }
  }
}

///|
test "larger Values filter remains cancellable with original finite cleanup" {
  let count = 500
  let prepared = values_filter_capacity_prepared(count, true, 2000)
  let assets = @publication_host.client_local_product_assets()
  let asset_contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let sequence = prepare_client_local_sequences(
      prepared,
      asset_contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap()[0]
  let (_, execution, measurement) = client_local_execution_limits(max_rows=2000)
  let provider = @local.local_bounded_relation_provider(
    execution, measurement, sequence,
  ).unwrap()
  let active = @local.start_managed_provider_with_execution(
    provider,
    sequence,
    [],
    2000,
    10000,
    execution,
  ).unwrap()
  let mut progress = 0L
  let mut work = 0L
  for _ in 0..<100000 {
    match @local.advance_managed_provider(active, 32).unwrap() {
      @local.Continue(progress=next, work=used)
      | @local.Waiting(progress=next, work=used) => {
        progress += next
        work += used
      }
      _ => fail("provider terminated before the selected cancellation point")
    }
    if progress > count.to_int64() + 10L {
      break
    }
  }
  assert_true(progress > count.to_int64() + 10L)
  assert_true(work <= execution.max_work.to_int64())
  assert_true(@local.cancel_managed_provider(active))
  let mut stopped = false
  for _ in 0..<100000 {
    match @local.advance_managed_provider(active, 1).unwrap() {
      @local.Continue(_) | @local.Waiting(_) | @local.Settling(_) => ()
      @local.Stopped(_) => {
        stopped = true
        break
      }
      _ =>
        fail(
          "cancelled provider published output or failed instead of stopping",
        )
    }
  }
  assert_true(stopped)
  values_filter_capacity_cleanup(active)
}

///|
fn values_filter_wide_prepared(
  count : Int,
) -> @publication_host.PreparedClientProgram {
  let assets = @publication_host.client_local_product_assets()
  let body = @json.parse(assets.environment) catch {
    _ => abort("bundled Environment JSON invalid")
  }
  guard body is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(cid)) else {
    abort("bundled Environment identity missing")
  }
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let rows = Array::makei(count, id => {
    "{\"id\":" + id.to_string() + ",\"second\":" + (id * 3).to_string() + "}"
  }).join(",")
  let program = "{\"version\":\"actql/0.1\",\"id\":\"values-filter-wide\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"input\",\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"second\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
    rows +
    "]}},{\"from\":\"input\",\"filter\":\"id >= 50\",\"as\":\"filtered\"}],\"results\":{\"rows\":{\"from\":\"filtered\",\"fields\":[\"id\",\"second\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  let prepared = @publication_host.prepare_effect_free_client_program(
    program,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  @publication_host.with_prepared_client_values_row_limit(prepared, 2000).unwrap()
}

///|
test "wide Values filter retains both independent columns at larger row counts" {
  let assets = @publication_host.client_local_product_assets()
  let asset_contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  for count in [500, 1000] {
    let prepared = values_filter_wide_prepared(count)
    let sequence = prepare_client_local_sequences(
        prepared,
        asset_contracts,
        assets.values,
        Some(assets.fragment),
        assets.ordered,
      ).unwrap()[0]
    let (_, execution, measurement) = client_local_execution_limits(
      max_rows=2000,
    )
    let provider = @local.local_bounded_relation_provider(
      execution, measurement, sequence,
    ).unwrap()
    let active = @local.start_managed_provider_with_execution(
      provider,
      sequence,
      [],
      2000,
      10000,
      execution,
    ).unwrap()
    let mut output : @execution.CompletedOutput? = None
    for _ in 0..<100000 {
      match @local.advance_managed_provider(active, 64).unwrap() {
        @local.Continue(_) | @local.Waiting(_) | @local.Settling(_) => ()
        @local.Complete(value, ..) => {
          output = Some(value)
          break
        }
        _ => {
          values_filter_capacity_cleanup(active)
          fail("wide Values filter did not complete normally")
        }
      }
    }
    let output = output.unwrap()
    assert_eq(@execution.completed_row_count(output), count - 50)
    for index in 0..<(count - 50) {
      let id = index + 50
      assert_eq(
        @execution.completed_output_row_wire(output, index, 1000, 10, 3).unwrap(),
        "{\"id\":" +
        id.to_string() +
        ",\"second\":" +
        (id * 3).to_string() +
        "}",
      )
    }
    values_filter_capacity_cleanup(active)
  }
}
