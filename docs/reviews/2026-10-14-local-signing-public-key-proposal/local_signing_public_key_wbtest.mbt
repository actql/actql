///|
// PROPOSAL ONLY. Independent Python JSON/hashlib expectations; no key access,
// signing, issuer installation or permission is exercised by these cases.
let public_key_proposal_wire : String =
  #|{"algorithm":"ed25519","public_key":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=","version":"actql-local-signing-public-key/0.1"}

///|
let public_key_proposal_cid : String = "sha256:9689096c43f7a1edbda0f95a62d7804485ce8a1ed0cf6834d7a6bc62709a05b7"

///|
fn public_key_proposal_raw() -> Bytes {
  Bytes::from_array(Array::makei(32, index => index.to_byte()))
}

///|
test "public-key proposal exact independent body and CID" {
  let value = prepare_local_signing_public_key(public_key_proposal_raw()).unwrap()
  assert_eq(value.json(), public_key_proposal_wire)
  assert_eq(value.cid(), public_key_proposal_cid)
  let admitted = admit_local_signing_public_key_json(
    public_key_proposal_wire, public_key_proposal_cid,
  ).unwrap()
  assert_eq(admitted.raw32().unwrap(), public_key_proposal_raw())
  assert_eq(admitted.json(), value.json())
  assert_eq(admitted.cid(), value.cid())
}

///|
test "public-key proposal exact32 refuses other lengths" {
  for length in [0, 31, 33, 256] {
    assert_eq(
      prepare_local_signing_public_key(Bytes::make(length, 0)).map(_ => ()),
      Err(InvalidPublicKey),
    )
  }
}

///|
test "public-key proposal RFC8032 public vector and distinct bytes" {
  let encoded = "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="
  let raw = @base64.decode(encoded[:]) catch { _ => fail("fixed public bytes") }
  let value = prepare_local_signing_public_key(raw).unwrap()
  assert_eq(
    value.cid(),
    "sha256:73bed10fdb3d584a1bad7e7c22ad93c1579582dbbe743cd67964a79165760a52",
  )
  assert_true(value.cid() != public_key_proposal_cid)
  assert_eq(
    admit_local_signing_public_key_json(value.json(), value.cid())
      .unwrap().raw32().unwrap(),
    raw,
  )
}

///|
test "public-key proposal closed canonical body refuses altered framing" {
  for body in [
    "null",
    "{",
    " " + public_key_proposal_wire,
    public_key_proposal_wire + "\n",
    public_key_proposal_wire.replace_all(old="ed25519", new="Ed25519"),
    public_key_proposal_wire.replace_all(old="ed25519", new="rsa"),
    public_key_proposal_wire.replace_all(old="{", new="{\"unknown\":null,"),
    public_key_proposal_wire.replace_all(old="{", new="{\"algorithm\":\"ed25519\","),
    public_key_proposal_wire.replace_all(old="\"algorithm\"", new="\"alg\\u006frithm\""),
    public_key_proposal_wire.replace_all(old=":", new=": "),
    public_key_proposal_wire.replace_all(
      old="actql-local-signing-public-key/0.1",
      new="actql-local-signing-public-key/" + "0.2",
    ),
    "{\"version\":\"actql-local-signing-public-key/0.1\",\"public_key\":\"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=\",\"algorithm\":\"ed25519\"}",
  ] {
    assert_true(
      admit_local_signing_public_key_json(body, public_key_proposal_cid)
      is Err(_),
    )
  }
}

///|
test "public-key proposal base64 admits only standard canonical padded bytes" {
  for encoded in [
    "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8",
    "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh9=",
    "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8_",
    "!".repeat(44),
    "A".repeat(42) + "==",
  ] {
    let body = public_key_proposal_wire.replace_all(
      old="AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=",
      new=encoded,
    )
    assert_true(
      admit_local_signing_public_key_json(body, public_key_proposal_cid)
      is Err(_),
    )
  }
}

///|
test "public-key proposal independent body and expected CID must both match" {
  assert_eq(
    admit_local_signing_public_key_json(
      public_key_proposal_wire, "sha256:" + "f".repeat(64),
    ).map(_ => ()),
    Err(PublicKeyIdentityMismatch),
  )
  assert_eq(
    admit_local_signing_public_key_json(
      public_key_proposal_wire, "copied-cid",
    ).map(_ => ()),
    Err(InvalidPublicKey),
  )
}
