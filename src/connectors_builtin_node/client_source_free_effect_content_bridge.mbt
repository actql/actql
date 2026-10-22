///|
/// The installed Host supplies its original unknown-provenance policy before
/// compilation. This is not a default, Source completion or Effect permission.
#export_name("clientProgramCompileLocalEffectsWithSourceFreePolicyBody")
pub fn client_program_compile_local_effects_with_source_free_policy_body(
  prepared : @publication_host.PreparedClientEffectComputation,
  policy_cid : String,
  policy_wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectCompilation,
  ClientProgramEffectCompilationBridgeIssue,
] {
  let policy = match
    @publication_host.admit_source_free_result_policy_body(
      policy_cid, policy_wire, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err(Compilation(Serialization(Generation(Policy(issue)))))
  }
  let manifests = match
    @publication_host.admit_client_compilation_manifests(
      @check_environment.compiler_grammar_manifest_wire(),
      @check_environment.compiler_barrier_contract_manifest_wire(),
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @publication_host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
    1000000,
    100000,
    100,
    source_free_policy=Some(policy),
  ).map_err(issue => {
    ClientProgramEffectCompilationBridgeIssue::Compilation(issue)
  })
}
