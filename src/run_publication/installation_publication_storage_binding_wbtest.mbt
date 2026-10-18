///|
fn installation_storage_vector() -> String {
  (
    // Authored from the five-field contract, independently of the Owner Writer.
    #|{"key_generation_cid":"sha256:2222222222222222222222222222222222222222222222222222222222222222","private_namespace":"publication-private","store_authority_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","store_contract_wire":"{\"version\":\"actql-local-publication-store/0.1\",\"isolation\":\"execution-namespace\",\"store_authority_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"}","version":"actql-installation-publication-storage-binding/0.1"}
  )
}

///|
test "installation storage DATA has independent exact bytes and identity" {
  let wire = installation_storage_vector()
  let identity = "sha256:bd174597f54d8a6dc4f7df7a5dc5ee41fb05f4e25651d6553983a5de9824c7f7"
  assert_eq(@utf8.encode(wire).length(), 511)
  let value = read_installation_publication_storage_binding(
    wire, identity, 511, 6, 1,
  ).unwrap()
  assert_eq(installation_publication_storage_binding_wire(value), wire)
  assert_eq(installation_publication_storage_binding_cid(value), identity)
  assert_eq(
    installation_publication_storage_binding_fields(value),
    ("sha256:" + "1".repeat(64), "sha256:" + "2".repeat(64)),
  )
  let prepared = prepare_installation_publication_storage_binding(
    "{\"version\":\"actql-local-publication-store/0.1\",\"isolation\":\"execution-namespace\",\"store_authority_cid\":\"sha256:" +
    "1".repeat(64) +
    "\"}",
    "sha256:" + "1".repeat(64),
    "sha256:" + "2".repeat(64),
    511,
    6,
    1,
  ).unwrap()
  assert_eq(installation_publication_storage_binding_wire(prepared), wire)
}

///|
test "installation storage DATA rejects closed shape and purpose substitutions" {
  let wire = installation_storage_vector()
  for
    candidate in [
      " " + wire,
      wire.replace(old="publication-private", new="local-continuation-private"),
      wire.replace(old="execution-namespace", new="shared"),
      wire.replace(old="key_generation_cid", new="key"),
      wire.replace(
        old="key_generation_cid",
        new="key_generation_cid,store_authority_cid",
      ),
      wire.replace(
        old="\"version\":\"actql-installation",
        new="\"extra\":null,\"version\":\"actql-installation",
      ),
      wire.replace(old="/0.1\"}", new="/9.9\"}"),
      wire.replace(
        old="\"private_namespace\":\"publication-private\"",
        new="\"private_namespace\":null",
      ),
      wire.replace(
        old="\"private_namespace\":\"publication-private\"",
        new="\"private_namespace\":\"publication-private\",\"private_namespace\":\"publication-private\"",
      ),
    ] {
    assert_true(
      read_installation_publication_storage_binding(
        candidate,
        "sha256:" + @sha.text_hex(candidate).unwrap(),
        2048,
        64,
        4,
      )
      is Err(_),
    )
  }
}

///|
test "installation storage DATA checks authority against exact embedded contract" {
  let wire = installation_storage_vector()
  let foreign = wire.replace(
    old="\"store_authority_cid\":\"sha256:" + "1".repeat(64),
    new="\"store_authority_cid\":\"sha256:" + "3".repeat(64),
  )
  // Changing the caller's expected hash cannot repair the embedded association.
  assert_true(
    read_installation_publication_storage_binding(
      foreign,
      "sha256:" + @sha.text_hex(foreign).unwrap(),
      2048,
      64,
      4,
    )
    is Err(InvalidField("store_contract_wire")),
  )
  let rewritten = wire.replace(old="\\\"version\\\":", new="\\\"version\\\": ")
  assert_true(
    read_installation_publication_storage_binding(
      rewritten,
      "sha256:" + @sha.text_hex(rewritten).unwrap(),
      2048,
      64,
      4,
    )
    is Err(InvalidField("store_contract_wire")),
  )
}

///|
test "installation storage DATA bounds every codec and retains old Model domain" {
  let wire = installation_storage_vector()
  let identity = "sha256:bd174597f54d8a6dc4f7df7a5dc5ee41fb05f4e25651d6553983a5de9824c7f7"
  for
    (bytes, nodes, depth) in [(510, 6, 1), (511, 5, 1), (511, 6, 0), (0, 6, 1)] {
    assert_true(
      read_installation_publication_storage_binding(
        wire, identity, bytes, nodes, depth,
      )
      is Err(_),
    )
  }
  assert_true(
    read_installation_publication_storage_binding(
      wire,
      "sha256:" + "0".repeat(64),
      511,
      6,
      2,
    )
    is Err(IdentityMismatch),
  )
  assert_true(
    seal_run_evidence_value("model_original_storage_binding", wire, 2048, 64, 4)
    is Err(_),
  )
}
