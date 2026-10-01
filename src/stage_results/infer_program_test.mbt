///|
// Typing fixture only: referenced dependency CIDs are not Host authority.
fn infer_program_tasks() -> @environment.ModelTasks {
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
fn infer_program_source(
  keep : Bool,
  structured_join? : Bool = false,
) -> @parameters.Source {
  let tail = if keep {
    (
      #|,{"join":{"with":"snapshot","kind":"inner","cardinality":"one_to_one","on":"id","select":{"id":"left.id","outcome":"left.outcome","value":"left.value","note":"right.text"}}}
    )
  } else {
    ""
  }
  let tail = if structured_join {
    tail.replace(
      old="\"id\":\"left.id\"",
      new="\"id\":{\"join_field\":{\"side\":\"left\",\"name\":\"id\"}}",
    )
  } else {
    tail
  }
  let prefix =
    #|{"version":"actql/0.1","id":"infer-program","stages":[{"id":"s","inputs":{"tickets":{"carrier":"relation","schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true},"secret":{"type":"string","nullable":false}},"primary_key":["id"]}},"steps":[{"select":["id","text","secret"],"as":"snapshot"},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"captured"}
  let suffix =
    #|,{"derive":{"assessment":{"object":{"input_key":{"object":{"id":{"field":"id"}}},"outcome":{"field":"outcome"},"value":{"field":"value"}}}}},{"select":["id","assessment"],"as":"projected"}],"results":{"out":{"from":"projected","fields":["id","assessment"]}}}],"results":{"answer":{"from":{"stage":"s","result":"out"}}}}
  local_program_parse(prefix + tail + suffix)
}

///|
fn infer_program_pipeline(wiring : ResultWiring) -> @pipeline.CheckedPipeline {
  @collection.pipeline(
    @parameters.collection(
      stage_port_source(wiring_stage_at(wiring, 0).unwrap()),
    ),
  )
}

///|
test "ordinary Program preparation retains typed INFER and KEEP dependencies" {
  for keep in [false, true] {
    let source = infer_program_source(keep)
    let tasks = infer_program_tasks()
    let prepared = prepare_local_program(
      source,
      local_program_limits(),
      model_tasks=Some(tasks),
    )
    let (wiring, usage) = match prepared {
      Ok(value) => value
      Err(Pipeline(_, issue)) => fail("\{@debug.Repr(issue.kind)}")
      Err(Results(_, issue)) => fail("\{@debug.Repr(issue.kind)}")
      Err(_) => fail("Program preparation failed outside the pipeline")
    }
    let pipeline = infer_program_pipeline(wiring)
    assert_eq(usage.steps, if keep { 5 } else { 4 })
    assert_eq(export_count(wiring), 1)
    assert_eq(@pipeline.lookup(pipeline, "snapshot"), Some(Step(0)))
    assert_eq(@pipeline.lookup(pipeline, "captured"), Some(Step(1)))
    let step = @pipeline.step_at(pipeline, 1).unwrap()
    guard step.operation is @pipeline.Infer(checked) else {
      fail("expected owned ModelTask acquisition")
    }
    assert_eq(@pipeline.input_occurrence_count(step), 1)
    assert_eq(@pipeline.input_occurrence_at(step, 0).unwrap().target, Step(0))
    assert_true(
      physical_equal(
        @evidence.infer_model_task(checked),
        @environment.resolve_model_task(tasks, "model-task:risk-score.v1").unwrap(),
      ),
    )
    let key = @pipeline.candidate_key(pipeline, Step(1)).unwrap()
    assert_true(
      physical_equal(@evidence.key_infer_producer(key).unwrap(), checked),
    )
    assert_true(
      physical_equal(
        @evidence.key_infer_dependency(key).unwrap(),
        @pipeline.candidate_key(pipeline, Step(0)).unwrap(),
      ),
    )
    assert_eq(@evidence.key_pending(key), [ValidateKeyProducer])
    assert_eq(@pipeline.operation_profile_count(step.operation), 0)
    assert_true(@pipeline.operation_profile_at(step.operation, 0) is None)
    assert_eq(@pipeline.operation_obligation_group_count(step.operation), 0)
    assert_true(@pipeline.logical_order(pipeline, Step(1)) is Some(_))
    let expressions = @pipeline.collect_expression_slots(
      pipeline,
      max_work=100,
      max_slots=10,
    ).unwrap()
    let mapping = @pipeline.expression_slot_at(expressions, 0).unwrap()
    assert_eq(mapping.step, 1)
    assert_eq(mapping.consumer, InferInput(0))
    assert_true(
      physical_equal(
        mapping.expression,
        @evidence.infer_input_binding_at(checked, 0).unwrap().expression,
      ),
    )
    if keep {
      let join = @pipeline.join_evidence(pipeline, 2).unwrap()
      assert_true(
        physical_equal(
          @evidence.key_infer_producer(join.left.unwrap()).unwrap(),
          checked,
        ),
      )
      assert_true(join.right is Some(_))
    }
    // Lowering retains INFER as an acquisition barrier; pure execution still
    // requires the model Host to dispatch this payload.
    let lowered = @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 10000,
    })
    let prepared = lowered.unwrap()
    guard @lower.node_at(prepared, 1) is Some(node) else {
      fail("INFER lowering node was not retained")
    }
    guard @lower.payload(node) is @lower.Infer(owned) else {
      fail("INFER did not remain an acquisition barrier")
    }
    assert_true(physical_equal(owned, checked))
  }
}

