///|
// Fixture builders create admitted input evidence, not expected compiler CIDs.
fn graph_conversion_fixture(
  unit : BuiltUnit,
  budget : IdentityBudget,
) -> (@pipeline.CheckedPipeline, @graph_input.GraphInputs) raise {
  let publication = @context.publication_row_limit_result(
    unit.publication_rows[0],
  )
  let policy = @capacity.application_closure_policy(
    @context.checked_capacity(publication.context),
  )
  let fields = @carrier.typed_rows(
    @schema.from_object(
      @contract.object_contract(
        [],
        nullable=false,
        max_fields=0,
        max_name_bytes=0,
      ).unwrap(),
    ).unwrap(),
  )
  let definition = @carrier.graph_node_definition(
    "N",
    [@contract.primitive(StringType, nullable=false)],
    fields,
    [],
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  let graph = @carrier.graph(
    "sha256:" + "1".repeat(64),
    [definition],
    [],
    max_definitions=1,
    max_contract_work=100,
  ).unwrap()
  let node = @source.parse_json(
    "[{\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"key\"},\"where\":\"true\",\"fields\":[\"key\"]}}]",
    { max_input_bytes: 1000, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  let cursor = @decode.admit(node, {
    max_nodes: 100,
    max_depth: 10,
    max_string_bytes: 1000,
    max_total_string_bytes: 1000,
  }).unwrap()
  let pipeline = @pipeline.check_carriers(cursor, [("g", graph)], None, None, {
    max_steps: 10,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 10000,
    max_tokens: 10000,
    max_depth: 100,
  }).unwrap()
  let witnesses : Array[@wire.WireWitness] = []
  let limits : Array[(Bytes, String)] = []
  let caps : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }
  for measure in ["nodes", "edges"] {
    let host = publication_host(
      @policy.ceiling(policy, "max_graph_input_" + measure).unwrap(),
      budget,
    )
    let bytes = publication_metadata(
      w => @host.emit(host, w) catch { e => raise Encoding(e) },
      budget,
    )
    witnesses.push(@wire.admit(bytes, @host.cid(host), caps).unwrap())
    let writer = @encode.writer(10000, 1000, 100)
    emit_graph_input_limit("graph-input:g", measure, host, writer, None)
    let body = @encode.finish(writer).replace(
      old="graph-input:g/",
      new="graph-input:g:",
    )
    let cid = "sha256:" + @sha.hex(@utf8.encode(body))
    let text = body.replace(
      old="\"subject_ref\":",
      new="\"resolved_limit_cid\":\"" + cid + "\",\"subject_ref\":",
    )
    limits.push((@utf8.encode(text), cid))
    let writer = identity_writer(budget)
    emit_graph_input_witness("g", measure, 1000L, cid, writer, None)
    let witness_cid = identity_finish(budget, writer)
    let bytes = publication_metadata(
      w => {
        emit_graph_input_witness("g", measure, 1000L, cid, w, Some(witness_cid))
      },
      budget,
    )
    witnesses.push(@wire.admit(bytes, witness_cid, caps).unwrap())
  }
  let mixed = @wire.check_mixed_claims(witnesses, limits, {
    max_entities: 10,
    max_references: 100,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 10,
    max_references: 100,
  }).unwrap()
  let sources = @host.bind_claim_sources(claims, [policy], {
    max_entries: 100,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  let inputs = @graph_input.check(pipeline, sources, policy, {
    max_work: 10000,
    max_name_bytes: 1000,
  }).unwrap()
  (pipeline, inputs)
}

///|
test "keyed Graph input conversion retains preflight and rejects a foreign pipeline" {
  let budget = IdentityBudget::{
    work: 100000000,
    bytes: 10000000,
    nodes: 1000000,
    depth: 100,
  }
  let (_, _, _, _, units) = local_construction_fixture(budget)
  let (pipeline, inputs) = graph_conversion_fixture(units[0], budget)
  // The synthetic Unit tests the conversion boundary, not final Program sealing.
  let unit = {
    ..units[0],
    pipeline,
    definition_cid: "sha256:" + "0".repeat(64),
  }
  let original = @graph_input.input_bound(inputs, 0, Nodes).unwrap()
  let converted = reidentify_graph_input(unit, original, budget)
  assert_true(physical_equal(converted.original, original))
  assert_eq(
    @wire.cid(converted.witness),
    "sha256:cf5b42833459da49cc5d3068d3aa1446066b490d71b0c323ed1e4562411b85dd",
  )
  assert_eq(
    @wire.limit_cid(converted.limit),
    "sha256:2d58f1dea7e6164f5b9b6e81dc5a83cb31e0c4381f2ab6028dc00411d208821d",
  )
  assert_true(@wire.limit_enforcement(converted.limit) is UnitPreflight)
  let arithmetic = @wire.mixed_arithmetic(converted.claims)
  let witnesses = Array::makei(@wire.claim_count(arithmetic), i => {
    @wire.claim_at(arithmetic, i).unwrap()
  })
  assert_true(
    @wire.check_arithmetic_claims(witnesses, {
      max_witnesses: 10,
      max_references: 100,
    })
    is Err(_),
  )
  let before = IdentityBudget::{ ..budget, }
  try reidentify_graph_input(units[0], original, budget) catch {
    UnitBuildFailure::ForeignOwner => ()
    e => raise e
  } noraise {
    _ => fail("foreign Graph owner accepted")
  }
  assert_eq(budget.work, before.work)
  assert_eq(budget.bytes, before.bytes)
  assert_eq(budget.nodes, before.nodes)
  let input_cid = @wire.cid(@graph_input.bound_witness(original))
  let body = "{\"inputs\":[\"\{input_cid}\"],\"law_id\":\"actql.bound.match-nodes\",\"semantic_ref\":\"checked-step:0\",\"unit\":\"rows\",\"value\":1000,\"version\":\"actql-bound-proof/0.1\"}"
  let proof_cid = "sha256:" + @sha.hex(@utf8.encode(body))
  let deps = if input_cid < proof_cid {
    [input_cid, proof_cid]
  } else {
    [proof_cid, input_cid]
  }
  let witness_body = "{\"dependencies\":[\"\{deps[0]}\",\"\{deps[1]}\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.match-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"\{proof_cid}\",\"semantic_ref\":\"checked-step:0\"},\"unit\":\"rows\",\"value\":1000,\"version\":\"actql-bound-witness/0.1\""
  let cid = "sha256:" + @sha.hex(@utf8.encode(witness_body + "}"))
  let caps : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }
  let wire = @wire.admit(
    @utf8.encode(witness_body + ",\"witness_cid\":\"\{cid}\"}"),
    cid,
    caps,
  ).unwrap()
  let proof = @wire.bind_program_proof(@utf8.encode(body), wire, caps).unwrap()
  let operation = @step_bounds.check_with_sources(pipeline, 0, proof, [
    GraphInput(original),
  ]).unwrap()
  let result = reidentify_step_graph([unit], operation, budget)
  assert_eq(result.inputs.length(), 0)
  assert_eq(result.graph_inputs.length(), 1)
  assert_true(physical_equal(result.graph_inputs[0].original, original))
  assert_eq(
    @wire.program_proof_input_at(result.proof, 0),
    Some(@wire.cid(converted.witness)),
  )
  let limits : Array[(Bytes, String)] = []
  let witnesses = publication_proof_claims([result], budget, limits~)
  assert_eq(limits.length(), 1)
  let mixed = @wire.check_mixed_claims(witnesses, limits, {
    max_entities: 10,
    max_references: 100,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
  let closed = @wire.check_mixed_program_claims(mixed, [result.proof], {
    max_witnesses: 10,
    max_references: 100,
  }).unwrap()
  assert_eq(@wire.claim_count(@wire.program_claim_arithmetic(closed)), 3)
}
