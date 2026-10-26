///|
// Existing independent signed vector and current-registration seam. The fake
// verify port counts crossings only; real cryptography has separate Native cases.
test "wrapper Reviewer authentication keeps complete original wire through canonical framing" {
  let registration = reviewer_authentication_test_registration()
  let original = reviewer_authentication_test_wire()
  let mut verifies = 0
  for embedded in [original, "\n " + original + " \t"] {
    let (authentication, actual) = authenticate_native_wrapper_reviewer_with(
      registration.selection,
      "{\"resolution\":" + embedded + "}",
      original,
      () => true,
      (_, _) => Some(registration),
      (key, bytes, signature) => {
        if key != registration.public_key_pem ||
          bytes !=
          @utf8.encode(
            "sha256:6a19960b235f700f5a88bcb26f324ad21e7e48d279f15160444fe687f6013dd1",
          ) ||
          signature !=
          "u2GRgUDJiDrrjYPJiC1z1VVL0JgnG9s9da2xfZlnkrnp034TjxpT9-M-dhhcID03Wa3SpFs-ghI48FICfSr9BQ" {
          abort("original wrapper proof crossing changed")
        }
        verifies += 1
        Ok(true)
      },
      reviewer_authentication_test_limits(),
    ).unwrap()
    assert_eq(actual, registration)
    assert_eq(authentication.key_id, registration.key_id)
    assert_eq(authentication.policy_cid, registration.policy_cid)
  }
  assert_eq(verifies, 2)
}

///|
test "wrapper Reviewer authentication refuses changed proof identity and bounds before verification" {
  let registration = reviewer_authentication_test_registration()
  let original = reviewer_authentication_test_wire()
  let changed_signature = original.replace_all(
    old="u2GRgUDJiDrr",
    new="v2GRgUDJiDrr",
  )
  let changed_cid = original.replace_all(
    old="sha256:87396910af30eb9f314ff792ef4711502b02f7a38dae5c5e05ca693a74411d01",
    new="sha256:" + "f".repeat(64),
  )
  // The existing Common preimage deliberately excludes proof/self identity.
  // Their equality therefore cannot replace complete signed-wire matching.
  for changed in [changed_signature, changed_cid] {
    assert_eq(
      @checkpoint.resolution_proof_preimage(
        changed,
        reviewer_authentication_test_limits(),
      ),
      @checkpoint.resolution_proof_preimage(
        original,
        reviewer_authentication_test_limits(),
      ),
    )
  }
  let mut reads = 0
  let mut verifies = 0
  for
    wrapper in [
      "{\"resolution\":" + changed_signature + "}",
      "{\"resolution\":" + changed_cid + "}",
      "{}",
      "{\"resolution\":null}",
      "{broken",
      "{\"resolution\":" + original + ",\"resolution\":" + original + "}",
      "{\"resolution\":" + original + "}" + " ".repeat(65536),
    ] {
    assert_true(
      authenticate_native_wrapper_reviewer_with(
        registration.selection,
        wrapper,
        original,
        () => true,
        (_, _) => {
          reads += 1
          Some(registration)
        },
        (_, _, _) => {
          verifies += 1
          Ok(true)
        },
        reviewer_authentication_test_limits(),
      )
      is Err(AttestationRejected),
    )
  }
  assert_true(
    authenticate_native_wrapper_reviewer_with(
      registration.selection,
      "{broken",
      original,
      () => false,
      (_, _) => {
        reads += 1
        Some(registration)
      },
      (_, _, _) => {
        verifies += 1
        Ok(true)
      },
      reviewer_authentication_test_limits(),
    )
    is Err(AuthorityDenied),
  )
  assert_true(
    authenticate_native_wrapper_reviewer_with(
      registration.selection,
      "{\"resolution\":" + original + "}",
      original + " ".repeat(65536),
      () => true,
      (_, _) => {
        reads += 1
        Some(registration)
      },
      (_, _, _) => {
        verifies += 1
        Ok(true)
      },
      reviewer_authentication_test_limits(),
    )
    is Err(AttestationRejected),
  )
  assert_eq(reads, 0)
  assert_eq(verifies, 0)
}

///|
test "wrapper Reviewer authentication retains post-verification current and physical failure" {
  let registration = reviewer_authentication_test_registration()
  let original = reviewer_authentication_test_wire()
  let wrapper = "{\"resolution\":" + original + "}"
  for lose_site in [false, true] {
    let mut verified = false
    let mut verifies = 0
    assert_true(
      authenticate_native_wrapper_reviewer_with(
        registration.selection,
        wrapper,
        original,
        () => !lose_site || !verified,
        (_, _) => if !lose_site && verified { None } else { Some(registration) },
        (_, _, _) => {
          verifies += 1
          verified = true
          Ok(true)
        },
        reviewer_authentication_test_limits(),
      )
      is Err(AuthorityDenied),
    )
    assert_eq(verifies, 1)
  }
  assert_true(
    authenticate_native_wrapper_reviewer_with(
      registration.selection,
      wrapper,
      original,
      () => true,
      (_, _) => Some(registration),
      (_, _, _) => Err(@signature.UnsupportedTarget),
      reviewer_authentication_test_limits(),
    )
    is Err(Signature(@signature.UnsupportedTarget)),
  )
}