///|
test "ordinary INFER reports missing installation alias and candidate key" {
  let source = infer_program_source(false)
  guard prepare_local_program(source, local_program_limits())
    is Err(Pipeline(0, issue)) else {
    fail("uninstalled model task was admitted")
  }
  assert_eq(issue.kind, MissingModelTasks)
  let tasks = infer_program_tasks()
  let rows = @carrier.relation(
    @carrier.typed_rows(
      @schema.from_object(
        @contract.object_contract(
          [
            ("id", @contract.primitive(StringType, nullable=false)),
            ("text", @contract.primitive(StringType, nullable=true)),
          ],
          nullable=false,
          max_fields=2,
          max_name_bytes=6,
        ).unwrap(),
      ).unwrap(),
    ),
  )
  let input =
    #|[{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"captured"}]
  let at = @decode.admit(
    @source.parse_json(input, {
      max_input_bytes: 1000,
      max_nodes: 100,
      max_depth: 20,
    }).unwrap(),
    {
      max_nodes: 100,
      max_depth: 20,
      max_string_bytes: 1000,
      max_total_string_bytes: 1000,
    },
  ).unwrap()
  let limits : @pipeline.Limits = {
    max_steps: 10,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_depth: 100,
  }
  guard @pipeline.check_carriers(
      at,
      [("rows", rows)],
      None,
      None,
      limits,
      model_tasks=Some(tasks),
    )
    is Err(issue) else {
    fail("field names alone supplied a candidate key")
  }
  assert_eq(issue.kind, Infer(CandidateKeyRequired))
  let unnamed =
    #|[{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}}}]
  let no_alias = @decode.admit(
    @source.parse_json(unnamed, {
      max_input_bytes: 1000,
      max_nodes: 100,
      max_depth: 20,
    }).unwrap(),
    {
      max_nodes: 100,
      max_depth: 20,
      max_string_bytes: 1000,
      max_total_string_bytes: 1000,
    },
  ).unwrap()
  guard @pipeline.check_carriers(
      no_alias,
      [("rows", rows)],
      None,
      None,
      limits,
      model_tasks=Some(tasks),
    )
    is Err(issue) else {
    fail("unnamed inference was admitted")
  }
  assert_eq(issue.kind, InferRequiresAlias)
}

///|
test "KEEP join projection retains the existing qualified field grammar" {
  let source = infer_program_source(true, structured_join=true)
  guard prepare_local_program(
      source,
      local_program_limits(),
      model_tasks=Some(infer_program_tasks()),
    )
    is Err(Pipeline(0, issue)) else {
    fail("expression-valued join projection changed the source grammar")
  }
  assert_eq(issue.kind, Join(InvalidBody))
}

///|
test "Program preparation rejects a same-CID foreign ModelTask environment" {
  let source = infer_program_source(false)
  let tasks = infer_program_tasks()
  let locals = @local.prepare_environment(
    source,
    @environment.model_tasks_environment(tasks),
    {
      max_work: 100000,
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 100,
    },
  ).unwrap()
  assert_true(
    prepare_local_program(
      source,
      local_program_limits(),
      environment=Some(locals),
      model_tasks=Some(tasks),
    )
    is Ok(_),
  )
  let foreign = infer_program_tasks()
  assert_true(
    prepare_local_program(
      source,
      local_program_limits(),
      environment=Some(locals),
      model_tasks=Some(foreign),
    )
    is Err(ForeignModelEnvironment),
  )
}
