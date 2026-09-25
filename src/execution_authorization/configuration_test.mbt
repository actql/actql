///|
fn any(values : Array[String]) -> Selector {
  AnyOf(values)
}

///|
fn box4(
  principal : Selector,
  connection : Selector,
  resource : Selector,
  operation : Selector,
) -> SelectorBox {
  { principal, connection, resource, operation, }
}

///|
fn everything() -> SelectorBox {
  box4(All, All, All, All)
}

///|
fn resources(values : Array[String]) -> SelectorBox {
  box4(All, All, any(values), All)
}

///|
fn entry(
  entry_id : String,
  outcome : ConfiguredOutcome,
  scope : SelectorBox,
  exclusions? : Array[SelectorBox] = [],
) -> RawAccountEntry {
  { entry_id, outcome, scope, exclusions, }
}

///|
fn config(entries : Array[RawAccountEntry]) -> RawAccountConfiguration {
  { account_id: "local-operator", entries, bootstrap: None, }
}

///|
fn at(
  resource : String,
  principal? : String = "p",
  connection? : String = "c",
  operation? : String = "read",
) -> AccessTuple {
  { principal, connection, resource, operation, }
}

///|
fn admit_ok(raw : RawAccountConfiguration) -> AdmittedAccountConfiguration {
  match admit_account_configuration(raw) {
    Ok(value) => value
    Err(_) => abort("expected admission")
  }
}

///|
fn checked(raw : RawAccountConfiguration) -> Result[Unit, ConfigurationIssue] {
  admit_account_configuration(raw).map(_ => ())
}

///|
fn conflict(raw : RawAccountConfiguration) -> OutcomeConflict {
  match admit_account_configuration(raw) {
    Err(ConflictingOutcomes(found)) => found
    _ => abort("expected an outcome conflict")
  }
}

///|
test "design 13a: delegate all except X conflicts with deny X,Y at Y" {
  let found = conflict(
    config([
      entry("cloud-delegate", Delegate, everything(), exclusions=[
        resources(["X"]),
      ]),
      entry("system-deny", Deny, resources(["X", "Y"])),
    ]),
  )
  assert_eq(found.first_entry_id, "cloud-delegate")
  assert_eq(found.first_outcome, Delegate)
  assert_eq(found.second_entry_id, "system-deny")
  assert_eq(found.second_outcome, Deny)
  assert_eq(found.witness.resource, Named("Y"))
  assert_eq(found.witness.principal, AnyOtherThan([]))
  assert_eq(
    found.witness.describe(),
    "principal=<any value> connection=<any value> resource=\"Y\" operation=<any value>",
  )
}

///|
test "design 13b: delegate all except X,Y and deny X,Y are disjoint" {
  let admitted = admit_ok(
    config([
      entry("system-deny", Deny, resources(["X", "Y"])),
      entry("cloud-delegate", Delegate, everything(), exclusions=[
        resources(["X", "Y"]),
      ]),
    ]),
  )
  assert_true(
    evaluate_account(admitted, at("X")) is Deny(Explicit("system-deny")),
  )
  assert_true(
    evaluate_account(admitted, at("Y")) is Deny(Explicit("system-deny")),
  )
  guard evaluate_account(admitted, at("not-yet-discovered"))
    is Delegate(delegated) else {
    abort("delegate")
  }
  assert_eq(delegated.entry_id, "cloud-delegate")
  assert_eq(delegated.account_id, "local-operator")
  assert_eq(delegated.tuple, at("not-yet-discovered"))
}

///|
test "design 14: allow X against explicit deny X is an error; against no-match it is valid" {
  let found = conflict(
    config([
      entry("deny-x", Deny, resources(["X"])),
      entry("allow-x", Allow, resources(["X"])),
    ]),
  )
  assert_eq(found.first_entry_id, "allow-x")
  assert_eq(found.second_entry_id, "deny-x")
  assert_eq(found.witness.resource, Named("X"))
  let only_allow = admit_ok(config([entry("allow-x", Allow, resources(["X"]))]))
  assert_true(evaluate_account(only_allow, at("X")) is Allow("allow-x"))
  assert_true(evaluate_account(only_allow, at("Y")) is Deny(NoMatch))
}

///|
test "entry order never resolves a conflict" {
  let forward = checked(
    config([entry("b", Allow, resources(["X"])), entry("a", Deny, everything())]),
  )
  let backward = checked(
    config([entry("a", Deny, everything()), entry("b", Allow, resources(["X"]))]),
  )
  assert_true(forward is Err(ConflictingOutcomes(_)))
  assert_eq(forward, backward)
}

