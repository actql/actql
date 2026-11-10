///|
// Codec-only original SealedCheckpoint. These fixtures issue no persisted
// custody, Reviewer authority, signing grant or actual approval signature.
fn saved_resolution_codec_checkpoint() -> @checkpoint.SealedCheckpoint {
  let (_, _, _, definition) = journal_test_run(
    "saved-resolution-codec", "checkpoint-run",
  )
  let original = checkpoint_test_artifact(definition)
  @checkpoint.seal_checkpoint(
    { ..original.checkpoint, requirements: [@checkpoint.EffectScopeApproved], },
    native_checkpoint_limits(),
  ).unwrap()
}

///|
test "Native saved resolution emitter binds actual approval evidence and quotes actor DATA" {
  let artifact = saved_resolution_codec_checkpoint()
  let limits = native_checkpoint_limits()
  let actor = "reviewer\"\\line"
  let authority = "sha256:" + "5".repeat(64)
  let writer = @encode.writer(
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  )
  emit_saved_effect_approval(
    writer,
    artifact,
    actor,
    authority,
    artifact.checkpoint.created_at,
  )
  let approval = @checkpoint.prepare_effect_approval_proof(
    artifact,
    @encode.finish(writer),
    authority,
    limits,
  ).unwrap()
  assert_eq(approval.actor(), actor)
  // Structural proof encoding only; no cryptographic acceptance is claimed.
  let (_, identity) = @checkpoint.seal_prepared_effect_approval_proof(
    approval,
    "reviewer-key",
    @base64.encode(Bytes::make(64, 0)),
  ).unwrap()
  let writer = @encode.writer(
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  )
  emit_saved_effect_resolution(
    writer,
    artifact,
    actor,
    "approved",
    artifact.checkpoint.created_at,
    approval_evidence_cid=Some(identity),
  )
  let prepared = @checkpoint.prepare_resolution_proof(
    artifact,
    @encode.finish(writer),
    limits,
  ).unwrap()
  assert_eq(prepared.actor(), actor)
  assert_eq(prepared.decision(), @checkpoint.Approved)
  assert_eq(prepared.checkpoint(), artifact)
}

///|
test "Native saved resolution rejection omits evidence and Core rejects missing approved evidence" {
  let artifact = saved_resolution_codec_checkpoint()
  let limits = native_checkpoint_limits()
  let writer = @encode.writer(
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  )
  emit_saved_effect_resolution(
    writer,
    artifact,
    "reviewer",
    "rejected",
    artifact.checkpoint.created_at,
  )
  let wire = @encode.finish(writer)
  assert_false(wire.contains("approval_evidence_cid"))
  assert_eq(
    @checkpoint.prepare_resolution_proof(artifact, wire, limits)
    .unwrap()
    .decision(),
    @checkpoint.Rejected,
  )
  let writer = @encode.writer(
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  )
  emit_saved_effect_resolution(
    writer,
    artifact,
    "reviewer",
    "approved",
    artifact.checkpoint.created_at,
  )
  assert_true(
    @checkpoint.prepare_resolution_proof(
      artifact,
      @encode.finish(writer),
      limits,
    )
    is Err(@checkpoint.EvidenceRequired),
  )
}

///|
test "Native saved decision construction measures actual escaped originals without using codec ceilings" {
  let artifact = saved_resolution_codec_checkpoint()
  let limits = native_checkpoint_limits()
  let actor = "reviewer日😀\"\\\n"
  let authority = "sha256:" + "5".repeat(64)
  let measured = @encode.measuring_writer(
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  )
  let written = @encode.writer(
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  )
  for writer in [measured, written] {
    emit_saved_effect_approval(
      writer,
      artifact,
      actor,
      authority,
      artifact.checkpoint.created_at,
    )
  }
  let (bytes, nodes, depth) = @encode.finish_measurement_usage(measured)
  assert_eq(bytes, @utf8.encode(@encode.finish(written)).length())
  assert_eq(nodes, 9)
  assert_eq(depth, 2)
  assert_true(bytes < limits.max_wire_bytes)
  assert_true(nodes < limits.max_nodes)
  for evidence in [None, Some("sha256:" + "6".repeat(64))] {
    let measured = @encode.measuring_writer(
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    let written = @encode.writer(
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    for writer in [measured, written] {
      emit_saved_effect_resolution(
        writer,
        artifact,
        actor,
        "approved",
        artifact.checkpoint.created_at,
        approval_evidence_cid=evidence,
      )
    }
    let (bytes, nodes, depth) = @encode.finish_measurement_usage(measured)
    assert_eq(bytes, @utf8.encode(@encode.finish(written)).length())
    assert_eq(nodes, if evidence is Some(_) { 13 } else { 12 })
    assert_eq(depth, 1)
    assert_true(bytes < limits.max_wire_bytes)
  }
}
