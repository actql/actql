///|
fn model_execution_core() -> Json raise {
  let text =
    #|{"backoff_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","default_publication":"outcomes","max_attempts_per_slot":2,"max_total_attempts":4,"max_total_cost_units":0,"max_total_duration_ms":1000,"max_total_token_reservation":128,"max_total_wire_bytes":2048,"media_input_contracts":{},"model_task_contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","retry_classification_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","version":"actql-model-execution-contract/0.1"}
  @json.parse(text)
}

///|
fn model_execution_fixture_task() -> ModelTaskContract raise {
  let environment = model_wire([sealed_fixture(model_core(), "contract_cid")])
  model_task_at(check_model_tasks(environment, model_limits()).unwrap(), 0).unwrap()
}

///|
fn model_execution_fixture_read(
  task : ModelTaskContract,
  core : Json,
) -> Result[ModelExecutionContract, ModelTaskIssue] raise {
  model_mutate(core, ["self_cid"], None)
  let text = sealed_fixture(core, "self_cid")
  let o = @json.parse(text)
  guard o is Object(fields) else { abort("object fixture") }
  guard fields["self_cid"] is String(pin) else { abort("CID fixture") }
  read_model_execution_contract(
    task,
    @utf8.encode(text),
    pin,
    model_limits().bodies,
    100000,
  )
}

///|
test "Model execution contract binds exact admitted task and all finite ceilings" {
  let task = model_execution_fixture_task()
  let checked = model_execution_fixture_read(task, model_execution_core()).unwrap()
  assert_true(physical_equal(model_execution_task(checked), task))
  assert_eq(model_execution_ceiling(checked, AttemptsPerSlot), 2L)
  assert_eq(model_execution_ceiling(checked, TotalAttempts), 4L)
  assert_eq(model_execution_ceiling(checked, TotalCostUnits), 0L)
  assert_eq(model_execution_ceiling(checked, TotalDurationMs), 1000L)
  assert_eq(model_execution_ceiling(checked, TotalWireBytes), 2048L)
  assert_eq(model_execution_ceiling(checked, TotalTokenReservation), 128L)
  assert_eq(model_execution_media_count(checked), 0)
  assert_eq(model_execution_media_at(checked, 0), None)
  assert_eq(model_execution_retry_cid(checked), "sha256:" + "a".repeat(64))
  assert_eq(model_execution_backoff_cid(checked), "sha256:" + "a".repeat(64))
  // Independent Node crypto vector; retries/backoff are still dependencies.
  assert_eq(
    model_execution_cid(checked),
    "sha256:564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da",
  )
  let (bytes, nodes, work) = model_execution_usage(checked)
  let limits : Limits = {
    max_bytes: bytes,
    max_nodes: nodes,
    max_depth: 100,
    max_members: 0,
  }
  let text = sealed_fixture(model_execution_core(), "self_cid")
  let pin = model_execution_cid(checked)
  assert_true(
    read_model_execution_contract(task, @utf8.encode(text), pin, limits, work)
    is Ok(_),
  )
  assert_true(
    read_model_execution_contract(
      task,
      @utf8.encode(text),
      pin,
      limits,
      work - 1,
    )
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    read_model_execution_contract(
      task,
      @utf8.encode(text),
      pin,
      { ..limits, max_bytes: bytes - 1, },
      work,
    )
    is Err({ kind: BodyLimit, .. }),
  )
  assert_true(
    read_model_execution_contract(
      task,
      @utf8.encode(text),
      pin,
      { ..limits, max_nodes: nodes - 1, },
      work,
    )
    is Err({ kind: BodyLimit, .. }),
  )
  assert_true(
    read_model_execution_contract(
      task,
      @utf8.encode(" " + text),
      pin,
      model_limits().bodies,
      100000,
    )
    is Err({ kind: InvalidBody, .. }),
  )
  assert_true(
    read_model_execution_contract(
      task,
      @utf8.encode(text),
      "sha256:" + "b".repeat(64),
      limits,
      work,
    )
    is Err({ kind: IdentityMismatch, .. }),
  )
  assert_true(
    read_model_execution_contract(
      task,
      @utf8.encode(text.replace(old="1000", new="1001")),
      pin,
      model_limits().bodies,
      100000,
    )
    is Err({ kind: IdentityMismatch, .. }),
  )
}

///|
test "Model execution rejects missing ceilings and wrong task references without defaults" {
  let task = model_execution_fixture_task()
  for
    name in [
      "version", "model_task_contract_cid", "retry_classification_contract_cid",
      "max_attempts_per_slot", "max_total_attempts", "max_total_cost_units", "max_total_duration_ms",
      "max_total_wire_bytes", "max_total_token_reservation", "backoff_contract_cid",
      "media_input_contracts", "default_publication",
    ] {
    let core = model_execution_core()
    model_mutate(core, [name], None)
    assert_true(
      model_execution_fixture_read(task, core) is Err({ kind: InvalidBody, .. }),
    )
  }
  let core = model_execution_core()
  model_mutate(
    core,
    ["model_task_contract_cid"],
    Some(Json::string("sha256:" + "b".repeat(64))),
  )
  assert_true(
    model_execution_fixture_read(task, core)
    is Err({ kind: ReferenceMismatch, .. }),
  )
  for
    (path, value) in [
      (["version"], Json::string("actql-model-execution-contract/" + "invalid")),
      (["default_publication"], Json::string("fail")),
      (["max_attempts_per_slot"], Json::number(0)),
      (["max_total_attempts"], Json::number(1.5)),
      (["max_total_cost_units"], Json::number(-1)),
      (["max_total_duration_ms"], Json::number(0)),
      (["max_total_wire_bytes"], Json::number(0)),
      (["max_total_token_reservation"], Json::number(0)),
      (["backoff_contract_cid"], Json::string("sha256:" + "A".repeat(64))),
      (["media_input_contracts"], Json::null()),
      (["unexpected"], Json::boolean(true)),
    ] {
    let core = model_execution_core()
    model_mutate(core, path, Some(value))
    assert_true(
      model_execution_fixture_read(task, core) is Err({ kind: InvalidBody, .. }),
    )
  }
}

///|
test "Model execution retains media contract references without pretending to admit content" {
  let task = model_execution_fixture_task()
  let core = model_execution_core()
  model_mutate(
    core,
    ["media_input_contracts"],
    Some(
      @json.parse(
        "{\"attachments\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"}",
      ),
    ),
  )
  let checked = model_execution_fixture_read(task, core).unwrap()
  assert_eq(model_execution_media_count(checked), 1)
  assert_eq(
    model_execution_media_at(checked, 0),
    Some(("attachments", "sha256:" + "b".repeat(64))),
  )
  model_mutate(
    core,
    ["media_input_contracts", "attachments"],
    Some(Json::string("not-a-cid")),
  )
  assert_true(
    model_execution_fixture_read(task, core) is Err({ kind: InvalidBody, .. }),
  )
}