///|
test "no-match denial is distinct from explicit denial" {
  let admitted = admit_ok(
    config([
      entry("deny-secrets", Deny, resources(["secrets"])),
      entry("allow-reports", Allow, resources(["reports"])),
    ]),
  )
  assert_true(
    evaluate_account(admitted, at("secrets")) is Deny(Explicit("deny-secrets")),
  )
  assert_true(evaluate_account(admitted, at("other")) is Deny(NoMatch))
  assert_true(
    evaluate_account(admitted, at("reports")) is Allow("allow-reports"),
  )
}

///|
test "tuple exclusions carve non-Cartesian scopes; per-dimension overlap is not a conflict" {
  let pair = fn(c : String, r : String) { box4(All, any([c]), any([r]), All) }
  let grid = box4(All, any(["A", "B"]), any(["X", "Y"]), All)
  let admitted = admit_ok(
    config([
      entry("allow-diagonal", Allow, grid, exclusions=[
        pair("A", "X"),
        pair("B", "Y"),
      ]),
      entry("deny-antidiagonal", Deny, grid, exclusions=[
        pair("A", "Y"),
        pair("B", "X"),
      ]),
    ]),
  )
  let t = fn(c : String, r : String) { at(r, connection=c) }
  assert_true(
    evaluate_account(admitted, t("A", "Y")) is Allow("allow-diagonal"),
  )
  assert_true(
    evaluate_account(admitted, t("B", "X")) is Allow("allow-diagonal"),
  )
  assert_true(
    evaluate_account(admitted, t("A", "X"))
    is Deny(Explicit("deny-antidiagonal")),
  )
  assert_true(
    evaluate_account(admitted, t("B", "Y"))
    is Deny(Explicit("deny-antidiagonal")),
  )
  assert_true(evaluate_account(admitted, t("C", "X")) is Deny(NoMatch))
  // Leaving one cell uncovered by both exclusion lists is a conflict there.
  let found = conflict(
    config([
      entry("allow-diagonal", Allow, grid, exclusions=[pair("A", "X")]),
      entry("deny-antidiagonal", Deny, grid, exclusions=[
        pair("A", "Y"),
        pair("B", "X"),
      ]),
    ]),
  )
  assert_eq(found.witness.connection, Named("B"))
  assert_eq(found.witness.resource, Named("Y"))
}

///|
test "broad selectors include unseen values; finite selectors do not" {
  let admitted = admit_ok(
    config([
      entry("local-all", Allow, box4(All, any(["local"]), All, All)),
      entry(
        "remote-reads",
        Delegate,
        box4(All, any(["remote"]), All, any(["read"])),
      ),
    ]),
  )
  assert_true(
    evaluate_account(admitted, at("brand-new-table", connection="local"))
    is Allow("local-all"),
  )
  assert_true(
    evaluate_account(admitted, at("r", connection="local", operation="new-op"))
    is Allow("local-all"),
  )
  assert_true(
    evaluate_account(admitted, at("r", connection="new-connection"))
    is Deny(NoMatch),
  )
  assert_true(
    evaluate_account(admitted, at("r", connection="remote", operation="delete"))
    is Deny(NoMatch),
  )
  assert_true(
    evaluate_account(admitted, at("r", connection="remote")) is Delegate(_),
  )
}

///|
test "all-minus-all exclusion leaves an entry without effect" {
  let admitted = admit_ok(
    config([
      entry("empty", Allow, everything(), exclusions=[everything()]),
      entry("deny", Deny, everything()),
    ]),
  )
  assert_true(evaluate_account(admitted, at("x")) is Deny(Explicit("deny")))
}

///|
test "same-outcome overlap is admitted and reports the least entry id" {
  let admitted = admit_ok(
    config([
      entry(
        "z-reports",
        Allow,
        box4(All, any(["c", "x"]), any(["reports"]), All),
      ),
      entry("m-local", Allow, box4(All, any(["c"]), All, All)),
      entry("deny-other", Deny, box4(All, any(["d"]), All, All)),
    ]),
  )
  assert_eq(admitted.entry_count(), 3)
  assert_true(evaluate_account(admitted, at("reports")) is Allow("m-local"))
  assert_true(
    evaluate_account(admitted, at("reports", connection="x"))
    is Allow("z-reports"),
  )
  // A different outcome overlapping either same-outcome entry still conflicts.
  let found = conflict(
    config([
      entry("z-reports", Allow, resources(["reports"])),
      entry("m-local", Allow, box4(All, any(["c"]), All, All)),
      entry("deny-d", Deny, box4(All, any(["d"]), All, All)),
    ]),
  )
  assert_eq(found.first_entry_id, "deny-d")
  assert_eq(found.second_entry_id, "z-reports")
  assert_eq(found.witness.connection, Named("d"))
  assert_eq(found.witness.resource, Named("reports"))
}

