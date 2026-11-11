///|
// The existing actual compiler/Values fixture supplies explicit semantic Scope
// DATA. These checks establish original-context identity/currentness only;
// they are not Source/Model execution, funding or an imported-evidence success.
fn saved_model_imported_scope_test_fixture(
  available : () -> Bool,
) -> (ClientCompiledRun, ClientInferCallScope, ClientInferSavedCallScope) raise {
  let (compiled, scope, _) = model_local_invocation_fixture()
  let definition = issue_client_compiled_run_definition(
    compiled, "saved-model-imports", "same-original-run", "2026-10-15T00:00:00.000Z",
    "2026-10-16T00:00:00.000Z",
  ).unwrap()
  let saved : ClientInferSavedCallScope = {
    compiled,
    definition,
    occurrence: scope.plan.occurrence,
    plan: scope.plan,
    artifact: scope.artifact,
    effective: scope.effective,
    named_sources: scope.named_sources.copy(),
    available,
  }
  (compiled, scope, saved)
}

///|
test "saved Model imported context keeps original Scope and refuses foreign equal-looking owners" {
  let calls = Ref(0)
  let (compiled, scope, saved) = saved_model_imported_scope_test_fixture(() => {
    calls.val += 1
    true
  })
  assert_true(saved_model_imported_scope_matches(compiled, scope, saved))
  assert_eq(calls.val, 1)
  let (foreign, foreign_scope, foreign_saved) = saved_model_imported_scope_test_fixture(() => {
      abort("foreign original must refuse before its custody callback")
    },
  )
  assert_false(saved_model_imported_scope_matches(foreign, scope, saved))
  assert_false(
    saved_model_imported_scope_matches(compiled, foreign_scope, saved),
  )
  assert_false(
    saved_model_imported_scope_matches(compiled, scope, foreign_saved),
  )
  // Equal admitted wire is not the retained nominal evidence original.
  let replacement = @publication.admit_run_evidence_value(
    @publication.run_evidence_value_name(saved.artifact),
    @publication.run_evidence_value_json(saved.artifact),
    10000,
    1000,
    20,
  ).unwrap()
  assert_false(
    saved_model_imported_scope_matches(
      compiled,
      { ..scope, artifact: replacement, },
      saved,
    ),
  )
  assert_eq(calls.val, 1)
}

///|
test "saved Model imported context rechecks original custody and never grants after its retirement" {
  let current = Ref(true)
  let calls = Ref(0)
  let (compiled, scope, saved) = saved_model_imported_scope_test_fixture(() => {
    calls.val += 1
    current.val
  })
  assert_true(saved_model_imported_scope_matches(compiled, scope, saved))
  current.val = false
  assert_false(saved_model_imported_scope_matches(compiled, scope, saved))
  assert_eq(calls.val, 2)
}

///|
test "saved Model imported context refuses a foreign occurrence with otherwise identical originals" {
  let calls = Ref(0)
  let (compiled, scope, saved) = saved_model_imported_scope_test_fixture(() => {
    calls.val += 1
    true
  })
  let (_, _, foreign) = saved_model_imported_scope_test_fixture(() => false)
  assert_false(
    saved_model_imported_scope_matches(compiled, scope, {
      ..saved,
      occurrence: foreign.occurrence,
    }),
  )
  assert_eq(calls.val, 0)
}

///|
test "saved Model imported Source join rejects another actual capture with equal logical rows" {
  // Reuse the existing actual Whole-capture fixture, with its explicit Source
  // metadata ports. This is a capture/semantic join control, not normal IO.
  let document =
    #|{"version":"actql/0.1","id":"saved-source-join","stages":[{"id":"joined","inputs":{"left_rows":{"connector":"crm/main","resource":"r"},"right_rows":{"connector":"crm/right","resource":"r"}},"from":"left_rows","steps":[{"join":{"with":"right_rows","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":4,"select":{"value":"left.id"}},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"joined":{"from":{"stage":"joined","result":"out"}}}}
  let environment = admit_client_check_environment(
    bound_effect_source_environment,
    "sha256:e3da0e91ef758728bdf6e58957c09fe044d97d1fa2a21c9c19e3bdf5109bf45b",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let prepared = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    client_standard_effect_computation_limits(),
  ).unwrap()
  let left = combined_unit_whole_capture(prepared, Ref(true), 0)
  let right = combined_unit_whole_capture(prepared, Ref(true), 1)
  assert_eq(
    @query.captured_source_relation_logical_cid(left.1),
    @query.captured_source_relation_logical_cid(right.1),
  )
  assert_false(
    @query.captured_source_relation_identity_matches_source(left.1, right.0),
  )
  let facts = @planning.source_acquisition_evidence_facts(left.2).unwrap()
  let saved = @publication.admit_model_source_observation(
    left.3,
    left.4,
    facts.source_ref,
    facts.source_contract_cid,
    "sha256:" + "a".repeat(64),
    facts.source_data_policy_cid,
    "2026-11-11T00:00:01.000Z",
    "2026-11-11T00:00:01.000Z",
  ).unwrap()
  assert_true(saved_model_imported_observation_matches(saved, left.4, left.3))
  assert_false(
    saved_model_imported_observation_matches(saved, right.4, right.3),
  )
  assert_false(saved_model_imported_observation_matches(saved, left.4, right.3))
}
