///|
test "prepared proof retains original decision without changing its independent wire identity" {
  let checkpoint = proof_preparation_checkpoint()
  let rejected = prepare_resolution_proof(
    checkpoint,
    proof_preparation_unsigned_wire,
    proof_preparation_limits(),
  ).unwrap()
  assert_eq(rejected.decision(), Rejected)
  assert_eq(rejected.preimage(), proof_preparation_expected_preimage)
  assert_eq(
    seal_prepared_resolution_proof(
      rejected, "reviewer-key", proof_preparation_encoding_signature,
    ).unwrap(),
    proof_preparation_emitted_wire,
  )
  let approved_wire = proof_preparation_unsigned_wire
    .replace_all(old="rejected", new="approved")
    .replace_all(
      old="{",
      new="{\"approval_evidence_cid\":\"sha256:" + "5".repeat(64) + "\",",
    )
  let approved = prepare_resolution_proof(
    checkpoint,
    approved_wire,
    proof_preparation_limits(),
  ).unwrap()
  assert_eq(approved.decision(), Approved)
  assert_true(approved.preimage() != rejected.preimage())
  assert_eq(approved.actor(), rejected.actor())
}
