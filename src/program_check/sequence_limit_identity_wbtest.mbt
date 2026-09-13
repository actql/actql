///|
// Fixed canonical bodies and SHA-256 expectations calculated independently with Node.
test "sequence limit identity preserves repeated candidates and separates Unit scopes" {
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
