///|
let canonical_config : String =
  #|{"version":"actql-execution-account-config/0.1","account_id":"acct",
  #| "entries":[
  #|  {"entry_id":"a","outcome":"delegate",
  #|   "principal":{"all":true},"connection":{"all":true},
  #|   "resource":{"all":true},"operation":{"all":true},
  #|   "exclusions":[
  #|    {"connection":{"all":true},"operation":{"all":true},"principal":{"all":true},"resource":{"any_of":["X"]}},
  #|    {"connection":{"any_of":["crm"]},"operation":{"all":true},"principal":{"all":true},"resource":{"all":true}}]},
  #|  {"entry_id":"b","outcome":"deny",
  #|   "principal":{"all":true},"connection":{"any_of":["crm","mail"]},
  #|   "resource":{"any_of":["X"]},"operation":{"all":true},"exclusions":[]}]}

///|
test "canonical wire spelling is admitted and identified" {
  let admitted = admit_account_configuration_json(canonical_config).unwrap()
  let cid = account_configuration_cid(admitted)
  assert_eq(admitted.configuration_cid(), cid)
  assert_eq(account_configuration_cid_json(canonical_config), Ok(cid))
  assert_true(cid.has_prefix("sha256:"))
}

///|
test "non-canonical wire order is rejected with its location" {
  // Exclusions ascend by their tuples' canonical JSON text:
  // {"connection":{"all":true},...} sorts before {"connection":{"any_of":...}}.
  let swapped = canonical_config
    .replace(
      old="{\"connection\":{\"all\":true},\"operation\":{\"all\":true},\"principal\":{\"all\":true},\"resource\":{\"any_of\":[\"X\"]}},",
      new="",
    )
    .replace(
      old="\"resource\":{\"all\":true}}]},",
      new="\"resource\":{\"all\":true}},{\"connection\":{\"all\":true},\"operation\":{\"all\":true},\"principal\":{\"all\":true},\"resource\":{\"any_of\":[\"X\"]}}]},",
    )
  assert_true(swapped != canonical_config)
  assert_eq(
    admit_account_configuration_json(swapped).map(_ => ()),
    Err(NonCanonicalOrder("$.entries[0].exclusions[1]")),
  )
  let values = canonical_config.replace(
    old="[\"crm\",\"mail\"]",
    new="[\"mail\",\"crm\"]",
  )
  assert_eq(
    admit_account_configuration_json(values).map(_ => ()),
    Err(NonCanonicalOrder("$.entries[1].connection.any_of[1]")),
  )
  let entries = canonical_config
    .replace(old="\"entry_id\":\"a\"", new="\"entry_id\":\"c\"")
    .replace(old="\"entry_id\":\"b\"", new="\"entry_id\":\"a\"")
  assert_eq(
    admit_account_configuration_json(entries).map(_ => ()),
    Err(NonCanonicalOrder("$.entries[1].entry_id")),
  )
  // Code-unit order, not code-point order: U+FF21 (one unit) sorts after
  // U+1F600 (surrogate pair starting 0xD83D).
  let supplementary = canonical_config.replace(
    old="[\"crm\",\"mail\"]",
    new="[\"\u{1F600}\",\"\u{FF21}\"]",
  )
  assert_true(admit_account_configuration_json(supplementary) is Ok(_))
  let reversed = canonical_config.replace(
    old="[\"crm\",\"mail\"]",
    new="[\"\u{FF21}\",\"\u{1F600}\"]",
  )
  assert_eq(
    admit_account_configuration_json(reversed).map(_ => ()),
    Err(NonCanonicalOrder("$.entries[1].connection.any_of[1]")),
  )
}

///|
test "identifiers are compared as NFC canonical text" {
  // The JSON source decoder admits every string as NFC/LF canonical text, so
  // a wire value is ordered and identified by its normalized form.
  let decomposed = canonical_config.replace(old="\"mail\"", new="\"n\u{0303}\"")
  let composed = canonical_config.replace(old="\"mail\"", new="\"\u{F1}\"")
  assert_eq(
    account_configuration_cid_json(decomposed),
    account_configuration_cid_json(composed),
  )
  assert_true(account_configuration_cid_json(composed) is Ok(_))
  // Two spellings of one identifier are one identifier.
  let duplicate = canonical_config.replace(
    old="[\"crm\",\"mail\"]",
    new="[\"\u{F1}\",\"n\u{0303}\"]",
  )
  assert_eq(
    admit_account_configuration_json(duplicate).map(_ => ()),
    Err(DuplicateSelectorValue("b", Scope(Connection), "\u{F1}")),
  )
  // A typed configuration must already carry canonical text.
  let raw = decode_account_configuration_json(canonical_config).unwrap()
  let entry = raw.entries[1]
  let typed = {
    ..raw,
    entries: [
      raw.entries[0],
      {
        ..entry,
        scope: { ..entry.scope, connection: AnyOf(["crm", "n\u{0303}"]), },
      },
    ],
  }
  assert_eq(
    admit_account_configuration(typed).map(_ => ()),
    Err(NonNormalizedText("$.entries[1].connection.any_of[1]")),
  )
  assert_eq(
    admit_account_configuration({ ..raw, account_id: "a\r\nb", }).map(_ => ()),
    Err(NonNormalizedText("$.account_id")),
  )
}

