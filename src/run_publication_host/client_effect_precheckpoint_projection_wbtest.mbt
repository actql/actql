///|
fn effect_projection_fixture() -> ClientRemoteEffectTaskProgress {
  let (_, allowed, definition, _, _) = bound_effect_source_fixture()
  inspect_client_remote_effect_task_progress(
    allowed, definition, "sha256:" + "c".repeat(64), [],
  ).unwrap()
}

///|
fn effect_projection_claims(
  progress : ClientRemoteEffectTaskProgress,
) -> Array[ClientRemoteEffectTaskRunClaim] {
  progress.progress.keys.map(task_key => {
    task_key,
    dispatch_cid: None,
    dispatch_reserved: false,
    physical_start_claimed: false,
  })
}

///|
fn effect_projection_state(value : ClientRemoteEffectTaskRunProjection) -> Map[String, Json] {
  let parsed = @json.parse(client_remote_effect_task_run_projection_fields(value)[0]) catch {
    _ => abort("Expected valid unpublished candidate")
  }
  guard parsed is Object(fields) else { abort("Expected original Run fields") }
  fields
}

///|
test "Effect pre-checkpoint original task inventory is preparing without invented publication" {
  let progress = effect_projection_fixture()
  let projected = project_client_remote_effect_task_run(
    progress, "2026-10-09T00:01:00.000Z", false, effect_projection_claims(progress),
  ).unwrap()
  let state = effect_projection_state(projected)
  assert_eq(state.get("status"), Some(Json::string("preparing")))
  assert_eq(state.get("result_available"), Some(Json::boolean(false)))
  assert_eq(state.get("revision"), None)
  let fields = client_remote_effect_task_run_projection_fields(projected)
  assert_eq(fields[3], "0")
  assert_eq(fields[4], "0")
}

///|
test "Effect pre-checkpoint cancellation request alone is not a whole Run pre-start fence" {
  let progress = effect_projection_fixture()
  let projected = project_client_remote_effect_task_run(
    progress, "2026-10-09T00:01:00.000Z", true, effect_projection_claims(progress),
  ).unwrap()
  assert_eq(effect_projection_state(projected).get("status"), Some(Json::string("preparing")))
}

///|
test "Effect pre-checkpoint missing original claimed observation remains reconciliation" {
  let progress = effect_projection_fixture()
  let claims = effect_projection_claims(progress)
  claims[0] = {
    ..claims[0],
    dispatch_cid: Some("sha256:" + "d".repeat(64)),
    dispatch_reserved: true,
    physical_start_claimed: true,
  }
  let projected = project_client_remote_effect_task_run(
    progress, "2026-10-09T00:01:00.000Z", true, claims,
  ).unwrap()
  let state = effect_projection_state(projected)
  assert_eq(state.get("status"), Some(Json::string("needs_reconciliation")))
  guard state.get("next_action") is Some(Object(action)) else { abort("Expected original action") }
  assert_eq(action.get("kind"), Some(Json::string("reconcile_run")))
}

///|
test "Effect pre-checkpoint completed computation and task cleanup cannot complete cancellation" {
  let original = effect_projection_fixture()
  // White-box reducer counter only. These authored task facts are not
  // physical Site evidence, a whole Run stop or a cleanup acknowledgement.
  let progress = {
    ..original,
    progress: {
      ..original.progress,
      completed: original.progress.keys.map(_ => true),
      execution_complete: true,
      cleanup_complete: true,
      observations: original.progress.keys.map(_ => Some({
        execution: Some(@remote.NativeSettled),
        cleanup: Some(@remote.CleanupReleased),
        revision: 1,
        execution_terminal: true,
        cleanup_complete: true,
      })),
    },
  }
  let projected = project_client_remote_effect_task_run(
    progress, "2026-10-09T00:01:00.000Z", true, effect_projection_claims(progress),
  ).unwrap()
  let state = effect_projection_state(projected)
  assert_eq(state.get("status"), Some(Json::string("running")))
  assert_eq(state.get("result_available"), Some(Json::boolean(false)))
  let fields = client_remote_effect_task_run_projection_fields(projected)
  assert_eq(fields[3], "0")
  assert_eq(fields[4], "0")
}

///|
test "Effect pre-checkpoint original claim set refuses missing duplicate foreign and inconsistent rows" {
  let progress = effect_projection_fixture()
  let now = "2026-10-09T00:01:00.000Z"
  let claims = effect_projection_claims(progress)
  assert_true(project_client_remote_effect_task_run(progress, now, false, []) is Err(InvalidStartClaims))
  let duplicate = claims.copy()
  duplicate[1] = duplicate[0]
  assert_true(project_client_remote_effect_task_run(progress, now, false, duplicate) is Err(InvalidStartClaims))
  let foreign = claims.copy()
  foreign[0] = { ..foreign[0], task_key: "foreign-task", }
  assert_true(project_client_remote_effect_task_run(progress, now, false, foreign) is Err(InvalidStartClaims))
  let invalid = claims.copy()
  invalid[0] = { ..invalid[0], physical_start_claimed: true, }
  assert_true(project_client_remote_effect_task_run(progress, now, false, invalid) is Err(InvalidStartClaims))
}
