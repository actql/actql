///|
// Private registered scheduling only: keep checked policy DATA, defer only
// immutable Catalog wires to the actual Run dependency inventory constructor.
#export_name("clientProgramEffectPublicationPolicyBodiesDeferredCatalog")
pub fn client_program_effect_publication_policy_bodies_deferred_catalog(
  value : @publication_host.PreparedClientEffectComputation,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  Array[(String, String, String)],
  @program_check.LocalDependencyBodyIssue,
] {
  @publication_host.prepared_client_effect_publication_policy_bodies(
    value,
    max_bytes,
    max_nodes,
    max_depth,
    retain_catalog=false,
  )
}

///|
#export_name("clientProgramKeyedLookupDeclaredFilePublicationInputDeferredCatalog")
pub fn client_program_keyed_lookup_declared_file_publication_input_deferred_catalog(
  lookup : @publication_host.ClientKeyedLookupInput,
  recorded_at : String,
  now_ms : Int64,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @execution.SuppliedRelationRead,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.finish_client_keyed_lookup_publication_input(
    lookup,
    max_bytes,
    max_nodes,
    max_depth,
    retain_body=true,
    native_completion=Some((recorded_at, now_ms)),
    defer_catalog=true,
  )
}
