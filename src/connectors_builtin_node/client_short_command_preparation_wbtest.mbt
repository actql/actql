///|
// Same independently authored original as the query/Common counter. No Host,
// Site, Source, Reference issuer or Effect Run is created by these callers.
fn short_command_source_environment() -> @program_check.CheckEnvironment {
  client_program_check_environment(
    (
      #|{"command_contracts":[{"atomicity":"single_target","command_id":"command:mail.send.v1","connector_id":"example","contract_cid":"sha256:2593e5c2992d42ce2dc58b92ca3140458cbae64172f09a560c05da96d0b2e5e4","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"body":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:ceffb59b34b9fee831dc4060f0de02e3268bc8fe8549ea4516f74e15da90c0e2","id":"mail.input","version":"vendor-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:db19239d74f021e17ac68b37e34a434a43c28a7d46f4329535afae74e148835c","id":"mail.output","version":"vendor-1"},"permissions":["mail.send"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"binding":{"kind":"installation"},"cardinality":"single","resource_kind":"mailbox"},"version":"vendor-1"}],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:53aca18bf5bf1663145cfda6198ef8707115e4196a023061797a92dcde16b6e7","commands":[{"atomicity":"single_target","command_id":"command:mail.send.v1","connector_id":"example","contract_cid":"sha256:2593e5c2992d42ce2dc58b92ca3140458cbae64172f09a560c05da96d0b2e5e4","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"body":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:ceffb59b34b9fee831dc4060f0de02e3268bc8fe8549ea4516f74e15da90c0e2","id":"mail.input","version":"vendor-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:db19239d74f021e17ac68b37e34a434a43c28a7d46f4329535afae74e148835c","id":"mail.output","version":"vendor-1"},"permissions":["mail.send"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"binding":{"kind":"installation"},"cardinality":"single","resource_kind":"mailbox"},"version":"vendor-1"}],"connector_id":"example","connector_version":"vendor-1","contracts":[{"body":{"additional_properties":false,"fields":{"body":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:ceffb59b34b9fee831dc4060f0de02e3268bc8fe8549ea4516f74e15da90c0e2","id":"mail.input","kind":"command_input","schema":"actql.contract/0.1","version":"vendor-1"},{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:db19239d74f021e17ac68b37e34a434a43c28a7d46f4329535afae74e148835c","id":"mail.output","kind":"command_output","schema":"actql.contract/0.1","version":"vendor-1"}],"schema":"actql.connector_catalog/0.1","source_views":[]}],"contract_registry":[{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:db19239d74f021e17ac68b37e34a434a43c28a7d46f4329535afae74e148835c","id":"mail.output","kind":"command_output","schema":"actql.contract/0.1","version":"vendor-1"},{"body":{"additional_properties":false,"fields":{"body":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:ceffb59b34b9fee831dc4060f0de02e3268bc8fe8549ea4516f74e15da90c0e2","id":"mail.input","kind":"command_input","schema":"actql.contract/0.1","version":"vendor-1"}],"evidence_bundle_cid":"sha256:3d1611e61f81eae841730a29b59d517104d3333f7a13a1dc27b55f94b0e202e2","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
    ),
    "sha256:3d1611e61f81eae841730a29b59d517104d3333f7a13a1dc27b55f94b0e202e2",
    false,
    false,
    true,
    false,
    false,
    false,
    false,
  ).unwrap()
}

///|
fn short_command_source_publication(
  environment : @program_check.CheckEnvironment,
) -> String {
  "{\"environmentCid\":\"" +
  @program_check.checking_environment_cid(environment) +
  "\",\"aliases\":[],\"commandTargets\":[{\"name\":\"mail.send\",\"targetRef\":\"connector://example/mailbox\",\"commandRef\":\"command:mail.send.v1\",\"installationBindingCid\":\"sha256:" +
  "d".repeat(64) +
  "\",\"installationOwnerCid\":\"sha256:" +
  "e".repeat(64) +
  "\"}]}"
}

///|
fn short_command_source_text() -> String {
  "SELECT 'operation-1' AS id, 'original body' AS body |> EFFECT COMMAND mail.send ID id INPUT (body = body)"
}

