///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap(),
    {
      max_nodes: 10000,
      max_depth: 100,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
  ).unwrap()
}

///|
fn tasks() -> @environment.ModelTasks {
  // Fixed ModelTask identities were independently calculated with Node crypto.
  let body =
    #|{"authored_model_selector":"fixture-risk-model","connector_id":"models/fixture","contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"text":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","max_items":2,"output_contract":{"additional_properties":false,"fields":{"reason":{"nullable":true,"type":"string"},"risk":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3","prompt_template_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:risk-score.v1","task_kind":"structured_generate","tool_policy":"none","version":"1"}
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[" +
    body +
    "],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let wire = @environment.read(
    @utf8.encode(prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix),
    cid,
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 10, },
  ).unwrap()
  @environment.check_model_tasks(wire, {
    bodies: {
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_members: 10,
    },
    contracts: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
    max_work: 100000,
  }).unwrap()
}

///|
fn limits() -> Limits {
  {
    max_work: 10000,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
    max_tokens: 1000,
    max_key_fields: 10,
    max_input_roles: 10,
  }
}

///|
fn infer_input(nullable_id? : Bool = false) -> @carrier.Carrier {
  let row = @contract.object_contract(
    [
      ("id", @contract.primitive(StringType, nullable=nullable_id)),
      ("tenant", @contract.primitive(NumberType, nullable=false)),
      ("text", @contract.primitive(StringType, nullable=true)),
      ("secret", @contract.primitive(StringType, nullable=false)),
      ("outcome", @contract.primitive(StringType, nullable=false)),
    ],
    nullable=false,
    max_fields=5,
    max_name_bytes=100,
  ).unwrap()
  @carrier.relation(@carrier.typed_rows(@schema.from_object(row).unwrap()))
}

///|
fn keys(input : @carrier.Carrier, tuples : Array[String]) -> @evidence.KeySet {
  let witnesses = tuples.map(text => {
    @evidence.declare_primary_key(cursor(text), input, {
      max_fields: 10,
      max_name_bytes: 100,
    }).unwrap()
  })
  @evidence.collect_keys(cursor("{}"), input, witnesses, {
    max_keys: 10,
    max_work: 10000,
    max_name_bytes: 10000,
  }).unwrap()
}

///|
fn body(
  key? : String? = Some("\"id\""),
  mapping? : String = "{\"text\":{\"field\":\"text\"}}",
  extra? : String = "",
) -> @decode.Cursor {
  let key = key.map(key => ",\"key\":" + key).unwrap_or("")
  cursor(
    "{\"contract\":\"model-task:risk-score.v1\",\"input\":" +
    mapping +
    key +
    extra +
    "}",
  )
}

///|
test "infer retains exact ModelTask key and expression owners without copying source rows" {
  let input = infer_input()
  let keys = keys(input, ["[\"id\",\"tenant\"]"])
  let tasks = tasks()
  let at = body(key=Some("[\"tenant\",\"id\"]"))
  let checked = check(at, input, Some(keys), tasks, None, limits()).unwrap()
  assert_true(physical_equal(source(checked), at))
  assert_true(
    physical_equal(
      input_records(checked),
      @carrier.relation_rows(input).unwrap(),
    ),
  )
  assert_true(
    physical_equal(
      key_witness(checked),
      @evidence.key_witness_at(keys, 0).unwrap(),
    ),
  )
  assert_true(
    physical_equal(
      model_task(checked),
      @environment.resolve_model_task(tasks, "model-task:risk-score.v1").unwrap(),
    ),
  )
  assert_eq(key_count(checked), 2)
  assert_eq(key_at(checked, 0).unwrap().field, @schema.Unqualified("tenant"))
  assert_eq(key_at(checked, 1).unwrap().field, @schema.Unqualified("id"))
  assert_true(key_at(checked, 2) is None)
  assert_eq(input_binding_count(checked), 1)
  let mapped = input_binding_at(checked, 0).unwrap()
  assert_eq(mapped.role, "text")
  assert_true(@expression.result_type(mapped.expression).nullable)
  assert_true(
    physical_equal(
      @expression.environment(mapped.expression).fields.unwrap(),
      @schema.as_object(input_schema(checked)).unwrap(),
    ),
  )
  assert_true(input_binding_at(checked, 1) is None)
  assert_true(@evidence.key_pending_count(key_witness(checked)) > 0)
  assert_eq(result_mode(checked), Outcomes)
  assert_true(minimum_classification(checked) is None)
  assert_true(max_items_guard(checked) is None)
  let output = output_schema(checked)
  assert_eq(@schema.field_count(output), 4)
  assert_true(@schema.lookup_reference(output, "secret") is None)
  assert_false(
    @schema.lookup_reference(output, "outcome").unwrap().contract.nullable,
  )
  let success = @schema.lookup_reference(output, "value").unwrap().contract
  assert_true(success.nullable)
  assert_true(
    @contract.type_equal(
      @contract.with_nullability(success, false),
      @environment.model_task_output(model_task(checked)),
      100,
    ),
  )
  guard success.shape is @contract.Object(fields) else { fail("closed output") }
  assert_true(@contract.field_at(fields, 0).unwrap().contract.nullable)
  assert_eq(@contract.field_at(fields, 1).unwrap().name, "risk")
  assert_false(@contract.field_at(fields, 1).unwrap().contract.nullable)
}

