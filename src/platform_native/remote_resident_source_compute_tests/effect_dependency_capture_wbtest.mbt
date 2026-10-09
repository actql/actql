// Actual Native dependency bodies from the independent receiver holding and
// completed consumer. Full dependency closure, encrypted capture, waiting and
// approval remain separate acceptance boundaries.

///|
fn retained_effect_dependency_capture(
  consumer : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  producer : @host.ClientEffectLocalResultArtifact,
  result : @host.ClientEffectLocalResultArtifact,
  root_index : Int,
  result_index : Int,
  result_export : @strategy.CapturedEffectLocalResultExport,
  result_receipt : @execution.CompletedRelationExportReceipt,
) -> Unit raise {
  let capture = (material, artifact, index, bytes, limits) => {
    consumer.capture_effect_dependency(
      material, inputs, artifact, index, limits, bytes, 4096, 64,
    )
  }
  let foreign = @host.issue_client_effect_run_definition(
    materials.allowed,
    "retained-effect",
    "foreign-dependency-capture",
    "2026-10-09T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let no_read = { ..resident_compute_limits(), max_rows: 0, }
  assert_true(
    capture(
      { ..materials, run_definition: foreign, },
      result,
      result_index,
      65536,
      no_read,
    )
    is Err(ForeignInput),
  )
  assert_true(
    capture(materials, result, root_index, 65536, no_read) is Err(ForeignInput),
  )
  assert_true(
    capture(materials, producer, result_index, 65536, no_read)
    is Err(ForeignInput),
  )
  // Receipt identity rejects a changed row even when the adapter supplies a
  // well-formed canonical Relation preimage and the original Artifact token.
  assert_true(
    @host.admit_client_effect_dependency_capture(
      materials, inputs, result, result_index, result_export, result_receipt, "[{\"id\":4}]",
      65536, 4096, 64,
    )
    is Err(Dependency(InvalidBody)),
  )
  assert_true(
    capture(materials, result, result_index, 1, resident_compute_limits())
    is Err(_),
  )
  let producer_capture = capture(
    materials,
    producer,
    root_index,
    65536,
    resident_compute_limits(),
  ).unwrap()
  let result_capture = capture(
    materials,
    result,
    result_index,
    65536,
    resident_compute_limits(),
  ).unwrap()
  assert_true(
    @host.client_effect_dependency_capture_matches_artifact(
      producer_capture, producer,
    ),
  )
  assert_false(
    @host.client_effect_dependency_capture_matches_artifact(
      producer_capture, result,
    ),
  )
  assert_true(
    @host.client_effect_dependency_capture_matches_artifact(
      result_capture, result,
    ),
  )
  let relation = (value : @host.ClientEffectDependencyCapture) => {
    let bodies = @host.client_effect_dependency_capture_bodies(value)
    assert_true(
      bodies.any(body => {
        @publication.captured_effect_dependency_body_kind(body) ==
        "local_dependencies"
      }),
    )
    bodies.filter(body => {
      @publication.captured_effect_dependency_body_kind(body) ==
      "relation_value"
    })
  }
  let producer_relation = relation(producer_capture)
  let consumer_relation = relation(result_capture)
  assert_eq(producer_relation.length(), 1)
  assert_eq(consumer_relation.length(), 1)
  assert_eq(
    @publication.captured_effect_dependency_body_json(producer_relation[0]),
    "{\"sort\":\"relation\",\"value\":[{\"id\":1},{\"id\":2},{\"id\":3}]}",
  )
  assert_eq(
    @publication.captured_effect_dependency_body_json(consumer_relation[0]),
    "{\"sort\":\"relation\",\"value\":[{\"id\":3}]}",
  )
  // Failure retired only its child export. Original private inputs remain
  // available and a retry produces the same immutable dependency facts.
  let retried = capture(
    materials,
    result,
    result_index,
    65536,
    resident_compute_limits(),
  ).unwrap()
  assert_eq(
    @host.client_effect_dependency_capture_bodies(retried).map(body => {
      (
        @publication.captured_effect_dependency_body_kind(body),
        @publication.captured_effect_dependency_body_cid(body),
      )
    }),
    @host.client_effect_dependency_capture_bodies(result_capture).map(body => {
      (
        @publication.captured_effect_dependency_body_kind(body),
        @publication.captured_effect_dependency_body_cid(body),
      )
    }),
  )
  println(
    "retained-effect-dependencies: actual producer and consumer bodies captured",
  )
}
