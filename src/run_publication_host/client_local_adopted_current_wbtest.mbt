///|
let adopted_current_test_body : Bytes = b"{\"configuration_custody_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"device\":\"7\",\"inode\":\"9\",\"intent_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"version\":\"actql-native-local-journal-custody/0.1\"}"

///|
let adopted_current_test_account_original : Bytes = b"{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"local:operator\",\"entries\":[{\"entry_id\":\"files\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"local-files\"]},\"resource\":{\"all\":true},\"operation\":{\"all\":true},\"exclusions\":[]}]}"

///|
fn adopted_current_test_observation(
  store : Ref[Int],
  body? : Bytes = adopted_current_test_body,
  generation? : (UInt64, UInt64) = (7, 9),
  key? : String = "adoption",
  revision? : Int64 = 0L,
  account? : @authorization.AdmittedAccountConfiguration = local_scope_test_account(),
  account_original? : Bytes = adopted_current_test_account_original,
) -> ClientLocalAdoptionCurrentObservation[Ref[Int]] {
  Observed(
    store,
    account,
    account_original,
    { key, body, revision, },
    generation,
  )
}

///|
test "adopted current material uses actual original custody and the existing scope body" {
  let store = Ref(0)
  let calls = Ref(0)
  let material = bind_client_local_adopted_host_material(store, () => {
    calls.val += 1
    adopted_current_test_ok(adopted_current_test_observation(store))
  }).unwrap()
  assert_eq(calls.val, 1)
  let body = client_local_adopted_authority_scope_body(
    material, store, "operator", "local",
  ).unwrap()
  assert_eq(calls.val, 2)
  assert_eq(
    body,
    client_local_authority_scope_body(
      local_scope_test_account(),
      "sha256:" + @sha.hex(adopted_current_test_body),
      "operator",
      "local",
    ).unwrap(),
  )
  // Independent literal-preimage digest, never copied from the product encoder.
  assert_eq(
    @sha.hex(adopted_current_test_body),
    "7bc883aee393aff6c01d3929a296a5b9da3e16c69451d2de88dd78d2b054e456",
  )
  assert_eq(
    @sha.hex(body),
    "2403f9f91c600a51db56159017ac9512ac7bf590127aaa032eb993a285561568",
  )
}

///|
test "unadopted and unknown commit do not bind current material or repair custody" {
  let store = Ref(0)
  assert_true(
    bind_client_local_adopted_host_material(store, () => {
      adopted_current_test_ok(NotAdopted)
    })
    is Err(NotAdopted),
  )
  assert_true(
    bind_client_local_adopted_host_material(store, () => {
      adopted_current_test_ok(CommitUnknown)
    })
    is Err(CommitUnknown),
  )
  assert_true(
    bind_client_local_adopted_host_material(store, () => {
      Err("original physical query failure")
    })
    is Err(Physical("original physical query failure")),
  )
}

///|
test "original material rejects another Store before invoking its current port" {
  let store = Ref(0)
  let foreign = Ref(0)
  let calls = Ref(0)
  let material = bind_client_local_adopted_host_material(store, () => {
    calls.val += 1
    adopted_current_test_ok(adopted_current_test_observation(store))
  }).unwrap()
  assert_true(
    client_local_adopted_authority_scope_body(
      material, foreign, "operator", "local",
    )
    is Err(ForeignStore),
  )
  assert_eq(calls.val, 1)
  assert_true(
    bind_client_local_adopted_host_material(store, () => {
      adopted_current_test_ok(adopted_current_test_observation(foreign))
    })
    is Err(ForeignStore),
  )
}

///|
test "original adoption requires its exact singleton key revision body and physical generation" {
  let store = Ref(0)
  for
    observed in [
      adopted_current_test_observation(store, key="foreign"),
      adopted_current_test_observation(store, revision=1L),
      adopted_current_test_observation(store, generation=(7, 10)),
      adopted_current_test_observation(
        store,
        body=adopted_current_test_body + b"\n",
      ),
      adopted_current_test_observation(store, body=b"{}"),
    ] {
    assert_true(
      bind_client_local_adopted_host_material(store, () => {
        adopted_current_test_ok(observed)
      })
      is Err(InvalidOriginal),
    )
  }
}

///|
test "current checks retain original material and reject changed account or adoption" {
  let store = Ref(0)
  let original = adopted_current_test_observation(store)
  let current = Ref(original)
  let material = bind_client_local_adopted_host_material(store, () => {
    adopted_current_test_ok(current.val)
  }).unwrap()
  let other = @authorization.admit_account_configuration_json(
    "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"revoked\",\"entries\":[]}",
  ).unwrap()
  current.val = adopted_current_test_observation(store, account=other)
  assert_true(
    client_local_adopted_current_account(material, store) is Err(ChangedCurrent),
  )
  current.val = adopted_current_test_observation(
    store,
    body=@utf8.encode(
      @utf8.decode(adopted_current_test_body).replace(
        old="\"inode\":\"9\"",
        new="\"inode\":\"10\"",
      ),
    ),
    generation=(7, 10),
  )
  assert_true(
    client_local_adopted_current_account(material, store) is Err(ChangedCurrent),
  )
  current.val = original
  assert_true(client_local_adopted_current_account(material, store) is Ok(_))
}

