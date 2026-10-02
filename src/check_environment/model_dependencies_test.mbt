///|
fn dependency_fixture(
  retry : String,
  backoff : String,
) -> (ModelExecutionContract, Bytes, Bytes, Bytes) raise {
  let prompt = sealed_fixture(
    @json.parse("{\"version\":\"actql-model-prompt/0.1\",\"payload\":null}"),
    "self_cid",
  )
  let retry = sealed_fixture(@json.parse(retry), "self_cid")
  let backoff = sealed_fixture(@json.parse(backoff), "self_cid")
  let pin = (wire : String) => {
    guard @json.parse(wire) is Object(fields) &&
      fields["self_cid"] is String(value) else {
      abort("fixture CID")
    }
    value
  }
  let task_core = model_core()
  model_mutate(
    task_core,
    ["prompt_template_cid"],
    Some(Json::string(pin(prompt))),
  )
  let task = model_task_at(
    check_model_tasks(
      model_wire([sealed_fixture(task_core, "contract_cid")]),
      model_limits(),
    ).unwrap(),
    0,
  ).unwrap()
  let execution_core = model_execution_core()
  let (_, _, task_cid) = model_task_identity(task)
  model_mutate(
    execution_core,
    ["model_task_contract_cid"],
    Some(Json::string(task_cid)),
  )
  model_mutate(
    execution_core,
    ["retry_classification_contract_cid"],
    Some(Json::string(pin(retry))),
  )
  model_mutate(
    execution_core,
    ["backoff_contract_cid"],
    Some(Json::string(pin(backoff))),
  )
  model_mutate(execution_core, ["max_attempts_per_slot"], Some(Json::number(1)))
  model_mutate(execution_core, ["max_total_attempts"], Some(Json::number(1)))
  (
    model_execution_fixture_read(task, execution_core).unwrap(),
    @utf8.encode(prompt),
    @utf8.encode(retry),
    @utf8.encode(backoff),
  )
}

///|
test "Single attempt dependencies resolve only their checked execution references" {
  let retry = "{\"version\":\"actql-model-retry-policy/0.1\",\"retryable_failures\":[]}"
  let backoff = "{\"version\":\"actql-model-backoff/0.1\",\"delays_ms\":[]}"
  let (execution, prompt, retries, delays) = dependency_fixture(retry, backoff)
  let read = (p, r, b) => {
    read_single_attempt_model_dependencies(
      execution,
      p,
      r,
      b,
      model_limits().bodies,
      100000,
    )
  }
  let bundle = read(Some(prompt), Some(retries), Some(delays)).unwrap()
  assert_true(single_attempt_model_dependencies_match(bundle, execution))
  let (foreign, _, _, _) = dependency_fixture(retry, backoff)
  assert_false(single_attempt_model_dependencies_match(bundle, foreign))
  assert_true(
    read(None, Some(retries), Some(delays)) is Err(Missing(ModelPrompt)),
  )
  assert_true(
    read(Some(prompt), None, Some(delays)) is Err(Missing(ModelRetryPolicy)),
  )
  assert_true(
    read(Some(prompt), Some(retries), None) is Err(Missing(ModelBackoff)),
  )
  assert_true(
    read(Some(retries), Some(retries), Some(delays))
    is Err(Body(ModelPrompt, { kind: InvalidBody, .. })),
  )
  let substituted = sealed_fixture(
    @json.parse("{\"version\":\"actql-model-prompt/0.1\",\"payload\":true}"),
    "self_cid",
  )
  assert_true(
    read(Some(@utf8.encode(substituted)), Some(retries), Some(delays))
    is Err(Body(ModelPrompt, { kind: IdentityMismatch, .. })),
  )
}

///|
test "Nonempty retry and backoff are structurally valid but unsupported before dispatch" {
  for
    (retry, backoff, expected) in [
      (
        "{\"version\":\"actql-model-retry-policy/0.1\",\"retryable_failures\":[\"timeout\"]}",
        "{\"version\":\"actql-model-backoff/0.1\",\"delays_ms\":[]}",
        ModelDependencyKind::ModelRetryPolicy,
      ),
      (
        "{\"version\":\"actql-model-retry-policy/0.1\",\"retryable_failures\":[]}",
        "{\"version\":\"actql-model-backoff/0.1\",\"delays_ms\":[0]}",
        ModelDependencyKind::ModelBackoff,
      ),
    ] {
    let (execution, prompt, retries, delays) = dependency_fixture(
      retry, backoff,
    )
    assert_true(
      read_single_attempt_model_dependencies(
        execution,
        Some(prompt),
        Some(retries),
        Some(delays),
        model_limits().bodies,
        100000,
      )
      is Err(UnsupportedPolicy(kind)) &&
      kind == expected,
    )
    // Invalid later input cannot be hidden by an earlier unsupported policy.
    assert_true(
      read_single_attempt_model_dependencies(
        execution,
        Some(prompt),
        Some(retries),
        Some(b"{}"),
        model_limits().bodies,
        100000,
      )
      is Err(Body(ModelBackoff, _)),
    )
  }
}
