///|
test "compiler manifests require exact pinned bodies" {
  let grammar = @environment.compiler_grammar_manifest_wire()
  let barrier = @environment.compiler_barrier_contract_manifest_wire()
  let admitted = admit_client_compilation_manifests(
    grammar, barrier, 10000, 1000, 20,
  )
  guard admitted is Ok(manifests) else { fail("pinned manifests rejected") }
  assert_eq(
    client_compilation_grammar_manifest_cid(manifests),
    @environment.compiler_grammar_manifest_cid(),
  )
  assert_eq(
    client_compilation_barrier_manifest_cid(manifests),
    @environment.compiler_barrier_contract_manifest_cid(),
  )
  assert_true(
    admit_client_compilation_manifests(
      @environment.program_source_grammar_cid(),
      barrier,
      10000,
      1000,
      20,
    )
    is Err(ClientCompilationManifestIssue::InvalidGrammarManifest),
  )
  assert_true(
    admit_client_compilation_manifests(
      grammar.replace(old="\"values\"", new="\"ValueS\""),
      barrier,
      10000,
      1000,
      20,
    )
    is Err(ClientCompilationManifestIssue::GrammarManifestMismatch),
  )
  assert_true(
    admit_client_compilation_manifests(
      grammar,
      barrier.replace(old="artifact_barrier", new="other_barrier"),
      10000,
      1000,
      20,
    )
    is Err(ClientCompilationManifestIssue::BarrierManifestMismatch),
  )
}
