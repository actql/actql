///|
test "saved plan presentation is byte identical and refuses foreign scope before funding" {
  let host = policy_host_fixture("saved-plan-presentation")
  let crypto = epoch_test_crypto()
  original_selection_fixture(host, "presentation-nonce", "presentation-run")
  |> ignore
  let saved = host
    .lookup_submitted_run_plan_by_id(
      crypto, "operator", "cli", "presentation-run",
    )
    .unwrap()
  let scope = saved.original.scope
  let mut calls = 0
  let mut quoted = (0L, 0L, 0L)
  let reserve = (r, e, raw) => {
    quoted = (r, e, raw)
    calls += 1
    Ok(())
  }
  let actual = native_saved_plan_reply(saved, scope, reserve).unwrap()
  let run_namespace = @publication.publication_contract_run_definition_scope(
    saved.original.definition,
  ).unwrap()
  let expected : Json = {
    "plan_view": @json.parse(saved.view),
    "run_ref": {
      "authorityScopeCid": scope,
      "namespaceId": run_namespace,
      "runDefinitionCid": @publication.publication_contract_identity(
        saved.original.definition,
      ),
    },
    "version": "actql-run-plan-view/0.1",
  }
  let expected = @canonical.from_json(expected, 8192, 64, 65536, data_keys=true)
  assert_eq(actual, @canonical.stringify_value(expected, 65536, 8192, 64))
  assert_eq(calls, 1)
  assert_true(quoted.0 > 0L && quoted.1 >= quoted.0 && quoted.2 > 0L)
  assert_true(
    native_saved_plan_reply(saved, "sha256:" + "f".repeat(64), reserve)
    is Err(ForeignRun),
  )
  assert_eq(calls, 1)
  host.close().unwrap()
}

///|
test "saved plan presentation reserves before emitting oversized private views and preserves refusal" {
  let host = policy_host_fixture("saved-plan-presentation-large")
  let crypto = epoch_test_crypto()
  original_selection_fixture(
    host, "presentation-large-nonce", "presentation-large-run",
  )
  |> ignore
  let saved = host
    .lookup_submitted_run_plan_by_id(
      crypto, "operator", "cli", "presentation-large-run",
    )
    .unwrap()
  // Whitebox geometry fixture only: production has no raw-wire holder factory.
  // This does not establish full large-plan provenance or cold admission.
  let saved = {
    ..saved,
    view: "{\"text\":\"" + "あ😀\\\"".repeat(12000) + "\"}",
  }
  let mut calls = 0
  let refusal = native_saved_plan_reply(saved, saved.original.scope, (_, _, _) => {
    calls += 1
    Err(CapacityExceeded)
  })
  assert_true(refusal is Err(CapacityExceeded))
  assert_eq(calls, 1)
  let mut quoted = (0L, 0L, 0L)
  let wire = native_saved_plan_reply(saved, saved.original.scope, (r, e, raw) => {
    quoted = (r, e, raw)
    Ok(())
  }).unwrap()
  assert_true(quoted.0 > 65536L && quoted.1 >= quoted.0 && quoted.2 > 65536L)
  assert_true(wire.has_prefix("{\"plan_view\":" + saved.view + ",\"run_ref\":"))
  guard @json.parse(wire) is Object(fields) else { fail("expected envelope") }
  assert_eq(fields.get("plan_view"), Some(@json.parse(saved.view)))
  host.close().unwrap()
}

///|
test "saved plan reference preserves canonical escaped Unicode run_namespace" {
  let host = policy_host_fixture("saved-plan-presentation-unicode")
  let crypto = epoch_test_crypto()
  original_selection_fixture(
    host, "presentation-unicode-nonce", "presentation-unicode-run",
  )
  |> ignore
  let saved = host
    .lookup_submitted_run_plan_by_id(
      crypto, "operator", "cli", "presentation-unicode-run",
    )
    .unwrap()
  guard @json.parse(
      @publication.publication_contract_json(saved.original.definition),
    )
    is Object(fields) else {
    fail("expected definition")
  }
  fields.remove("run_definition_cid")
  let run_namespace = "日本語😀\"\\"
  fields["scope_id"] = Json::string(run_namespace)
  let body = @canonical.stringify_value(
    @canonical.from_json(Json::object(fields), 64, 4, 8192, data_keys=true),
    8192,
    64,
    4,
  )
  let definition = @publication.seal_publication_contract(
    "run_definition", body, 8192, 64, 4,
  ).unwrap()
  let saved = { ..saved, original: { ..saved.original, definition, }, }
  let wire = native_saved_plan_reply(saved, saved.original.scope, (_, _, _) => {
    Ok(())
  }).unwrap()
  guard @json.parse(wire) is Object(envelope) &&
    envelope.get("run_ref") is Some(Object(reference)) else {
    fail("expected Run reference")
  }
  assert_eq(reference.get("namespaceId"), Some(Json::string(run_namespace)))
  let expected = @canonical.from_json(
    @json.parse(wire),
    8192,
    64,
    65536,
    data_keys=true,
  )
  assert_eq(wire, @canonical.stringify_value(expected, 65536, 8192, 64))
  host.close().unwrap()
}
