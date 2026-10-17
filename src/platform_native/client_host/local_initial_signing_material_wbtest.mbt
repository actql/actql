///|
fn initial_signing_fixture(
  name : String,
) -> (String, String, NativeLocalAdoptionSession, @crypto.Library) raise {
  // Each independent Store has its own original parent/claim. Opening another
  // Store under a currently locked parent would test lock contention instead.
  let top = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(top).unwrap()
  parent.create_directory(name).unwrap() |> ignore
  let source = parent.open_child(name).unwrap()
  let path = top + "/" + name
  let account = name + ".account.json"
  let writer = source.create_writer("account.stage", 4096L).unwrap()
  writer.append(local_selected_account).unwrap()
  writer.seal(account).unwrap() |> ignore
  let crypto = @crypto.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(256),
  ).unwrap()
  let session = match
    begin_native_local_host_adoption(
      path,
      name + ".host",
      path,
      account,
      "operator",
      crypto,
    ) {
    Ok(value) => value
    Err(_) =>
      fail("initial Signing fixture: begin_native_local_host_adoption refused")
  }
  (path, account, session, crypto)
}

///|
fn initial_signing_private_present(
  session : NativeLocalAdoptionSession,
) -> Bool {
  session.root.inspect_generation("local-signing-key.pem")
  is Ok(Some(generation)) &&
  generation.size == 119L
}

///|
test "initial Signing material uses exclusive Store generation and real matching key pair" {
  let (_, _, session, crypto) = initial_signing_fixture("initial-signing-real")
  let material = session.create_initial_signing_material(crypto).unwrap()
  let public_key = session.initial_signing_public_key(material).unwrap()
  assert_true(
    public_key.length() == 113 && initial_signing_private_present(session),
  )
  let (private_key, generation) = local_adoption_read(
    session.root,
    "local-signing-key.pem",
    119L,
  ).unwrap()
  assert_true(generation == material.generation && private_key.length() == 119)
  let payload = @utf8.encode("initial key proof e\u{301}\r\n")
  let signature = crypto.sign_ed25519(private_key, payload).unwrap()
  assert_true(crypto.verify_ed25519(public_key, payload, signature).unwrap())
  assert_false(
    crypto.verify_ed25519(public_key, b"different", signature).unwrap(),
  )
  assert_true(
    session.root.inspect_generation("local-signing-key.pem.stage").unwrap()
    is None,
  )
  assert_true(session.close())
  assert_true(session.initial_signing_public_key(material) is Err(Closed))
}

///|
test "initial Signing material aliases cannot generate twice or substitute another Store" {
  let (_, _, session, crypto) = initial_signing_fixture("initial-signing-alias")
  let copied_session = { ..session, }
  let material = session.create_initial_signing_material(crypto).unwrap()
  let generation = material.generation
  let failure = match copied_session.create_initial_signing_material(crypto) {
    Err(value) => value
    Ok(_) => fail("same original creation generated another key")
  }
  assert_true(failure.issue() is AmbiguousInitialization)
  assert_true(session.initial_signing_public_key(material) is Ok(_))
  assert_eq(
    session.root.inspect_generation("local-signing-key.pem").unwrap(),
    Some(generation),
  )
  let (_, _, other, _) = initial_signing_fixture("initial-signing-foreign")
  assert_true(other.initial_signing_public_key(material) is Err(CustodyLost))
  assert_true(other.close())
  assert_true(session.close())
}

///|
test "reopened Signing initialization restores no key by generation even when keys are missing" {
  let (path, account, session, crypto) = initial_signing_fixture(
    "initial-signing-missing",
  )
  let original = session.intent_cid()
  assert_true(session.close())
  let restored = begin_native_local_host_adoption(
    path, "initial-signing-missing.host", path, account, "operator", crypto,
  ).unwrap()
  assert_eq(restored.intent_cid(), original)
  let failure = match restored.create_initial_signing_material(crypto) {
    Err(value) => value
    Ok(_) => fail("reopened missing key selected fresh generation")
  }
  assert_true(failure.issue() is AmbiguousInitialization)
  assert_eq(
    restored.root.inspect_generation("local-signing-key.pem").unwrap(),
    None,
  )
  assert_eq(
    restored.root.inspect_generation("local-signing-key.pem.stage").unwrap(),
    None,
  )
  assert_true(restored.close())
}

