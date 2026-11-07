///|
fn[T, E] Result::native_request_stage(
  self : Result[T, E],
  stage : String,
) -> T raise {
  match self {
    Ok(value) => value
    Err(_) => fail(stage)
  }
}

///|
fn[T] Option::native_request_stage(self : T?, stage : String) -> T raise {
  match self {
    Some(value) => value
    None => fail(stage)
  }
}

///|
// Independently authored input and installed Mapping. The fixture's declared
// input digests were calculated with Python hashlib, not the product output.
// This preparation/admission fixture grants no physical Provider permission.
let native_client_effect_fixture_document : String =
  #|{"id":"native-effect","results":{"published":{"from":{"result":"out","stage":"source"}}},"stages":[{"effects":{"save":{"create":{"from":{"result":"out"},"mapping":"mapping:crm.account.v1","target":"connector://crm/account"}}},"id":"source","inputs":{},"results":{"out":{"fields":["value"],"from":"selected"}},"steps":[{"as":"selected","values":{"rows":[{"value":"e\u0301\r\n"}],"schema":{"value":{"nullable":false,"type":"string"}}}}]}],"version":"actql/0.1"}

///|
let native_client_effect_fixture_environment_wire : String =
  #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:67979d9f5507bd9dd0809091d96b7dc96a1dce6e30df75ad0fac523f9c3ad808","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:1be9426a9b8809a531aae1c2cac2bfe7bef35b4fccff982c52da4a4de350190b","mapping_ref":"mapping:crm.account.v1","minimum_approval":"required","permission_rules":[{"effect_kind":"create","permissions":["scope:create"],"selector_class":"none","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bb7f22131b239944c4d7f01ddc3eaf675c34e38ca195527a90c6863668150e66","version":"salesforce-v1","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}

///|
fn native_client_effect_fixture_environment() -> @checked.CheckEnvironment {
  @host.admit_client_check_environment(
    native_client_effect_fixture_environment_wire,
    "sha256:67979d9f5507bd9dd0809091d96b7dc96a1dce6e30df75ad0fac523f9c3ad808",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
// Actual Native facility and same Common Request. This component has no
// Journal/Account/provider/approval/normal CLI or Saved acceptance claim.
fn native_effect_request_facility(
  input : @host.ClientSubmittedIntent,
) -> (
  @arena.InstalledArenaHost,
  @arena.InstalledArenaDomain,
  @arena.InstalledArenaRetainedExecution,
  @resources.BackedPreparationAdmission[@host.ClientSubmittedIntent],
) raise {
  // Match the SAME existing ordinary policy, rather than the first authored
  // 32MiB component facility that correctly refused its full checker peak.
  let policy = @local.client_local_preparation_initial_limits(
    @local.client_local_resource_policy(),
  ).native_request_stage("ordinary native Request policy")
  let policy = {
    ..policy,
    attempts: 32,
    holdings: 32,
    transfer_bytes: 32000000L,
  }
  let payload = policy.retained_bytes + policy.execution_bytes
  let mut domain_bytes = payload
  for _ in 0..<16 {
    let required = @bootstrap.execution_domain_necessary_bytes(
      domain_bytes, payload,
    )
    assert_true(required > 0L)
    if required <= domain_bytes {
      break
    }
    domain_bytes = required
  }
  let bytes = domain_bytes * 2L
  let arena = @arena.prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    bytes,
    {
      planning_work: 100000,
      attempts: 100000,
      holdings: 100000,
      transfer_bytes: 100000000000L,
      retained_bytes: 0L,
      execution_bytes: bytes,
    },
    65536L,
  ).native_request_stage("Native Request stage 19")
  arena.acquire().native_request_stage("Native Request stage 20")
  let backing = arena
    .borrow_backing()
    .native_request_stage("Native Request stage 21")
  arena
  .enter_backing_borrow_scope(backing)
  .native_request_stage("Native Request stage 22")
  let domain = match
    arena
    .prepare_domain_in_process(backing, domain_bytes, policy)
    .native_request_stage("Native Request stage 23") {
    @arena.PreparedDomain(value) => value
    @arena.PendingDomain(_, _) => fail("actual Request domain pending")
  }
  arena.transfer_domain(domain).native_request_stage("Native Request stage 24")
  arena
  .leave_backing_borrow_scope(backing)
  .native_request_stage("Native Request stage 25")
  arena
  .return_backing_borrow(backing)
  .native_request_stage("Native Request stage 26")
  arena
  .prepare_domain_read(domain)
  .native_request_stage("Native Request stage 27")
  let (physical, initial) = match
    arena
    .prepare_domain_retained_request_execution(domain, input, {
      bootstrap_retained: 1048576L,
      bootstrap_execution: 1048576L,
    })
    .native_request_stage("Native Request stage 28") {
    @arena.ReadyRequestExecution(physical, initial) => (physical, initial)
    @arena.PendingRequestExecution(_, _) =>
      fail("actual Request initializer pending")
  }
  (arena, domain, physical, initial)
}

///|
// Consume inner prepared/compilation aliases before the physical Read returns.
// Only a scalar outcome escapes this frame; the original Request keeps its
// own payload until logical cleanup severs it before Native retirement.
fn native_effect_request_consume(
  parent : @local.ClientRequestPreparation[@host.ClientSubmittedIntent],
  input : @host.ClientSubmittedIntent,
) -> Int raise {
  let environment = native_client_effect_fixture_environment()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" + @checked.checking_environment_cid(environment) + "\",\"aliases\":[]}",
  ).native_request_stage("Effect original publication")
  let result = @native.prepare_native_client_submitted_request(
    parent, input, environment, publication,
  )
  if result is Ok((preparation, holder)) {
    guard @native.native_client_submitted_preparation(preparation) is EffectComputation(prepared) else {
      fail("Effect was replaced by Pure")
    }
    assert_true(holder is @native.Effect(_))
    assert_eq(@native.native_client_submitted_preparation_intent_cid(preparation), @host.client_submitted_intent_cid(input))
    let normalization = @host.issue_prepared_client_effect_normalization(prepared).native_request_stage("Effect original normalization")
    let manifests = @host.admit_client_compilation_manifests(
      @environment.compiler_grammar_manifest_wire(),
      @environment.compiler_barrier_contract_manifest_wire(),
      10000, 1000, 20,
    ).native_request_stage("Effect original manifests")
    let compilation = @host.issue_prepared_client_effect_compilation(
      prepared, manifests, @host.client_standard_values_sequence_limits(),
      1000, 1000, 65536, 8192, 64, normalization=Some(normalization),
    ).native_request_stage("Effect first sequence compiler")
    assert_true(physical_equal(@host.client_effect_compilation_owner(compilation), prepared))
    @native.return_native_client_submitted_request_body(holder).native_request_stage("Effect original borrow return") |> ignore
  }
  match result {
    Ok(_) => 0
    Err(@native.RequestBranchUnavailable) => 1
    Err(_) => 2
  }
}