///|
test "actual public Source lowerer retains the original Command publication and private ID" {
  let environment = short_command_source_environment()
  let publication = short_command_source_publication(environment)
  let lowered = match
    client_program_lower_source(
      short_command_source_text(),
      "sql",
      environment,
      publication,
      None,
    ) {
    Ok(value) => value
    Err(SourcePreparation(Frontend(QueryLowering(ExpressionTyping(issue))))) =>
      raise issue
    Err(
      SourcePreparation(
        Frontend(QueryLowering(Expression({ issue: UnknownReference, .. })))
      )
    ) => fail("Source.Command.UnknownReference")
    Err(SourcePreparation(Frontend(QueryLowering(UnknownColumn)))) =>
      fail("Source.Command.UnknownColumn")
    Err(SourcePreparation(Frontend(QueryLowering(UnknownRelation)))) =>
      fail("Source.Command.UnknownRelation")
    Err(SourcePreparation(Frontend(QueryLowering(InvalidQuery)))) =>
      fail("Source.Command.InvalidQuery")
    Err(SourcePreparation(Frontend(QueryLowering(InvalidContext)))) =>
      fail("Source.Command.InvalidContext")
    Err(SourcePreparation(Frontend(QueryLowering(_)))) =>
      fail("Source.Command.OtherLowering")
    Err(SourcePreparation(Publication)) => fail("Source.Command.Publication")
    Err(SourcePreparation(Frontend(_))) =>
      fail("Source.Command.SyntaxOrEncoding")
    Err(_) => fail("Source.Command.OtherPreparation")
  }
  let selection = lowered.command_selection.unwrap()
  let target = @query_program.short_command_selection_target(selection)
  assert_eq(@query_program.short_command_selection_stage(selection), 0)
  assert_eq(
    @query_program.short_command_selection_effect(selection),
    "aql_command_effect",
  )
  let contract = @query_program.resolved_command_target_contract(target)
  assert_true(
    physical_equal(
      @check_environment.member_environment(
        @check_environment.command_target_member(contract),
      ),
      @program_check.checking_environment_wire(environment),
    ),
  )
  let (_, _, binding, owner) = @query_program.resolved_command_target_identity(
    target,
  )
  assert_eq(binding, "sha256:" + "d".repeat(64))
  assert_eq(owner, "sha256:" + "e".repeat(64))
  let program = lowered.program.unwrap()
  let header = @stage_syntax.effect_header_at(
    @stage_syntax.collect_effect_headers(program, 1, 10000).unwrap(),
    0,
  ).unwrap()
  assert_eq(@stage_syntax.effect_header_command_input_key(header), Some("id"))
  assert_eq(
    @stage_syntax.effect_header_published_command_target(header),
    Some(("connector://example/mailbox", None)),
  )
  assert_eq(@stage_syntax.export_count(program), 0)
}

///|
test "actual Source preparation refuses to discard original Command publication before capture" {
  let environment = short_command_source_environment()
  let publication = short_command_source_publication(environment)
  let outcome = client_program_prepare_source_computation_with_parameters(
    short_command_source_text(),
    "sql",
    environment,
    publication,
    None,
    None,
    true,
    [],
  )
  assert_true(
    outcome
    is SourcePure(
      Rejected(SourcePreparation(CommandTargetOriginalsUnavailable))
    ),
  )
  assert_eq(
    client_source_preparation_issue_code(CommandTargetOriginalsUnavailable),
    "source_unsupported",
  )
}

///|
test "actual Source caller refuses foreign Command publication before expression binding" {
  let environment = short_command_source_environment()
  let publication = short_command_source_publication(environment).replace(
    old=@program_check.checking_environment_cid(environment),
    new="sha256:" + "f".repeat(64),
  )
  assert_true(
    client_program_lower_source(
      short_command_source_text(),
      "sql",
      environment,
      publication,
      None,
    )
    is Err(SourcePreparation(Publication)),
  )
  assert_eq(
    client_source_preparation_issue_code(
      Frontend(QueryLowering(CommandTargetBinding(WorkLimit))),
    ),
    "source_limit",
  )
  assert_eq(
    client_source_preparation_issue_code(
      Frontend(QueryLowering(CommandTargetBinding(UnresolvedTarget))),
    ),
    "source_unresolved",
  )
}
