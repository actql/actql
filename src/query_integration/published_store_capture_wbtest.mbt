///|
// Copy of the existing independently authored STORE pair preimage. The test
// supplies an explicit Core capacity recipe, not a normal physical profile.
fn published_store_capture_with_completion(
  input_key? : Bool = false,
  rows? : String,
) -> (
  @publication_host.PreparedClientEffectComputation,
  @strategy.CapturedEffectRunDAG,
  @strategy.CapturedEffectInputs,
  @local_driver.LocalManagedDispatchOperations[Int],
  Ref[Bool],
  @execution.ManagedCompletedOutput[Int],
) raise {
  let wire =
    #|{"command_contracts":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file"},"version":"fixture-1"}],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:b68e536b6a4324573fc3ac3d39904dcab677c9ec0f1c624f12994b920270a2dd","commands":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file"},"version":"fixture-1"}],"connector_id":"storage","connector_version":"fixture-1","contracts":[{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"fixture","connector_id":"storage","connector_version":"fixture-1"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"evidence_bundle_cid":"sha256:a3fc9bc8b36a77651425b10479d518ccfcaf89a0f6bb05a8c38690b003232a2a","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:6960590acec3fcbd045e40dbb94ec08f77c3a2d271943b019a8ada57283a3208","conversions":[],"mapping_contract_cid":"sha256:8cb37a084de7d9c2092baffabb3ab29a8663aad8ad9a4b9d806e15fd98e77295","mapping_ref":"mapping:fixture.archive.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"store","permissions":["scope:write"],"selector_class":"none","write_fields":["id","value"]}],"primary_identity":"id","required_fields":["id","value"],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"id":{"field":"id","null_behavior":"reject"},"value":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","store_command":{"catalog_cid":"sha256:b68e536b6a4324573fc3ac3d39904dcab677c9ec0f1c624f12994b920270a2dd","command_contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","command_ref":"command:fixture.upload.v1"},"target_ref":"connector://storage/archive","target_schema":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bd89154b566792abefae13b781921bdb85725e117f241b99ce245d14d0efa37a","version":"fixture-1","writable_fields":["id","value"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
  let (_, base, limits) = local_effect_export_fixture()
  let policy = @encode.writer(10000, 2000, 64)
  @environment.emit_host_policy(
    @program_check.checking_environment_wire(base),
    policy,
  )
  let body = wire
    .replace(
      old="\"evidence_bundle_cid\":\"sha256:a3fc9bc8b36a77651425b10479d518ccfcaf89a0f6bb05a8c38690b003232a2a\",",
      new="",
    )
    .replace(
      old="\"host_policy_profile\":{}",
      new="\"host_policy_profile\":" + @encode.finish(policy),
    )
  let cid = "sha256:" + @sha.hex(@utf8.encode(body))
  let wire = body.replace(
    old="\"host_policy_profile\":",
    new="\"evidence_bundle_cid\":\"" + cid + "\",\"host_policy_profile\":",
  )
  let bundle = @environment.read(@utf8.encode(wire), cid, {
    max_bytes: 40000,
    max_nodes: 4000,
    max_depth: 100,
    max_members: 100,
  }).unwrap()
  let environment = @program_check.checking_environment(
    bundle,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let document =
    #|{"version":"actql/0.1","id":"published-store-capture","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"value":{"type":"string","nullable":false}},"rows":[{"id":"one","value":"original"}]},"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","value"]}},"effects":{"save":{"command":{"contract":"command:fixture.upload.v1","from":{"result":"out"},"input":{"id":{"field":"id"},"value":{"field":"value"}},"target":{"published_store":{"mapping_ref":"mapping:fixture.archive.v1","target_ref":"connector://storage/archive"}}}}}}],"results":{"published":{"from":{"stage":"source","result":"out"}}}}
  let document = if input_key {
    document.replace(
      old="\"contract\":\"command:fixture.upload.v1\"",
      new="\"contract\":\"command:fixture.upload.v1\",\"input_key\":\"id\"",
    )
  } else {
    document
  }
  let document = match rows {
    None => document
    Some(rows) =>
      document.replace(
        old="\"rows\":[{\"id\":\"one\",\"value\":\"original\"}]",
        new="\"rows\":" + rows,
      )
  }
  let prepared = @publication_host.prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let (_, _, _, captured) = local_effect_open_run(prepared)
  let run = @strategy.captured_effect_run_dag(captured)
  let (operations, completed, available) = local_effect_execute_managed_values(
    prepared, run,
  )
  let inputs = @strategy.pin_captured_effect_sources(captured, 2).unwrap()
  (prepared, captured, inputs, operations, available, completed)
}

///|
fn published_store_capture_fixture(
  input_key? : Bool = false,
) -> (
  @publication_host.PreparedClientEffectComputation,
  @strategy.CapturedEffectRunDAG,
  @strategy.CapturedEffectInputs,
  @local_driver.LocalManagedDispatchOperations[Int],
  Ref[Bool],
) raise {
  let (prepared, captured, inputs, operations, available, _) = published_store_capture_with_completion(
    input_key~,
  )
  (prepared, captured, inputs, operations, available)
}

///|
fn published_store_capture_reference(
  live : Ref[Bool],
) -> @admitted.CheckedValue {
  let source = @source.parse_json(
    "{\"nullable\":false,\"resource_kind\":\"file\",\"type\":\"resource_ref\"}",
    { max_input_bytes: 1024, max_nodes: 64, max_depth: 8, },
  ).unwrap()
  let cursor = @decode.admit(source, {
    max_nodes: 64,
    max_depth: 8,
    max_string_bytes: 1024,
    max_total_string_bytes: 1024,
  }).unwrap()
  let contract = @value_contract.read_checked(cursor, {
    max_nodes: 64,
    max_depth: 8,
    max_text_bytes: 1024,
  }).unwrap()
  let wire =
    #|{"$actql_ref":"resource","authority_scope_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","boundary_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","identity_cid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","provider_identity_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","provider_namespace":"fixture","resource_kind":"file","version":"actql-resource-ref/0.1"}
  let issuer = @admitted.bind_reference_issuer(
    (_, candidate) => candidate == wire,
    _ => live.val,
  )
  @admitted.issue_reference(issuer, contract, wire, {
    max_bytes: 1024,
    max_nodes: 64,
    max_depth: 8,
    max_text_units: 1024,
  }).unwrap()
}

///|
test "explicit Command input key refuses original captured proposal until whole-input proof is available" {
  let (_, captured, inputs, operations, available) = published_store_capture_fixture(
    input_key=true,
  )
  let pair = @strategy.captured_effect_published_store_binding(inputs, 0, 100)
    .unwrap()
    .unwrap()
  let target = @strategy.bind_captured_effect_command_target(
    inputs,
    0,
    pair,
    published_store_capture_reference(Ref(true)),
    100,
  ).unwrap()
  assert_eq(local_managed_test_rows(operations), [
    "{\"id\":\"one\",\"value\":\"original\"}",
  ])
  assert_true(
    @strategy.prepare_captured_effect_proposal_plan(
      inputs,
      0,
      2,
      100,
      published_target=Some(target),
    )
    is Err(@strategy.CapturedEffectProposalIssue::NotReady),
  )
  @strategy.release_captured_effect_inputs(inputs) |> ignore
  available.val = false
  (operations.close)()
  (operations.cleanup_refresh)() |> ignore
  let run = @strategy.captured_effect_run_dag(captured)
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
}

///|
test "published STORE captured proposal keeps one original Run and target across rows and retirement" {
  let (_, captured, inputs, operations, available) = published_store_capture_fixture()
  let pair = @strategy.captured_effect_published_store_binding(inputs, 0, 100)
    .unwrap()
    .unwrap()
  let live = Ref(true)
  let reference = published_store_capture_reference(live)
  let target = @strategy.bind_captured_effect_command_target(
    inputs, 0, pair, reference, 100,
  ).unwrap()
  let proposal = @strategy.prepare_captured_effect_proposal_plan(
    inputs,
    0,
    2,
    100,
    published_target=Some(target),
  ).unwrap()
  let rows = local_managed_test_rows(operations)
  assert_eq(rows, ["{\"id\":\"one\",\"value\":\"original\"}"])
  let row = @identity.from_source(
    @source.parse_json(rows[0], {
      max_input_bytes: 1024,
      max_nodes: 64,
      max_depth: 8,
    }).unwrap(),
    64,
    8,
    1024,
  )
  let (selector, changes) = @strategy.project_captured_effect_proposal_row(
    proposal, row, 0, 2, 100, 1024, 64, 8,
  ).unwrap()
  guard reference.value is @admitted.Reference(original) else {
    fail("issued reference")
  }
  assert_eq(selector, @admitted.reference_wire(original))
  assert_eq(
    changes, "{\"state\":\"present\",\"value\":{\"id\":\"one\",\"value\":\"original\"}}",
  )
  @strategy.finish_captured_effect_proposal_plan(proposal, 1).unwrap()
  let separate = @strategy.pin_captured_effect_sources(captured, 2).unwrap()
  assert_true(
    @strategy.prepare_captured_effect_proposal_plan(
      separate,
      0,
      2,
      100,
      published_target=Some(target),
    )
    is Err(@strategy.CapturedEffectProposalIssue::ForeignBinding),
  )
  @strategy.release_captured_effect_inputs(separate) |> ignore
  let pending = @strategy.prepare_captured_effect_proposal_plan(
    inputs,
    0,
    2,
    100,
    published_target=Some(target),
  ).unwrap()
  let finishing = @strategy.prepare_captured_effect_proposal_plan(
    inputs,
    0,
    2,
    100,
    published_target=Some(target),
  ).unwrap()
  live.val = false
  assert_true(
    @strategy.project_captured_effect_proposal_row(
      pending, row, 0, 2, 100, 1024, 64, 8,
    )
    is Err(@strategy.CapturedEffectProposalIssue::NotReady),
  )
  assert_true(
    @strategy.finish_captured_effect_proposal_plan(finishing, 0)
    is Err(@strategy.CapturedEffectProposalIssue::NotReady),
  )
  assert_true(
    @strategy.bind_captured_effect_command_target(
      inputs, 0, pair, reference, 100,
    )
    is Err(@strategy.CapturedEffectProposalIssue::NotReady),
  )
  @strategy.release_captured_effect_inputs(inputs) |> ignore
  assert_true(
    @strategy.captured_effect_published_store_binding(inputs, 0, 100)
    is Err(@strategy.CapturedEffectProposalIssue::NotReady),
  )
  available.val = false
  (operations.close)()
  (operations.cleanup_refresh)() |> ignore
  let run = @strategy.captured_effect_run_dag(captured)
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
}

///|
test "published STORE captured proposal rejects an equal-definition foreign Run and pair" {
  let (prepared, captured, inputs, operations, available) = published_store_capture_fixture()
  let (
    foreign_prepared,
    foreign,
    foreign_inputs,
    foreign_operations,
    foreign_available,
  ) = published_store_capture_fixture()
  assert_eq(
    @publication_host.prepared_client_effect_computation_definition_cid(
      prepared,
    ),
    @publication_host.prepared_client_effect_computation_definition_cid(
      foreign_prepared,
    ),
  )
  let pair = @strategy.captured_effect_published_store_binding(inputs, 0, 100)
    .unwrap()
    .unwrap()
  let foreign_pair = @strategy.captured_effect_published_store_binding(
      foreign_inputs, 0, 100,
    )
    .unwrap()
    .unwrap()
  assert_eq(
    @environment.mapping_shape_cid(@environment.store_command_mapping(pair)),
    @environment.mapping_shape_cid(
      @environment.store_command_mapping(foreign_pair),
    ),
  )
  let reference = published_store_capture_reference(Ref(true))
  let target = @strategy.bind_captured_effect_command_target(
    inputs, 0, pair, reference, 100,
  ).unwrap()
  assert_true(
    @strategy.bind_captured_effect_command_target(
      foreign_inputs, 0, pair, reference, 100,
    )
    is Err(@strategy.CapturedEffectProposalIssue::ForeignBinding),
  )
  assert_true(
    @strategy.prepare_captured_effect_proposal_plan(
      foreign_inputs,
      0,
      2,
      100,
      published_target=Some(target),
    )
    is Err(@strategy.CapturedEffectProposalIssue::ForeignBinding),
  )
  for
    (run, pins, physical, live) in [
      (captured, inputs, operations, available),
      (foreign, foreign_inputs, foreign_operations, foreign_available),
    ] {
    @strategy.release_captured_effect_inputs(pins) |> ignore
    live.val = false
    (physical.close)()
    (physical.cleanup_refresh)() |> ignore
    let dag = @strategy.captured_effect_run_dag(run)
    @strategy.stop_captured_dag(dag)
    @strategy.refresh_captured_retention(dag)
    let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(dag))
    assert_eq(usage.held_bytes, 0L)
    assert_eq(usage.reserved_execution_bytes, 0L)
    assert_eq(usage.reserved_retention_bytes, 0L)
  }
}
