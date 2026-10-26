///|
fn success_fixture_prefix() -> String {
  // The tuple is unique; id alone is deliberately not unique for self-joins.
  (
    #|{"values":{"schema":{"id":{"type":"string","nullable":false},"slot":{"type":"string","nullable":false},"text":{"type":"string","nullable":false}},"rows":[{"id":"same","slot":"one","text":"first"},{"id":"same","slot":"two","text":"second"}]},"as":"seed"},
    #|{"assert_rows":{"unique_by":["id","slot"]}},
    #|{"infer":{"contract":"model-task:risk-score.v1","key":["id","slot"],"input":{"text":{"field":"text"}}},"as":"outcomes"}
  )
}

///|
fn success_fixture_program(
  prefix : String,
  predicate : String,
  value : String,
) -> @program.Program {
  let text = "{\"version\":\"actql/0.1\",\"id\":\"fixture.infer_success\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    prefix +
    ",{\"filter\":" +
    predicate +
    "},{\"derive\":{\"risk\":{\"property\":{\"name\":\"risk\",\"value\":" +
    value +
    "}},\"reason\":{\"property\":{\"name\":\"reason\",\"value\":" +
    value +
    "}}}},{\"select\":[\"risk\",\"reason\"],\"as\":\"final\"}],\"results\":{\"rows\":{\"from\":\"final\",\"fields\":[\"risk\",\"reason\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  @program.parse(text, construction_limits().program, format=Json).unwrap()
}

///|
fn success_fixture_check(
  program : @program.Program,
  environment? : @check.CheckEnvironment = infer_member_environment(),
) -> @pipeline.CheckedPipeline raise {
  match @check.check_parsed(program, environment, None, check_limits()) {
    Checked(checked) => @check.unit_pipeline(checked, 0).unwrap()
    Rejected(error) =>
      match @check.diagnostic_cause(error) {
        Source(SourceView(Program(Program(Pipeline(_, issue))))) =>
          fail("success fixture: " + @debug.to_string(issue.kind))
        Source(SourceView(Context(Stages(Capacity(_, _, issue))))) =>
          fail("success fixture capacity: " + @debug.to_string(issue))
        Source(issue) => raise issue
        other => raise other
      }
    NeedsInputs(_) => fail("closed success fixture requires no external inputs")
  }
}

///|
fn success_fixture_pipeline(
  prefix : String,
  predicate : String,
  value : String,
) -> @pipeline.CheckedPipeline raise {
  success_fixture_check(success_fixture_program(prefix, predicate, value))
}

///|
fn success_fixture_nullability(
  pipeline : @pipeline.CheckedPipeline,
) -> (Bool, Bool) {
  let output = @pipeline.output_carrier(pipeline).unwrap()
  let schema = @carrier.complete_schema(@carrier.relation_rows(output).unwrap()).unwrap()
  (
    @schema.lookup_reference(schema, "risk").unwrap().contract.nullable,
    @schema.lookup_reference(schema, "reason").unwrap().contract.nullable,
  )
}

///|
test "Infer success proof refines only the original non-null success members" {
  for
    predicate in [
      (
        #|{"eq":[{"field":"outcome"},{"literal":"ok"}]}
      ),
      (
        #|{"eq":[{"literal":"ok"},{"field":"outcome"}]}
      ),
      (
        #|{"and":[{"eq":[{"field":"outcome"},{"literal":"ok"}]},{"eq":[{"field":"id"},{"literal":"same"}]}]}
      ),
    ] {
    let checked = success_fixture_pipeline(
      success_fixture_prefix(),
      predicate,
      "{\"field\":\"value\"}",
    )
    assert_eq(success_fixture_nullability(checked), (false, true))
  }
}

///|
test "Infer success proof refuses other outcomes OR NOT and computed status" {
  for
    predicate in [
      (
        #|{"eq":[{"field":"outcome"},{"literal":"failed:timeout"}]}
      ),
      (
        #|{"or":[{"eq":[{"field":"outcome"},{"literal":"ok"}]},{"literal":true}]}
      ),
      (
        #|{"not":{"eq":[{"field":"outcome"},{"literal":"failed:timeout"}]}}
      ),
      (
        #|{"eq":[{"concat":[{"field":"outcome"},{"literal":""}]},{"literal":"ok"}]}
      ),
    ] {
    assert_eq(
      success_fixture_nullability(
        success_fixture_pipeline(
          success_fixture_prefix(),
          predicate,
          "{\"field\":\"value\"}",
        ),
      ),
      (true, true),
    )
  }
}

