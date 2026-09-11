///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 30,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn pipeline(
  body : String,
  parameters? : @parameter.Declarations? = None,
) -> @pipeline.CheckedPipeline {
  let schema = @schema.from_object(
    @contract.object_contract(
      [("id", @contract.primitive(NumberType, nullable=false))],
      nullable=false,
      max_fields=1,
      max_name_bytes=2,
    ).unwrap(),
  ).unwrap()
  @pipeline.check(cursor(body), [("rows", schema)], parameters, None, {
    max_steps: 20,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 10000,
    max_tokens: 10000,
    max_depth: 100,
  }).unwrap()
}

///|
// Build integrity-valid claims, including intentionally false application claims.
// Hash correctness is covered independently by the SHA and wire corpus suites.
fn proof(
  law : String,
  value : Int,
  derivation : String,
  reference? : String = "checked-step:0",
  unit? : String = "rows",
) -> @wire.ProgramProofClaim {
  let body = "{\"inputs\":[],\"law_id\":\"" +
    law +
    "\",\"semantic_ref\":\"" +
    reference +
    "\",\"unit\":\"" +
    unit +
    "\",\"value\":" +
    value.to_string() +
    ",\"version\":\"actql-bound-proof/0.1\"}"
  let id = "sha256:" + @sha.hex(@utf8.encode(body))
  let preimage = "{\"dependencies\":[\"" +
    id +
    "\"],\"derivation\":" +
    derivation +
    ",\"law_id\":\"" +
    law +
    "\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"" +
    id +
    "\",\"semantic_ref\":\"" +
    reference +
    "\"},\"unit\":\"" +
    unit +
    "\",\"value\":" +
    value.to_string() +
    ",\"version\":\"actql-bound-witness/0.1\""
  let cid = "sha256:" + @sha.hex(@utf8.encode(preimage + "}"))
  let bytes = @utf8.encode(preimage + ",\"witness_cid\":\"" + cid + "\"}")
  let caps : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }
  let wire = @wire.admit(bytes, cid, caps).unwrap()
  @wire.bind_program_proof(@utf8.encode(body), wire, caps).unwrap()
}

///|
test "operation applications retain the checked owner and verify global and literal clamp laws" {
  for
    (body, law, n, derivation) in [
      (
        "[{\"group\":{\"by\":[],\"aggregates\":{}}}]", "actql.bound.global-group",
        1, "{\"op\":\"source\"}",
      ),
      (
        "[{\"take\":7}]", "actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}",
      ),
      (
        "[{\"take\":{\"count\":7,\"offset\":100}}]", "actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}",
      ),
      (
        "[{\"top_k\":{\"k\":7,\"by\":[{\"id\":\"asc\"}]}}]", "actql.bound.top-k",
        7, "{\"maximum\":7,\"op\":\"clamp\"}",
      ),
      (
        "[{\"top_k_by\":{\"partition_by\":[],\"k\":7,\"by\":[{\"id\":\"asc\"}]}}]",
        "actql.bound.top-k", 7, "{\"maximum\":7,\"op\":\"clamp\"}",
      ),
    ] {
    let p = pipeline(body)
    let claim = proof(law, n, derivation)
    let checked = @capacity_program_step.check(p, 0, claim).unwrap()
    assert_true(
      physical_equal(@capacity_program_step.checked_pipeline(checked), p),
    )
    assert_true(
      physical_equal(@capacity_program_step.checked_proof(checked), claim),
    )
    assert_eq(@capacity_program_step.checked_step(checked), 0)
    assert_eq(@capacity_program_step.subject_ref(p, 0), Some("checked-step:0"))
    assert_true(@capacity_program_step.subject_ref(p, -1) is None)
    assert_true(@capacity_program_step.subject_ref(p, 1) is None)
    assert_true(@capacity_program_step.check(p, 1, claim) is Err(MissingStep))
  }
}

///|
test "matching values and valid proof identities do not establish an operation application" {
  let group = pipeline(
    "[{\"group\":{\"by\":[],\"aggregates\":{}},\"as\":\"grouped\"}]",
  )
  let take = pipeline("[{\"take\":1}]")
  let grouped = pipeline("[{\"group\":{\"by\":[\"id\"],\"aggregates\":{}}}]")
  let source = "{\"op\":\"source\"}"
  let group_proof = proof("actql.bound.global-group", 1, source)
  assert_true(
    @capacity_program_step.check(take, 0, group_proof) is Err(LawMismatch),
  )
  assert_true(
    @capacity_program_step.check(grouped, 0, group_proof)
    is Err(UnsupportedOperation),
  )
  assert_true(
    @capacity_program_step.check(
      group,
      0,
      proof("actql.bound.global-group", 2, source),
    )
    is Err(ValueMismatch),
  )
  assert_true(
    @capacity_program_step.check(
      group,
      0,
      proof("actql.bound.global-group", 1, source, unit="nodes"),
    )
    is Err(LawMismatch),
  )
  assert_true(
    @capacity_program_step.check(
      group,
      0,
      proof("actql.bound.global-group", 1, source, reference="grouped"),
    )
    is Err(SubjectMismatch),
  )
  assert_true(
    @capacity_program_step.check(take, 0, proof("actql.bound.take", 1, source))
    is Err(InvalidDerivation),
  )
  assert_true(
    @capacity_program_step.check(
      take,
      0,
      proof("actql.bound.take", 1, "{\"maximum\":2,\"op\":\"clamp\"}"),
    )
    is Err(InvalidDerivation),
  )
}

///|
test "partitioned selection and unresolved Parameter counts cannot supply global literal bounds" {
  let claim = proof("actql.bound.top-k", 7, "{\"maximum\":7,\"op\":\"clamp\"}")
  let partitioned = pipeline(
    "[{\"top_k_by\":{\"partition_by\":[\"id\"],\"k\":7,\"by\":[{\"id\":\"asc\"}]}}]",
  )
  assert_true(
    @capacity_program_step.check(partitioned, 0, claim)
    is Err(UnsupportedOperation),
  )
  let d = @parameter.read_declarations(
    Some(cursor("{\"n\":{\"type\":\"number\",\"default\":7}}")),
    { max_parameters: 1, max_nodes: 30, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let p = pipeline("[{\"take\":{\"$param\":\"n\"}}]", parameters=Some(d))
  assert_true(
    @capacity_program_step.check(
      p,
      0,
      proof("actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}"),
    )
    is Err(UnresolvedCount),
  )
}
