///|
fn retained_effect_retention_dependency_wire(kind : String) -> String {
  "{\"name\":\"fixture-resident-effect-" +
  kind +
  "\",\"version\":\"actql-installed-local-policy/0.1\"}"
}

///|
fn retained_effect_retention_dependency_cid(kind : String) -> String {
  "sha256:" +
  @sha.hex(@utf8.encode(retained_effect_retention_dependency_wire(kind)))
}

///|
fn retained_effect_capture_inventory(
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  source : @publication.CapturedEffectSourceArtifact,
  manifest : @host.ClientEffectLocalManifest,
  artifact : @host.ClientEffectLocalResultArtifact,
  imported : @host.ClientEffectImportedEvidence,
  acquired : @host.ClientEffectAcquiredEvidence,
  acquired_bodies : (String, String),
  captures : Array[@host.ClientEffectDependencyCapture],
) -> (
  @publication.CapturedLocalEffectSourceEvidence,
  @publication.CapturedEffectDependencyInventory,
) raise {
  let leaves = [
    "retention_contract", "metadata_retention_policy", "clock_contract",
  ].map(kind => {
    @publication.admit_hashed_effect_dependency_body(
      kind,
      retained_effect_retention_dependency_cid(kind),
      retained_effect_retention_dependency_wire(kind),
      65536,
      4096,
      64,
    ).unwrap()
  })
  let limits : @publication.CapturedEffectDependencyLimits = {
    max_entries: 100,
    max_total_bytes: 65536,
    max_depth: 64,
    max_references: 1000,
  }
  let issue = (bodies, leaves, wire) => {
    @host.issue_client_effect_capture_inventory(
      materials,
      inputs,
      0,
      source,
      manifest,
      artifact,
      imported,
      acquired,
      wire,
      acquired_bodies.1,
      bodies,
      leaves,
      limits,
      10000,
      64,
    )
  }
  assert_true(issue([], leaves, acquired_bodies.0) is Err(ForeignInput))
  assert_true(
    issue([captures[1], captures[1]], leaves, acquired_bodies.0)
    is Err(ForeignInput),
  )
  assert_true(
    issue(captures, leaves, "{\"sort\":\"relation\",\"value\":[{\"id\":4}]}")
    is Err(Dependency(InvalidBody)),
  )
  assert_true(
    issue(captures, [], acquired_bodies.0) is Err(Dependency(MissingDependency)),
  )
  let (local_source, inventory) = issue(captures, leaves, acquired_bodies.0).unwrap()
  let wire = @publication.captured_effect_dependency_inventory_json(inventory)
  @publication.admit_captured_effect_source_dependencies(
    [local_source],
    wire,
    65536,
    10000,
    64,
  ).unwrap()
  |> ignore
  let extra = @publication.admit_hashed_effect_dependency_body(
    "clock_contract",
    "sha256:" +
    @sha.hex(
      @utf8.encode(
        "{\"name\":\"unused-policy\",\"version\":\"actql-installed-local-policy/0.1\"}",
      ),
    ),
    "{\"name\":\"unused-policy\",\"version\":\"actql-installed-local-policy/0.1\"}",
    65536,
    4096,
    64,
  ).unwrap()
  assert_true(
    issue(captures, [..leaves, extra], acquired_bodies.0)
    is Err(Dependency(UnusedDependency)),
  )
  println(
    "retained-effect-capture: exact acquired/imported dependency closure admitted",
  )
  (local_source, inventory)
}
