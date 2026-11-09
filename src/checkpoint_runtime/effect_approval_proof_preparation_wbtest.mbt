///|
// Independent Python json/hashlib vector. Zero signature bytes below exercise
// codec/subject admission only, never authentication or signing permission.
let effect_approval_proof_unsigned : String =
  #|{"approved_at":"2026-09-25T11:00:00.000Z","approver":"alice","authority_scope_cid":"sha256:5555555555555555555555555555555555555555555555555555555555555555","claims":["effect_scope_approved","partial_application_accepted"],"effect_preview_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","review_projection_cid":"sha256:4444444444444444444444444444444444444444444444444444444444444444","version":"actql-approval-attestation/0.1"}

///|
test "typed Effect approval proof preserves independent preimage and signed evidence framing" {
  let artifact = sealed_of(effect_request())
  let prepared = prepare_effect_approval_proof(
    artifact,
    effect_approval_proof_unsigned,
    cid("5"),
    limits(),
  ).unwrap()
  assert_eq(prepared.checkpoint(), artifact)
  assert_eq(prepared.actor(), "alice")
  assert_eq(
    prepared.preimage(),
    "sha256:75f0a64d19c2dfca5525b8e0d6e696a8f59f882cf00349babf7872cf452b4a5d",
  )
  let (evidence, identity) = seal_prepared_effect_approval_proof(
    prepared, "reviewer-key", proof_preparation_encoding_signature,
  ).unwrap()
  assert_eq(canonical_cid(evidence), identity)
  let original = check_evidence(
    evidence,
    identity,
    artifact,
    "alice",
    cid("5"),
    limits(),
    None,
  ) catch {
    _ => fail("existing closed Evidence admission refused")
  }
  assert_eq(wire_of(original, limits()), Some(evidence))
}

///|
test "typed Effect approval proof shares original authority claim and closed-field refusals" {
  let artifact = sealed_of(effect_request())
  for
    (old, replacement) in [
      ("effect_scope_approved", "foreign_claim"),
      ("partial_application_accepted", "effect_scope_approved"),
      (cid("3"), cid("8")),
      (cid("4"), cid("8")),
      (cid("5"), cid("8")),
      ("\"version\":", "\"proof\":{},\"version\":"),
    ] {
    assert_true(
      prepare_effect_approval_proof(
        artifact,
        effect_approval_proof_unsigned.replace_all(old~, new=replacement),
        cid("5"),
        limits(),
      )
      is Err(_),
    )
  }
  let prepared = prepare_effect_approval_proof(
    artifact,
    effect_approval_proof_unsigned,
    cid("5"),
    limits(),
  ).unwrap()
  assert_true(
    seal_prepared_effect_approval_proof(
      prepared, "reviewer-key", "c2lnbmF0dXJl",
    )
    is Err(_),
  )
}

///|
test "admitted Approved resolution exposes the same original approval proof for actual Host verification" {
  let artifact = sealed_of(effect_request())
  let prepared = prepare_effect_approval_proof(
    artifact,
    effect_approval_proof_unsigned,
    cid("5"),
    limits(),
  ).unwrap()
  let (evidence, identity) = seal_prepared_effect_approval_proof(
    prepared, "reviewer-key", proof_preparation_encoding_signature,
  ).unwrap()
  let fields = resolution_fields_for(artifact, "approved", Some(identity))
  fields.remove("proof") |> ignore
  let unsigned = wire_of(
    canonical_of(Json::object(fields), limits()).unwrap(),
    limits(),
  ).unwrap()
  let resolution = prepare_resolution_proof(artifact, unsigned, limits()).unwrap()
  let candidate = seal_prepared_resolution_proof(
    resolution, "reviewer-key", proof_preparation_encoding_signature,
  ).unwrap()
  // Existing Common authentication fixture, not a cryptographic signature.
  let admitted = admit(artifact, candidate, Some(evidence)).unwrap()
  assert_eq(
    admitted.approval_proof_materials(limits()),
    Ok(
      Some(
        (
          "reviewer-key",
          prepared.preimage(),
          proof_preparation_encoding_signature,
        ),
      ),
    ),
  )
}

///|
test "prepared Resolution requires the exact original Approval proof materials" {
  let artifact = sealed_of(effect_request())
  let approval = prepare_effect_approval_proof(
    artifact,
    effect_approval_proof_unsigned,
    cid("5"),
    limits(),
  ).unwrap()
  let (evidence, identity) = seal_prepared_effect_approval_proof(
    approval, "reviewer-key", proof_preparation_encoding_signature,
  ).unwrap()
  let prepare = (decision, evidence_cid) => {
    let fields = resolution_fields_for(artifact, decision, evidence_cid)
    fields.remove("proof") |> ignore
    let wire = wire_of(
      canonical_of(Json::object(fields), limits()).unwrap(),
      limits(),
    ).unwrap()
    prepare_resolution_proof(artifact, wire, limits()).unwrap()
  }
  let proof = prepare("approved", Some(identity))
  assert_eq(
    proof.approval_proof_materials(evidence, cid("5")),
    Ok(
      (
        "reviewer-key",
        approval.preimage(),
        proof_preparation_encoding_signature,
      ),
    ),
  )
  let candidate = seal_prepared_resolution_proof(
    proof, "reviewer-key", proof_preparation_encoding_signature,
  ).unwrap()
  let admitted = admit(artifact, candidate, Some(evidence)).unwrap()
  assert_eq(
    admitted.approval_proof_materials(limits()),
    Ok(
      Some(
        (
          "reviewer-key",
          approval.preimage(),
          proof_preparation_encoding_signature,
        ),
      ),
    ),
  )
  assert_true(proof.approval_proof_materials(evidence, cid("8")) is Err(_))
  assert_true(
    prepare("approved", Some(cid("8"))).approval_proof_materials(
      evidence,
      cid("5"),
    )
    is Err(_),
  )
  assert_true(
    prepare("rejected", None).approval_proof_materials(evidence, cid("5"))
    is Err(_),
  )
  assert_true(
    proof.approval_proof_materials(
      evidence.replace_all(old="reviewer-key", new="foreign-key"),
      cid("5"),
    )
    is Err(_),
  )
}
