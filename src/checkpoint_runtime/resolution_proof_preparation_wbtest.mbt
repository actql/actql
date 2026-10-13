///|
// Independent Python JSON/hashlib expectations from the retained corpus.
// Zero proof bytes exercise encoding only, never signature or approval admission.
let proof_preparation_checkpoint_wire : String =
  #|{"checkpoint_cid":"sha256:048fda4a694108b305607cfa62df06e42fea357d0850cd16e8e30cf1de06216f","checkpoint_id":"proof-cp","continuation_state_cid":"sha256:2222222222222222222222222222222222222222222222222222222222222222","created_at":"2026-09-25T10:00:00.000Z","expires_at":"2026-09-26T10:00:00.000Z","human_summary":"Review one bounded update","kind":"effect_set","phase":"commit","reason_code":"effect_review_required","required_artifact":{"artifact_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","artifact_type":"effect_set_preview"},"requirements":["effect_scope_approved"],"review_projection_cid":"sha256:4444444444444444444444444444444444444444444444444444444444444444","run_definition_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","run_id":"proof-run","subject":{"continuation":"resume_unit","kind":"run_unit","run_id":"proof-run","unit_id":"proof-unit"},"version":"actql-execution-checkpoint/0.1"}

///|
let proof_preparation_unsigned_wire : String =
  #|{"actor":"release-approver","checkpoint_cid":"sha256:048fda4a694108b305607cfa62df06e42fea357d0850cd16e8e30cf1de06216f","checkpoint_id":"proof-cp","decided_at":"2026-09-25T10:00:00.000Z","decision":"rejected","required_artifact_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","resolution_id":"proof-resolution","review_projection_cid":"sha256:4444444444444444444444444444444444444444444444444444444444444444","run_definition_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","run_id":"proof-run","version":"actql-checkpoint-resolution/0.1"}

///|
let proof_preparation_emitted_wire : String =
  #|{"actor":"release-approver","checkpoint_cid":"sha256:048fda4a694108b305607cfa62df06e42fea357d0850cd16e8e30cf1de06216f","checkpoint_id":"proof-cp","decided_at":"2026-09-25T10:00:00.000Z","decision":"rejected","proof":{"key_id":"reviewer-key","scheme":"ed25519-v1","signature":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="},"required_artifact_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","resolution_cid":"sha256:8a920b135bcbc731602d48e0dc1755201812f21684b15034d972d3eedc6a36fc","resolution_id":"proof-resolution","review_projection_cid":"sha256:4444444444444444444444444444444444444444444444444444444444444444","run_definition_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","run_id":"proof-run","version":"actql-checkpoint-resolution/0.1"}

///|
let proof_preparation_expected_preimage : String = "sha256:9686204b65f205ddf882555c2ae88afa82682f5d3ae000f4abd1f4e68803a72c"

///|
let proof_preparation_encoding_signature : String = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="

///|
fn proof_preparation_limits() -> WireLimits {
  { max_wire_bytes: 4096, max_nodes: 64, max_depth: 8, }
}

///|
fn proof_preparation_checkpoint() -> SealedCheckpoint {
  admit_checkpoint_wire(
    proof_preparation_checkpoint_wire,
    proof_preparation_limits(),
  ).unwrap()
}

///|
test "proof preparation exact independent body CID and canonical emission" {
  let checkpoint = proof_preparation_checkpoint()
  let prepared = prepare_resolution_proof(
    checkpoint,
    proof_preparation_unsigned_wire,
    proof_preparation_limits(),
  ).unwrap()
  assert_eq(prepared.checkpoint(), checkpoint)
  assert_eq(prepared.actor(), "release-approver")
  assert_eq(prepared.preimage(), proof_preparation_expected_preimage)
  let emitted = seal_prepared_resolution_proof(
    prepared, "reviewer-key", proof_preparation_encoding_signature,
  ).unwrap()
  assert_eq(emitted, proof_preparation_emitted_wire)
  assert_eq(
    resolution_proof_preimage(emitted, proof_preparation_limits()),
    Ok(proof_preparation_expected_preimage),
  )
  // Existing signed decoding still checks its own CID and original subject.
  let decoded = decode_resolution(
    parse_wire(emitted, proof_preparation_limits()).unwrap(),
    checkpoint,
    proof_preparation_limits(),
  ) catch {
    _ => fail("signed framing rejected")
  }
  assert_eq(decoded.proof_preimage, proof_preparation_expected_preimage)
}

///|
test "proof preparation rejects incoming proof self CID and unknown fields" {
  for name in ["proof", "resolution_cid", "unknown"] {
    let body = proof_preparation_unsigned_wire.replace_all(
      old="{",
      new="{\"" + name + "\":null,",
    )
    assert_eq(
      prepare_resolution_proof(
        proof_preparation_checkpoint(),
        body,
        proof_preparation_limits(),
      ).map(_ => ()),
      Err(ResolutionUnknownField(name)),
    )
  }
}