///|
test "Native same Request carries original Effect preparation and retires original borrow" {
  let input = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" + native_client_effect_fixture_document + ",\"parameters\":null}",
    65536, 8192, 64,
  ).native_request_stage("original Effect intent")
  let (arena, domain, physical, initial) = native_effect_request_facility(input)
  let parent = @local.begin_backed_request_preparation(
    initial, input, @local.client_local_resource_policy(),
  ).native_request_stage("Effect original Request")
  arena.enter_domain_retained_execution(physical).native_request_stage("Effect Read enter")
  let outcome = native_effect_request_consume(parent, input)
  assert_eq(outcome, 0)
  assert_true(@local.abort_request_preparation_after_cleanup(parent) is Err(_))
  arena.leave_domain_retained_execution(physical).native_request_stage("Effect Read leave")
  match arena.close_domain_retained_execution(physical) {
    Ok(_) => ()
    Err(@arena.Domain(issue)) => fail("Effect retirement Domain: " + @debug.to_string(issue))
    Err(@arena.Child(issue)) => fail("Effect retirement Child: " + @debug.to_string(issue))
    Err(@arena.Initialization(@bootstrap.Domain(issue))) => {
      let observation = arena.observe_domain_retained_execution_cleanup(physical).native_request_stage("Effect original cleanup metadata")
      fail("Effect retirement InitializationDomain: " + @debug.to_string(issue) + " metadata=" +
        @debug.to_string((observation.users, observation.active, observation.generic_live_extents,
          observation.managed_live_blocks, observation.managed_requested_bytes,
          observation.minimum_managed_request, observation.maximum_managed_request)))
    }
    Err(@arena.Initialization(@bootstrap.Child(issue))) => fail("Effect retirement InitializationChild: " + @debug.to_string(issue))
    Err(@arena.Initialization(@bootstrap.Inventory(_))) => fail("Effect retirement InitializationInventory")
    Err(@arena.Initialization(@bootstrap.Quiescence(_))) => fail("Effect retirement InitializationQuiescence")
  }
  @local.abort_request_preparation_after_cleanup(parent).native_request_stage("Effect original Request retirement")
  arena.close_domain_after_owner_ack(domain).native_request_stage("Effect domain return")
  arena.try_close().native_request_stage("Effect arena return")
}
