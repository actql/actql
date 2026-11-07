///|
// Real Core source/request/compiler/material boundary. The Account fixture is
// explicit; this grants no physical Host, durable acceptance or start.
fn source_request_original() -> (
  @checked.CheckEnvironment,
  @input.LocalSourceComputation,
  @input.LocalSubmittedPreparation,
) {
  let env = environment()
  let intent = @host.prepare_client_submitted_intent(
    "{\"input\":{\"format\":\"sql\",\"text\":\"SELECT 1 AS n\"},\"kind\":\"aql\",\"parameters\":null}",
    65536, 8192, 64,
  ).unwrap()
  let source = @input.prepare_local_source_computation(
    intent,
    env,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(env) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let submitted = @input.local_source_pure_submitted_preparation(
    source, intent, env,
  ).unwrap()
  (env, source, submitted)
}

///|
fn source_request_plan(
  submitted : @input.LocalSubmittedPreparation,
) -> LocalRunPlan {
  let input = @input.local_submitted_preparation_input(submitted)
  let current = account(Allow)
  prepare_source_free_local_run(
    input,
    "sha256:" + "b".repeat(64),
    "original-source-request",
    permit(input, current),
    current,
    tuple(),
    context_cid(),
    "sha256:" + "c".repeat(64),
    "local",
    "source-original-run",
    "2026-10-10T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
    submitted=Some(submitted),
  ).unwrap()
}

///|
test "published Source Run keeps original input intent instead of legacy source-free domain" {
  let (_, source, submitted) = source_request_original()
  let original = source_request_plan(submitted)
  let expected = @input.local_source_computation_request(
    source,
    "sha256:" + "b".repeat(64),
    "original-source-request",
  ).unwrap()
  assert_eq(local_run_request(original), expected)
  assert_eq(
    @host.client_request_input_cid(local_run_request(original)),
    @host.client_submitted_intent_cid(
      @input.local_submitted_preparation_intent(submitted),
    ),
  )
  let legacy = @host.prepare_source_free_client_request_identity(
    local_run_prepared(original),
    "sha256:" + "b".repeat(64),
    "original-source-request",
  ).unwrap()
  assert_true(
    @host.client_request_identity_relation(legacy, expected) is ChangedIntent,
  )
  @host.validate_client_run_binding(
    expected,
    local_run_prepared(original),
    local_run_compiled(original),
    local_run_definition(original),
  ).unwrap()
  let input = @input.local_submitted_preparation_input(submitted)
  let (_, _, foreign) = source_request_original()
  let current = account(Allow)
  assert_true(
    local_run_request_original(
      input,
      "sha256:" + "b".repeat(64),
      "original-source-request",
      Some(foreign),
    )
    is Err(@host.IdentityMismatch),
  )
  assert_true(
    physical_equal(
      local_run_prepared(original),
      @input.local_prepared_program(input),
    ),
  )
  assert_true(
    authorized_input(
      local_run_prepared(original),
      permit(input, current),
      current,
      tuple(),
      context_cid(),
    ),
  )
}

///|
test "published Source saved materials preserve request and codec program without fresh issuance" {
  let (env, _, submitted) = source_request_original()
  let original = source_request_plan(submitted)
  let input = @input.local_submitted_preparation_input(submitted)
  let wire = export_local_run_materials(original, env, environment_wire, None).unwrap()
  let cid = local_run_definition_cid(original)
  let materials = restore_local_run_materials(wire, cid).unwrap()
  let current = account(Allow)
  let restore = (selection : @input.LocalSubmittedPreparation?) => {
    restore_source_free_local_run_from_materials(
      input,
      materials,
      cid,
      local_run_request(original),
      "sha256:" + "b".repeat(64),
      permit(input, current),
      current,
      tuple(),
      context_cid(),
      "sha256:" + "c".repeat(64),
      submitted=selection,
    )
  }
  assert_true(restore(None) is Err(Start(@host.ChangedIntent)))
  let restored = restore(Some(submitted)).unwrap()
  assert_eq(local_run_request(restored), local_run_request(original))
  assert_eq(local_run_definition_cid(restored), cid)
  assert_true(
    physical_equal(
      local_run_prepared(restored),
      @host.client_task_run_materials_retained_program(
        @host.client_task_run_materials_retained_input(materials),
      ),
    ),
  )
  let (_, _, foreign) = source_request_original()
  assert_true(restore(Some(foreign)) is Err(Request(@host.IdentityMismatch)))
  assert_true(
    restore_local_run_materials(wire, "sha256:" + "f".repeat(64)) is Err(_),
  )
}
