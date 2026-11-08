///|
// Fixed AES-GCM vectors produced independently by Node crypto with a public
// key/nonce. This is storage authentication, never Model dispatch authority.
test "native Model evidence roles authenticate independent Node envelopes" {
  let library = load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
  ).unwrap()
  let key = Bytes::makei(32, i => i.to_byte())
  let cid = "sha256:" + "0".repeat(64)
  let plaintext = @utf8.encode("native-private-evidence-fixture")
  for
    (role, wire) in [
      (
        "model_call_attempt", "{\"version\":\"actql-private-publication-evidence/0.1\",\"nonce\":\"AAECAwQFBgcICQoL\",\"tag\":\"dN9Mga/N1XIST+FTvMlEvA==\",\"ciphertext\":\"KWOicrOA72v/KOHqxYxVCPW/41GeGDpRXg6d8WgbZQ==\"}",
      ),
      (
        "model_attempt_accounting", "{\"version\":\"actql-private-publication-evidence/0.1\",\"nonce\":\"AAECAwQFBgcICQoL\",\"tag\":\"EzaJNARXV/fRlC1bRzohjw==\",\"ciphertext\":\"KWOicrOA72v/KOHqxYxVCPW/41GeGDpRXg6d8WgbZQ==\"}",
      ),
      (
        "model_attempt_outcome", "{\"version\":\"actql-private-publication-evidence/0.1\",\"nonce\":\"AAECAwQFBgcICQoL\",\"tag\":\"FbS+7gcOZ5NKwXaPQ2rP4w==\",\"ciphertext\":\"KWOicrOA72v/KOHqxYxVCPW/41GeGDpRXg6d8WgbZQ==\"}",
      ),
      (
        "model_dispatch_authority", "{\"version\":\"actql-private-publication-evidence/0.1\",\"nonce\":\"AAECAwQFBgcICQoL\",\"tag\":\"CQmJdSG8+ngezDOchVMfrQ==\",\"ciphertext\":\"KWOicrOA72v/KOHqxYxVCPW/41GeGDpRXg6d8WgbZQ==\"}",
      ),
      (
        "model_slot_capture", "{\"version\":\"actql-private-publication-evidence/0.1\",\"nonce\":\"AAECAwQFBgcICQoL\",\"tag\":\"m0YYf2V5n2b5UrT4I+RmYw==\",\"ciphertext\":\"KWOicrOA72v/KOHqxYxVCPW/41GeGDpRXg6d8WgbZQ==\"}",
      ),
      (
        "model_invocation_evidence", "{\"version\":\"actql-private-publication-evidence/0.1\",\"nonce\":\"AAECAwQFBgcICQoL\",\"tag\":\"9I2VjM1b//+vZ0VImmcG1Q==\",\"ciphertext\":\"KWOicrOA72v/KOHqxYxVCPW/41GeGDpRXg6d8WgbZQ==\"}",
      ),
      (
        "model_capture_bundle", "{\"version\":\"actql-private-publication-evidence/0.1\",\"nonce\":\"AAECAwQFBgcICQoL\",\"tag\":\"+1vZzsFo77N/tHjcLVlXLw==\",\"ciphertext\":\"KWOicrOA72v/KOHqxYxVCPW/41GeGDpRXg6d8WgbZQ==\"}",
      ),
      (
        "model_attachment_admission", "{\"version\":\"actql-private-publication-evidence/0.1\",\"nonce\":\"AAECAwQFBgcICQoL\",\"tag\":\"Pn2KLRHO2/pFrrr3rZuCag==\",\"ciphertext\":\"KWOicrOA72v/KOHqxYxVCPW/41GeGDpRXg6d8WgbZQ==\"}",
      ),
    ] {
    let envelope = @utf8.encode(wire)
    assert_eq(
      library.open_private_evidence(key, role, cid, envelope),
      Ok(plaintext),
    )
    assert_true(
      library.open_private_evidence(key, "effect_capture", cid, envelope)
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
    let saved = library
      .seal_private_evidence(key, role, cid, plaintext)
      .unwrap()
    assert_eq(
      library.open_private_evidence(key, role, cid, saved),
      Ok(plaintext),
    )
  }
}
