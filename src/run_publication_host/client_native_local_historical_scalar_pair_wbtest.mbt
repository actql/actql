///|
fn historical_pair_test_restore(
  saved? : Bytes = historical_scalar_pair_test_saved_body(),
  original? : ClientNativeLocalRuntime = scalar_pair_test_admit(
    scalar_pair_test_original_runtime_wire(),
  ),
  historical? : ClientNativeLocalRuntime = scalar_pair_test_admit(
    historical_scalar_pair_test_runtime_wire(),
  ),
) -> Result[
  ClientNativeLocalScalarRuntimePair,
  ClientNativeLocalScalarRuntimePairIssue,
] {
  restore_client_native_local_historical_scalar_runtime_pair_metadata(
    saved, original, historical,
  )
}

///|
test "historical scalar metadata preserves independent saved bytes and original complete CID" {
  let pair = historical_pair_test_restore().unwrap()
  let body = client_native_local_scalar_runtime_pair_body(pair)
  assert_eq(body, historical_scalar_pair_test_saved_body())
  assert_eq(body.length(), 523)
  assert_eq(
    @sha.hex(body),
    "2b06a81d8266f98c954a76556c3312e3abba0acb8615f19c501ce3df920d367b",
  )
  assert_eq(
    pair.original.source_sha,
    "109564ef9a4f8241096292843b875d4c81fbb6f3",
  )
  assert_eq(pair.current.source_sha, "a3b1643fbedc5180db38b6e08459a188f05b1135")
}

///|
test "historical scalar metadata refuses a one-byte saved body change and proof substitution" {
  let body = @utf8.decode(historical_scalar_pair_test_saved_body())
  for
    changed in [
      body + "\n",
      body.replace(old="a3b1643f", new="b3b1643f"),
      body.replace(
        old="8bdf483589d04809f0e2e198708adc8335b38179f332e58d25a8a09497633a22",
        new="0".repeat(64),
      ),
      body.replace(old="primitive-scalar-values", new="all-values"),
      "{}",
    ] {
    assert_true(
      historical_pair_test_restore(saved=@utf8.encode(changed))
      is Err(InvalidOriginal),
    )
  }
}

///|
test "historical scalar metadata cannot select another source or swap the manifest pair" {
  let original = scalar_pair_test_admit(
    scalar_pair_test_original_runtime_wire(),
  )
  let prior = scalar_pair_test_admit(historical_scalar_pair_test_runtime_wire())
  assert_true(
    historical_pair_test_restore(original=prior, historical=original)
    is Err(UnknownPredecessor),
  )
  let other = scalar_pair_test_admit(
    historical_scalar_pair_test_runtime_wire().replace(
      old="a3b1643f",
      new="b3b1643f",
    ),
  )
  assert_true(
    historical_pair_test_restore(historical=other) is Err(InvalidOriginal),
  )
  assert_true(
    historical_pair_test_restore(
      historical=scalar_pair_test_admit(scalar_pair_test_current_runtime_wire()),
    )
    is Err(InvalidOriginal),
  )
}

///|
test "historical scalar metadata refuses changed complete member role bytes hash and ABI closure" {
  let wire = historical_scalar_pair_test_runtime_wire()
  for
    changed in [
      wire.replace(old="1268496", new="1268497"),
      wire.replace(old="671786", new="671787"),
      wire.replace(old="licenses/sqlite3.h", new="licenses/sqlite-other.h"),
      wire.replace(old="26.0", new="25.0"),
      wire.replace(old="\"role\": \"registry\"", new="\"role\": \"other\""),
      wire.replace(
        old="6ae574874934fcda0f8b0d7bf5f26b085a6c25fad25f5be319f4430ba9e66633",
        new="0".repeat(64),
      ),
      wire + "\n",
    ] {
    // The existing closed manifest reader may reject first. If it can issue
    // metadata, the historical factory must still reject the exact pair.
    match
      admit_client_native_local_runtime(
        changed,
        "a3b1643fbedc5180db38b6e08459a188f05b1135",
        "darwin-arm64",
        @sha.hex(@utf8.encode(changed)),
      ) {
      Err(_) => ()
      Ok(value) =>
        assert_true(historical_pair_test_restore(historical=value) is Err(_))
    }
  }
}

///|
test "historical metadata does not remove ordinary restore actual-body premises" {
  let original = scalar_pair_test_admit(
    scalar_pair_test_original_runtime_wire(),
  )
  let prior = scalar_pair_test_admit(historical_scalar_pair_test_runtime_wire())
  let saved = historical_scalar_pair_test_saved_body()
  let actual = restore_client_native_local_scalar_runtime_pair(
    saved,
    original,
    prior,
    scalar_pair_test_original_assets(),
    scalar_pair_test_reviewed_current_assets(),
  ).unwrap()
  assert_eq(client_native_local_scalar_runtime_pair_body(actual), saved)
  assert_true(
    restore_client_native_local_scalar_runtime_pair(
      saved,
      original,
      prior,
      scalar_pair_test_original_assets(),
      scalar_pair_test_original_assets(),
    )
    is Err(AssetChanged),
  )
  // The new method returns only the same historical logical metadata.
  assert_eq(
    client_native_local_scalar_runtime_pair_body(
      historical_pair_test_restore().unwrap(),
    ),
    saved,
  )
}

///|
test "historical scalar metadata preimage cannot carry scope authority or replacement originals" {
  let saved = @utf8.decode(historical_scalar_pair_test_saved_body())
  for
    extra in [
      "authority_scope_cid", "current_permission", "replacement_preparation", "physical_custody",
    ] {
    let changed = saved.replace(old="{", new="{\"" + extra + "\":\"forged\",")
    assert_true(
      historical_pair_test_restore(saved=@utf8.encode(changed))
      is Err(InvalidOriginal),
    )
  }
}
