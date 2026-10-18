///|
fn mock_answer_task() -> @environment.PublicModelTaskDeclaration {
  @environment.read_public_model_task_document(
    (
      #|{"task":"model-task:original.v1","input":{"text":"string"},"output":{"enabled":"boolean"},"instructions":"original"}
    ),
    "json",
    {
      bodies: {
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 16,
        max_members: 100,
      },
      contracts: { max_nodes: 100, max_depth: 16, max_text_bytes: 1000, },
      max_work: 100000,
    },
  ).unwrap()
}

///|
fn mock_answer_limits() -> ModelMockAnswerLimits {
  {
    document: {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 16,
      max_members: 100,
    },
    values: { max_nodes: 100, max_depth: 16, max_text_bytes: 1000, },
    max_entries: 10,
    max_work: 100000,
  }
}

///|
fn mock_answer_wire(body : String) -> String {
  "{\"task\":\"model-task:original.v1\",\"answers\":" + body + "}"
}

///|
test "mock answers retain actual Task output and exact default and keyed DATA" {
  let task = mock_answer_task()
  let yaml =
    #|task: model-task:original.v1
    #|answers:
    #|  default: {enabled: false}
    #|  by_key:
    #|    "e\u0301": {enabled: true}
    #|    "é": {enabled: false}
  let original = read_model_mock_answer_document(
    task,
    yaml,
    "yaml",
    mock_answer_limits(),
  ).unwrap()
  assert_eq(model_mock_answer_count(original, task), Ok(2))
  let fallback = model_mock_answer_default(original, task).unwrap().unwrap()
  let output = @environment.public_model_task_contract(
    @environment.public_model_task_declaration_contracts(task).1,
  )
  assert_true(physical_equal(fallback.contract, output))
  let first = model_mock_answer_at(original, task, 0).unwrap().unwrap()
  let second = model_mock_answer_at(original, task, 1).unwrap().unwrap()
  assert_eq(first.0, "e\u{0301}")
  assert_eq(second.0, "é")
  assert_true(physical_equal(first.1.contract, output))
  assert_true(physical_equal(second.1.contract, output))
  assert_true(model_mock_answer_at(original, task, -1).unwrap() is None)
  assert_true(model_mock_answer_at(original, task, 2).unwrap() is None)
}