///|
test "duplicate exclusions are rejected" {
  let duplicated = canonical_config.replace(
    old="\"resource\":{\"any_of\":[\"X\"]}},",
    new="\"resource\":{\"any_of\":[\"X\"]}},{\"connection\":{\"all\":true},\"operation\":{\"all\":true},\"principal\":{\"all\":true},\"resource\":{\"any_of\":[\"X\"]}},",
  )
  assert_eq(
    admit_account_configuration_json(duplicated).map(_ => ()),
    Err(DuplicateExclusion("a", 1)),
  )
}

///|
test "typed configurations are identified by their canonical document" {
  let admitted = admit_account_configuration_json(canonical_config).unwrap()
  let raw = decode_account_configuration_json(canonical_config).unwrap()
  // Reorder entries, selector values and exclusions: same identity.
  let shuffled : RawAccountConfiguration = {
    ..raw,
    entries: raw.entries
    .rev()
    .map(entry => {
      ..entry,
      scope: {
        ..entry.scope,
        connection: match entry.scope.connection {
          AnyOf(values) => AnyOf(values.rev())
          All => All
        },
      },
      exclusions: entry.exclusions.rev(),
    }),
  }
  assert_true(shuffled != raw)
  let typed = admit_account_configuration(shuffled).unwrap()
  assert_eq(
    account_configuration_cid(typed),
    account_configuration_cid(admitted),
  )
  let other = admit_account_configuration({ ..raw, account_id: "other", }).unwrap()
  assert_true(
    account_configuration_cid(other) != account_configuration_cid(admitted),
  )
}

///|
test "admission outcomes map to the pinned error codes" {
  let admitted = admit_account_configuration_json(canonical_config).unwrap()
  let denied = evaluate_account(admitted, {
    principal: "p",
    connection: "crm",
    resource: "X",
    operation: "o",
  })
  guard runtime_action_for(denied) is Some(action) else { fail("deny") }
  assert_eq(runtime_action_error_code(action), Some("ACTQL_E_ACCOUNT_DENIED"))
  let unmatched = evaluate_account(admitted, {
    principal: "p",
    connection: "crm",
    resource: "Y",
    operation: "o",
  })
  guard runtime_action_for(unmatched) is Some(no_match) else {
    fail("no match")
  }
  assert_eq(
    runtime_action_error_code(no_match),
    Some("ACTQL_E_ACCOUNT_NO_MATCH"),
  )
  assert_eq(
    deny_reason_error_code(ConfigurationMissing),
    "ACTQL_E_ACCOUNT_CONFIG_INVALID",
  )
  assert_eq(
    configuration_issue_error_code(InvalidAccountId),
    ACCOUNT_CONFIG_INVALID_CODE,
  )
  assert_eq(
    decision_failure_error_code(Timeout),
    "ACTQL_E_DELEGATION_UNAVAILABLE",
  )
  let delegated = evaluate_account(admitted, {
    principal: "p",
    connection: "files",
    resource: "Y",
    operation: "o",
  })
  guard delegated is Delegate(found) else { fail("delegate") }
  assert_eq(runtime_action_for(delegated), None)
  let request = prepare_decision_request(
    found,
    configuration_cid=account_configuration_cid(admitted),
    boundary=Acquisition,
    subject_cid="sha256:" + "1".repeat(64),
    context_cid="sha256:" + "2".repeat(64),
    answering_authorities=["alice"],
  ).unwrap()
  let binding : AnswerBinding = {
    subject: request.subject(),
    authority: "alice",
  }
  let rejected = admit_host_answer(request, Reject(binding)).unwrap()
  assert_eq(
    runtime_action_error_code(rejected),
    Some("ACTQL_E_DELEGATION_REJECTED"),
  )
  let failed = admit_host_answer(request, Failure(Unavailable)).unwrap()
  assert_eq(
    runtime_action_error_code(failed),
    Some(DELEGATION_UNAVAILABLE_CODE),
  )
  let deferred = admit_host_answer(request, Defer(request.subject())).unwrap()
  assert_eq(runtime_action_error_code(deferred), None)
  let permitted = admit_host_answer(request, Permit(binding, [])).unwrap()
  assert_eq(runtime_action_error_code(permitted), None)
}
