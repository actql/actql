// Independent expected rows/schema for the two existing Native Programs.
// These are not generated from the Result or captured evidence.

///|
fn retained_effect_expected_rows(provider : Bool) -> String {
  if provider {
    "[{\"id\":3,\"record\":\"001000000000001\"}]"
  } else {
    "[{\"id\":3}]"
  }
}

///|
fn retained_effect_expected_schema(provider : Bool) -> String {
  if provider {
    "{\"id\":{\"nullable\":false,\"type\":\"number\"},\"record\":{\"max_utf8_bytes\":15,\"nullable\":false,\"type\":\"string\"}}"
  } else {
    "{\"id\":{\"nullable\":false,\"type\":\"number\"}}"
  }
}

///|
// Complete original Run capture from the actual retained Native consumer and
// physical Provider Preview. Existing semantic/custody Owners issue and persist
// computation and Source evidence. Target Preview wire has separate custody.
// Store reconstruction keeps the live Ledger; this does not claim
// Host restart, a Cloud waiting commit, approval or Effect execution.
fn retained_effect_provider_capture(
  consumer : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  result : @host.ClientEffectLocalResultArtifact,
  result_index : Int,
  receiver : @host.ClientEffectLocalResultArtifact,
  root_index : Int,
  result_export : @strategy.CapturedEffectLocalResultExport,
  result_receipt : @execution.CompletedRelationExportReceipt,
  imported : @host.ClientEffectImportedEvidence,
  acquired : @host.ClientEffectAcquiredEvidence,
  acquired_bodies : (String, String),
  facts : ResidentProviderFacts,
  public_result : @host.PublicationOutputExport,
  stop_custodies : Array[(@resident.ResidentEffectSourceCustody, @store.Store)],
) -> Unit raise {
  let (prepared, source) = resident_provider_preview(
    consumer, materials, inputs, result_index, result, invocation, facts,
  )
  let public_capture = retained_effect_result_capture(
    consumer,
    materials,
    inputs,
    imported,
    invocation,
    observation,
    acquired,
    public_result,
    provider=true,
  )
  let dependencies = retained_effect_dependency_capture(
    consumer,
    materials,
    inputs,
    receiver,
    result,
    root_index,
    result_index,
    result_export,
    result_receipt,
    provider=true,
  )
  let manifest = @host.issue_client_effect_local_manifest(
    materials.prepared,
    @host.client_effect_imported_invocation(imported),
    [result],
    65536,
    4096,
    64,
  ).unwrap()
  let (local_source, inventory) = retained_effect_capture_inventory(
    materials, inputs, source, manifest, result, imported, acquired, acquired_bodies,
    dependencies,
  )
  retained_effect_source_store(
    consumer,
    materials,
    inputs,
    result,
    source,
    result_index,
    stop_custodies,
    provider=true,
  )
  retained_effect_complete_capture(
    consumer,
    materials,
    inputs,
    invocation,
    prepared.preview,
    prepared.proof,
    source,
    local_source,
    inventory,
    prepared.authoring,
    public_capture,
    provider=true,
  )
  public_capture.output.cancel()
  assert_true(
    @strategy.captured_effect_preview_inputs_available(prepared.preview),
  )
  println(
    "native-effect-provider: original computation captured from physical Preview and confirmed through encrypted Store recovery",
  )
}
