///|
fn wire_issue(body : String) -> WireIssue {
  match decode_account_configuration_json(body) {
    Err(MalformedWire(issue)) => issue
    _ => abort("expected a wire issue")
  }
}

///|
let wire_valid : String =
  #|{"version":"actql-execution-account-config/0.1","account_id":"cloud-service",
  #| "entries":[
  #|  {"entry_id":"cloud-delegate","outcome":"delegate",
  #|   "principal":{"all":true},"connection":{"all":true},
  #|   "resource":{"all":true},"operation":{"all":true},
  #|   "exclusions":[{"principal":{"all":true},"connection":{"all":true},
  #|                  "resource":{"any_of":["X","Y"]},"operation":{"all":true}}]},
  #|  {"entry_id":"system-deny","outcome":"deny",
  #|   "principal":{"all":true},"connection":{"all":true},
  #|   "resource":{"any_of":["Y","X"]},"operation":{"all":true},"exclusions":[]}],
  #| "bootstrap":{"profile_id":"local","profile_version":"0.1.0",
  #|   "profile_cid":"sha256:0000000000000000000000000000000000000000000000000000000000000000"}}

///|
test "wire configuration decodes and admits" {
  guard decode_account_configuration_json(wire_valid) is Ok(raw) else {
    abort("decode")
  }
  assert_eq(raw.account_id, "cloud-service")
  assert_eq(raw.entries.length(), 2)
  assert_eq(raw.entries[0].outcome, Delegate)
  assert_eq(raw.entries[0].scope.resource, All)
  assert_eq(raw.entries[0].exclusions[0].resource, AnyOf(["X", "Y"]))
  assert_eq(raw.entries[1].scope.resource, AnyOf(["Y", "X"]))
  assert_eq(raw.bootstrap.map(profile => profile.profile_id), Some("local"))
  guard admit_account_configuration_json(wire_valid) is Ok(admitted) else {
    abort("admit")
  }
  let tuple : AccessTuple = {
    principal: "p",
    connection: "c",
    resource: "Y",
    operation: "o",
  }
  assert_true(
    evaluate_account(admitted, tuple) is Deny(Explicit("system-deny")),
  )
}

///|
test "wire conflicts are reported through admission" {
  let body = wire_valid.replace(old="\"X\",\"Y\"]}", new="\"X\"]}")
  guard admit_account_configuration_json(body)
    is Err(ConflictingOutcomes(found)) else {
    abort("conflict")
  }
  assert_eq(found.witness.resource, Named("Y"))
}

///|
test "wire shape violations are rejected with a path" {
  assert_eq(wire_issue("{").kind, InvalidJson)
  assert_eq(
    wire_issue(
      wire_valid.replace(old="0.1\",\"account_id", new="0.2\",\"account_id"),
    ),
    { kind: UnsupportedVersion, path: "$.version", },
  )
  assert_eq(
    wire_issue(
      wire_valid.replace(
        old="\"outcome\":\"deny\"",
        new="\"outcome\":\"review\"",
      ),
    ),
    { kind: InvalidShape, path: "$.entries[1].outcome", },
  )
  assert_eq(
    wire_issue(
      wire_valid.replace(
        old="\"system-deny\",\"outcome\":\"deny\",\n   \"principal\":{\"all\":true}",
        new="\"system-deny\",\"outcome\":\"deny\",\n   \"principal\":{\"all\":false}",
      ),
    ),
    { kind: InvalidShape, path: "$.entries[1].principal.all", },
  )
  assert_eq(
    wire_issue(
      wire_valid.replace(
        old="\"resource\":{\"any_of\":[\"Y\",\"X\"]}",
        new="\"resource\":{\"any_of\":[\"Y\"],\"all\":true}",
      ),
    ).kind,
    InvalidShape,
  )
  assert_eq(
    wire_issue(
      wire_valid.replace(
        old="\"exclusions\":[]",
        new="\"exclusions\":[],\"priority\":1",
      ),
    ).kind,
    InvalidShape,
  )
  assert_eq(wire_issue(wire_valid.replace(old=",\"exclusions\":[]", new="")), {
    kind: InvalidShape,
    path: "$.entries[1].exclusions",
  })
  assert_eq(
    wire_issue(
      "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"a\",\"entries\":[],\"bootstrap\":null}",
    ),
    { kind: InvalidShape, path: "$.bootstrap", },
  )
  assert_eq(
    wire_issue(wire_valid.replace(old="[\"Y\",\"X\"]", new="[\"Y\",1]")),
    { kind: InvalidShape, path: "$.entries[1].resource.any_of[1]", },
  )
}

///|
test "wire bounds are enforced before admission" {
  let large = "{\"pad\":\"" + "x".repeat(MAX_CONFIG_INPUT_BYTES) + "\"}"
  assert_eq(wire_issue(large).kind, InputTooLarge)
  let long_name = "n".repeat(MAX_NAME_LENGTH * 4 + 1)
  assert_eq(
    wire_issue(wire_valid.replace(old="cloud-service", new=long_name)).kind,
    InvalidShape,
  )
  let entry = "{\"entry_id\":\"e\",\"outcome\":\"allow\",\"principal\":{\"all\":true},\"connection\":{\"all\":true},\"resource\":{\"all\":true},\"operation\":{\"all\":true},\"exclusions\":[]}"
  let entries = Array::make(MAX_ENTRIES + 1, entry).join(",")
  let body = "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"a\",\"entries\":[" +
    entries +
    "]}"
  assert_eq(wire_issue(body), { kind: InvalidShape, path: "$.entries", })
  let exclusion = "{\"principal\":{\"all\":true},\"connection\":{\"all\":true},\"resource\":{\"all\":true},\"operation\":{\"all\":true}}"
  let many = Array::make(MAX_EXCLUSIONS_PER_ENTRY + 1, exclusion).join(",")
  let with_many = "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"a\",\"entries\":[" +
    entry.replace(old="\"exclusions\":[]", new="\"exclusions\":[" + many + "]") +
    "]}"
  assert_eq(wire_issue(with_many), {
    kind: InvalidShape,
    path: "$.entries[0].exclusions",
  })
  // Maximum structural nesting is accepted at the depth bound.
  let nested = "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"a\",\"entries\":[" +
    entry.replace(
      old="\"exclusions\":[]",
      new="\"exclusions\":[{\"principal\":{\"any_of\":[\"p\"]},\"connection\":{\"all\":true},\"resource\":{\"all\":true},\"operation\":{\"all\":true}}]",
    ) +
    "]}"
  assert_true(admit_account_configuration_json(nested) is Ok(_))
  assert_eq(
    wire_issue(nested.replace(old="[\"p\"]", new="[[\"p\"]]")).kind,
    InvalidJson,
  )
}

///|
test "wire admission rejects malformed selectors" {
  assert_eq(
    admit_account_configuration_json(
      wire_valid.replace(old="[\"Y\",\"X\"]", new="[]"),
    ).map(_ => ()),
    Err(EmptyAnyOf("system-deny", Scope(Resource))),
  )
  assert_eq(
    admit_account_configuration_json(
      wire_valid.replace(old="[\"Y\",\"X\"]", new="[\"X\",\"X\"]"),
    ).map(_ => ()),
    Err(DuplicateSelectorValue("system-deny", Scope(Resource), "X")),
  )
}
