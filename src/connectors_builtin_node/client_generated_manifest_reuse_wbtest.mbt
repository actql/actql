///|
test "generated compiler manifests are admitted once for one loaded compiler" {
  let cached = Ref(None)
  let reads = Ref(0)
  let read = () => {
    reads.val += 1
    read_client_generated_compilation_manifests()
  }
  let first = client_generated_compilation_manifests(cached~, read~).unwrap()
  let second = client_generated_compilation_manifests(cached~, read~).unwrap()
  assert_eq(reads.val, 1)
  assert_true(physical_equal(first, second))
  assert_eq(
    @publication_host.client_compilation_grammar_manifest_cid(first),
    @check_environment.compiler_grammar_manifest_cid(),
  )
  assert_eq(
    @publication_host.client_compilation_barrier_manifest_cid(first),
    @check_environment.compiler_barrier_contract_manifest_cid(),
  )
}

///|
test "a generated manifest admission failure remains the original failure" {
  let cached = Ref(None)
  let reads = Ref(0)
  let read = () => {
    reads.val += 1
    @publication_host.admit_client_compilation_manifests(
      "{}",
      @check_environment.compiler_barrier_contract_manifest_wire(),
      100000,
      10000,
      100,
    )
  }
  assert_true(
    client_generated_compilation_manifests(cached~, read~)
    is Err(GrammarManifestMismatch),
  )
  assert_true(
    client_generated_compilation_manifests(cached~, read~)
    is Err(GrammarManifestMismatch),
  )
  assert_eq(reads.val, 1)
}

///|
test "independent compiler admissions and public manifest refusals stay separate" {
  let first = Ref(None)
  let other = Ref(None)
  let reads = Ref(0)
  let read = () => {
    reads.val += 1
    read_client_generated_compilation_manifests()
  }
  let original = client_generated_compilation_manifests(cached=first, read~).unwrap()
  let separate = client_generated_compilation_manifests(cached=other, read~).unwrap()
  assert_eq(reads.val, 2)
  assert_false(physical_equal(original, separate))
  assert_true(
    @publication_host.admit_client_compilation_manifests(
      "{",
      @check_environment.compiler_barrier_contract_manifest_wire(),
      100000,
      10000,
      100,
    )
    is Err(InvalidGrammarManifest),
  )
  assert_true(
    @publication_host.admit_client_compilation_manifests(
      @check_environment.compiler_grammar_manifest_wire(),
      "{}",
      100000,
      10000,
      100,
    )
    is Err(BarrierManifestMismatch),
  )
  assert_true(
    @publication_host.admit_client_compilation_manifests(
      @check_environment.compiler_grammar_manifest_wire(),
      @check_environment.compiler_barrier_contract_manifest_wire(),
      0,
      10000,
      100,
    )
    is Err(InvalidBudget),
  )
}

///|
test "new public Programs retain their own compilation with shared manifests" {
  let environment = keyed_source_environment()
  let publication = "{\"environmentCid\":\"" +
    client_program_checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let installed = client_program_prepare_public_source_environment(
    environment, publication,
  ).unwrap()
  let plans : Array[String] = []
  for query in ["SELECT 1 AS id", "SELECT 2 AS id"] {
    guard client_program_prepare_source_computation_in_public_environment(
        query,
        "sql",
        environment,
        installed,
        None,
        None,
        false,
        [],
      )
      is SourcePure(Prepared(prepared)) else {
      fail("each new query must retain the original preparation")
    }
    let compiled = client_program_compile_local_values(prepared).unwrap()
    plans.push(
      @publication_host.client_values_executable_plan_cid(
        @publication_host.client_values_compilation_plan(compiled),
      ),
    )
  }
  assert_true(plans[0] != plans[1])
}
