// Independent vectors calculated from literal canonical JSON with Python hashlib.

///|
fn hold_vector_distribution_body() -> String {
  "{\"runtime_bundle_cids\":[\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"],\"version\":\"actql-remote-runtime-bundle-distribution/0.1\"}"
}

///|
fn hold_vector_distribution_cid() -> String {
  "sha256:db2c1d1c2bcac2bac713db8b6065ef525014133c60b672540d20f9be0bdb4f06"
}

///|
fn hold_vector_scope_body() -> String {
  "{\"attempt_id\":\"hold-a\",\"authority_scope_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"coordinator_authority\":\"coordinator-a\",\"distribution_cid\":\"sha256:db2c1d1c2bcac2bac713db8b6065ef525014133c60b672540d20f9be0bdb4f06\",\"environment\":\"production\",\"runtime_bundle_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"set_revision_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"site_generation\":7,\"site_key\":\"site-a\",\"version\":\"actql-remote-runtime-bundle-hold-scope/0.1\",\"workspace_id\":\"workspace-a\"}"
}

///|
fn hold_vector_scope_cid() -> String {
  "sha256:a47fd39adfd002964881687963b875b86549365ebea8c4d89a82f2948e02f3c3"
}

///|
fn hold_vector_binding_body() -> String {
  "{\"attempt_id\":\"hold-a\",\"authority_scope_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"catalog_incarnation\":\"123e4567-e89b-42d3-a456-426614174000\",\"coordinator_authority\":\"coordinator-a\",\"distribution_cid\":\"sha256:db2c1d1c2bcac2bac713db8b6065ef525014133c60b672540d20f9be0bdb4f06\",\"environment\":\"production\",\"initial_revision\":11,\"runtime_bundle_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"set_revision_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"site_generation\":7,\"site_key\":\"site-a\",\"version\":\"actql-remote-runtime-bundle-hold-binding/0.1\",\"workspace_id\":\"workspace-a\"}"
}

///|
fn hold_vector_binding_cid() -> String {
  "sha256:43996a2fa47f5c49b74175ad6906ee2d9c03ac74f5f1163fe3b087c5f79ad594"
}
