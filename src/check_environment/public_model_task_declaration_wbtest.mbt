///|
fn declaration_limits() -> ModelTaskLimits {
  {
    bodies: {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 32,
      max_members: 100,
    },
    contracts: { max_nodes: 100, max_depth: 16, max_text_bytes: 1000, },
    max_work: 100000,
  }
}

///|
fn declaration_cursor(wire : String) -> @decode.Cursor {
  let node = @source.parse_json_bytes_preserving(@utf8.encode(wire), {
    max_input_bytes: 10000,
    max_nodes: 1000,
    max_depth: 32,
  }).unwrap()
  @decode.admit(node, {
    max_nodes: 1000,
    max_depth: 32,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }).unwrap()
}

///|
fn declaration_base(extra : String) -> String {
  "{\"task\":\"model-task:opaque e\u{0301}.version\",\"input\":{\"notes\":\"string\"},\"output\":{\"value\":\"boolean\"},\"instructions\":\"Original e\\u0301\\r\\n\"" +
  extra +
  "}"
}

///|
test "public Task document reads strict JSON and YAML with exact keys and instruction text" {
  let yaml =
    #|task: model-task:public.original
    #|input: {notes: string}
    #|output: {enabled: boolean}
    #|instructions: "Original e\u0301\r\n"
  let value = read_public_model_task_document(
    yaml,
    "yaml",
    declaration_limits(),
  ).unwrap()
  assert_eq(
    public_model_task_declaration_identity(value),
    ("model-task:public.original", "model-task:public.original"),
  )
  assert_eq(
    public_model_task_declaration_instructions(value),
    "Original e\u{0301}\r\n",
  )
  assert_true(
    read_public_model_task_document(
      declaration_base(""),
      "json",
      declaration_limits(),
    )
    is Ok(_),
  )
  let invalid = yaml.replace(old="notes", new="e\u{0301}")
  assert_true(
    read_public_model_task_document(invalid, "yaml", declaration_limits())
    is Err(_),
  )
  assert_true(
    read_public_model_task_document(yaml, "unknown", declaration_limits())
    is Err(_),
  )
  let (work, _, _) = public_model_task_declaration_usage(value)
  assert_true(
    read_public_model_task_document(yaml, "yaml", {
      ..declaration_limits(),
      max_work: work,
    })
    is Ok(_),
  )
  assert_true(
    read_public_model_task_document(yaml, "yaml", {
      ..declaration_limits(),
      max_work: work - 1,
    })
    is Err(_),
  )
}

///|
test "public Task retains exact identifier version instructions and original contracts" {
  let root = declaration_cursor(declaration_base(""))
  let value = read_public_model_task_declaration(root, declaration_limits()).unwrap()
  assert_true(
    physical_equal(public_model_task_declaration_original(value), root),
  )
  assert_eq(
    public_model_task_declaration_identity(value),
    (
      "model-task:opaque e\u{0301}.version", "model-task:opaque e\u{0301}.version",
    ),
  )
  assert_eq(
    public_model_task_declaration_instructions(value),
    "Original e\u{0301}\r\n",
  )
  assert_eq(public_model_task_declaration_model(value), None)
  assert_eq(public_model_task_declaration_limits(value), (None, None))
  let (input, output) = public_model_task_declaration_contracts(value)
  assert_eq(
    public_model_task_contract_schema(input).0,
    (
      #|{"additional_properties":false,"fields":{"notes":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"}
    ),
  )
  assert_eq(
    public_model_task_contract_schema(output).0,
    (
      #|{"additional_properties":false,"fields":{"value":{"nullable":false,"type":"boolean"}},"nullable":false,"type":"object"}
    ),
  )
}

///|
test "public Task keeps an explicit atomic model pair and finite task limits" {
  let value = read_public_model_task_declaration(
    declaration_cursor(
      declaration_base(
        ",\"model\":{\"provider\":\"second\",\"name\":\"m\"},\"limits\":{\"max_items\":2,\"max_output_tokens\":200}",
      ),
    ),
    declaration_limits(),
  ).unwrap()
  assert_eq(public_model_task_declaration_model(value), Some(("second", "m")))
  assert_eq(public_model_task_declaration_limits(value), (Some(2L), Some(200L)))
  let empty = read_public_model_task_declaration(
    declaration_cursor(
      (
        #|{"task":"model-task:empty","input":{},"output":{},"instructions":""}
      ),
    ),
    declaration_limits(),
  ).unwrap()
  assert_eq(public_model_task_declaration_instructions(empty), "")
}

///|
test "public Task refuses partial model pairs nulls unknown fields and invalid limits" {
  for
    extra in [
      ",\"model\":null", ",\"model\":{\"provider\":\"p\"}", ",\"model\":{\"name\":\"m\"}",
      ",\"model\":{\"provider\":\"p\",\"name\":\"m\",\"extra\":true}", ",\"model\":{\"provider\":\"\",\"name\":\"m\"}",
      ",\"limits\":null", ",\"limits\":{\"max_items\":0}", ",\"limits\":{\"max_items\":null}",
      ",\"limits\":{\"max_output_tokens\":-1}", ",\"limits\":{\"max_output_tokens\":9007199254740992}",
      ",\"limits\":{\"temperature\":0}", ",\"version\":\"invented\"", ",\"allow\":true",
    ] {
    assert_true(
      read_public_model_task_declaration(
        declaration_cursor(declaration_base(extra)),
        declaration_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "public Task validates both contracts without default field or Unicode repair" {
  for
    wire in [
      "{\"task\":\"model-task:t\",\"input\":{},\"instructions\":\"x\"}", "{\"task\":\"model-task:t\",\"output\":{},\"instructions\":\"x\"}",
      "{\"task\":\"model-task:t\",\"input\":{},\"output\":{},\"instructions\":null}",
      "{\"task\":\"model-task:t\",\"input\":{},\"output\":{\"x\":\"invented\"},\"instructions\":\"x\"}",
      "{\"task\":\"model-task:t\",\"input\":{\"e\\u0301\":\"string\"},\"output\":{},\"instructions\":\"x\"}",
      "{\"task\":\"model-task:t\",\"input\":{},\"output\":{\"x\":{\"type\":\"string\",\"default\":\"x\"}},\"instructions\":\"x\"}",
    ] {
    assert_true(
      read_public_model_task_declaration(
        declaration_cursor(wire),
        declaration_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "public Task shares contract and work budgets across input output and declaration" {
  let root = declaration_cursor(declaration_base(""))
  let limits = declaration_limits()
  let value = read_public_model_task_declaration(root, limits).unwrap()
  let (work, nodes, text) = public_model_task_declaration_usage(value)
  let exact = {
    ..limits,
    max_work: work,
    contracts: { ..limits.contracts, max_nodes: nodes, max_text_bytes: text, },
  }
  assert_true(read_public_model_task_declaration(root, exact) is Ok(_))
  assert_true(
    read_public_model_task_declaration(root, { ..exact, max_work: work - 1, })
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    read_public_model_task_declaration(root, {
      ..limits,
      contracts: { ..limits.contracts, max_nodes: nodes - 1, },
    })
    is Err(_),
  )
  assert_true(
    read_public_model_task_declaration(root, {
      ..limits,
      contracts: { ..limits.contracts, max_text_bytes: text - 1, },
    })
    is Err(_),
  )
}
