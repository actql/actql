///|
fn model_limits() -> ModelTaskLimits {
  {
    bodies: {
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_members: 10,
    },
    contracts: { max_nodes: 1000, max_depth: 50, max_text_bytes: 10000, },
    max_work: 100000,
  }
}

///|
fn model_core() -> Json raise {
  let text =
    #|{"authored_model_selector":"fixture-risk-model","connector_id":"models/fixture","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"text":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","max_items":2,"output_contract":{"additional_properties":false,"fields":{"reason":{"nullable":true,"type":"string"},"risk":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3","prompt_template_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:risk-score.v1","task_kind":"structured_generate","tool_policy":"none","version":"1"}
  @json.parse(text)
}

///|
fn model_wire(tasks : Array[String]) -> WireEnvironment {
  let items = tasks.copy()
  items.sort_by((a, b) => {
    @sha.hex(@utf8.encode(a)).compare(@sha.hex(@utf8.encode(b)))
  })
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[" +
    items.join(",") +
    "],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let text = prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix
  read(@utf8.encode(text), cid, {
    max_bytes: 200000,
    max_nodes: 20000,
    max_depth: 100,
    max_members: 100,
  }).unwrap()
}

///|
fn model_mutate(
  core : Json,
  path : Array[String],
  replacement : Json?,
) -> Unit raise {
  mutate_reference_fixture(core, path, 0, replacement)
}

///|
test "ModelTask resolves typed contracts and retains exact environment identity" {
  let body = sealed_fixture(model_core(), "contract_cid")
  let environment = model_wire([body])
  let tasks = check_model_tasks(environment, model_limits()).unwrap()
  let task = resolve_model_task(tasks, "model-task:risk-score.v1").unwrap()
  // Independent SHA-256 vectors calculated with Node crypto and canonical JSON.
  assert_eq(
    model_task_identity(task),
    (
      "model-task:risk-score.v1", "1", "sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560",
    ),
  )
  assert_eq(
    model_task_schema_cids(task),
    (
      "sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7",
      "sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3",
    ),
  )
  let item = member_at(environment, ModelTaskContracts, 0).unwrap()
  assert_true(physical_equal(model_tasks_environment(tasks), environment))
  assert_true(
    physical_equal(member_environment(model_task_member(task)), environment),
  )
  assert_true(model_task_for(tasks, item) is Some(_))
  let foreign = model_wire([body])
  assert_true(
    model_task_for(tasks, member_at(foreign, ModelTaskContracts, 0).unwrap())
    is None,
  )
  assert_true(model_task_at(tasks, -1) is None)
  assert_true(model_task_at(tasks, 1) is None)
  assert_true(
    resolve_model_task(tasks, "model-task:unknown")
    is Err({ kind: UnknownSelector(_), .. }),
  )
  assert_eq(model_task_connector(task), "models/fixture")
  assert_eq(model_task_model_selector(task), "fixture-risk-model")
  assert_eq(model_task_max_items(task), Some(2L))
  assert_eq(model_task_generation_config(task).seed_requested, Some(-7L))
  assert_eq(model_task_generation_config(task).max_output_tokens, 32L)
  assert_eq(model_task_generation_config(task).top_p, 1.0)
  assert_true(model_task_input(task).shape is @value_contract.Object(_))
  assert_false(model_task_output(task).nullable)
  guard model_task_output(task).shape is @value_contract.Object(output_fields) else {
    fail("closed output object")
  }
  let reason = @value_contract.field_at(output_fields, 0).unwrap()
  assert_eq(reason.name, "reason")
  assert_true(reason.contract.nullable)
  assert_true(model_task_accepts_classification(task, Public))
  assert_true(model_task_accepts_classification(task, Internal))
  assert_false(model_task_accepts_classification(task, Confidential))
  assert_false(model_task_accepts_classification(task, Unknown))
  assert_eq(model_task_region_count(task), 1)
  assert_eq(model_task_region_at(task, 0), Some("fixture-region"))
  assert_eq(model_task_region_at(task, 1), None)
  assert_false(model_task_provider_retention(task))
}

///|
test "ModelTask admission rejects recomputed environment over stale inner identities" {
  let core = model_core()
  let text = sealed_fixture(core, "contract_cid")
  let changed = text.replace(old="fixture-risk-model", new="other-risk-model")
  assert_true(
    check_model_tasks(model_wire([changed]), model_limits())
    is Err({ kind: IdentityMismatch, .. }),
  )
  for
    (name, expected) in [
      ("input_schema_cid", ModelTaskIssueKind::InputSchemaMismatch),
      ("output_schema_cid", ModelTaskIssueKind::OutputSchemaMismatch),
    ] {
    let core = model_core()
    model_mutate(core, [name], Some(Json::string("sha256:" + "b".repeat(64))))
    assert_true(
      check_model_tasks(
        model_wire([sealed_fixture(core, "contract_cid")]),
        model_limits(),
      )
      is Err({ kind, .. }) &&
      kind == expected,
    )
  }
  let body = sealed_fixture(model_core(), "contract_cid")
  assert_true(
    check_model_tasks(model_wire([body, body]), model_limits())
    is Err({ kind: DuplicateSelector(_), .. }),
  )
  let other = model_core()
  model_mutate(other, ["version"], Some(Json::string("2")))
  assert_true(
    check_model_tasks(
      model_wire([body, sealed_fixture(other, "contract_cid")]),
      model_limits(),
    )
    is Err({ kind: DuplicateSelector(_), .. }),
  )
}

///|
test "ModelTask checks unused malformed declarations and closed generation data handling" {
  for
    (path, value) in [
      (["schema"], Some(Json::string("actql.model_task/9"))),
      (["task_id"], Some(Json::string("risk-score"))),
      (["connector_id"], Some(Json::string(""))),
      (["prompt_template_cid"], Some(Json::string("sha256:" + "A".repeat(64)))),
      (["tool_policy"], Some(Json::string("tools"))),
      (["retrieval_policy"], Some(Json::string("search"))),
      (["streaming"], Some(Json::boolean(true))),
      (["max_items"], Some(Json::number(0))),
      (["max_items"], Some(Json::number(1.5))),
      (["unexpected"], Some(Json::boolean(true))),
      (["generation_config", "temperature"], None),
      (["generation_config", "top_p"], Some(Json::number(0))),
      (["generation_config", "top_p"], Some(Json::number(1.1))),
      (["generation_config", "max_output_tokens"], Some(Json::number(0))),
      (["generation_config", "seed_requested"], Some(Json::null())),
      (["generation_config", "hidden_tools"], Some(Json::boolean(true))),
      (["data_handling", "training_use"], Some(Json::string("allowed"))),
      (["data_handling", "retention"], Some(Json::string("unknown"))),
      (
        ["data_handling", "accepted_classifications"],
        Some(@json.parse("[\"unknown\"]")),
      ),
      (
        ["data_handling", "accepted_classifications"],
        Some(@json.parse("[\"public\",\"public\"]")),
      ),
      (["data_handling", "accepted_classifications"], Some(@json.parse("[]"))),
      (["data_handling", "allowed_regions"], Some(@json.parse("[\"x\",\"x\"]"))),
      (["data_handling", "allowed_regions"], Some(@json.parse("[]"))),
    ] {
    let core = model_core()
    model_mutate(core, path, value)
    assert_true(
      check_model_tasks(
        model_wire([sealed_fixture(core, "contract_cid")]),
        model_limits(),
      )
      is Err({ kind: InvalidBody, .. }),
    )
  }
}

///|
test "ModelTask has no omitted required-member defaults and keeps optional bounds absent" {
  for
    name in [
      "schema", "task_id", "version", "connector_id", "task_kind", "authored_model_selector",
      "prompt_template_cid", "input_schema_cid", "input_contract", "output_schema_cid",
      "output_contract", "generation_config", "tool_policy", "retrieval_policy",
      "streaming", "data_handling",
    ] {
    let core = model_core()
    model_mutate(core, [name], None)
    assert_true(
      check_model_tasks(
        model_wire([sealed_fixture(core, "contract_cid")]),
        model_limits(),
      )
      is Err({ kind: InvalidBody, .. }),
    )
  }
  let core = model_core()
  model_mutate(core, ["max_items"], None)
  model_mutate(core, ["generation_config", "seed_requested"], None)
  let checked = check_model_tasks(
    model_wire([sealed_fixture(core, "contract_cid")]),
    model_limits(),
  ).unwrap()
  let task = model_task_at(checked, 0).unwrap()
  assert_eq(model_task_max_items(task), None)
  assert_eq(model_task_generation_config(task).seed_requested, None)
  assert_eq(model_task_generation_config(task).temperature, 0.0)
}

///|
test "ModelTask input and output require checked nonnull closed object schemas" {
  for name in ["input_contract", "output_contract"] {
    let cid_name = if name == "input_contract" {
      "input_schema_cid"
    } else {
      "output_schema_cid"
    }
    for
      value in [
        @json.parse("{\"nullable\":false,\"type\":\"string\"}"),
        @json.parse(
          "{\"additional_properties\":false,\"fields\":{},\"nullable\":true,\"type\":\"object\"}",
        ),
      ] {
      let core = model_core()
      model_mutate(core, [name], Some(value))
      let cid = "sha256:" + @sha.hex(@utf8.encode(canonical_fixture(value)))
      model_mutate(core, [cid_name], Some(Json::string(cid)))
      assert_true(
        check_model_tasks(
          model_wire([sealed_fixture(core, "contract_cid")]),
          model_limits(),
        )
        is Err({ kind: InvalidObjectContract, .. }),
      )
    }
    let core = model_core()
    let invalid = @json.parse(
      "{\"additional_properties\":true,\"fields\":{},\"nullable\":false,\"type\":\"object\"}",
    )
    model_mutate(core, [name], Some(invalid))
    model_mutate(
      core,
      [cid_name],
      Some(
        Json::string(
          "sha256:" + @sha.hex(@utf8.encode(canonical_fixture(invalid))),
        ),
      ),
    )
    assert_true(
      check_model_tasks(
        model_wire([sealed_fixture(core, "contract_cid")]),
        model_limits(),
      )
      is Err({ kind: InvalidValueContract(_), .. }),
    )
  }
}

///|
test "ModelTask preparation limits accumulate across supplied bodies and contracts" {
  let body = sealed_fixture(model_core(), "contract_cid")
  let environment = model_wire([body])
  let tasks = check_model_tasks(environment, model_limits()).unwrap()
  let (bytes, nodes, work, contract_nodes, contract_text, count) = model_tasks_usage(
    tasks,
  )
  assert_eq(count, 1)
  let exact : ModelTaskLimits = {
    bodies: {
      max_bytes: bytes,
      max_nodes: nodes,
      max_depth: 100,
      max_members: 1,
    },
    contracts: {
      max_nodes: contract_nodes,
      max_depth: 50,
      max_text_bytes: contract_text,
    },
    max_work: work,
  }
  assert_true(check_model_tasks(environment, exact) is Ok(_))
  assert_true(
    check_model_tasks(environment, { ..exact, max_work: work - 1, })
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    check_model_tasks(environment, {
      ..exact,
      bodies: { ..exact.bodies, max_bytes: bytes - 1, },
    })
    is Err({ kind: BodyLimit, .. }),
  )
  assert_true(
    check_model_tasks(environment, {
      ..exact,
      bodies: { ..exact.bodies, max_nodes: nodes - 1, },
    })
    is Err({ kind: BodyLimit, .. }),
  )
  assert_true(
    check_model_tasks(environment, {
      ..exact,
      bodies: { ..exact.bodies, max_members: 0, },
    })
    is Err({ kind: TaskLimit, .. }),
  )
  assert_true(
    check_model_tasks(environment, {
      ..exact,
      contracts: { ..exact.contracts, max_nodes: contract_nodes - 1, },
    })
    is Err({ kind: InvalidValueContract(_), .. }),
  )
  assert_true(
    check_model_tasks(environment, {
      ..exact,
      contracts: { ..exact.contracts, max_text_bytes: contract_text - 1, },
    })
    is Err({ kind: InvalidValueContract(_), .. }),
  )
  assert_true(
    check_model_tasks(environment, { ..exact, max_work: -1, })
    is Err({ kind: InvalidLimits, .. }),
  )
  assert_true(
    check_model_tasks(model_wire([]), { ..exact, max_work: 0, }) is Ok(_),
  )
  let other = model_core()
  model_mutate(other, ["task_id"], Some(Json::string("model-task:other")))
  let two = model_wire([body, sealed_fixture(other, "contract_cid")])
  assert_true(
    check_model_tasks(two, { ..model_limits(), contracts: exact.contracts, })
    is Err({ kind: InvalidValueContract(_), .. }),
  )
}
