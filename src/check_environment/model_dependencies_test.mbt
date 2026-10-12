///|
fn dependency_fixture(
  retry : String,
  backoff : String,
  input? : Json,
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
  if input is Some(input) {
    model_mutate(task_core, ["input_contract"], Some(input))
    model_mutate(
      task_core,
      ["input_schema_cid"],
      Some(
        Json::string(
          "sha256:" + @sha.hex(@utf8.encode(canonical_fixture(input))),
        ),
      ),
    )
  }
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
fn model_media_dependency_fixture() -> Json raise {
  @json.parse(
    (
      #|{"version":"actql-model-media-input/0.1","payload":{"media_type":"application/pdf","max_bytes":4096,"max_pages":4,"max_frames":null,"complete":true,"transfer_method":"inline_bytes","classifications":["internal"],"regions":["fixture-region"],"egress_scope_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}
    ),
  )
}

///|
test "Model media dependencies resolve their original checked role and canonical body" {
  let (base, prompt, retry, backoff) = dependency_fixture(
    "{\"version\":\"actql-model-retry-policy/0.1\",\"retryable_failures\":[]}",
    "{\"version\":\"actql-model-backoff/0.1\",\"delays_ms\":[]}",
    input=@json.parse(
      (
        #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"document":{"type":"content_ref","nullable":true,"media_type":"application/pdf"}}}
      ),
    ),
  )
  let media_wire = sealed_fixture(model_media_dependency_fixture(), "self_cid")
  guard @json.parse(media_wire) is Object(body) &&
    body["self_cid"] is String(pin) else {
    fail("sealed media fixture")
  }
  let core = model_execution_core()
  let task = model_execution_task(base)
  for
    (name, value) in [
      ("model_task_contract_cid", model_task_identity(task).2),
      ("retry_classification_contract_cid", model_execution_retry_cid(base)),
      ("backoff_contract_cid", model_execution_backoff_cid(base)),
    ] {
    model_mutate(core, [name], Some(Json::string(value)))
  }
  model_mutate(
    core,
    ["media_input_contracts"],
    Some(Json::object(Map([("document", Json::string(pin))]))),
  )
  let execution = model_execution_fixture_read(task, core).unwrap()
  let limits = model_limits().bodies
  let read = (media : Array[(String, Bytes)]) => {
    read_single_attempt_model_dependencies(
      execution,
      Some(prompt),
      Some(retry),
      Some(backoff),
      limits,
      100000,
      media~,
    )
  }
  // A valid symbolic reference used to be ignored entirely by dependency
  // admission. Neither the provider nor a differently named body supplies it.
  assert_true(read([]) is Err(Missing(ModelMediaInput("document"))))
  assert_true(
    read([("wrong-role", @utf8.encode(media_wire))])
    is Err(Missing(ModelMediaInput("document"))),
  )
  assert_true(
    read([
      ("document", @utf8.encode(media_wire)),
      ("document", @utf8.encode(media_wire)),
    ])
    is Err(Body(ModelMediaInput("document"), { kind: InvalidBody, .. })),
  )
  let admitted = read([("document", @utf8.encode(media_wire))]).unwrap()
  let media = single_attempt_model_media(admitted, "document").unwrap()
  assert_eq(
    pin, "sha256:ece55a0064625c262ee09ae48b8293377848469876c77b1c19718dab759280fe",
  )
  assert_eq(model_dependency_identity(media), pin)
  // Three canonical byte passes (3 * 420), envelope inspection (123) and
  // closed media-field inspection (232), independently from product output.
  assert_eq(model_dependency_usage(media), (420, 15, 1615))
  assert_true(
    read_model_dependency(
      ModelMediaInput("document"),
      @utf8.encode(media_wire),
      pin,
      { ..limits, max_bytes: 420, max_nodes: 15, },
      1615,
    )
    is Ok(_),
  )
  assert_true(
    read_model_dependency(
      ModelMediaInput("document"),
      @utf8.encode(media_wire),
      pin,
      limits,
      1614,
    )
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(model_dependency_payload(media) is Some(_))
  assert_true(single_attempt_model_media(admitted, "wrong-role") is None)
  assert_true(
    read([("document", prompt)])
    is Err(Body(ModelMediaInput("document"), { kind: InvalidBody, .. })),
  )
  let substituted = model_media_dependency_fixture()
  model_mutate(substituted, ["payload", "max_bytes"], Some(Json::number(8192)))
  assert_true(
    read([("document", @utf8.encode(sealed_fixture(substituted, "self_cid")))])
    is Err(Body(ModelMediaInput("document"), { kind: IdentityMismatch, .. })),
  )
  let total = prompt.length() +
    retry.length() +
    backoff.length() +
    @utf8.encode(media_wire).length()
  assert_true(
    read_single_attempt_model_dependencies(
      execution,
      Some(prompt),
      Some(retry),
      Some(backoff),
      { ..limits, max_bytes: total - 1, },
      100000,
      media=[("document", @utf8.encode(media_wire))],
    )
    is Err(Body(ModelMediaInput("document"), { kind: BodyLimit, .. })),
  )
}

///|
test "Model media body refuses missing bounds and unsupported or ambiguous transport facts" {
  for
    (path, replacement) in [
      (["payload", "max_bytes"], None),
      (["payload", "max_pages"], None),
      (["payload", "complete"], Some(Json::boolean(false))),
      (["payload", "max_bytes"], Some(Json::number(0))),
      (["payload", "transfer_method"], Some(Json::string("arbitrary_url"))),
      (
        ["payload", "classifications"],
        Some(@json.parse("[\"internal\",\"internal\"]")),
      ),
      (["payload", "regions"], Some(@json.parse("[]"))),
      (["payload", "egress_scope_cid"], Some(Json::string("unbound"))),
      (["payload", "extra"], Some(Json::boolean(true))),
    ] {
    let body = model_media_dependency_fixture()
    model_mutate(body, path, replacement)
    let wire = sealed_fixture(body, "self_cid")
    guard @json.parse(wire) is Object(fields) &&
      fields["self_cid"] is String(pin) else {
      fail("sealed invalid fixture")
    }
    assert_true(
      read_model_dependency(
        ModelMediaInput("document"),
        @utf8.encode(wire),
        pin,
        model_limits().bodies,
        100000,
      )
      is Err({ kind: InvalidBody, .. }),
    )
  }
}

///|
test "Model media roles match declared Content types without inspecting input rows" {
  let wire = sealed_fixture(model_media_dependency_fixture(), "self_cid")
  guard @json.parse(wire) is Object(body) && body["self_cid"] is String(pin) else {
    fail("media fixture CID")
  }
  for
    (field, expected) in [
      (
        "{\"type\":\"content_ref\",\"nullable\":true,\"media_type\":\"application/pdf\"}",
        None,
      ),
      ("{\"type\":\"content_ref\",\"nullable\":false}", None),
      (
        "{\"type\":\"array\",\"nullable\":true,\"max_items\":2,\"items\":{\"type\":\"content_ref\",\"nullable\":true,\"media_type\":\"application/pdf\"}}",
        None,
      ),
      (
        "{\"type\":\"content_ref\",\"nullable\":true,\"media_type\":\"image/png\"}",
        Some(ModelMediaRoleIssue::MediaTypeMismatch),
      ),
      (
        "{\"type\":\"string\",\"nullable\":true}",
        Some(ModelMediaRoleIssue::UnsupportedShape),
      ),
      (
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"content_ref\",\"nullable\":false,\"media_type\":\"application/pdf\"}}",
        Some(ModelMediaRoleIssue::UnsupportedShape),
      ),
      (
        "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{\"nested\":{\"type\":\"content_ref\",\"nullable\":true,\"media_type\":\"application/pdf\"}}}",
        Some(ModelMediaRoleIssue::UnsupportedShape),
      ),
    ] {
    let input = @json.parse(
      "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{\"document\":" +
      field +
      "}}",
    )
    let (base, prompt, retry, backoff) = dependency_fixture(
      "{\"version\":\"actql-model-retry-policy/0.1\",\"retryable_failures\":[]}",
      "{\"version\":\"actql-model-backoff/0.1\",\"delays_ms\":[]}",
      input~,
    )
    let task = model_execution_task(base)
    let core = model_execution_core()
    for
      (name, value) in [
        ("model_task_contract_cid", model_task_identity(task).2),
        ("retry_classification_contract_cid", model_execution_retry_cid(base)),
        ("backoff_contract_cid", model_execution_backoff_cid(base)),
      ] {
      model_mutate(core, [name], Some(Json::string(value)))
    }
    model_mutate(
      core,
      ["media_input_contracts"],
      Some(Json::object(Map([("document", Json::string(pin))]))),
    )
    let execution = model_execution_fixture_read(task, core).unwrap()
    let result = read_single_attempt_model_dependencies(
      execution,
      Some(prompt),
      Some(retry),
      Some(backoff),
      model_limits().bodies,
      100000,
      media=[("document", @utf8.encode(wire))],
    )
    match expected {
      Some(expected) =>
        assert_true(
          result is Err(MediaRole("document", actual)) && actual == expected,
        )
      None => {
        let dependencies = result.unwrap()
        let original = single_attempt_model_media(dependencies, "document").unwrap()
        assert_eq(model_dependency_identity(original), pin)
        // Every direct nullable Content role still requires a contract, even
        // when a future call supplies NULL or the input Relation is empty.
        assert_true(
          read_single_attempt_model_dependencies(
            base,
            Some(prompt),
            Some(retry),
            Some(backoff),
            model_limits().bodies,
            100000,
          )
          is Err(Missing(ModelMediaInput("document"))),
        )
      }
    }
  }
  let (execution, prompt, retry, backoff) = dependency_fixture(
    "{\"version\":\"actql-model-retry-policy/0.1\",\"retryable_failures\":[]}", "{\"version\":\"actql-model-backoff/0.1\",\"delays_ms\":[]}",
  )
  let task = model_execution_task(execution)
  let core = model_execution_core()
  for
    (name, value) in [
      ("model_task_contract_cid", model_task_identity(task).2),
      (
        "retry_classification_contract_cid",
        model_execution_retry_cid(execution),
      ),
      ("backoff_contract_cid", model_execution_backoff_cid(execution)),
    ] {
    model_mutate(core, [name], Some(Json::string(value)))
  }
  model_mutate(
    core,
    ["media_input_contracts"],
    Some(Json::object(Map([("document", Json::string(pin))]))),
  )
  let wrong_role = model_execution_fixture_read(task, core).unwrap()
  assert_true(
    read_single_attempt_model_dependencies(
      wrong_role,
      Some(prompt),
      Some(retry),
      Some(backoff),
      model_limits().bodies,
      100000,
      media=[("document", @utf8.encode(wire))],
    )
    is Err(MediaRole("document", UnknownRole)),
  )
  // Ordinary scalar dependencies retain their existing admitted path.
  assert_true(
    read_single_attempt_model_dependencies(
      execution,
      Some(prompt),
      Some(retry),
      Some(backoff),
      model_limits().bodies,
      100000,
    )
    is Ok(_),
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
