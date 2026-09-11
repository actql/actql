// Fixed identities computed independently with Node SHA-256.

///|
fn claim_fixture(text : String, cid : String) -> WireWitness {
  admit(@utf8.encode(text), cid, {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 4,
  }).unwrap()
}

///|
fn graph_fixture() -> Array[WireWitness] {
  [
    (
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"sha256:4e337aedc516e70c3d485250b34d1714dd581b81152a7d523385116e768ae7d8\",\"sha256:5fcd31e277805ff23d0735eba1c0f7f593e74051f8e10cec75add7546a7e2df1\"],\"derivation\":{\"inputs\":[\"sha256:4e337aedc516e70c3d485250b34d1714dd581b81152a7d523385116e768ae7d8\",\"sha256:5fcd31e277805ff23d0735eba1c0f7f593e74051f8e10cec75add7546a7e2df1\"],\"op\":\"min\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"semantic_ref\":\"test\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:edcb8c52b6eb039e3921483526e43330e5fbd9bccf06f058c78f7cf4b2c89af7\"}",
      "sha256:edcb8c52b6eb039e3921483526e43330e5fbd9bccf06f058c78f7cf4b2c89af7",
    ),
    (
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"sha256:c45284d6873944a628377446337cf4995e27c377c5f19aca273bc885a1edb479\"],\"derivation\":{\"input\":\"sha256:c45284d6873944a628377446337cf4995e27c377c5f19aca273bc885a1edb479\",\"maximum\":5,\"op\":\"clamp\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"semantic_ref\":\"test\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:5fcd31e277805ff23d0735eba1c0f7f593e74051f8e10cec75add7546a7e2df1\"}",
      "sha256:5fcd31e277805ff23d0735eba1c0f7f593e74051f8e10cec75add7546a7e2df1",
    ),
    (
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"sha256:4756afe022cb72a4e816b27166608c57775ec72b70c978bf1cd0a0f475ea7259\"],\"derivation\":{\"factor\":3,\"input\":\"sha256:4756afe022cb72a4e816b27166608c57775ec72b70c978bf1cd0a0f475ea7259\",\"op\":\"multiply\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"semantic_ref\":\"test\"},\"unit\":\"rows\",\"value\":12,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:c45284d6873944a628377446337cf4995e27c377c5f19aca273bc885a1edb479\"}",
      "sha256:c45284d6873944a628377446337cf4995e27c377c5f19aca273bc885a1edb479",
    ),
    (
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"sha256:4e337aedc516e70c3d485250b34d1714dd581b81152a7d523385116e768ae7d8\"],\"derivation\":{\"left\":\"sha256:4e337aedc516e70c3d485250b34d1714dd581b81152a7d523385116e768ae7d8\",\"op\":\"add\",\"right\":\"sha256:4e337aedc516e70c3d485250b34d1714dd581b81152a7d523385116e768ae7d8\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"semantic_ref\":\"test\"},\"unit\":\"rows\",\"value\":4,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:4756afe022cb72a4e816b27166608c57775ec72b70c978bf1cd0a0f475ea7259\"}",
      "sha256:4756afe022cb72a4e816b27166608c57775ec72b70c978bf1cd0a0f475ea7259",
    ),
    (
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"sha256:e9e066e027ce7bb50c3582f89204147d909e3e02d5289c97e8ba9568d22d8aca\"],\"derivation\":{\"input\":\"sha256:e9e066e027ce7bb50c3582f89204147d909e3e02d5289c97e8ba9568d22d8aca\",\"op\":\"preserve\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"semantic_ref\":\"test\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:4e337aedc516e70c3d485250b34d1714dd581b81152a7d523385116e768ae7d8\"}",
      "sha256:4e337aedc516e70c3d485250b34d1714dd581b81152a7d523385116e768ae7d8",
    ),
    (
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"maximum\":8,\"op\":\"clamp\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"semantic_ref\":\"test\"},\"unit\":\"rows\",\"value\":8,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:6567cec35c805d86713aca23cab761fe435a34475a88582292b67c768106b5bc\"}",
      "sha256:6567cec35c805d86713aca23cab761fe435a34475a88582292b67c768106b5bc",
    ),
    (
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"semantic_ref\":\"test\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:e9e066e027ce7bb50c3582f89204147d909e3e02d5289c97e8ba9568d22d8aca\"}",
      "sha256:e9e066e027ce7bb50c3582f89204147d909e3e02d5289c97e8ba9568d22d8aca",
    ),
  ].map(pair => claim_fixture(pair.0, pair.1))
}

///|
fn bad_graph_fixtures() -> Array[WireWitness] {
  [
    (
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"sha256:e9e066e027ce7bb50c3582f89204147d909e3e02d5289c97e8ba9568d22d8aca\"],\"derivation\":{\"input\":\"sha256:e9e066e027ce7bb50c3582f89204147d909e3e02d5289c97e8ba9568d22d8aca\",\"op\":\"preserve\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"semantic_ref\":\"test\"},\"unit\":\"rows\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:6aea77bab2f864ec722faba877b490157e5fef16b20b4866bbb2a39a69535272\"}",
      "sha256:6aea77bab2f864ec722faba877b490157e5fef16b20b4866bbb2a39a69535272",
    ),
    (
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"sha256:e9e066e027ce7bb50c3582f89204147d909e3e02d5289c97e8ba9568d22d8aca\"],\"derivation\":{\"input\":\"sha256:e9e066e027ce7bb50c3582f89204147d909e3e02d5289c97e8ba9568d22d8aca\",\"op\":\"preserve\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"semantic_ref\":\"test\"},\"unit\":\"bytes\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:09793776a45f0ea98952b88c224b1e2091902cacc003e570a813456545c74737\"}",
      "sha256:09793776a45f0ea98952b88c224b1e2091902cacc003e570a813456545c74737",
    ),
    (
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"sha256:e9e066e027ce7bb50c3582f89204147d909e3e02d5289c97e8ba9568d22d8aca\"],\"derivation\":{\"factor\":9007199254740991,\"input\":\"sha256:e9e066e027ce7bb50c3582f89204147d909e3e02d5289c97e8ba9568d22d8aca\",\"op\":\"multiply\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"semantic_ref\":\"test\"},\"unit\":\"rows\",\"value\":9007199254740991,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:11b0b6885a563adf8f8e5a5b0149b03aa1482e319102a94b759c415682dae620\"}",
      "sha256:11b0b6885a563adf8f8e5a5b0149b03aa1482e319102a94b759c415682dae620",
    ),
    (
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"semantic_ref\":\"test\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:38a63681d8324e1e20c574320593b3dd660d3d030318fc84d8b94c59d2f6dddb\"}",
      "sha256:38a63681d8324e1e20c574320593b3dd660d3d030318fc84d8b94c59d2f6dddb",
    ),
  ].map(pair => claim_fixture(pair.0, pair.1))
}

///|
let graph_references : Int = 20
