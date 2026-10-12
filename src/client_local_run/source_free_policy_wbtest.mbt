///|
// Independent normative policy preimage: no contributing Source and unknown
// provenance. The CID is fixed from the contract, never from product output.
let source_free_original_policy : String =
  #|{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}

///|
let source_free_original_policy_cid : String = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"

///|
fn source_free_policy_plan(
  input : @input.LocalPreparedInput,
  cid? : String = source_free_original_policy_cid,
  body? : String = source_free_original_policy,
) -> Result[LocalRunPlan, LocalRunIssue] {
  let current = account(Allow)
  prepare_source_free_local_publication_run(
    input,
    "sha256:" + "b".repeat(64),
    "original-submission",
    permit(input, current),
    current,
    tuple(),
    context_cid(),
    "sha256:" + "c".repeat(64),
    "local",
    "original-policy-run",
    "2026-10-12T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
    (cid, body),
  )
}

///|
test "source-free plan retains original compiled policy before invocation" {
  for
    input in [
      prepared(@input.Aql("SELECT 1 AS n")),
      prepared(@input.Program(program)),
    ] {
    let plan = source_free_policy_plan(input).unwrap()
    let compiled = local_run_compiled(plan)
    assert_true(@host.client_compiled_run_matches(compiled, plan.prepared))
    assert_true(
      physical_equal(
        @host.client_compiled_run_admission(compiled),
        plan.admission,
      ),
    )
    assert_eq(
      @host.client_compiled_run_publication_policy_bodies(
        compiled, 65536, 8192, 64,
      ).unwrap(),
      [
        (
          "data_policy", source_free_original_policy_cid, source_free_original_policy,
        ),
      ],
    )
    let (observation, invocation) = issue_source_free_local_run_invocation(plan).unwrap()
    let body = @json.parse(@publication.run_evidence_value_json(observation))
    let fields = match body {
      Object(fields) => fields
      _ => abort("Expected object")
    }
    assert_true(
      fields.get("data_policy_cid") is Some(String(cid)) &&
      cid == source_free_original_policy_cid,
    )
    assert_true(
      fields.get("source_evidence_cids") is Some(Array(values)) &&
      values.is_empty(),
    )
    assert_true(
      fields.get("captured_input_artifact_cids") is Some(Array(values)) &&
      values.is_empty(),
    )
    assert_true(
      fields.get("consistency") is Some(String(value)) &&
      value == "no_external_sources",
    )
    assert_eq(@host.prepared_client_acquisition_count(plan.prepared), 0)
    assert_true(
      @publication.publication_contract_identity(invocation).has_prefix(
        "sha256:",
      ),
    )
  }
}

///|
test "missing source-free policy does not synthesize Source or Model policy" {
  let original = plan(prepared(@input.Aql("SELECT 1 AS n")), "missing-policy")
  assert_true(
    @host.client_compiled_run_source_free_result_policy_body(
      local_run_compiled(original),
    )
    is None,
  )
  assert_true(issue_source_free_local_run_invocation(original) is Err(_))
  assert_eq(@host.prepared_client_acquisition_count(original.prepared), 0)
}

///|
test "source-free policy invalid CID and falsely public provenance refuse" {
  let input = prepared(@input.Aql("SELECT 1 AS n"))
  assert_true(
    source_free_policy_plan(input, cid="sha256:" + "d".repeat(64))
    is Err(Admission(@host.InvalidResultPolicy)),
  )
  let public = "{\"classification\":\"public\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":false,\"version\":\"actql-effective-data-policy/0.1\"}"
  assert_true(
    source_free_policy_plan(input, body=public)
    is Err(Admission(@host.InvalidResultPolicy)),
  )
}

///|
test "materials rewrap original admission without issuing policy or new Run" {
  let input = prepared(@input.Aql("SELECT 1 AS n"))
  let original = source_free_policy_plan(input).unwrap()
  let wire = export_local_run_materials(
    original,
    environment(),
    environment_wire,
    None,
  ).unwrap()
  let materials = restore_local_run_materials(
    wire,
    local_run_definition_cid(original),
  ).unwrap()
  let compiled = @host.client_task_run_materials_compiled_original(materials).unwrap()
  assert_true(@host.client_compiled_run_matches(compiled, materials.prepared))
  assert_true(
    physical_equal(
      @host.client_compiled_run_admission(compiled),
      materials.admission,
    ),
  )
  assert_eq(
    @publication.publication_contract_identity(materials.run_definition),
    local_run_definition_cid(original),
  )
  // The original task codec contains no policy journal. Rewrapping must not
  // turn a successful material read into publication permission after restart.
  assert_true(
    @host.client_compiled_run_source_free_result_policy_body(compiled) is None,
  )
  assert_true(
    @host.issue_client_compiled_local_values_invocation(
      compiled,
      materials.run_definition,
      65536,
      8192,
      64,
    )
    is Err(_),
  )
}

///|
test "foreign task material cannot rewrap original compiled custody" {
  let input = prepared(@input.Aql("SELECT 1 AS n"))
  let original = source_free_policy_plan(input).unwrap()
  let wire = export_local_run_materials(
    original,
    environment(),
    environment_wire,
    None,
  ).unwrap()
  let materials = restore_local_run_materials(
    wire,
    local_run_definition_cid(original),
  ).unwrap()
  let foreign = source_free_policy_plan(prepared(@input.Aql("SELECT 2 AS n"))).unwrap()
  assert_true(
    @host.client_task_run_materials_compiled_original({
      ..materials,
      compilation: foreign.compilation,
    })
    is Err(_),
  )
}
