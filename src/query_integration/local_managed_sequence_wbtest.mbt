///|
fn sequence_capacity_material(
  environment : @environment.WireEnvironment,
  input_proof : @wire.ProgramProofClaim,
) -> @context.StageCapacityInput raise {
  let policy = @environment.capacity_policy(
    @environment.read_capacity(environment, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
  )
  let witnesses = []
  let artifacts = []
  let mut output_host_cid = ""
  for
    (field, unit, suffix) in [
      ("max_temporal_matches_per_key", "matches_per_key", "matches-per-key"),
      ("max_temporal_output_rows", "rows", "output"),
    ] {
    let host = @host.create(@capacity_policy.ceiling(policy, field).unwrap(), {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap()
    let writer = @encode.writer(10000, 1000, 30)
    @host.emit(host, writer)
    let host_text = @encode.finish(writer)
    let host_wire = @wire.admit(@utf8.encode(host_text), @host.cid(host), {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap()
    witnesses.push(host_wire)
    if suffix == "output" {
      output_host_cid = @wire.cid(host_wire)
    }
    let candidates = [host_text]
    let effective = @wire.value(host_wire)
    let body = "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[" +
      candidates.join(",") +
      "],\"effective_max\":" +
      effective.to_string() +
      ",\"enforcement\":\"engine_atomic\",\"subject_ref\":\"sequence:checked-step:0:" +
      suffix +
      "\",\"unit\":\"" +
      unit +
      "\",\"version\":\"actql-resolved-limit/0.1\"}"
    let cid = "sha256:" + @sha.hex(@utf8.encode(body))
    artifacts.push(
      (
        @utf8.encode(
          body.replace(
            old="\"subject_ref\":",
            new="\"resolved_limit_cid\":\"" + cid + "\",\"subject_ref\":",
          ),
        ),
        cid,
      ),
    )
  }
  let output_proof = query_capacity_proof(
    "actql.bound.sequence-output",
    @wire.value(witnesses[1]),
    "{\"op\":\"source\"}",
    inputs=[output_host_cid],
    step=0,
  )
  witnesses.push(@wire.program_proof_witness(input_proof))
  witnesses.push(@wire.program_proof_witness(output_proof))
  let mixed = @wire.check_mixed_claims(witnesses, artifacts, {
    max_entities: 10,
    max_references: 20,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(
    mixed,
    [input_proof, output_proof],
    { max_witnesses: 10, max_references: 20, },
  ).unwrap()
  let sources = @host.bind_claim_sources(claims, [policy], {
    max_entries: 10,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  {
    stage: "matched",
    sources,
    uses: [
      Sequence(
        step=0,
        matches=@wire.mixed_limit_at(mixed, 0).unwrap(),
        output=@wire.mixed_limit_at(mixed, 1).unwrap(),
      ),
    ],
  }
}

///|
fn local_values_sequence_program() -> String {
  (
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"events","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"key":{"type":"number","nullable":false},"clock":{"type":"number","nullable":false},"value":{"type":"number","nullable":false}},"rows":[{"id":3,"key":1,"clock":3,"value":2},{"id":1,"key":1,"clock":1,"value":1},{"id":4,"key":2,"clock":4,"value":2},{"id":2,"key":1,"clock":2,"value":2},{"id":5,"key":2,"clock":3,"value":1}]},"as":"out"}],"results":{"r":{"from":"out","fields":["id","key","clock","value"]}}},{"id":"matched","inputs":{"x":{"result":{"stage":"events","result":"r"}}},"steps":[{"from":"x","sequence":{"by":["key"],"id":"id","time":"clock","pattern":[{"as":"start","where":"value = 1"},{"as":"end","where":"value = 2"}],"within":10,"overlap":"allow","contiguity":"subsequence"},"as":"out"}],"results":{"r":{"from":"out","fields":["end_id","end_time_ms","key","match_end_ms","match_start_ms","start_id","start_time_ms"]}}},{"id":"consumer_a","inputs":{"x":{"result":{"stage":"matched","result":"r"}}},"steps":[{"select":["key","start_id","end_id"],"as":"out"}],"results":{"r":{"from":"out","fields":["key","start_id","end_id"]}}},{"id":"consumer_b","inputs":{"x":{"result":{"stage":"matched","result":"r"}}},"steps":[{"select":["end_id","start_id","key"],"as":"out"}],"results":{"r":{"from":"out","fields":["end_id","start_id","key"]}}}],"results":{"source":{"from":{"stage":"a","result":"r"}}}}
  )
}

///|
test "standard Host runs bounded sequence matching for two consumers" {
  let (run, issuer) = captured_graph_fixture(
    local_values_sequence_chain=true,
    managed_publication=true,
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 20,
      holdings: 20,
      transfer_bytes: 300000L,
      retained_bytes: 134217728L,
      execution_bytes: 536870912L,
    }),
  )
  assert_true(
    @strategy.configure_captured_managed_identity_policy(
      run, true, false, false, false,
    ),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    dispatch_test_generated(run),
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
  ).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: 3000,
        max_nodes: 300,
        max_columns: 7,
        max_order_work: 1000,
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
  let events_live = Ref(true)
  let (events_ops, events) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    events_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let event_rows = local_managed_test_rows(events_ops)
  let match_live = Ref(true)
  let match_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (match_ops, matched) = run_local_managed_test_task(
    installed,
    run,
    2,
    [events],
    [event_rows],
    2,
    match_live,
    obligations=match_obligations,
  )
  let matched_rows = local_managed_test_rows(match_ops)
  assert_eq(matched_rows, [
    "{\"end_id\":2,\"end_time_ms\":2,\"key\":1,\"match_end_ms\":2,\"match_start_ms\":1,\"start_id\":1,\"start_time_ms\":1}",
    "{\"end_id\":3,\"end_time_ms\":3,\"key\":1,\"match_end_ms\":3,\"match_start_ms\":1,\"start_id\":1,\"start_time_ms\":1}",
    "{\"end_id\":4,\"end_time_ms\":4,\"key\":2,\"match_end_ms\":4,\"match_start_ms\":3,\"start_id\":5,\"start_time_ms\":3}",
  ])
  let published = @execution.managed_obligations_identities(match_obligations).filter(requirement => {
      requirement.domain == @execution.LogicalRelation &&
      requirement.subject == @execution.NamedResult
    },
  )
  assert_eq(published.length(), 1)
  match
    @execution.managed_completed_identity_requirement_status(
      matched,
      published[0],
    ) {
    Some(@execution.EstablishedSourceRetained(contract, cid)) => {
      assert_eq(contract, @execution.logical_relation_canonical_contract_cid())
      assert_eq(
        cid, "sha256:eab1f4eaca55131b4c2875c7c8fe6556c9239a1aca4a9cd05b91e73f7e3da950",
      )
    }
    _ => fail("sequence output did not establish publication identity")
  }
  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    3,
    [matched],
    [matched_rows],
    3,
    first_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    4,
    [matched],
    [matched_rows],
    4,
    second_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  assert_eq(local_managed_test_rows(first_ops), [
    "{\"key\":1,\"start_id\":1,\"end_id\":2}", "{\"key\":1,\"start_id\":1,\"end_id\":3}",
    "{\"key\":2,\"start_id\":5,\"end_id\":4}",
  ])
  assert_eq(local_managed_test_rows(second_ops), [
    "{\"end_id\":2,\"start_id\":1,\"key\":1}", "{\"end_id\":3,\"start_id\":1,\"key\":1}",
    "{\"end_id\":4,\"start_id\":5,\"key\":2}",
  ])
  first_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(matched))
  second_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  match_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (match_ops.close)()
  (match_ops.cleanup_refresh)() |> ignore
  events_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (events_ops.close)()
  (events_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}