///|
test "current loss at the next scope boundary does not return retained bytes" {
  let store = Ref(0)
  let calls = Ref(0)
  let material = bind_client_local_adopted_host_material(store, () => {
    calls.val += 1
    adopted_current_test_ok(
      if calls.val == 3 {
        CommitUnknown
      } else {
        adopted_current_test_observation(store)
      },
    )
  }).unwrap()
  client_local_adopted_authority_scope_body(
    material, store, "operator", "local",
  ).unwrap()
  |> ignore
  assert_true(
    client_local_adopted_authority_scope_body(
      material, store, "operator", "local",
    )
    is Err(CommitUnknown),
  )
  assert_eq(calls.val, 3)
}

///|
test "scope and adoption do not replace the existing Account Allow or Deny" {
  let store = Ref(0)
  let material = bind_client_local_adopted_host_material(store, () => {
    adopted_current_test_ok(adopted_current_test_observation(store))
  }).unwrap()
  assert_true(
    client_local_adopted_account_outcome(material, store, {
      principal: "operator",
      connection: "local",
      resource: "run",
      operation: "publish",
    })
    is Ok(@authorization.Deny(_)),
  )
  assert_true(
    client_local_adopted_account_outcome(material, store, {
      principal: "operator",
      connection: "local-files",
      resource: "run",
      operation: "publish",
    })
    is Ok(@authorization.Allow(_)),
  )
}

///|
test "current loss at the next Account boundary refuses an earlier Allow" {
  let store = Ref(0)
  let calls = Ref(0)
  let material = bind_client_local_adopted_host_material(store, () => {
    calls.val += 1
    if calls.val == 3 {
      Err("original fence expired")
    } else {
      Ok(adopted_current_test_observation(store))
    }
  }).unwrap()
  assert_true(
    client_local_adopted_account_outcome(material, store, {
      principal: "operator",
      connection: "local-files",
      resource: "run",
      operation: "publish",
    }) is Ok(@authorization.Allow(_)),
  )
  assert_true(
    client_local_adopted_account_outcome(material, store, {
      principal: "operator",
      connection: "local-files",
      resource: "run",
      operation: "publish",
    })
    is Err(Physical("original fence expired")),
  )
}

///|
test "scope retains one immutable projection but each new operation checks current" {
  let store = Ref(0)
  let calls = Ref(0)
  let current = Ref(adopted_current_test_observation(store))
  let material = bind_client_local_adopted_host_material(store, () => {
    calls.val += 1
    adopted_current_test_ok(current.val)
  }).unwrap()
  let first = client_local_adopted_authority_scope_body(
    material, store, "operator", "local-files",
  ).unwrap()
  let again = client_local_adopted_authority_scope_body(
    material, store, "operator", "local-files",
  ).unwrap()
  assert_true(physical_equal(first, again))
  assert_eq(calls.val, 3)
  let other = client_local_adopted_authority_scope_body(
    material, store, "other", "local-files",
  ).unwrap()
  assert_true(first != other)
  assert_eq(calls.val, 4)
  current.val = adopted_current_test_observation(store, key="foreign")
  assert_true(
    client_local_adopted_authority_scope_body(
      material, store, "other", "local-files",
    ) is Err(ChangedCurrent),
  )
  assert_eq(calls.val, 5)
}

///|
fn adopted_current_test_ok(
  observation : ClientLocalAdoptionCurrentObservation[Ref[Int]],
) -> Result[ClientLocalAdoptionCurrentObservation[Ref[Int]], String] {
  Ok(observation)
}

///|
test "current material retains exact account source even when its identity is unchanged" {
  let store = Ref(0)
  let current = Ref(adopted_current_test_observation(store))
  let material = bind_client_local_adopted_host_material(store, () => {
    adopted_current_test_ok(current.val)
  }).unwrap()
  let changed = adopted_current_test_account_original + b"\r\n"
  let parsed = @authorization.admit_account_configuration_json(
    @utf8.decode(changed),
  ).unwrap()
  assert_eq(
    parsed.configuration_cid(),
    local_scope_test_account().configuration_cid(),
  )
  current.val = adopted_current_test_observation(
    store,
    account=parsed,
    account_original=changed,
  )
  assert_true(
    client_local_adopted_current_account(material, store) is Err(ChangedCurrent),
  )
  for raw in [b"{}", b"\xff"] {
    assert_true(
      bind_client_local_adopted_host_material(store, () => {
        adopted_current_test_ok(
          adopted_current_test_observation(store, account_original=raw),
        )
      })
      is Err(InvalidOriginal),
    )
  }
}

///|
test "original physical identity retains the full unsigned Native device and inode range" {
  let store = Ref(0)
  let body = @utf8.encode(
    @utf8.decode(adopted_current_test_body)
    .replace(old="\"device\":\"7\"", new="\"device\":\"18446744073709551615\"")
    .replace(old="\"inode\":\"9\"", new="\"inode\":\"9223372036854775808\""),
  )
  let material = bind_client_local_adopted_host_material(store, () => {
    adopted_current_test_ok(
      adopted_current_test_observation(
        store,
        body~,
        generation=(0xFFFFFFFFFFFFFFFFUL, 0x8000000000000000UL),
      ),
    )
  }).unwrap()
  assert_true(client_local_adopted_current_account(material, store) is Ok(_))
}