///|
test "infer requires exactly one whole candidate tuple and preserves duplicate witnesses" {
  let input = infer_input()
  let tasks = tasks()
  let sole = keys(input, ["[\"id\"]"])
  let checked = check(body(key=None), input, Some(sole), tasks, None, limits()).unwrap()
  assert_eq(key_at(checked, 0).unwrap().field, @schema.Unqualified("id"))
  let duplicate = keys(input, ["[\"id\"]", "[\"id\"]"])
  assert_eq(@evidence.key_witness_count(duplicate), 2)
  assert_true(
    check(body(key=None), input, Some(duplicate), tasks, None, limits())
    is Ok(_),
  )
  let multiple = keys(input, ["[\"id\"]", "[\"tenant\"]"])
  assert_true(
    check(body(key=None), input, Some(multiple), tasks, None, limits())
    is Err({ kind: AmbiguousCandidateKey, .. }),
  )
  assert_true(
    check(body(), input, Some(multiple), tasks, None, limits()) is Ok(_),
  )
  assert_true(
    check(body(), input, None, tasks, None, limits())
    is Err({ kind: CandidateKeyRequired, .. }),
  )
  let compound = keys(input, ["[\"id\",\"tenant\"]"])
  assert_true(
    check(body(), input, Some(compound), tasks, None, limits())
    is Err({ kind: CandidateKeyRequired, .. }),
  )
  assert_true(
    check(
      body(key=Some("[\"id\",\"tenant\",\"secret\"]")),
      input,
      Some(compound),
      tasks,
      None,
      limits(),
    )
    is Err({ kind: CandidateKeyRequired, .. }),
  )
  for key in ["[]", "[\"id\"]", "[\"id\",\"id\"]", "null"] {
    assert_true(
      check(body(key=Some(key)), input, Some(sole), tasks, None, limits())
      is Err({ kind: InvalidKeyTuple, .. }),
    )
  }
  assert_true(
    check(
      body(key=Some("\"unknown\"")),
      input,
      Some(sole),
      tasks,
      None,
      limits(),
    )
    is Err({ kind: UnknownKeyField("unknown"), .. }),
  )
  assert_true(
    check(
      body(key=Some("\"outcome\"")),
      input,
      Some(sole),
      tasks,
      None,
      limits(),
    )
    is Err({ kind: KeyRoleCollision("outcome"), .. }),
  )
  let foreign = infer_input()
  assert_true(
    check(body(), foreign, Some(sole), tasks, None, limits())
    is Err({ kind: InputKeyOwnerMismatch, .. }),
  )
  let nullable = infer_input(nullable_id=true)
  let nullable_keys = keys(nullable, ["[\"tenant\"]"])
  assert_true(
    check(body(), nullable, Some(nullable_keys), tasks, None, limits())
    is Err({ kind: InvalidKeyType("id"), .. }),
  )
}

