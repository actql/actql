///|
// Existing independent Checkpoint proof corpus. The zero signature tests
// encoding only; it is never approval, Reviewer authority or physical use.
let local_checkpoint_proof_checkpoint : String =
  #|{"checkpoint_cid":"sha256:048fda4a694108b305607cfa62df06e42fea357d0850cd16e8e30cf1de06216f","checkpoint_id":"proof-cp","continuation_state_cid":"sha256:2222222222222222222222222222222222222222222222222222222222222222","created_at":"2026-09-25T10:00:00.000Z","expires_at":"2026-09-26T10:00:00.000Z","human_summary":"Review one bounded update","kind":"effect_set","phase":"commit","reason_code":"effect_review_required","required_artifact":{"artifact_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","artifact_type":"effect_set_preview"},"requirements":["effect_scope_approved"],"review_projection_cid":"sha256:4444444444444444444444444444444444444444444444444444444444444444","run_definition_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","run_id":"proof-run","subject":{"continuation":"resume_unit","kind":"run_unit","run_id":"proof-run","unit_id":"proof-unit"},"version":"actql-execution-checkpoint/0.1"}

///|
let local_checkpoint_proof_unsigned : String =
  #|{"actor":"release-approver","checkpoint_cid":"sha256:048fda4a694108b305607cfa62df06e42fea357d0850cd16e8e30cf1de06216f","checkpoint_id":"proof-cp","decided_at":"2026-09-25T10:00:00.000Z","decision":"rejected","required_artifact_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","resolution_id":"proof-resolution","review_projection_cid":"sha256:4444444444444444444444444444444444444444444444444444444444444444","run_definition_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","run_id":"proof-run","version":"actql-checkpoint-resolution/0.1"}

///|
test "Local checkpoint proof preserves independent unsigned preimage and actor" {
  let proof = prepare_client_local_checkpoint_proof(
    local_checkpoint_proof_checkpoint, local_checkpoint_proof_unsigned,
  ).unwrap()
  assert_eq(proof.actor(), "release-approver")
  assert_eq(
    proof.preimage(),
    "sha256:9686204b65f205ddf882555c2ae88afa82682f5d3ae000f4abd1f4e68803a72c",
  )
  let wire = proof.seal("reviewer-key", "A".repeat(86) + "==").unwrap()
  assert_eq(
    @checkpoint.resolution_proof_preimage(wire, {
      max_wire_bytes: 4096,
      max_nodes: 64,
      max_depth: 8,
    }).unwrap(),
    proof.preimage(),
  )
}

///|
test "Local checkpoint proof rejects foreign subject and incoming signature before key use" {
  for
    altered in [
      local_checkpoint_proof_unsigned.replace_all(
        old="proof-run",
        new="foreign-run",
      ),
      local_checkpoint_proof_unsigned.replace(old="{", new="{\"proof\":null,"),
      local_checkpoint_proof_unsigned.replace(
        old="{",
        new="{\"resolution_cid\":null,",
      ),
    ] {
    assert_true(
      prepare_client_local_checkpoint_proof(
        local_checkpoint_proof_checkpoint, altered,
      )
      is Err(_),
    )
  }
}

///|
test "Local checkpoint proof encoding cannot attach an invalid Ed25519 result" {
  let proof = prepare_client_local_checkpoint_proof(
    local_checkpoint_proof_checkpoint, local_checkpoint_proof_unsigned,
  ).unwrap()
  for signature in ["", "c2lnbmF0dXJl", "A".repeat(87) + "="] {
    assert_true(proof.seal("reviewer-key", signature) is Err(_))
  }
}