///|
test "reopened generated Signing file keeps its original generation without recapture" {
  let (path, account, session, crypto) = initial_signing_fixture(
    "initial-signing-reopen",
  )
  let material = session.create_initial_signing_material(crypto).unwrap()
  let generation = material.generation
  assert_true(session.close())
  let restored = begin_native_local_host_adoption(
    path, "initial-signing-reopen.host", path, account, "operator", crypto,
  ).unwrap()
  assert_true(restored.initial_signing_public_key(material) is Err(CustodyLost))
  assert_true(restored.create_initial_signing_material(crypto) is Err(_))
  assert_eq(
    restored.root.inspect_generation("local-signing-key.pem").unwrap(),
    Some(generation),
  )
  assert_true(restored.close())
}

///|
test "initial Signing crypto failure preserves its original issue and no second attempt" {
  let (_, _, session, crypto) = initial_signing_fixture(
    "initial-signing-crypto-failure",
  )
  let unsupported = @crypto.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
  ).unwrap()
  let failure = match session.create_initial_signing_material(unsupported) {
    Err(value) => value
    Ok(_) => fail("unfunded diagnostic generation was admitted")
  }
  assert_true(failure.issue() is Crypto(@crypto.InvalidInput))
  failure.retry_cleanup().unwrap()
  let repeated = match session.create_initial_signing_material(crypto) {
    Err(value) => value
    Ok(_) => fail("failed initialization regenerated a key")
  }
  assert_true(physical_equal(failure, repeated))
  assert_eq(
    session.root.inspect_generation("local-signing-key.pem").unwrap(),
    None,
  )
  assert_true(
    session.root.inspect_generation("local-signing-key.pem.stage").unwrap()
    is Some(generation) &&
    generation.size == 0L,
  )
  assert_true(session.close())
}

///|
#borrow(root)
extern "C" fn initial_signing_fail_root_sync(
  root : @filesystem.Root,
  count : Int,
) -> Unit = "actql_native_filesystem_test_fail_root_sync"

///|
test "initial Signing seal failure retains partial key and primary failure after cleanup" {
  let (_, _, session, crypto) = initial_signing_fixture(
    "initial-signing-sync-failure",
  )
  initial_signing_fail_root_sync(session.root, 1)
  let failure = match session.create_initial_signing_material(crypto) {
    Err(value) => value
    Ok(_) => fail("failed directory sync returned ready key")
  }
  assert_true(failure.issue() is WritePending(_, _))
  assert_true(initial_signing_private_present(session))
  failure.retry_cleanup().unwrap()
  assert_true(failure.issue() is WritePending(_, _))
  assert_true(session.create_initial_signing_material(crypto) is Err(_))
  assert_true(session.close())
  assert_true(initial_signing_private_present(session))
}

///|
test "initial Signing target conflict is preserved without reading or replacing it" {
  let (_, _, session, crypto) = initial_signing_fixture(
    "initial-signing-conflict",
  )
  let writer = session.root.create_writer("occupied.stage", 8L).unwrap()
  writer.append(b"occupied").unwrap()
  let generation = writer.seal("local-signing-key.pem").unwrap()
  let failure = match session.create_initial_signing_material(crypto) {
    Err(value) => value
    Ok(_) => fail("existing private target selected fresh generation")
  }
  assert_true(failure.issue() is CustodyLost)
  assert_eq(
    session.root.inspect_generation("local-signing-key.pem").unwrap(),
    Some(generation),
  )
  assert_eq(
    session.root.inspect_generation("local-signing-key.pem.stage").unwrap(),
    None,
  )
  assert_true(session.close())
}
