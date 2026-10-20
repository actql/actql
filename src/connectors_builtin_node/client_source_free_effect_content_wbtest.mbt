///|
fn source_free_content_effect_fixture() -> @publication_host.PreparedClientEffectComputation {
  let environment = store_public_bridge_fixture("collection")
  let outcome = client_program_prepare_source_computation_with_parameters(
    "SELECT 1 AS id |> SERIALIZE FORMAT JSONL ORDER BY id OPTIONS (name = 'one.jsonl') |> EFFECT STORE storage.archive SET (path = 'copy.jsonl', content = content)",
    "sql",
    environment,
    store_public_bridge_publication(environment),
    None,
    None,
    true,
    [],
  )
  match outcome {
    SourceEffect(EffectPrepared(value)) => value
    _ => abort("the actual source-free Content STORE is statically prepared")
  }
}

///|
fn source_free_content_effect_policy() -> String {
  "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}"
}

///|
test "source-free Content Effect compiler requires and retains its original explicit Host policy" {
  let prepared = source_free_content_effect_fixture()
  assert_true(
    client_program_compile_local_effects(prepared)
    is Err(Compilation(Serialization(UnsupportedGraph))),
  )
  let compilation = client_program_compile_local_effects_with_source_free_policy_body(
    prepared,
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
    source_free_content_effect_policy(),
    1000000,
    100000,
    100,
  ).unwrap()
  let wire = client_program_effect_compilation_plan_wire(compilation)
  assert_true(wire.contains("\"kind\":\"content_barrier\""))
  assert_true(
    wire.contains(
      "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
    ),
  )
  assert_true(wire.contains("\"published_store\""))
  assert_true(wire.contains("\"command:fixture.upload.v1\""))
}

///|
test "source-free Content Effect compiler refuses a substituted classification body or CID" {
  let prepared = source_free_content_effect_fixture()
  let cid = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  for
    (identity, wire) in [
      ("sha256:" + "a".repeat(64), source_free_content_effect_policy()),
      (
        cid,
        source_free_content_effect_policy().replace(
          old="unknown\"",
          new="internal\"",
        ),
      ),
      (cid, "{}"),
    ] {
    assert_true(
      client_program_compile_local_effects_with_source_free_policy_body(
        prepared, identity, wire, 1000000, 100000, 100,
      )
      is Err(_),
    )
  }
}

///|
test "source-free Content Effect compilation restores only its original policy and complete saved plan" {
  let prepared = source_free_content_effect_fixture()
  let cid = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  let policy = @publication_host.admit_source_free_result_policy_body(
    cid,
    source_free_content_effect_policy(),
    1000000,
    100000,
    100,
  ).unwrap()
  let compilation = client_program_compile_local_effects_with_source_free_policy_body(
    prepared,
    cid,
    source_free_content_effect_policy(),
    1000000,
    100000,
    100,
  ).unwrap()
  let manifests = @publication_host.admit_client_compilation_manifests(
    @check_environment.compiler_grammar_manifest_wire(),
    @check_environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  let restore = fn(policy, plan) {
    @publication_host.admit_prepared_client_effect_compilation(
      prepared,
      plan,
      client_program_effect_compilation_fact_manifest_wire(compilation),
      client_program_effect_compilation_template_wire(compilation),
      client_program_effect_compilation_compiled_plan_wire(compilation),
      manifests,
      @publication_host.client_standard_values_sequence_limits(),
      100000,
      10000,
      1000000,
      100000,
      100,
      source_free_policy=policy,
    )
  }
  let plan = client_program_effect_compilation_plan_wire(compilation)
  assert_true(restore(Some(policy), plan) is Ok(_))
  assert_true(restore(None, plan) is Err(_))
  assert_true(
    restore(Some(policy), plan.replace(old="copy.jsonl", new="other.jsonl"))
    is Err(_),
  )
}