///|
test "infer mapping is closed explicit and type compatible including nullable source values" {
  let input = infer_input()
  let keys = keys(input, ["[\"id\"]"])
  let tasks = tasks()
  assert_true(
    check(body(mapping="{}"), input, Some(keys), tasks, None, limits())
    is Err({ kind: MissingInputRole("text"), .. }),
  )
  assert_true(
    check(
      body(mapping="{\"secret\":{\"field\":\"secret\"}}"),
      input,
      Some(keys),
      tasks,
      None,
      limits(),
    )
    is Err({ kind: UnknownInputRole("secret"), .. }),
  )
  assert_true(
    check(
      body(mapping="{\"text\":{\"field\":\"secret\"}}"),
      input,
      Some(keys),
      tasks,
      None,
      limits(),
    )
    is Ok(_),
  )
  assert_true(
    check(
      body(mapping="{\"text\":{\"literal\":null}}"),
      input,
      Some(keys),
      tasks,
      None,
      limits(),
    )
    is Ok(_),
  )
  assert_true(
    check(
      body(mapping="{\"text\":{\"field\":\"absent\"}}"),
      input,
      Some(keys),
      tasks,
      None,
      limits(),
    )
    is Err({ kind: Expression(@expression.UnknownField("absent")), .. }),
  )
  assert_true(
    check(
      body(mapping="{\"text\":{\"field\":\"tenant\"}}"),
      input,
      Some(keys),
      tasks,
      None,
      limits(),
    )
    is Err({ kind: Expression(@expression.TypeMismatch(_)), .. }),
  )
  assert_true(
    check(body(mapping="null"), input, Some(keys), tasks, None, limits())
    is Err({ kind: InvalidBody, .. }),
  )
  for
    extra in [
      ",\"unrecognized\":true", ",\"on_non_success\":\"retry\"", ",\"minimum_classification\":\"unknown\"",
      ",\"key\":null",
    ] {
    let at = body(key=None, extra~)
    assert_true(check(at, input, Some(keys), tasks, None, limits()) is Err(_))
  }
  let checked = check(
    body(
      extra=",\"on_non_success\":\"fail\",\"minimum_classification\":\"restricted\",\"max_items\":2",
    ),
    input,
    Some(keys),
    tasks,
    None,
    limits(),
  ).unwrap()
  assert_eq(result_mode(checked), Fail)
  assert_true(minimum_classification(checked) is Some(@environment.Restricted))
  assert_eq(
    @relation.count_value(max_items_guard(checked).unwrap()),
    @relation.Literal(2L),
  )
  // An authored classification is retained, not treated as Host authority.
  assert_false(
    @environment.model_task_accepts_classification(
      model_task(checked),
      Restricted,
    ),
  )
  for guard_text in ["0", "-1", "1.5", "null", "9007199254740992"] {
    assert_true(
      check(
        body(extra=",\"max_items\":" + guard_text),
        input,
        Some(keys),
        tasks,
        None,
        limits(),
      )
      is Err({ kind: Guard(_), .. }),
    )
  }
  assert_true(
    @source.parse_json("{\"max_items\":-0}", {
      max_input_bytes: 100,
      max_nodes: 10,
      max_depth: 5,
    })
    is Err(_),
  )
}

///|
test "infer shares the existing positive count guard and parameter declaration owner" {
  let input = infer_input()
  let keys = keys(input, ["[\"id\"]"])
  let params = @parameter.read_declarations(
    Some(cursor("{\"limit\":{\"type\":\"number\",\"nullable\":true}}")),
    { max_parameters: 10, max_nodes: 100, max_depth: 20, max_text_bytes: 1000, },
  ).unwrap()
  let checked = check(
    body(extra=",\"max_items\":{\"$param\":\"limit\"}"),
    input,
    Some(keys),
    tasks(),
    Some(params),
    limits(),
  ).unwrap()
  let author_guard = max_items_guard(checked).unwrap()
  assert_true(
    physical_equal(
      @relation.count_value_parameters(author_guard).unwrap(),
      params,
    ),
  )
  assert_eq(@relation.count_value(author_guard), @relation.Parameter("limit"))
  assert_eq(@relation.count_value_pending_count(author_guard), 1)
  assert_true(
    @relation.count_value_pending_at(author_guard, 0).unwrap().kind
    is @relation.BoundInteger(name="limit", minimum=1L),
  )
  assert_true(@relation.count_value_pending_at(author_guard, 1) is None)
  assert_true(
    check(
      body(extra=",\"max_items\":{\"$param\":\"absent\"}"),
      input,
      Some(keys),
      tasks(),
      Some(params),
      limits(),
    )
    is Err({ kind: Guard(@relation.UnknownParameter("absent")), .. }),
  )
}

///|
test "infer admission keeps cumulative budgets across mapping key and guard work" {
  let input = infer_input()
  let keys = keys(input, ["[\"id\"]"])
  let tasks = tasks()
  for
    small in [
      { ..limits(), max_work: 0, },
      { ..limits(), max_nodes: 0, },
      { ..limits(), max_text_bytes: 0, },
      { ..limits(), max_key_fields: 0, },
      { ..limits(), max_input_roles: 0, },
    ] {
    assert_true(check(body(), input, Some(keys), tasks, None, small) is Err(_))
  }
  assert_true(
    check(body(), input, Some(keys), tasks, None, { ..limits(), max_work: -1, })
    is Err({ kind: InvalidLimits, .. }),
  )
  let checked = check(body(), input, Some(keys), tasks, None, limits()).unwrap()
  assert_true(usage(checked).work > 0)
  assert_true(usage(checked).nodes > 0)
  assert_true(usage(checked).text_bytes > 0)
}

