// Independent Node AES-256-GCM fixture using a public test key and nonce.
// No deployed credential or private capture is embedded here.

///|
test "native private evidence authenticates the existing Store envelope" {
  let library = load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
  ).unwrap()
  let key = Bytes::makei(32, i => i.to_byte())
  let cid = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  let fixture = @utf8.encode(
    (
      #|{"version":"actql-private-publication-evidence/0.1","nonce":"AAECAwQFBgcICQoL","tag":"Kl0I/chTHRBRVhomWM83vQ==","ciphertext":"KWOicrOA72v/KOHqxYxVCPW/41GeGDpRXg6d8WgbZQ=="}
    ),
  )
  let plaintext = @utf8.encode("native-private-evidence-fixture")
  assert_eq(
    library.open_private_evidence(key, "effect_capture", cid, fixture),
    Ok(plaintext),
  )
  assert_true(
    library.open_private_evidence(key, "effect_preview", cid, fixture)
    is Err(CipherRejected),
  )
  assert_true(
    library.open_private_evidence(
      Bytes::make(32, 0),
      "effect_capture",
      cid,
      fixture,
    )
    is Err(CipherRejected),
  )
  assert_true(
    library.open_private_evidence(
      key,
      "effect_capture",
      "sha256:" + "1".repeat(64),
      fixture,
    )
    is Err(CipherRejected),
  )
  let encrypted = library
    .seal_private_evidence(key, "effect_capture", cid, plaintext)
    .unwrap()
  assert_true(encrypted != fixture)
  assert_eq(
    library.open_private_evidence(key, "effect_capture", cid, encrypted),
    Ok(plaintext),
  )
  let altered = Bytes::makei(fixture.length(), i => {
    if i == fixture.length() - 4 {
      65
    } else {
      fixture[i]
    }
  })
  assert_true(
    library.open_private_evidence(key, "effect_capture", cid, altered) is Err(_),
  )
  assert_true(
    library.seal_private_evidence(key, "effect_capture", cid, Bytes::new(0))
    is Err(InvalidInput),
  )
  assert_true(
    library.open_private_evidence(
      key,
      "effect_capture",
      cid,
      @utf8.encode("{}"),
    )
    is Err(InvalidInput),
  )
}

///|
test "native continuation checkpoint and Catalog roles authenticate independent Node envelopes" {
  let library = load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
  ).unwrap()
  let key = Bytes::makei(32, i => i.to_byte())
  let cid = "sha256:" + "0".repeat(64)
  let plaintext = @utf8.encode("native-private-evidence-fixture")
  for
    (role, tag) in [
      ("continuation_record", "3yJDT2CxbtjfVQftN2GjCg=="),
      ("checkpoint", "nNFQ/3TzvkCWXAw8mHf78g=="),
      ("effect_catalog", "Lp6w6J1zL2EI2B/BmufyJQ=="),
    ] {
    // Public deterministic AES-GCM vector generated independently by Node's
    // crypto API, not copied from the Native implementation's output.
    let envelope = @utf8.encode(
      "{\"version\":\"actql-private-publication-evidence/0.1\",\"nonce\":\"AAECAwQFBgcICQoL\",\"tag\":\"" +
      tag +
      "\",\"ciphertext\":\"KWOicrOA72v/KOHqxYxVCPW/41GeGDpRXg6d8WgbZQ==\"}",
    )
    assert_eq(
      library.open_private_evidence(key, role, cid, envelope),
      Ok(plaintext),
    )
    for
      foreign in [
        "effect_capture", "effect_preview", "effect_catalog", "checkpoint", "continuation_record",
      ] {
      if foreign != role {
        assert_true(
          library.open_private_evidence(key, foreign, cid, envelope)
          is Err(CipherRejected),
        )
      }
    }
    assert_true(
      library.open_private_evidence(Bytes::make(32, 0), role, cid, envelope)
      is Err(CipherRejected),
    )
    assert_true(
      library.open_private_evidence(
        key,
        role,
        "sha256:" + "1".repeat(64),
        envelope,
      )
      is Err(CipherRejected),
    )
  }
  assert_true(
    library.seal_private_evidence(key, "arbitrary", cid, plaintext)
    is Err(InvalidInput),
  )
}
