///|
// Fixed canonical bodies and SHA-256 expectations calculated independently with Node.
test "sequence limit identity preserves repeated candidates and separates Unit scopes" {
  let mut variant = 0
  for
    (w, wc, raw, cid, subject, unit, expected) in [
      (
        "{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09\"}",
        "sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09",
        "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09\"},{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09\"}],\"effective_max\":3,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:48d1334621b37c37b9c621df0508c711b22709b953cf9715b714ea7e369d5a84\",\"subject_ref\":\"sequence:checked-step:0:matches-per-key\",\"unit\":\"matches_per_key\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:48d1334621b37c37b9c621df0508c711b22709b953cf9715b714ea7e369d5a84",
        "unit:sha256:0000000000000000000000000000000000000000000000000000000000000000#/steps/0/sequence/matches-per-key",
        "matches_per_key", "sha256:f59aa2eb8344b839acf80ef13b74f68ece013c23e345212b7602bedc48336fbd",
      ),
      (
        "{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09\"}",
        "sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09",
        "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09\"},{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09\"}],\"effective_max\":3,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:48d1334621b37c37b9c621df0508c711b22709b953cf9715b714ea7e369d5a84\",\"subject_ref\":\"sequence:checked-step:0:matches-per-key\",\"unit\":\"matches_per_key\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:48d1334621b37c37b9c621df0508c711b22709b953cf9715b714ea7e369d5a84",
        "unit:sha256:1111111111111111111111111111111111111111111111111111111111111111#/steps/0/sequence/matches-per-key",
        "matches_per_key", "sha256:63cdafa7585ff7d4fff093450483f10b0e1adfecad3f9b206d507100a6a771fd",
      ),
      (
        "{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"}",
        "sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1",
        "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"},{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"}],\"effective_max\":7,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:561ef90c5f4330dd974f167849f65ed003c30f1fb68b4fbaec526406dd34814e\",\"subject_ref\":\"sequence:checked-step:0:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:561ef90c5f4330dd974f167849f65ed003c30f1fb68b4fbaec526406dd34814e",
        "unit:sha256:0000000000000000000000000000000000000000000000000000000000000000#/steps/0/sequence/output",
        "rows", "sha256:d82cc34e5636e311c9a7eb341d5284dfa04073d0108ba8a5e65e877d8016ea07",
      ),
      (
        "{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"}",
        "sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1",
        "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"},{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"}],\"effective_max\":7,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:561ef90c5f4330dd974f167849f65ed003c30f1fb68b4fbaec526406dd34814e\",\"subject_ref\":\"sequence:checked-step:0:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:561ef90c5f4330dd974f167849f65ed003c30f1fb68b4fbaec526406dd34814e",
        "unit:sha256:1111111111111111111111111111111111111111111111111111111111111111#/steps/0/sequence/output",
        "rows", "sha256:f2ab62f9e408df842feefb6ea8b8b9f3f9eb5cc8517e7677b512a4b05d548a20",
      ),
    ] {
    let witness = @wire.admit(@utf8.encode(w), wc, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap()
    let claims = @wire.check_arithmetic_claims([witness], {
      max_witnesses: 1,
      max_references: 100,
    }).unwrap()
    let original = @wire.admit_limit(@utf8.encode(raw), cid, claims, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
      max_candidates: 2,
    }).unwrap()
    // Independent canonical preimages: two unchanged Host occurrences plus a
    // Unit-owned guard in CID order, covering tighter, equal and looser bounds.
    let vectors = match variant {
      0 =>
        [
          (
            1L, "7b1a015f0cfea137b345f65bdd30181ae19b5bd74b17f65e520bde4d4386ba6e",
            "6e40001d0ce2e1e179267c8ece4982da7cefb370261c39b1735f9894757369da",
          ),
          (
            3L, "4f533637728d0c637109918e2d59b75471c736cc997caeab5f12d87a0638899e",
            "3bdfa93240c814c9fdbe3dba1736efb17b3756ae73fdca842d67a84dee5397dd",
          ),
          (
            4L, "26c0efbc0bcd49b9d5d030a69f5cc7cef056f6e30b95e46bea21594bf8449a99",
            "c383a9943700e3b0ad63a6542024f2ab05cb64951350d76d8237f95f9e354c73",
          ),
        ]
      1 =>
        [
          (
            1L, "1c9188d8679c104f49dba47c1caedb61a3da27b7133272e0b4634ecc211ec206",
            "e186c9ed937fc9b2774c052262d140a91dff2546350abfefc4d153cda902093e",
          ),
          (
            3L, "d1c1b26cb8bcbc60983ef27e38e6c28b7ca039d453c23cb34f1cff5c130a00a7",
            "50e54a5fbb4b7bae0e449a1a9cad3c2f5756ec3b3fba26c32a480fc41ebd8cd2",
          ),
          (
            4L, "40cd5db659a9fea5682dd1ca60f12d8660e3c2b31ba3dffa8a11943f72eb550b",
            "2a1233e54194b7e4570fbc692c0b095cfec5c01a8be1833c2badd47b31f6a41a",
          ),
        ]
      2 =>
        [
          (
            1L, "43a5fbcbbd70548092f47dd5a3ffe29aa84dc5e27dd9e6e4f6aecac7dfb52781",
            "af69e5e69c795dac691f6c51a110fcc4b80004b49d93e9c5a332255cd747c7f6",
          ),
          (
            7L, "d520f0d2367b20b822fee0658dbae1849a73220b59bc70679696f6aa7bbb7066",
            "72ff8dc10f7d81ad252d58a9a1162b4060fd642ff583a513721e7a1b0d507774",
          ),
          (
            8L, "1a74dea894ff2521f951f8ee7252b8249b078fcdc23991ab5508fbd4a7e4b3d2",
            "56ffe71203bd8110a8243457206d1f006da5ac1641d6f12191f4b95d1cdd2b8b",
          ),
        ]
      _ =>
        [
          (
            1L, "311aa4d2e9c1299fe47bfb39858f52246b48d1dec74b7601ab7400cd95264be0",
            "7316cf7d3efbebb858ae0c35b95826fd7eb2a883a6f3d40c7a328ee5d884db41",
          ),
          (
            7L, "8dc4f813a87ec08a625e4ea578aff88326df18ae320d45b63c9751978a6b7218",
            "114b9b731afbe9fe0712eb87b6f5564442d9011ac722cbc361035cd22463f0b9",
          ),
          (
            8L, "21e32621831f4797f41a067514d2d4eb4e18fcd705094eb664099bc0dac1dfc7",
            "70e5b7bc0c669ee5169d4e79112d185da198ea72f4ed330b014281fc2bafb7e3",
          ),
        ]
    }
    let definition = "sha256:" +
      (if variant % 2 == 0 { "0" } else { "1" }).repeat(64)
    let (field, law) = if unit == "rows" {
      ("max_output_rows", "actql.guard.sequence-output")
    } else {
      ("max_matches_per_key", "actql.guard.sequence-matches")
    }
    for (value, guard_cid, limit_cid) in vectors {
      let budget = IdentityBudget::{
        work: 100000,
        bytes: 10000,
        nodes: 1000,
        depth: 30,
      }
      let guard_witness = emit_unit_guard_witness(
        definition,
        "$.steps[0].sequence." + field,
        law,
        unit,
        value,
        budget,
      )
      assert_eq(@wire.cid(guard_witness), "sha256:" + guard_cid)
      // Exhaustion during dependency admission remains a budget failure,
      // rather than being mislabeled as a foreign source owner.
      for work in [0, 145] {
        try
          reidentify_sequence_limit(
            original,
            subject,
            unit,
            { work, bytes: 10000, nodes: 1000, depth: 30, },
            guard_witness=Some(guard_witness),
          )
        catch {
          UnitBuildFailure::BudgetExceeded => ()
          e => raise e
        } noraise {
          _ => fail("dependency admission exceeded its work budget")
        }
      }
      let before = IdentityBudget::{ ..budget, }
      let converted = reidentify_sequence_limit(
        original,
        subject,
        unit,
        budget,
        guard_witness=Some(guard_witness),
      )
      assert_eq(@wire.limit_cid(converted), "sha256:" + limit_cid)
      assert_eq(
        @derivation.minimum_candidate_count(@wire.limit_minimum(converted)),
        3,
      )
      let exact = IdentityBudget::{
        work: before.work - budget.work,
        bytes: before.bytes - budget.bytes,
        nodes: before.nodes - budget.nodes,
        depth: 30,
      }
      assert_eq(
        @wire.limit_cid(
          reidentify_sequence_limit(
            original,
            subject,
            unit,
            { ..exact, },
            guard_witness=Some(guard_witness),
          ),
        ),
        "sha256:" + limit_cid,
      )
      try
        reidentify_sequence_limit(
          original,
          subject,
          unit,
          { ..exact, work: exact.work - 1, },
          guard_witness=Some(guard_witness),
        )
      catch {
        UnitBuildFailure::BudgetExceeded => ()
        e => raise e
      } noraise {
        _ => fail("guarded limit escaped short work budget")
      }
    }
    variant += 1
    let budget = IdentityBudget::{
      work: 100000,
      bytes: 10000,
      nodes: 1000,
      depth: 30,
    }
    let converted = reidentify_sequence_limit(original, subject, unit, budget)
    assert_eq(@wire.limit_cid(converted), expected)
    assert_eq(@wire.limit_subject(converted), subject)
    assert_true(@wire.limit_cid(converted) != @wire.limit_cid(original))
    assert_eq(
      @derivation.minimum_candidate_count(@wire.limit_minimum(converted)),
      2,
    )
    assert_true(physical_equal(@wire.limit_claims(converted), claims))
    let exact = IdentityBudget::{
      work: 100000 - budget.work,
      bytes: 10000 - budget.bytes,
      nodes: 1000 - budget.nodes,
      depth: 30,
    }
    assert_eq(
      @wire.limit_cid(
        reidentify_sequence_limit(original, subject, unit, { ..exact, }),
      ),
      expected,
    )
    try
      reidentify_sequence_limit(original, subject, unit, {
        ..exact,
        work: exact.work - 1,
      })
    catch {
      UnitBuildFailure::BudgetExceeded => ()
      e => raise e
    } noraise {
      _ => fail("short work budget escaped")
    }
  }
}
