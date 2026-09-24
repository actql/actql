///|
pub(all) enum ClientCompilationManifestIssue {
  InvalidBudget
  InvalidGrammarManifest
  InvalidBarrierManifest
  GrammarManifestMismatch
  BarrierManifestMismatch
} derive(Eq, Debug)

///|
/// Verified compiler inputs for an Executable Plan. These identities do not
/// authorize a Run or prove that the rest of the Plan is complete.
pub struct ClientCompilationManifests {
  grammar_manifest_cid : String
  barrier_contract_manifest_cid : String
}

///|
pub fn client_compilation_grammar_manifest_cid(
  value : ClientCompilationManifests,
) -> String {
  value.grammar_manifest_cid
}

///|
pub fn client_compilation_barrier_manifest_cid(
  value : ClientCompilationManifests,
) -> String {
  value.barrier_contract_manifest_cid
}

///|
/// Admit the exact pinned manifest bodies before using their identities in a
/// Plan. Requiring the body prevents a source-grammar or placeholder CID from
/// standing in for a verified compiler manifest.
pub fn admit_client_compilation_manifests(
  grammar_wire : String,
  barrier_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientCompilationManifests, ClientCompilationManifestIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidBudget)
  }
  guard parse_plan_identity_value(
      grammar_wire, max_wire_bytes, max_nodes, max_depth,
    )
    is Some(_) else {
    return Err(InvalidGrammarManifest)
  }
  guard parse_plan_identity_value(
      barrier_wire, max_wire_bytes, max_nodes, max_depth,
    )
    is Some(_) else {
    return Err(InvalidBarrierManifest)
  }
  if grammar_wire != @environment.compiler_grammar_manifest_wire() {
    return Err(GrammarManifestMismatch)
  }
  if barrier_wire != @environment.compiler_barrier_contract_manifest_wire() {
    return Err(BarrierManifestMismatch)
  }
  Ok({
    grammar_manifest_cid: @environment.compiler_grammar_manifest_cid(),
    barrier_contract_manifest_cid: @environment.compiler_barrier_contract_manifest_cid(),
  })
}
