///|
fn initialization_fixture_account() -> Bytes {
  // Independent original Account corpus bytes; no output-derived expected CID.
  @utf8.encode(
    "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"local:operator\",\"entries\":[{\"entry_id\":\"files\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"local-files\"]},\"resource\":{\"all\":true},\"operation\":{\"all\":true},\"exclusions\":[]}]}",
  )
}

///|
fn initialization_fixture_physical() -> ClientLocalInitializationPhysical {
  {
    nonce: "01".repeat(32),
    parent: (1UL, 2UL),
    root: (3UL, 4UL),
    source_root: (5UL, 6UL),
    source_file: "account.json",
    source_path: "/private/e\u{0301}\r\n",
    source_generation: (18446744073709551615UL, 8UL, 270L),
    state_name: "state",
  }
}

///|
fn initialization_fixture_body() -> Bytes {
  client_local_initialization_body(
    local_scope_test_account(),
    initialization_fixture_account(),
    b"{\"files\":[],\"managed_root\":null,\"version\":\"actql-native-local-configuration-selection/0.1\"}",
    initialization_fixture_physical(),
  ).unwrap()
}

///|
test "original initialization chain preserves independently fixed Native preimages and CIDs" {
  let init = initialization_fixture_body()
  assert_eq(init.length(), 716)
  assert_eq(
    @sha.hex(init),
    "d7b077fa3a803302e5a5374ca5dc71ea879876760af126b7e1c0eaf16d9cf46b",
  )
  let custody = client_local_configuration_custody_body(init, (9UL, 10UL, 270L)).unwrap()
  assert_eq(
    custody, b"{\"device\":\"9\",\"inode\":\"10\",\"intent_cid\":\"sha256:d7b077fa3a803302e5a5374ca5dc71ea879876760af126b7e1c0eaf16d9cf46b\",\"size\":\"270\",\"version\":\"actql-native-local-configuration-custody/0.1\"}",
  )
  assert_eq(
    @sha.hex(custody),
    "9d5bc55377e09ef63628e1c1e111f4bb6f1ba2e6ade3ba8fb0743187072e3c05",
  )
  let journal = client_local_journal_custody_body(init, custody, (11UL, 12UL)).unwrap()
  assert_eq(
    journal, b"{\"configuration_custody_cid\":\"sha256:9d5bc55377e09ef63628e1c1e111f4bb6f1ba2e6ade3ba8fb0743187072e3c05\",\"device\":\"11\",\"inode\":\"12\",\"intent_cid\":\"sha256:d7b077fa3a803302e5a5374ca5dc71ea879876760af126b7e1c0eaf16d9cf46b\",\"version\":\"actql-native-local-journal-custody/0.1\"}",
  )
  assert_eq(
    @sha.hex(journal),
    "7ea6e70633f16c976c66cf544d70a9dad86a9ad0864d5ce78e99c6733db3ab54",
  )
}

///|
test "original record CID inputs preserve Native physical crypto issuance boundary" {
  let custody = client_local_configuration_custody_record(
    "sha256:" + "a".repeat(64),
    (9UL, 10UL, 270L),
  ).unwrap()
  let fields = client_local_original_record_fields(custody, [
    "device", "inode", "intent_cid", "size", "version",
  ]).unwrap()
  assert_eq(fields[2], "sha256:" + "a".repeat(64))
  assert_true(
    client_local_initialization_record_body([]) is Err(InvalidOriginal),
  )
  assert_true(
    client_local_initialization_record_body(Array::make(17, "x"))
    is Err(InvalidOriginal),
  )
}

///|
test "initialization rejects wrong original Account and impossible physical length nonce or limits" {
  let physical = initialization_fixture_physical()
  let body = initialization_fixture_account()
  for
    altered in [
      { ..physical, nonce: "01".repeat(31), },
      { ..physical, nonce: "G".repeat(64), },
      { ..physical, source_generation: (1UL, 2UL, -1L), },
      { ..physical, source_generation: (1UL, 2UL, 271L), },
    ] {
    assert_true(
      client_local_initialization_body(
        local_scope_test_account(),
        body,
        b"{}",
        altered,
      )
      is Err(InvalidOriginal),
    )
  }
  assert_true(
    client_local_initialization_body(
      local_scope_test_account(),
      b"{}",
      b"{}",
      physical,
    )
    is Err(InvalidOriginal),
  )
  assert_true(
    client_local_configuration_custody_body(
      Bytes::make(8193, 0),
      (1UL, 2UL, 3L),
    )
    is Err(InvalidOriginal),
  )
  assert_true(
    client_local_journal_custody_body(b"{}", Bytes::make(8193, 0), (1UL, 2UL))
    is Err(InvalidOriginal),
  )
}

///|
test "initialization original bytes and decomposed path are not normalized or default repaired" {
  let physical = initialization_fixture_physical()
  let first = initialization_fixture_body()
  let changed = client_local_initialization_body(
    local_scope_test_account(),
    initialization_fixture_account(),
    b"{\"files\":[],\"managed_root\":null,\"version\":\"actql-native-local-configuration-selection/0.1\"}",
    { ..physical, source_path: "/private/é\r\n", },
  ).unwrap()
  assert_true(first != changed)
  let changed_nonce = client_local_initialization_body(
    local_scope_test_account(),
    initialization_fixture_account(),
    b"{}",
    { ..physical, nonce: "02".repeat(32), },
  ).unwrap()
  assert_true(first != changed_nonce)
}