///|
test "mock answers keep explicit empty absence and reject null without manufacturing an answer" {
  let task = mock_answer_task()
  let original = read_model_mock_answer_document(
    task,
    mock_answer_wire("{}"),
    "json",
    mock_answer_limits(),
  ).unwrap()
  assert_true(model_mock_answer_default(original, task).unwrap() is None)
  assert_eq(model_mock_answer_count(original, task), Ok(0))
  for body in ["null", "{\"default\":null}", "{\"by_key\":null}"] {
    assert_true(
      read_model_mock_answer_document(
        task,
        mock_answer_wire(body),
        "json",
        mock_answer_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "mock answers validate every unused answer and preserve strict document grammar" {
  let task = mock_answer_task()
  for
    wire in [
      mock_answer_wire("{\"default\":{\"enabled\":\"false\"}}"),
      mock_answer_wire(
        "{\"default\":{\"enabled\":true},\"by_key\":{\"unused\":{\"enabled\":0}}}",
      ),
      mock_answer_wire(
        "{\"by_key\":{\"same\":{\"enabled\":true},\"same\":{\"enabled\":false}}}",
      ),
      mock_answer_wire("{\"default\":{\"enabled\":true,\"extra\":false}}"),
      mock_answer_wire("{\"default\":{\"enabled\":true},\"unknown\":{}}"),
      "{\"task\":\"model-task:original.v1\",\"answers\":{},\"provider\":\"live\"}",
      "{\"task\":\"model-task:original.v1\"}",
      mock_answer_wire("{}") + "true",
    ] {
    assert_true(
      read_model_mock_answer_document(task, wire, "json", mock_answer_limits())
      is Err(_),
    )
  }
  assert_true(
    read_model_mock_answer_document(
      task,
      mock_answer_wire("{}"),
      "unknown",
      mock_answer_limits(),
    )
    is Err(InvalidBody),
  )
}

///|
test "mock answers bind the same Task original not an equal identifier or copied inventory" {
  let task = mock_answer_task()
  let original = read_model_mock_answer_document(
    task,
    mock_answer_wire("{\"default\":{\"enabled\":true}}"),
    "json",
    mock_answer_limits(),
  ).unwrap()
  let same_id = mock_answer_task()
  assert_true(
    model_mock_answer_default(original, same_id) is Err(ForeignOriginal),
  )
  let copied : ModelMockAnswers = { ..original, }
  assert_true(model_mock_answer_count(copied, task) is Err(ForeignOriginal))
  assert_true(retire_model_mock_answers(copied, task) is Err(ForeignOriginal))
  assert_true(model_mock_answer_default(original, task).unwrap() is Some(_))
  assert_true(
    read_model_mock_answer_document(
      task,
      mock_answer_wire("{}").replace(old="original.v1", new="other.v1"),
      "json",
      mock_answer_limits(),
    )
    is Err(TaskIdentity),
  )
}

///|
test "mock answers bound aggregate typed holdings and all keyed entries" {
  let task = mock_answer_task()
  let wire = mock_answer_wire(
    "{\"default\":{\"enabled\":true},\"by_key\":{\"a\":{\"enabled\":false}}}",
  )
  let limits = mock_answer_limits()
  let original = read_model_mock_answer_document(task, wire, "json", limits).unwrap()
  let (_, nodes, text) = model_mock_answer_usage(original)
  let exact : ModelMockAnswerLimits = {
    ..limits,
    values: { ..limits.values, max_nodes: nodes, max_text_bytes: text, },
    max_entries: 1,
  }
  assert_true(
    read_model_mock_answer_document(task, wire, "json", exact) is Ok(_),
  )
  assert_true(
    read_model_mock_answer_document(task, wire, "json", {
      ..exact,
      max_entries: 0,
    })
    is Err(EntryLimit),
  )
  assert_true(
    read_model_mock_answer_document(task, wire, "json", {
      ..exact,
      values: { ..exact.values, max_nodes: nodes - 1, },
    })
    is Err(OutputValue),
  )
  assert_true(
    read_model_mock_answer_document(task, wire, "json", {
      ..exact,
      values: { ..exact.values, max_text_bytes: text - 1, },
    })
    is Err(OutputValue),
  )
}

///|
test "mock answers reserve complete parse work and cancel incomplete typing at exact work bound" {
  let task = mock_answer_task()
  let limits = mock_answer_limits()
  let wire = mock_answer_wire("{\"default\":{\"enabled\":true}}")
  let original = read_model_mock_answer_document(task, wire, "json", limits).unwrap()
  let (work, _, _) = model_mock_answer_usage(original)
  assert_true(
    read_model_mock_answer_document(task, wire, "json", {
      ..limits,
      max_work: work,
    })
    is Ok(_),
  )
  assert_true(
    read_model_mock_answer_document(task, wire, "json", {
      ..limits,
      max_work: work - 1,
    })
    is Err(WorkLimit),
  )
  assert_true(
    read_model_mock_answer_document(task, wire, "json", {
      ..limits,
      max_work: 1,
    })
    is Err(WorkLimit),
  )
  assert_true(
    read_model_mock_answer_document(task, wire, "json", {
      ..limits,
      document: { ..limits.document, max_bytes: 1, },
    })
    is Err(BodyLimit),
  )
  assert_true(
    read_model_mock_answer_document(task, wire, "json", {
      ..limits,
      max_entries: -1,
    })
    is Err(InvalidLimits),
  )
}

///|
test "mock answer retirement drops managed aliases without retiring an escaped checked value" {
  let task = mock_answer_task()
  let original = read_model_mock_answer_document(
    task,
    mock_answer_wire(
      "{\"default\":{\"enabled\":true},\"by_key\":{\"a\":{\"enabled\":false}}}",
    ),
    "json",
    mock_answer_limits(),
  ).unwrap()
  let escaped = model_mock_answer_default(original, task).unwrap().unwrap()
  assert_eq(retire_model_mock_answers(original, task), Ok(()))
  assert_true(original.task is None)
  assert_true(original.document is None)
  assert_true(original.fallback is None)
  assert_eq(original.entries.length(), 0)
  assert_true(model_mock_answer_count(original, task) is Err(Retired))
  assert_true(model_mock_answer_default(original, task) is Err(Retired))
  assert_true(retire_model_mock_answers(original, task) is Err(Retired))
  assert_true(
    physical_equal(
      escaped.contract,
      @environment.public_model_task_contract(
        @environment.public_model_task_declaration_contracts(task).1,
      ),
    ),
  )
}
