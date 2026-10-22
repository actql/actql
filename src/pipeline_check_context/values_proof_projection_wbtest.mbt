///|
// Complete prior proof-construction block, retained only as a regression
// reference. Its emitted claims are not the independent expected CID vectors.
fn previous_values_measurement_proof(
  subject : String,
  bytes : Int,
  metadata : @wire.LimitLimits,
  meter : ValuesMetadataBudget?,
) -> Result[@wire.ProgramProofClaim, ValuesWireResolutionIssue] {
  let limits : @wire.Limits = {
    max_bytes: metadata.max_bytes,
    max_nodes: metadata.max_nodes,
    max_depth: metadata.max_depth,
  }
  fn writer() -> @encode.Writer raise @encode.EncodeFailure {
    @encode.writer(limits.max_bytes, limits.max_nodes, limits.max_depth)
  }
  fn hasher() -> @encode.Writer raise @encode.EncodeFailure {
    @encode.hashing_writer(limits.max_bytes, limits.max_nodes, limits.max_depth)
  }
  try {
    reserve_values_metadata(meter, metadata, out => {
      emit_values_measurement_proof(subject, bytes, out)
    })
    let hash = hasher()
    emit_values_measurement_proof(subject, bytes, hash)
    let proof_cid = "sha256:" + @encode.finish_hash(hash)
    let proof_out = writer()
    emit_values_measurement_proof(subject, bytes, proof_out)
    let proof_bytes = @wire_utf8.encode(@encode.finish(proof_out))
    reserve_values_metadata(meter, metadata, out => {
      emit_values_measurement_witness(
        subject,
        bytes,
        proof_cid,
        Some(values_metadata_cid),
        out,
      )
    })
    let hash = hasher()
    emit_values_measurement_witness(subject, bytes, proof_cid, None, hash)
    let witness_cid = "sha256:" + @encode.finish_hash(hash)
    let witness_out = writer()
    emit_values_measurement_witness(
      subject,
      bytes,
      proof_cid,
      Some(witness_cid),
      witness_out,
    )
    let witness = match
      @wire.admit(
        @wire_utf8.encode(@encode.finish(witness_out)),
        witness_cid,
        limits,
      ) {
      Ok(v) => v
      Err(e) => return Err(Proof(e))
    }
    let proof = match @wire.bind_program_proof(proof_bytes, witness, limits) {
      Ok(v) => v
      Err(e) => return Err(Proof(e))
    }
    Ok(proof)
  } catch {
    issue => Err(Encoding(issue))
  }
}

///|
fn proof_projection_text(proof : @wire.ProgramProofClaim) -> String raise {
  let out = @encode.writer(10000, 1000, 20)
  @wire.emit(@wire.program_proof_witness(proof), out)
  @encode.finish(out)
}

///|
test "Values measurement projection preserves complete original proof wire and reservations" {
  let limits : @wire.LimitLimits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
    max_candidates: 1,
  }
  for bytes in [0, 2, 25, 2147483647] {
    let old_meter : ValuesMetadataBudget = {
      bytes: 10000,
      nodes: 1000,
      used_bytes: 0,
      used_nodes: 0,
    }
    let new_meter : ValuesMetadataBudget = {
      bytes: 10000,
      nodes: 1000,
      used_bytes: 0,
      used_nodes: 0,
    }
    let old = previous_values_measurement_proof(
      "checked-step:0",
      bytes,
      limits,
      Some(old_meter),
    ).unwrap()
    let new = prepare_values_measurement_proof(
      "checked-step:0",
      bytes,
      limits,
      Some(new_meter),
    ).unwrap()
    assert_eq(proof_projection_text(new), proof_projection_text(old))
    assert_eq(
      @wire.cid(@wire.program_proof_witness(new)),
      @wire.cid(@wire.program_proof_witness(old)),
    )
    assert_eq(
      (
        new_meter.bytes,
        new_meter.nodes,
        new_meter.used_bytes,
        new_meter.used_nodes,
      ),
      (
        old_meter.bytes,
        old_meter.nodes,
        old_meter.used_bytes,
        old_meter.used_nodes,
      ),
    )
    assert_eq(@wire.program_proof_form(new), @wire.DerivedInputs)
    assert_eq(@wire.program_proof_input_count(new), 0)
  }
}

///|
test "Values projection preserves partial reservations and encoding refusal under tight metadata" {
  let wide : @wire.LimitLimits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
    max_candidates: 1,
  }
  for
    (limits, bytes, nodes) in [
      (wide, 1, 1000),
      (wide, 10000, 1),
      (wide, 600, 1000),
      (wide, 10000, 20),
      ({ ..wide, max_bytes: 1, }, 10000, 1000),
      ({ ..wide, max_bytes: 400, }, 10000, 1000),
      ({ ..wide, max_nodes: 7, }, 10000, 1000),
      ({ ..wide, max_depth: 1, }, 10000, 1000),
    ] {
    let old_meter : ValuesMetadataBudget = {
      bytes,
      nodes,
      used_bytes: 0,
      used_nodes: 0,
    }
    let new_meter : ValuesMetadataBudget = {
      bytes,
      nodes,
      used_bytes: 0,
      used_nodes: 0,
    }
    assert_true(
      previous_values_measurement_proof(
        "checked-step:0",
        25,
        limits,
        Some(old_meter),
      )
      is Err(Encoding(@encode.OutputLimit)),
    )
    assert_true(
      prepare_values_measurement_proof(
        "checked-step:0",
        25,
        limits,
        Some(new_meter),
      )
      is Err(Encoding(@encode.OutputLimit)),
    )
    assert_eq(
      (
        new_meter.bytes,
        new_meter.nodes,
        new_meter.used_bytes,
        new_meter.used_nodes,
      ),
      (
        old_meter.bytes,
        old_meter.nodes,
        old_meter.used_bytes,
        old_meter.used_nodes,
      ),
    )
  }
  for
    limits in [
      { ..wide, max_bytes: 1, },
      { ..wide, max_bytes: 400, },
      { ..wide, max_nodes: 7, },
      { ..wide, max_depth: 1, },
    ] {
    assert_true(
      previous_values_measurement_proof("checked-step:0", 25, limits, None)
      is Err(Encoding(@encode.OutputLimit)),
    )
    assert_true(
      prepare_values_measurement_proof("checked-step:0", 25, limits, None)
      is Err(Encoding(@encode.OutputLimit)),
    )
  }
}
