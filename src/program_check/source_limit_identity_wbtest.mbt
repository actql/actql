///|
fn source_limit_identity_fixture() -> @wire.LimitClaim {
  // Independently authored sorted JSON and Node SHA-256, not builder output.
  let candidate =
    #|{"dependencies":["sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],"derivation":{"op":"source"},"law_id":"actql.contract.file-listing-items","role":"contract_ceiling","source":{"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","field":"file_listing.max_listing_items","kind":"contract"},"unit":"rows","value":3,"version":"actql-bound-witness/0.1","witness_cid":"sha256:6e86f6cfc19878d93e7c15149cc1c0ecc7751c730dc6d35c13adcf46dc4b552b"}
  let witness = @wire.admit(
    @utf8.encode(candidate),
    "sha256:6e86f6cfc19878d93e7c15149cc1c0ecc7751c730dc6d35c13adcf46dc4b552b",
    { max_bytes: 2000, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  let claims = @wire.check_arithmetic_claims([witness], {
    max_witnesses: 1,
    max_references: 1,
  }).unwrap()
  let body =
    #|{"author_guard_binding":"absent","breach":"fail","candidates":[
  let tail =
    #|],"effective_max":3,"enforcement":"streaming_atomic","resolved_limit_cid":"sha256:c10c48d41c8becf6c1b0fc4346f02b3d4934ce3ceae5c54128b246a56f305829","subject_ref":"source-input:files:rows","unit":"rows","version":"actql-resolved-limit/0.1"}
  @wire.admit_limit(
    @utf8.encode(body + candidate + tail),
    "sha256:c10c48d41c8becf6c1b0fc4346f02b3d4934ce3ceae5c54128b246a56f305829",
    claims,
    { max_bytes: 2000, max_nodes: 100, max_depth: 10, max_candidates: 1, },
  ).unwrap()
}

///|
test "Source limit Unit conversion meters identity without changing acquisition enforcement" {
  let original = source_limit_identity_fixture()
  let subject = "unit:sha256:" + "0".repeat(64) + "#/inputs/files/rows"
  // Independent stream sizes: preimage 778 bytes/24 nodes, record 873/25.
  // Work: subject 95 + three candidate visits + hash (778+24) +
  // measure/write/UTF-8/admission (4*873+2*25) = 4442.
  let budget = IdentityBudget::{
    work: 4442,
    bytes: 1651,
    nodes: 49,
    depth: 10,
  }
  let converted = reidentify_sequence_limit(
    original,
    subject,
    "rows",
    budget,
    enforcement=@wire.limit_enforcement(original),
  )
  assert_eq(
    @wire.limit_cid(converted),
    "sha256:d1a4ed2024230aa8711fbd1cff0aeb4722dec73e516068dad0d66068b4daa432",
  )
  assert_eq(@wire.limit_subject(converted), subject)
  assert_eq(@wire.limit_enforcement(converted), @wire.StreamingAtomic)
  assert_eq(@derivation.minimum_value(@wire.limit_minimum(converted)), 3L)
  assert_true(
    physical_equal(@wire.limit_claims(converted), @wire.limit_claims(original)),
  )
  assert_eq((budget.work, budget.bytes, budget.nodes), (0, 0, 0))
  assert_eq(@wire.limit_subject(original), "source-input:files:rows")
  assert_eq(
    @wire.limit_cid(original),
    "sha256:c10c48d41c8becf6c1b0fc4346f02b3d4934ce3ceae5c54128b246a56f305829",
  )
}

///|
test "Source limit conversion refuses one-short work and retained metadata budgets" {
  let original = source_limit_identity_fixture()
  let subject = "unit:sha256:" + "0".repeat(64) + "#/inputs/files/rows"
  for
    (work, bytes, nodes) in [
      (4441, 1651, 49),
      (4442, 1650, 49),
      (4442, 1651, 48),
    ] {
    let budget = IdentityBudget::{ work, bytes, nodes, depth: 10, }
    try
      reidentify_sequence_limit(
        original,
        subject,
        "rows",
        budget,
        enforcement=@wire.limit_enforcement(original),
      )
    catch {
      UnitBuildFailure::BudgetExceeded | UnitBuildFailure::Encoding(_) => ()
      issue => raise issue
    } noraise {
      _ => fail("Source limit conversion accepted a metadata/work shortage")
    }
  }
}
