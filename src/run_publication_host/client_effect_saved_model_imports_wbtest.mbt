///|
// The existing actual compiler/Values fixture supplies explicit semantic Scope
// DATA. These checks establish original-context identity/currentness only;
// they are not Source/Model execution, funding or an imported-evidence success.
fn saved_model_imported_scope_test_fixture(
  available : () -> Bool,
) -> (ClientCompiledRun, ClientInferCallScope, ClientInferSavedCallScope) raise {
  let (compiled, scope, _) = model_local_invocation_fixture()
  let definition = issue_client_compiled_run_definition(
    compiled, "saved-model-imports", "same-original-run",
    "2026-10-15T00:00:00.000Z", "2026-10-16T00:00:00.000Z",
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
  let (foreign, foreign_scope, foreign_saved) = saved_model_imported_scope_test_fixture(
    () => abort("foreign original must refuse before its custody callback"),
  )
  assert_false(saved_model_imported_scope_matches(foreign, scope, saved))
  assert_false(saved_model_imported_scope_matches(compiled, foreign_scope, saved))
  assert_false(saved_model_imported_scope_matches(compiled, scope, foreign_saved))
  // Equal admitted wire is not the retained nominal evidence original.
  let replacement = @publication.admit_run_evidence_value(
    @publication.run_evidence_value_name(saved.artifact),
    @publication.run_evidence_value_json(saved.artifact),
    10000, 1000, 20,
  ).unwrap()
  assert_false(
    saved_model_imported_scope_matches(
      compiled, { ..scope, artifact: replacement, }, saved,
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
    saved_model_imported_scope_matches(
      compiled, scope, { ..saved, occurrence: foreign.occurrence, },
    ),
  )
  assert_eq(calls.val, 0)
}