///|
test "proof preparation binds each original checkpoint Run and artifact field" {
  for
    (field, old) in [
      ("checkpoint_id", "proof-cp"),
      (
        "checkpoint_cid", "sha256:048fda4a694108b305607cfa62df06e42fea357d0850cd16e8e30cf1de06216f",
      ),
      ("run_id", "proof-run"),
      ("run_definition_cid", "sha256:" + "1".repeat(64)),
      ("required_artifact_cid", "sha256:" + "3".repeat(64)),
      ("review_projection_cid", "sha256:" + "4".repeat(64)),
    ] {
    let replacement = if field.has_suffix("_cid") {
      "sha256:" + "f".repeat(64)
    } else {
      "foreign"
    }
    let body = proof_preparation_unsigned_wire.replace_all(
      old~,
      new=replacement,
    )
    assert_eq(
      prepare_resolution_proof(
        proof_preparation_checkpoint(),
        body,
        proof_preparation_limits(),
      ).map(_ => ()),
      Err(CheckpointBindingMismatch(field)),
    )
  }
  let foreign_subject = proof_preparation_unsigned_wire.replace_all(
    old="{",
    new="{\"prepare_attempt_id\":\"other\",",
  )
  assert_eq(
    prepare_resolution_proof(
      proof_preparation_checkpoint(),
      foreign_subject,
      proof_preparation_limits(),
    ).map(_ => ()),
    Err(CheckpointBindingMismatch("prepare_attempt_id")),
  )
}

///|
test "proof preparation decision window keeps before at and after expiration separate" {
  let checkpoint = proof_preparation_checkpoint()
  for
    (time, allowed) in [
      ("2026-09-25T09:59:59.999Z", false),
      ("2026-09-25T10:00:00.000Z", true),
      ("2026-09-26T09:59:59.999Z", true),
      ("2026-09-26T10:00:00.000Z", false),
      ("2026-09-26T10:00:00.001Z", false),
    ] {
    let result = prepare_resolution_proof(
      checkpoint,
      proof_preparation_unsigned_wire.replace_all(
        old="2026-09-25T10:00:00.000Z",
        new=time,
      ),
      proof_preparation_limits(),
    )
    if allowed {
      assert_true(result is Ok(_))
    } else {
      assert_eq(result.map(_ => ()), Err(DecisionOutsideWindow))
    }
  }
}

///|
test "proof preparation requires approval evidence framing without granting approval" {
  let checkpoint = proof_preparation_checkpoint()
  let approved = proof_preparation_unsigned_wire.replace_all(
    old="rejected",
    new="approved",
  )
  assert_eq(
    prepare_resolution_proof(checkpoint, approved, proof_preparation_limits()).map(_ => {
        ()
      },
    ),
    Err(EvidenceRequired),
  )
  let extra = proof_preparation_unsigned_wire.replace_all(
    old="{",
    new="{\"approval_evidence_cid\":\"sha256:" + "5".repeat(64) + "\",",
  )
  assert_eq(
    prepare_resolution_proof(checkpoint, extra, proof_preparation_limits()).map(_ => {
        ()
      },
    ),
    Err(EvidenceForbidden),
  )
  assert_true(
    prepare_resolution_proof(
      checkpoint,
      extra.replace_all(old="rejected", new="approved"),
      proof_preparation_limits(),
    )
    is Ok(_),
  )
}

///|
test "proof preparation refuses duplicate malformed null and bounded framing" {
  let checkpoint = proof_preparation_checkpoint()
  for
    body in [
      "null",
      "{",
      proof_preparation_unsigned_wire.replace_all(
        old="{",
        new="{\"actor\":\"other\",",
      ),
    ] {
    assert_true(
      prepare_resolution_proof(checkpoint, body, proof_preparation_limits())
      is Err(_),
    )
  }
  let missing = proof_preparation_unsigned_wire.replace_all(
    old="\"actor\":\"release-approver\",",
    new="",
  )
  assert_eq(
    prepare_resolution_proof(checkpoint, missing, proof_preparation_limits()).map(_ => {
        ()
      },
    ),
    Err(ResolutionMissingField("actor")),
  )
  assert_true(
    prepare_resolution_proof(checkpoint, proof_preparation_unsigned_wire, {
      ..proof_preparation_limits(),
      max_wire_bytes: 100,
    })
    is Err(_),
  )
  assert_true(
    prepare_resolution_proof(checkpoint, proof_preparation_unsigned_wire, {
      ..proof_preparation_limits(),
      max_nodes: 4,
    })
    is Err(_),
  )
  assert_true(
    prepare_resolution_proof(checkpoint, proof_preparation_unsigned_wire, {
      ..proof_preparation_limits(),
      max_depth: 0,
    })
    is Err(_),
  )
}

///|
test "proof preparation emission requires exact canonical Ed25519 bytes" {
  let prepared = prepare_resolution_proof(
    proof_preparation_checkpoint(),
    proof_preparation_unsigned_wire,
    proof_preparation_limits(),
  ).unwrap()
  for signature in ["", "c2lnbmF0dXJl", "!".repeat(88), "A".repeat(85) + "B=="] {
    assert_true(
      seal_prepared_resolution_proof(prepared, "reviewer-key", signature)
      is Err(_),
    )
  }
  assert_eq(
    seal_prepared_resolution_proof(
      prepared, "", proof_preparation_encoding_signature,
    ),
    Err(ResolutionInvalidField("proof.key_id")),
  )
  assert_true(
    seal_prepared_resolution_proof(
      prepared,
      "x".repeat(4097),
      proof_preparation_encoding_signature,
    )
    is Err(_),
  )
}

///|
test "proof preparation shared binding preserves signed proof error precedence" {
  let checkpoint = proof_preparation_checkpoint()
  let wire = proof_preparation_emitted_wire
    .replace_all(old="proof-run", new="foreign-run")
    .replace_all(old="ed25519-v1", new="wrong-scheme")
  let issue = decode_resolution(
    parse_wire(wire, proof_preparation_limits()).unwrap(),
    checkpoint,
    proof_preparation_limits(),
  ) catch {
    ResolutionFailed(issue) => {
      assert_eq(issue, ResolutionInvalidField("proof.scheme"))
      return
    }
  }
  ignore(issue)
  fail("invalid signed proof was accepted")
}