///|
test "allow versus delegate overlap is also a conflict" {
  let found = conflict(
    config([
      entry("a", Allow, everything()),
      entry("d", Delegate, box4(any(["svc"]), All, All, All), exclusions=[
        box4(All, All, All, any(["read"])),
      ]),
    ]),
  )
  assert_eq(found.witness.principal, Named("svc"))
  assert_eq(found.witness.operation, AnyOtherThan(["read"]))
  assert_eq(
    found.witness.describe(),
    "principal=\"svc\" connection=<any value> resource=<any value> operation=<any value other than \"read\">",
  )
}

///|
test "malformed configurations are rejected" {
  let ok = entry("e", Allow, everything())
  assert_eq(checked({ ..config([ok]), account_id: "", }), Err(InvalidAccountId))
  assert_eq(
    checked(config([ok, entry("", Deny, everything())])),
    Err(InvalidEntryId(1)),
  )
  assert_eq(
    checked(config([ok, entry("e", Allow, resources(["x"]))])),
    Err(DuplicateEntryId("e")),
  )
  assert_eq(
    checked(config([entry("e", Allow, resources([]))])),
    Err(EmptyAnyOf("e", Scope(Resource))),
  )
  assert_eq(
    checked(
      config([
        entry("e", Allow, everything(), exclusions=[
          box4(any([]), All, All, All),
        ]),
      ]),
    ),
    Err(EmptyAnyOf("e", Exclusion(0, Principal))),
  )
  assert_eq(
    checked(config([entry("e", Allow, resources(["b", "a", "b"]))])),
    Err(DuplicateSelectorValue("e", Scope(Resource), "b")),
  )
  assert_eq(
    checked(config([entry("e", Allow, resources(["a", ""]))])),
    Err(InvalidSelectorValue("e", Scope(Resource))),
  )
  let too_many = Array::makei(MAX_SELECTOR_VALUES + 1, i => "v\{i}")
  assert_eq(
    checked(config([entry("e", Allow, resources(too_many))])),
    Err(SelectorTooLarge("e", Scope(Resource))),
  )
  let exclusions = Array::make(MAX_EXCLUSIONS_PER_ENTRY + 1, resources(["x"]))
  assert_eq(
    checked(config([entry("e", Allow, everything(), exclusions~)])),
    Err(TooManyExclusions("e")),
  )
  let entries = Array::makei(MAX_ENTRIES + 1, i => {
    entry("e\{i}", Allow, everything())
  })
  assert_eq(checked(config(entries)), Err(TooManyEntries(MAX_ENTRIES + 1)))
  assert_eq(
    checked({
      ..config([ok]),
      bootstrap: Some({
        profile_id: "p",
        profile_version: "1",
        profile_cid: "sha256:00",
      }),
    }),
    Err(InvalidBootstrapProfile),
  )
  // Value order is not significant.
  let left = admit_ok(config([entry("e", Allow, resources(["b", "a"]))]))
  assert_true(evaluate_account(left, at("a")) is Allow("e"))
}

///|
test "an empty configuration and a missing configuration both deny" {
  let empty = admit_ok(config([]))
  assert_true(evaluate_account(empty, at("x")) is Deny(NoMatch))
  assert_true(
    evaluate_account_state(Missing, at("x")) is Deny(ConfigurationMissing),
  )
  assert_true(evaluate_account_state(Admitted(empty), at("x")) is Deny(NoMatch))
}

///|
test "bootstrap provenance binds to a Host adoption record" {
  let profile : BootstrapProfile = {
    profile_id: "actql-local-initial",
    profile_version: "0.1.0",
    profile_cid: "sha256:" + "a".repeat(64),
  }
  let raw = {
    ..config([entry("work-area", Allow, resources(["workspace"]))]),
    bootstrap: Some(profile),
  }
  let admitted = admit_ok(raw)
  assert_eq(admitted.bootstrap_profile(), Some(profile))
  let record : BootstrapAdoptionRecord = {
    record_id: "adoption-1",
    account_id: "local-operator",
    profile,
  }
  guard bind_bootstrap_adoption(admitted, record) is Ok(bound) else {
    abort("bind")
  }
  assert_eq(bound.adoption, record)
  assert_eq(bound.configuration.account_id(), "local-operator")
  assert_eq(
    bind_bootstrap_adoption(admitted, {
      ..record,
      profile: { ..profile, profile_version: "0.2.0", },
    }).map(_ => ()),
    Err(ProfileMismatch),
  )
  assert_eq(
    bind_bootstrap_adoption(admitted, { ..record, account_id: "other", }).map(_ => {
      ()
    }),
    Err(AccountMismatch),
  )
  assert_eq(
    bind_bootstrap_adoption(admitted, { ..record, record_id: "", }).map(_ => ()),
    Err(InvalidAdoptionRecord),
  )
  assert_eq(
    bind_bootstrap_adoption(admit_ok(config([])), record).map(_ => ()),
    Err(ConfigurationWithoutBootstrapProfile),
  )
}