///|
test "Infer success proof does not trust synthetic outcome and value field names" {
  let prefix =
    #|{"values":{"schema":{"outcome":{"type":"string","nullable":false},"value":{"type":"object","nullable":true,"fields":{"risk":{"type":"string","nullable":false},"reason":{"type":"string","nullable":true}}}},"rows":[{"outcome":"ok","value":null}]},"as":"synthetic"}
  assert_eq(
    success_fixture_nullability(
      success_fixture_pipeline(
        prefix, "{\"eq\":[{\"field\":\"outcome\"},{\"literal\":\"ok\"}]}", "{\"field\":\"value\"}",
      ),
    ),
    (true, true),
  )
}

///|
test "Infer success proof keeps same-producer self-join occurrences distinct" {
  for side in ["left", "right"] {
    let join = ",{\"join\":{\"with\":\"outcomes\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"status\":\"left.outcome\",\"result\":\"" +
      side +
      ".value\"}}}"
    let checked = success_fixture_pipeline(
      success_fixture_prefix() + join,
      "{\"eq\":[{\"field\":\"status\"},{\"literal\":\"ok\"}]}",
      "{\"field\":\"result\"}",
    )
    assert_eq(success_fixture_nullability(checked), (side != "left", true))
  }
}

///|
fn success_fixture_nodes(
  pipeline : @pipeline.CheckedPipeline,
  count : Int,
) -> Array[@evidence.InferFilterNode] {
  let nodes : Array[@evidence.InferFilterNode] = []
  for i in 0..<count {
    let step = @pipeline.step_at(pipeline, i).unwrap()
    nodes.push(
      match step.filter_refinement {
        Some(proof) => @evidence.Refined(proof)
        None =>
          match step.operation {
            Infer(checked) => @evidence.Infer(checked)
            Unary(checked) => @evidence.Unary(checked)
            Join(checked~, ..) => @evidence.Join(checked)
            _ => @evidence.Other(step.source, @pipeline.step_schema(step))
          }
      },
    )
  }
  nodes
}

///|
fn success_fixture_filter(
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
) -> @relation.CheckedOperation {
  match @pipeline.step_at(pipeline, index).unwrap().operation {
    Unary(operation) => operation
    _ => abort("expected authored Filter")
  }
}

///|
fn success_fixture_proof_limits() -> @evidence.FilterProofLimits {
  {
    max_work: 100000,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }
}

///|
test "Infer success proof rejects foreign and independently rechecked equal-shaped owners" {
  let program = success_fixture_program(
    success_fixture_prefix(),
    "{\"eq\":[{\"field\":\"outcome\"},{\"literal\":\"ok\"}]}",
    "{\"field\":\"value\"}",
  )
  let first = success_fixture_check(program)
  let second = success_fixture_check(program)
  let root = @pipeline.source(first)
  let filter = success_fixture_filter(first, 3)
  let nodes = success_fixture_nodes(first, 3)
  assert_true(
    @evidence.refine_infer_filter(
      root,
      nodes,
      filter,
      success_fixture_proof_limits(),
    )
    is Ok(_),
  )
  assert_true(
    @evidence.refine_infer_filter(
      root,
      success_fixture_nodes(second, 3),
      filter,
      success_fixture_proof_limits(),
    )
    is Err({ kind: ForeignProofInput, .. }),
  )
  let mixed = nodes.copy()
  mixed[2] = success_fixture_nodes(second, 3)[2]
  assert_true(
    @evidence.refine_infer_filter(
      root,
      mixed,
      filter,
      success_fixture_proof_limits(),
    )
    is Err({ kind: ForeignProofInput, .. }),
  )
  let foreign = success_fixture_pipeline(
    success_fixture_prefix(),
    "{\"eq\":[{\"field\":\"outcome\"},{\"literal\":\"ok\"}]}",
    "{\"field\":\"value\"}",
  )
  assert_true(
    @evidence.refine_infer_filter(
      @pipeline.source(foreign),
      nodes,
      filter,
      success_fixture_proof_limits(),
    )
    is Err({ kind: ForeignProofSource, .. }),
  )
  assert_true(
    @evidence.refine_infer_filter(root, nodes, filter, {
      ..success_fixture_proof_limits(),
      max_work: 0,
    })
    is Err({ kind: ProofBudgetExceeded, .. }),
  )
  assert_true(
    @evidence.refine_infer_filter(root, nodes, filter, {
      ..success_fixture_proof_limits(),
      max_nodes: 0,
    })
    is Err({ kind: ProofBudgetExceeded, .. }),
  )
  assert_true(
    @evidence.refine_infer_filter(root, nodes, filter, {
      ..success_fixture_proof_limits(),
      max_text_bytes: 0,
    })
    is Err({ kind: ProofBudgetExceeded, .. }),
  )
}