///|
test "infer alias keys require explicit completion without enumerating alias products" {
  let input = infer_input()
  let original = keys(input, ["[\"id\",\"tenant\"]"])
  let op = @relation.check(
    Select,
    cursor(
      "[\"id\",{\"copy\":\"id\"},\"tenant\",{\"region\":\"tenant\"},\"text\"]",
    ),
    @carrier.complete_schema(@carrier.relation_rows(input).unwrap()).unwrap(),
    None,
    {
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_depth: 100,
      max_tokens: 1000,
    },
  ).unwrap()
  let projected = @evidence.advance_keys(Some(original), op, {
      max_work: 10000,
      max_name_bytes: 10000,
    }).unwrap().keys
  assert_eq(@evidence.key_witness_count(projected), 1)
  let input = @carrier.relation(@evidence.key_set_records(projected))
  let tasks = tasks()
  assert_true(
    check(body(key=None), input, Some(projected), tasks, None, limits())
    is Err({ kind: AmbiguousCandidateKey, .. }),
  )
  for tuple in ["[\"id\",\"tenant\"]", "[\"region\",\"copy\"]"] {
    assert_true(
      check(
        body(key=Some(tuple)),
        input,
        Some(projected),
        tasks,
        None,
        limits(),
      )
      is Ok(_),
    )
  }
  assert_true(
    check(
      body(key=Some("[\"id\",\"copy\"]")),
      input,
      Some(projected),
      tasks,
      None,
      limits(),
    )
    is Err({ kind: CandidateKeyRequired, .. }),
  )
  let typed = check(
    body(key=Some("[\"region\",\"copy\"]")),
    input,
    Some(projected),
    tasks,
    None,
    limits(),
  ).unwrap()
  assert_eq(key_at(typed, 0).unwrap().field, @schema.Unqualified("region"))
  assert_eq(key_at(typed, 1).unwrap().field, @schema.Unqualified("copy"))
}

///|
test "infer refuses missing complete row contracts and unknown ModelTask selectors" {
  let open = @carrier.relation(
    @carrier.rows([], field_set=Open, max_fields=0, max_name_bytes=0).unwrap(),
  )
  assert_true(
    check(body(), open, None, tasks(), None, limits())
    is Err({ kind: IncompleteInputContract, .. }),
  )
  let input = infer_input()
  let keys = keys(input, ["[\"id\"]"])
  let unknown = cursor(
    "{\"contract\":\"model-task:unknown\",\"key\":\"id\",\"input\":{\"text\":{\"field\":\"text\"}}}",
  )
  assert_true(
    check(unknown, input, Some(keys), tasks(), None, limits())
    is Err(
      { kind: Task(@environment.UnknownSelector("model-task:unknown")), .. }
    ),
  )
}

///|
test "infer uses typed qualified scopes and exact cross-product key provenance" {
  let left = infer_input()
  let right = infer_input()
  let lkeys = keys(left, ["[\"id\"]"])
  let rkeys = keys(right, ["[\"id\"]"])
  let op = @join.check_cross(
    cursor("{\"with\":\"right\",\"max_output_rows\":4}"),
    @carrier.complete_schema(@carrier.relation_rows(left).unwrap()).unwrap(),
    @carrier.complete_schema(@carrier.relation_rows(right).unwrap()).unwrap(),
    None,
    { max_work: 10000, max_text_bytes: 10000, max_nodes: 1000, max_depth: 100, },
  ).unwrap()
  let keys = @evidence.transfer_cross_join_keys(Some(lkeys), Some(rkeys), op, {
      max_work: 10000,
      max_name_bytes: 10000,
    }).unwrap().keys
  let input = @carrier.relation(@evidence.key_set_records(keys))
  let at = body(
    key=Some("[\"right.id\",\"left.id\"]"),
    mapping="{\"text\":{\"join_field\":{\"side\":\"left\",\"name\":\"text\"}}}",
  )
  let checked = check(at, input, Some(keys), tasks(), None, limits()).unwrap()
  assert_eq(key_at(checked, 0).unwrap().field, @schema.Qualified(Right, "id"))
  assert_eq(key_at(checked, 1).unwrap().field, @schema.Qualified(Left, "id"))
  assert_true(
    @schema.lookup_reference(output_schema(checked), "right.id") is Some(_),
  )
  assert_true(
    @schema.lookup_reference(output_schema(checked), "left.id") is Some(_),
  )
  assert_true(
    @schema.lookup_reference(output_schema(checked), "left.secret") is None,
  )
  assert_true(
    @expression.result_type(input_binding_at(checked, 0).unwrap().expression).nullable,
  )
  assert_true(
    @evidence.key_cross_join_producer(key_witness(checked)) is Some(_),
  )
  let missing_scope = body(
    key=Some("[\"right.id\",\"left.id\"]"),
    mapping="{\"text\":{\"field\":\"text\"}}",
  )
  assert_true(
    check(missing_scope, input, Some(keys), tasks(), None, limits())
    is Err({ kind: Expression(@expression.UnknownField("text")), .. }),
  )
}

