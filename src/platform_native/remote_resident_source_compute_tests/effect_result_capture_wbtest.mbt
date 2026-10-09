// Real Native Named Result projection plus original Run/import provenance.
// Normalization metadata is a fixture. This does not establish encrypted
// private capture, a waiting commit, approval, Effect apply or Cloud acceptance.

///|
fn retained_effect_result_capture(
  consumer : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  imported : @host.ClientEffectImportedEvidence,
  invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  acquired : @host.ClientEffectAcquiredEvidence,
  public_result : @host.PublicationOutputExport,
  provider? : Bool = false,
) -> @resident.ResidentEffectResultCapture raise {
  let retention = retained_compute_effect_retention()
  let journal = @publication.seal_run_evidence_value(
    "normalization_journal",
    "{\"version\":\"actql-normalization-journal/0.1\",\"rule_catalog_cid\":\"" +
    retained_compute_cid("d") +
    "\",\"entries\":[]}",
    65536,
    4096,
    64,
  ).unwrap()
  let observed = @host.client_effect_acquired_observation(acquired)
  let capture = (material, invocation, evidence, limits) => {
    consumer.capture_effect_result(
      material,
      inputs,
      imported,
      invocation,
      observation,
      retention,
      journal,
      [],
      [],
      evidence,
      limits,
      65536,
      4096,
      64,
    )
  }
  let another_run = @host.issue_client_effect_run_definition(
    materials.allowed,
    "retained-effect",
    "foreign-result-capture",
    "2026-10-09T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  // A zero row budget would fail a Native output read. Binding rejection must
  // happen first, without creating a new export or acquiring another Source.
  assert_true(
    capture(
      { ..materials, run_definition: another_run, },
      invocation,
      [observed],
      { ..resident_compute_limits(), max_rows: 0, },
    )
    is Err(Context(ForeignRun)),
  )
  let foreign_invocation = @publication.seal_publication_contract(
    "run_invocation",
    "{\"version\":\"actql-run-invocation/0.1\",\"invocation_template_cid\":\"" +
    retained_compute_cid("f") +
    "\",\"observation_set_cid\":\"" +
    retained_compute_cid("e") +
    "\"}",
    65536,
    4096,
    64,
  ).unwrap()
  assert_true(
    capture(materials, foreign_invocation, [observed], {
      ..resident_compute_limits(),
      max_rows: 0,
    })
    is Err(Context(Context(ForeignInvocation))),
  )
  // Even a valid new observation and Invocation of this same Template must
  // not refresh the already-transferred producer's original capture identity.
  let refreshed_observation = @publication.seal_run_evidence_value(
    "observation_set",
    @publication.run_evidence_value_json(observation)
    .replace_all(
      old="\"observation_set_cid\":\"" +
        @publication.run_evidence_value_identity(observation) +
        "\",",
      new="",
    )
    .replace_all(old="2026-10-09T01:00:01.000Z", new="2026-10-09T01:00:02.000Z"),
    65536,
    4096,
    64,
  ).unwrap()
  let refreshed_invocation = @publication.issue_run_invocation(
    @host.client_effect_compilation_template(materials.compilation),
    refreshed_observation,
    65536,
    4096,
    64,
  ).unwrap()
  @publication.resolve_run_local_result_evidence_refs(
    @host.client_effect_allowed_run_admission(materials.allowed),
    materials.run_definition,
    refreshed_invocation,
    refreshed_observation,
    retention,
  ).unwrap()
  |> ignore
  assert_true(
    @publication.publication_contract_identity(refreshed_invocation) !=
    @publication.publication_contract_identity(invocation),
  )
  assert_true(
    consumer.capture_effect_result(
      materials,
      inputs,
      imported,
      refreshed_invocation,
      refreshed_observation,
      retention,
      journal,
      [],
      [],
      [observed],
      { ..resident_compute_limits(), max_rows: 0, },
      65536,
      4096,
      64,
    )
    is Err(Context(ForeignInvocation)),
  )
  // The already-completed public probe and the retained Effect input occupy
  // the existing pin ceiling. A second capture must refuse rather than raise
  // that ceiling. Retire the finished probe before transferring this boundary
  // to the product capture operation.
  assert_true(
    capture(materials, invocation, [observed], resident_compute_limits())
    is Err(Native(Export(Retain(Physical(HoldingLimit))))),
  )
  public_result.cancel()
  // The Receipt Owner refuses an incomplete original Source inventory. Its
  // failed preparation must return only its new public Result borrow, leaving
  // the retained producer/import inputs live for the following successful call.
  match capture(materials, invocation, [], resident_compute_limits()) {
    Err(Receipt(_)) => ()
    Err(Context(_)) =>
      fail("missing Source evidence failed before Receipt: context")
    Err(Native(Export(Retain(PreviewWorkLimit)))) =>
      fail("public Result borrow refused: pin ceiling")
    Err(Native(Export(Retain(_)))) => fail("public Result borrow refused")
    Err(Native(_)) =>
      fail("missing Source evidence failed before Receipt: Native export")
    Err(Export(_)) =>
      fail("missing Source evidence failed before Receipt: portable export")
    Err(Manifest(_)) =>
      fail("missing Source evidence failed before Receipt: Manifest")
    Err(Unavailable) =>
      fail("missing Source evidence failed before Receipt: current custody")
    Ok(value) => {
      value.output.cancel()
      fail("missing Source evidence was accepted")
    }
  }
  let held = consumer.usage().reserved_retention_bytes
  let result = capture(
    materials,
    invocation,
    [observed],
    resident_compute_limits(),
  ).unwrap()
  assert_eq(consumer.usage().reserved_retention_bytes, held)
  let public_definition = @publication.prepare_result_definition(
    @host.prepared_client_effect_computation_definition_cid(materials.prepared),
    "answer",
  ).unwrap()
  assert_eq(
    @publication.publication_contract_identity(result.definition),
    @publication.publication_contract_identity(
      @publication.result_definition_contract(public_definition),
    ),
  )
  let local_definition = @host.issue_client_effect_local_result_definition(
    materials.prepared,
    1,
    "r",
    65536,
    4096,
    64,
  ).unwrap()
  assert_true(
    @publication.publication_contract_identity(result.definition) !=
    @host.client_effect_local_result_definition_cid(local_definition),
  )
  @publication.validate_run_publication_chain(
    materials.run_definition,
    invocation,
    [result.definition],
    [result.artifact],
    result.manifest,
    65536,
    4096,
    64,
  ).unwrap()
  |> ignore
  assert_true(
    @publication.publication_contract_json(result.receipt).contains(
      @publication.run_evidence_value_identity(observed),
    ),
  )
  assert_true(
    @publication.publication_contract_json(result.receipt).contains(
      @publication.publication_contract_identity(invocation),
    ),
  )
  assert_eq(
    result.output.result_schema_wire().unwrap(),
    retained_effect_expected_schema(provider),
  )
  assert_eq(result.output.row_count().unwrap(), 1)
  let replay = result.output.replay().unwrap()
  let rows = StringBuilder()
  while replay.next().unwrap() is Some(chunk) {
    rows.write_string(chunk)
  }
  rows.write_string(replay.finish().unwrap())
  assert_eq(rows.to_string(), retained_effect_expected_rows(provider))
  println(
    "retained-effect-result: actual public Artifact, Manifest, Receipt and snapshot captured",
  )
  result
}