///|
test "Infer success proof preserves missing-side outer join nullability" {
  let prefix = success_fixture_prefix() +
    (
      #|,{"filter":{"eq":[{"field":"outcome"},{"literal":"failed:timeout"}]},"as":"failures"},{"from":"outcomes","join":{"with":"failures","kind":"left","on":[{"left":"id","right":"id"}],"select":{"status":"left.outcome","result":"right.value"}}}
    )
  let checked = success_fixture_pipeline(
    prefix, "{\"eq\":[{\"field\":\"status\"},{\"literal\":\"ok\"}]}", "{\"field\":\"result\"}",
  )
  assert_eq(success_fixture_nullability(checked), (true, true))
}

///|
test "Infer success proof preserves an originally nullable success ancestor" {
  let program = success_fixture_program(
    success_fixture_prefix(),
    "{\"eq\":[{\"field\":\"outcome\"},{\"literal\":\"ok\"}]}",
    "{\"property\":{\"name\":\"details\",\"value\":{\"field\":\"value\"}}}",
  )
  let checked = success_fixture_check(
    program,
    environment=infer_nullable_success_environment(),
  )
  assert_eq(success_fixture_nullability(checked), (true, true))
}

///|
test "Infer success proof cannot be transplanted into an independently checked prefix" {
  let prefix = success_fixture_prefix() +
    (
      #|,{"filter":{"eq":[{"field":"outcome"},{"literal":"ok"}]}}
    )
  let program = success_fixture_program(
    prefix, "{\"eq\":[{\"field\":\"outcome\"},{\"literal\":\"ok\"}]}", "{\"field\":\"value\"}",
  )
  let first = success_fixture_check(program)
  let second = success_fixture_check(program)
  let nodes = success_fixture_nodes(first, 4)
  assert_true(nodes[3] is @evidence.Refined(_))
  nodes[3] = success_fixture_nodes(second, 4)[3]
  assert_true(
    @evidence.refine_infer_filter(
      @pipeline.source(first),
      nodes,
      success_fixture_filter(first, 4),
      success_fixture_proof_limits(),
    )
    is Err({ kind: ForeignProofInput, .. }),
  )
}

///|
test "Infer success proof keeps lowered Filter and fragment output schemas coherent" {
  let checked = success_fixture_pipeline(
    success_fixture_prefix(),
    "{\"eq\":[{\"field\":\"outcome\"},{\"literal\":\"ok\"}]}",
    "{\"field\":\"value\"}",
  )
  let prepared = @lower.prepare(checked, {
    max_nodes: 1000,
    max_references: 1000,
    max_work: 10000,
    max_identifier_bytes: 10000,
  }).unwrap()
  let bound = @lower.bind_parameters(
    prepared,
    None,
    max_parameters=0,
    max_name_bytes=10000,
  ).unwrap()
  let expressions : @lower.ExpressionLimits = {
    max_nodes: 1000,
    max_work: 10000,
    max_depth: 100,
    max_literal_nodes: 1000,
    max_literal_text_bytes: 10000,
  }
  let kernel = @lower.prepare_kernel(
    bound,
    3,
    max_bindings=1000,
    max_name_bytes=10000,
    expressions,
  ).unwrap()
  let output = @lower.kernel_output_schema(kernel)
  assert_false(
    @schema.lookup_reference(output, "value").unwrap().contract.nullable,
  )
  let sequence = @lower.prepare_sequence_with_infer_boundary(bound, 2, {
    max_steps: 1000,
    max_rows: 1000,
    max_cells: 10000,
    max_bindings: 1000,
    max_name_bytes: 10000,
    expressions,
  }).unwrap()
  let fragment = @lower.prepare_fragment_pipeline(sequence, 3, {
    max_roots: 1000,
    max_pointer_bytes: 10000,
    max_work: 10000,
  }).unwrap()
  assert_false(
    @schema.lookup_reference(
      @lower.fragment_pipeline_output_schema(fragment),
      "value",
    ).unwrap().contract.nullable,
  )
  let downstream = @lower.prepare_kernel(
    bound,
    5,
    max_bindings=1000,
    max_name_bytes=10000,
    expressions,
  ).unwrap()
  assert_false(
    @schema.lookup_reference(@lower.kernel_output_schema(downstream), "risk").unwrap().contract.nullable,
  )
  assert_true(
    @schema.lookup_reference(@lower.kernel_output_schema(downstream), "reason").unwrap().contract.nullable,
  )
}
