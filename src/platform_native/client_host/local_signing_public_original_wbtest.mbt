///|
// Authored metadata frames with independent Python JSON/hashlib expectations.
// These are not HMAC packets, file projections, Host grants or private keys.
let signing_public_original_wire : String =
  #|{"adoption_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","authority_scope_cid":"sha256:2222222222222222222222222222222222222222222222222222222222222222","installation_configuration_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","projection":"AAA=","public_key_cid":"sha256:9689096c43f7a1edbda0f95a62d7804485ce8a1ed0cf6834d7a6bc62709a05b7","public_key_original":"{\"algorithm\":\"ed25519\",\"public_key\":\"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=\",\"version\":\"actql-local-signing-public-key/0.1\"}","purpose":"host_attestation","version":"actql-native-local-installation-original/0.1"}

///|
let signing_public_legacy_wire : String =
  #|{"adoption_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","authority_scope_cid":"sha256:2222222222222222222222222222222222222222222222222222222222222222","installation_configuration_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","projection":"AAA=","purpose":"host_attestation","version":"actql-native-local-installation-original/0.1"}

///|
let signing_public_original_cid : String = "sha256:9689096c43f7a1edbda0f95a62d7804485ce8a1ed0cf6834d7a6bc62709a05b7"

///|
test "signing installation metadata retains the exact independent public original" {
  let fields = local_signing_installation_fields(
    @utf8.encode(signing_public_original_wire),
  ).unwrap()
  guard fields.public_key is Some(original) else {
    fail("new metadata frame lost its public original")
  }
  assert_eq(original.cid(), signing_public_original_cid)
  assert_eq(original.raw32().unwrap(), Bytes::from_array(Array::makei(32, i => i.to_byte())))
  assert_eq(fields.purpose, "host_attestation")
  assert_eq(fields.projection, "AAA=")
}

///|
test "legacy signing metadata stays missing without current replacement" {
  let fields = local_signing_installation_fields(
    @utf8.encode(signing_public_legacy_wire),
  ).unwrap()
  assert_true(fields.public_key is None)
  assert_eq(fields.purpose, "host_attestation")
  assert_eq(fields.projection, "AAA=")
}

///|
test "signing public original requires both saved body and saved CID" {
  for incomplete in [
    "{\"adoption_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"authority_scope_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"installation_configuration_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"projection\":\"AAA=\",\"public_key_original\":\"{\\\"algorithm\\\":\\\"ed25519\\\",\\\"public_key\\\":\\\"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=\\\",\\\"version\\\":\\\"actql-local-signing-public-key/0.1\\\"}\",\"purpose\":\"host_attestation\",\"version\":\"actql-native-local-installation-original/0.1\"}",
    "{\"adoption_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"authority_scope_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"installation_configuration_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"projection\":\"AAA=\",\"public_key_cid\":\"sha256:9689096c43f7a1edbda0f95a62d7804485ce8a1ed0cf6834d7a6bc62709a05b7\",\"purpose\":\"host_attestation\",\"version\":\"actql-native-local-installation-original/0.1\"}"
  ] {
    assert_true(local_signing_installation_fields(@utf8.encode(incomplete)) is Err(CustodyLost))
  }
}

///|
test "signing public original rejects wrong identity and extra metadata" {
  for wire in [
    signing_public_original_wire.replace_all(old=signing_public_original_cid, new="sha256:" + "4".repeat(64)),
    signing_public_original_wire.replace_all(old="ed25519", new="rsa"),
    "{\"extra\":\"unexpected\"," + signing_public_original_wire[1:].to_owned(),
    signing_public_original_wire.replace_all(old="AAA=", new="AAA=\",\"projection\":\"AAA="),
  ] {
    assert_true(local_signing_installation_fields(@utf8.encode(wire)) is Err(CustodyLost))
  }
}

///|
test "bounded signing metadata does not accept an oversized public original" {
  let wire = signing_public_original_wire.replace_all(
    old="AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=", new="A".repeat(2049),
  )
  assert_true(local_signing_installation_fields(@utf8.encode(wire)) is Err(CustodyLost))
}

///|
test "signing public installation encoder matches the independent full preimage" {
  let public_key = @credential.prepare_local_signing_public_key(
    Bytes::from_array(Array::makei(32, i => i.to_byte())),
  ).unwrap()
  let body = local_signing_public_installation_body(
    "sha256:" + "1".repeat(64),
    "sha256:" + "2".repeat(64),
    "sha256:" + "3".repeat(64),
    Bytes::make(2, 0),
    @credential.HostAttestation,
    public_key,
  ).unwrap()
  assert_eq(body, @utf8.encode(signing_public_original_wire))
}

///|
test "signing public installation stays inside the original payload and packet bounds" {
  let public_key = @credential.prepare_local_signing_public_key(
    Bytes::from_array(Array::makei(32, i => i.to_byte())),
  ).unwrap()
  let payload = local_signing_public_installation_body(
    "sha256:" + "1".repeat(64),
    "sha256:" + "2".repeat(64),
    "sha256:" + "3".repeat(64),
    Bytes::make(234, 0),
    @credential.HostAttestation,
    public_key,
  ).unwrap()
  // Independent compact JSON/base64 sizes for the maximum original export.
  // The zero tag is a framing fixture, never a valid Host HMAC or permission.
  assert_eq(payload.length(), 965)
  let packet_shape = local_adoption_record([
    ("payload", @base64.encode(payload)), ("tag", "0".repeat(64)),
  ]).unwrap()
  assert_eq(packet_shape.length(), 1375)
  assert_true(payload.length() < 2048)
  assert_true(packet_shape.length() < 8192)
}