///|
test "infer result keys retain the exact producer and KEEP join dependency" {
  let input = infer_input()
  let input_keys = keys(input, ["[\"id\"]"])
  let checked = check(body(), input, Some(input_keys), tasks(), None, limits()).unwrap()
  let exact : @evidence.TransferLimits = { max_work: 4, max_name_bytes: 2, }
  let transferred = result_keys(checked, exact).unwrap()
  assert_eq((transferred.work, transferred.name_bytes), (4, 2))
  assert_eq(@evidence.key_witness_count(transferred.keys), 1)
  let key = @evidence.key_witness_at(transferred.keys, 0).unwrap()
  assert_eq(@evidence.key_origin(key), InferResult)
  assert_true(
    physical_equal(@evidence.key_infer_producer(key).unwrap(), checked),
  )
  assert_true(
    physical_equal(
      @evidence.key_infer_dependency(key).unwrap(),
      key_witness(checked),
    ),
  )
  assert_true(
    @evidence.key_pending_count(@evidence.key_infer_dependency(key).unwrap()) >
    0,
  )
  assert_eq(@evidence.key_pending_at(key, 0), Some(ValidateKeyProducer))
  assert_eq(@evidence.key_field_count(key), 1)
  assert_eq(
    @evidence.key_field_at(key, 0).unwrap().name,
    @schema.Unqualified("id"),
  )
  assert_true(
    physical_equal(
      @carrier.complete_schema(@evidence.keyed_records(key)).unwrap(),
      output_schema(checked),
    ),
  )
  for limited in [{ ..exact, max_work: 3, }, { ..exact, max_name_bytes: 1, }] {
    assert_true(
      result_keys(checked, limited) is Err({ kind: LimitExceeded, .. }),
    )
  }
  // KEEP's one-to-one join consumes the output proof, not a declaration rebuilt
  // from a schema, task CID, unique fixture rows or the original input owner.
  let join = @join.check(
    cursor(
      "{\"with\":\"captured\",\"kind\":\"inner\",\"on\":\"id\",\"cardinality\":\"one_to_one\"}",
    ),
    input_schema(checked),
    output_schema(checked),
    None,
    { max_work: 10000, max_text_bytes: 10000, max_nodes: 1000, max_depth: 100, },
  ).unwrap()
  let selected = @evidence.select_join_key(
    join,
    Right,
    Some(transferred.keys),
    { max_work: 10000, max_name_bytes: 10000, },
  ).unwrap().key.unwrap()
  assert_true(
    physical_equal(@evidence.key_infer_producer(selected).unwrap(), checked),
  )
  assert_true(
    physical_equal(
      @evidence.keyed_records(selected),
      @evidence.keyed_records(key),
    ),
  )
  assert_eq(
    @evidence.key_field_at(selected, 0).unwrap().name,
    @schema.Unqualified("id"),
  )
  assert_true(
    @evidence.select_join_key(join, Right, Some(input_keys), {
      max_work: 10000,
      max_name_bytes: 10000,
    })
    is Err({ kind: InputContractMismatch, .. }),
  )
  let foreign = check(body(), input, Some(input_keys), tasks(), None, limits()).unwrap()
  let foreign_keys = result_keys(foreign, exact).unwrap().keys
  assert_true(
    @evidence.select_join_key(join, Right, Some(foreign_keys), {
      max_work: 10000,
      max_name_bytes: 10000,
    })
    is Err({ kind: InputContractMismatch, .. }),
  )
}
