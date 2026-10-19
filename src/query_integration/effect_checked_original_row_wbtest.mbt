///|
// Independently authored update Program and Mapping, admitted by the existing
// Common owners. Explicit fixture policy/capacity is not installed authority.
fn checked_original_update_prepared() -> @publication_host.PreparedClientEffectComputation raise {
  let (_, base, limits) = local_effect_export_fixture()
  let original = @program_check.checking_environment_wire(base)
  let original_mapping = @environment.member_at(original, MappingContracts, 0).unwrap()
  let mapping_writer = @encode.writer(20000, 2000, 100)
  @environment.emit_member(original_mapping, mapping_writer)
  let mapping = @encode.finish(mapping_writer)
    .replace(
      old="\"mapping_contract_cid\":\"" +
        @environment.member_cid(original_mapping) +
        "\",",
      new="",
    )
    .replace(old="\"effect_kind\":\"create\"", new="\"effect_kind\":\"update\"")
    .replace(old="\"scope:create\"", new="\"scope:update\"")
    .replace(old="\"selector_class\":\"none\"", new="\"selector_class\":\"id\"")
  let mapping_cid = "sha256:" + @sha.hex(@utf8.encode(mapping))
  let mapping = mapping.replace(
    old="\"mapping_ref\":",
    new="\"mapping_contract_cid\":\"" + mapping_cid + "\",\"mapping_ref\":",
  )
  let environment_writer = @encode.writer(40000, 4000, 100)
  @environment.emit(original, environment_writer)
  let body = @encode.finish(environment_writer).replace(
    old="\"evidence_bundle_cid\":\"" + @environment.cid(original) + "\",",
    new="",
  )
  let old_mapping_writer = @encode.writer(20000, 2000, 100)
  @environment.emit_member(original_mapping, old_mapping_writer)
  let body = body.replace(old=@encode.finish(old_mapping_writer), new=mapping)
  let environment_cid = "sha256:" + @sha.hex(@utf8.encode(body))
  let body = body.replace(
    old="\"host_policy_profile\":",
    new="\"evidence_bundle_cid\":\"" +
      environment_cid +
      "\",\"host_policy_profile\":",
  )
  let admitted = @environment.read(@utf8.encode(body), environment_cid, {
    max_bytes: 40000,
    max_nodes: 4000,
    max_depth: 100,
    max_members: 100,
  }).unwrap()
  let environment = @program_check.checking_environment(
    admitted,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let program =
    #|{"version":"actql/0.1","id":"original-checked-update","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"value":{"type":"number","nullable":false}},"rows":[{"id":"one","value":7},{"id":"two","value":9}]},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value","id"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"},"id":"id","set":{"Name":{"field":"value"}}}}}}],"results":{"published":{"from":{"stage":"source","result":"out"}}}}
  @publication_host.prepare_client_effect_computation(
    program,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
}

///|
fn checked_original_update_execution() -> (
  @strategy.CapturedEffectRunDAG,
  @strategy.CapturedEffectInputs,
  @client_local_host.LocalValuesExecution,
) raise {
  let prepared = checked_original_update_prepared()
  let (allowed, definition, _) = captured_subject_compile_allowed(prepared)
  let bound = @publication_host.bind_client_effect_compiled_run(
    prepared, allowed, definition,
  ).unwrap()
  let registry = @identity.stringify_value(
    registered_body(),
    100000,
    10000,
    100,
  )
  let values = @identity.stringify_value(
    registered_values(),
    100000,
    10000,
    100,
  )
  let fragment = Some(
    @identity.stringify_value(registered_fragment(), 100000, 10000, 100),
  )
  let capacity = @client_local_host.client_effect_local_ledger_limits(
    prepared,
    registry,
    values,
    fragment,
    None,
  ).unwrap()
  let captured = @publication_host.open_prepared_source_free_client_effect_run(
    bound, capacity,
  ).unwrap()
  let configured = @client_local_host.configure_source_free_effect_local_retained_host(
    bound,
    captured,
    registry,
    values,
    fragment,
    None,
  ).unwrap()
  let execution = @client_local_host.execute_source_free_values_guarded(
    configured,
    64,
    1000,
    () => true,
  ).unwrap()
  let inputs = @strategy.pin_captured_effect_sources(captured, 2).unwrap()
  (captured, inputs, execution)
}

///|
test "actual Captured Mapping uses only its original typed Result row and current export" {
  let (captured, inputs, execution) = checked_original_update_execution()
  let (rows, limits) = values_effect_export_test_limits()
  let index = values_effect_export_test_index(inputs, "out")
  let export_owner = execution
    .prepare_effect_result_export(
      captured, inputs, index, rows, 100, 10000, limits,
    )
    .unwrap()
  let exported = export_owner.captured_export().unwrap()
  let preparation = @strategy.captured_effect_local_result_export_preparation(
    exported,
  )
  while !@execution.advance_completed_result_relation_export(preparation, 64).unwrap().0 {
    ()
  }
  let stream = @execution.finish_completed_result_relation_export_preparation(
    preparation,
  ).unwrap()
  let plan = @strategy.prepare_captured_effect_proposal_plan(
    inputs, 0, 10, 10000,
  ).unwrap()
  let (_, first) = @execution.next_completed_output_export_original_row(
      stream, 1000, 20, 10000,
    )
    .unwrap()
    .unwrap()
  let first_checked = @strategy.project_captured_effect_checked_proposal_row(
    plan,
    exported,
    first,
    10,
    10000,
    { max_nodes: 100, max_depth: 20, max_text_bytes: 1000, },
  ).unwrap()
  let selected = @strategy.captured_effect_checked_proposal_row_selector(
    first_checked,
  ).unwrap()
  assert_true(selected.value is @admitted.Text("one"))
  let (name, original) = @strategy.captured_effect_checked_proposal_row_field_at(
    first_checked, 0,
  ).unwrap()
  assert_eq(name, "Name")
  assert_true(original.value is @admitted.Number(7))
  assert_eq(
    @strategy.captured_effect_checked_proposal_row_field_count(first_checked),
    Some(1),
  )
  let (_, second) = @execution.next_completed_output_export_original_row(
      stream, 1000, 20, 10000,
    )
    .unwrap()
    .unwrap()
  assert_false(
    @strategy.captured_effect_checked_proposal_row_available(first_checked),
  )
  let second_checked = @strategy.project_captured_effect_checked_proposal_row(
    plan,
    exported,
    second,
    10,
    10000,
    { max_nodes: 100, max_depth: 20, max_text_bytes: 1000, },
  ).unwrap()
  assert_true(
    @strategy.captured_effect_checked_proposal_row_selector(second_checked).unwrap().value
    is @admitted.Text("two"),
  )
  export_owner.close()
  assert_false(
    @strategy.captured_effect_checked_proposal_row_available(second_checked),
  )
  assert_true(
    @strategy.captured_effect_checked_proposal_row_field_at(second_checked, 0)
    is None,
  )
  @strategy.retire_captured_effect_checked_proposal_row(first_checked)
  @strategy.retire_captured_effect_checked_proposal_row(second_checked)
  @execution.cancel_completed_output_export(stream)
  @strategy.cancel_captured_effect_proposal_plan(plan)
  values_effect_export_test_close(captured, inputs, execution)
}
