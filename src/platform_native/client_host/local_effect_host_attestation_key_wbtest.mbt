///|
// Existing independent fixture constants are JSON string fragments. The actual
// selected configuration contains decoded PEM; only this test input is decoded.
fn local_host_authority_pem_fixture(value : String) -> String {
  value.replace_all(old="\\n", new="\n")
}

///|
// The existing key-custody fixture owns real adopted files, public-key decoding
// and HMAC/SQLite originals. Its descriptor body is synthetic, not a private
// PEM. These checks cannot establish physical signing or Resolution admission.
test "Local operational Host authority reads only its unchanged adopted independent key original" {
  let (host, file) = signing_original_host("local-host-attestation-original")
  let key = signing_original_binding(host, file)
    .capture_signing_key_original()
    .unwrap()
  let row = host.database
    .read("client_local_installation_originals", file)
    .unwrap()
  let issued = host.database
    .read("client_local_installation_custody", "issued")
    .unwrap()
  let grants = host.database
    .read("client_local_grant_custody", "issued")
    .unwrap()
  let authority = local_effect_host_attestation_authority(
    host,
    key,
    local_host_authority_pem_fixture(signing_original_public_b),
  ).unwrap()
  assert_eq(authority.key_id, "host-attestation-2026")
  assert_eq(
    authority.public_key_pem,
    local_host_authority_pem_fixture(signing_original_public_a),
  )
  assert_eq(key.public_key_cid(), signing_original_public_a_cid)
  assert_eq(
    host.database.read("client_local_installation_originals", file).unwrap().body,
    row.body,
  )
  assert_eq(
    host.database.read("client_local_installation_originals", file).unwrap().revision,
    row.revision,
  )
  assert_eq(
    host.database.read("client_local_installation_custody", "issued").unwrap().body,
    issued.body,
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().body,
    grants.body,
  )
  assert_true(
    host.database.scan_after("client_local_grant_originals", "")
    is Err(@sqlite.NotFound),
  )
  host.close().unwrap()
  assert_true(
    local_effect_host_attestation_authority(
      host,
      key,
      local_host_authority_pem_fixture(signing_original_public_b),
    )
    is Err(ReviewerUnavailable),
  )
}

///|
test "Local operational Host authority refuses the Reviewer role same public key and foreign Host" {
  let (host, file) = signing_original_host("local-host-attestation-distinct")
  let key = signing_original_binding(host, file)
    .capture_signing_key_original()
    .unwrap()
  assert_true(
    local_effect_host_attestation_authority(
      host,
      key,
      local_host_authority_pem_fixture(signing_original_public_a),
    )
    is Err(ReviewerUnavailable),
  )
  // Same raw bytes with a different PEM line-break spelling are still the same
  // key. Authority separation is not a text/key-label comparison.
  let alternate = local_host_authority_pem_fixture(signing_original_public_a).replace_all(
    old="\n",
    new="\r\n",
  )
  assert_eq(
    host.epoch.crypto.ed25519_public_key_raw32(alternate).unwrap(),
    host.epoch.crypto
    .ed25519_public_key_raw32(
      local_host_authority_pem_fixture(signing_original_public_a),
    )
    .unwrap(),
  )
  assert_true(
    local_effect_host_attestation_authority(host, key, alternate)
    is Err(ReviewerUnavailable),
  )
  host.close().unwrap()
  let (reviewer_host, reviewer_key) = reviewer_signing_scope_key_fixture(
    "local-host-attestation-reviewer",
  )
  assert_true(
    local_effect_host_attestation_authority(
      reviewer_host,
      reviewer_key,
      local_host_authority_pem_fixture(signing_original_public_b),
    )
    is Err(ReviewerUnavailable),
  )
  // This exact original key belongs to a different Host. No copied key id,
  // public bytes or configuration can substitute that physical parent.
  assert_true(
    local_effect_host_attestation_authority(
      reviewer_host,
      key,
      local_host_authority_pem_fixture(signing_original_public_b),
    )
    is Err(ReviewerUnavailable),
  )
  reviewer_host.close().unwrap()
}

///|
test "Local operational Host authority refuses missing custody and identical-body file replacement" {
  for variant in 0..<3 {
    let (host, file) = signing_original_host(
      "local-host-attestation-current-" + variant.to_string(),
    )
    let key = signing_original_binding(host, file)
      .capture_signing_key_original()
      .unwrap()
    if variant == 0 {
      let row = host.database
        .read("client_local_installation_originals", file)
        .unwrap()
      host.journal
      .transaction(() => {
        host.database
        .remove_exact(
          "client_local_installation_originals",
          file,
          row.revision,
          row.body,
        )
        .map_err(issue => NativeClientRunJournalIssue::Physical(issue))
      })
      .unwrap()
    } else {
      let root = host.session.source_root
      let name = if variant == 1 {
        file
      } else {
        "local-host-attestation-current-2.descriptor"
      }
      let (body, generation) = local_adoption_read(root, name, 8192L).unwrap()
      root.reclaim_generation(name, generation).unwrap()
      let writer = root.create_writer(name + ".replace", 8192L).unwrap()
      writer.append(body).unwrap()
      writer.seal(name).unwrap() |> ignore
    }
    assert_true(
      local_effect_host_attestation_authority(
        host,
        key,
        local_host_authority_pem_fixture(signing_original_public_b),
      )
      is Err(ReviewerUnavailable),
    )
    assert_true(
      host.database.scan_after("client_local_grant_originals", "")
      is Err(@sqlite.NotFound),
    )
    host.close().unwrap()
  }
}
