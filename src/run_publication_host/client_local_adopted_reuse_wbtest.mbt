///|
test "one original material keeps independent scope run and result current observations" {
  let store = Ref(0)
  let calls = Ref(0)
  let material = bind_client_local_adopted_host_material(store, () => {
    calls.val += 1
    adopted_current_test_ok(adopted_current_test_observation(store))
  }).unwrap()
  client_local_adopted_authority_scope_body(
    material, store, "operator", "local-files",
  ).unwrap()
  |> ignore
  for resource in ["run", "result/answer"] {
    assert_true(
      client_local_adopted_account_outcome(material, store, {
        principal: "operator",
        connection: "local-files",
        resource,
        operation: "read",
      })
      is Ok(@authorization.Allow(_)),
    )
  }
  // Each boundary observes once; pure scope/evaluation has no hidden callback.
  assert_eq(calls.val, 4)
}

///|
test "retained material never carries an earlier Allow across a failed current observation" {
  let store = Ref(0)
  for refuse_at in 2..<=4 {
    let calls = Ref(0)
    let material = bind_client_local_adopted_host_material(store, () => {
      calls.val += 1
      if calls.val == refuse_at {
        Err("current unavailable")
      } else {
        adopted_current_test_ok(adopted_current_test_observation(store))
      }
    }).unwrap()
    let scope = client_local_adopted_authority_scope_body(
      material, store, "operator", "local-files",
    )
    if refuse_at == 2 {
      assert_true(scope is Err(Physical("current unavailable")))
      continue
    }
    assert_true(scope is Ok(_))
    let run = client_local_adopted_account_outcome(material, store, {
      principal: "operator",
      connection: "local-files",
      resource: "run",
      operation: "read",
    })
    if refuse_at == 3 {
      assert_true(run is Err(Physical("current unavailable")))
      continue
    }
    assert_true(run is Ok(@authorization.Allow(_)))
    assert_true(
      client_local_adopted_account_outcome(material, store, {
        principal: "operator",
        connection: "local-files",
        resource: "result/answer",
        operation: "read",
      })
      is Err(Physical("current unavailable")),
    )
  }
}
