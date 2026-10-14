///|
// Independent JSON/hashlib vectors for the existing execution identity laws.
// Public metadata admission is not original journal custody or signing authority.
fn signing_request_subject_fixture(
  caller : String,
  input : String,
  scope : String,
  intent : String,
) -> ClientRequestIdentity {
  admit_client_request_identity_record(
    "sha256:" + "4".repeat(64),
    caller,
    "sha256:" + "1".repeat(64),
    "sha256:" + "2".repeat(64),
    input,
    scope,
    intent,
  ).unwrap()
}

///|
test "Local signing request fields select original fingerprint and logical scope independently" {
  let scope = "sha256:4d08ebef01bc0df2fb984f06e1778fb88a13ea79ff8611c88911d9211c23ac6d"
  let intent = "sha256:a8a1fc7e0a89847817252aa407df0fae423e22cc079a8f6bd7f9a4197abf26ee"
  let original = signing_request_subject_fixture(
    "caller-a", "sha256:" + "3".repeat(64), scope, intent,
  )
  assert_eq(client_request_intent_cid(original), intent)
  assert_eq(client_request_scope_cid(original), scope)
  assert_true(scope != client_request_authority_scope_cid(original))
  assert_true(scope != intent)
}

///|
test "equal signing intent in another logical scope remains a different original request" {
  let intent = "sha256:a8a1fc7e0a89847817252aa407df0fae423e22cc079a8f6bd7f9a4197abf26ee"
  let a = signing_request_subject_fixture(
    "caller-a", "sha256:" + "3".repeat(64),
    "sha256:4d08ebef01bc0df2fb984f06e1778fb88a13ea79ff8611c88911d9211c23ac6d", intent,
  )
  let b = signing_request_subject_fixture(
    "caller-b", "sha256:" + "3".repeat(64),
    "sha256:2b0ea5ceefadf11edabee798eac47082bffd6370f31f2d1a9a1d41a7641e3cf8", intent,
  )
  assert_eq(client_request_intent_cid(a), client_request_intent_cid(b))
  assert_true(client_request_scope_cid(a) != client_request_scope_cid(b))
  assert_eq(client_request_identity_relation(b, a), DifferentRequest)
}

///|
test "changed signing intent under the same logical scope remains a conflict" {
  let scope = "sha256:4d08ebef01bc0df2fb984f06e1778fb88a13ea79ff8611c88911d9211c23ac6d"
  let a = signing_request_subject_fixture(
    "caller-a", "sha256:" + "3".repeat(64), scope,
    "sha256:a8a1fc7e0a89847817252aa407df0fae423e22cc079a8f6bd7f9a4197abf26ee",
  )
  let b = signing_request_subject_fixture(
    "caller-a", "sha256:" + "5".repeat(64), scope,
    "sha256:274ab3f8fc8006c7d2e54dcd29702da5814dfdfc588ac30c158fa7e1c34d35ff",
  )
  assert_eq(client_request_scope_cid(a), client_request_scope_cid(b))
  assert_true(client_request_intent_cid(a) != client_request_intent_cid(b))
  assert_eq(client_request_identity_relation(b, a), ChangedIntent)
}
