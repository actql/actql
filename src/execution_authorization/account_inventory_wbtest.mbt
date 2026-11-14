///|
fn account_inventory_name(prefix : String, index : Int) -> String {
  let suffix = index.to_string()
  prefix + "0".repeat(4 - suffix.length()) + suffix
}

///|
fn account_inventory_scope(resources : Selector) -> SelectorBox {
  { principal: All, connection: All, resource: resources, operation: All, }
}

///|
fn account_inventory_entry(index : Int) -> RawAccountEntry {
  {
    entry_id: account_inventory_name("entry-", index),
    outcome: Allow,
    scope: account_inventory_scope(All),
    exclusions: [],
  }
}

///|
fn account_inventory_raw(
  entries : Array[RawAccountEntry],
) -> RawAccountConfiguration {
  { account_id: "inventory-account", bootstrap: None, entries, }
}

///|
// Independent ASCII fixture spelling, never a product canonical encoder.
fn account_inventory_selector_wire(selector : Selector) -> String {
  match selector {
    All => "{\"all\":true}"
    AnyOf(values) =>
      "{\"any_of\":[" +
      values.map(value => "\"" + value + "\"").join(",") +
      "]}"
  }
}

///|
fn account_inventory_box_wire(box : SelectorBox) -> String {
  "\"principal\":" +
  account_inventory_selector_wire(box.principal) +
  ",\"connection\":" +
  account_inventory_selector_wire(box.connection) +
  ",\"resource\":" +
  account_inventory_selector_wire(box.resource) +
  ",\"operation\":" +
  account_inventory_selector_wire(box.operation)
}

///|
fn account_inventory_wire(entries : Array[RawAccountEntry]) -> String {
  let rows = entries.map(entry => {
    let exclusions = entry.exclusions
      .map(box => "{" + account_inventory_box_wire(box) + "}")
      .join(",")
    "{\"entry_id\":\"" +
    entry.entry_id +
    "\",\"outcome\":\"allow\"," +
    account_inventory_box_wire(entry.scope) +
    ",\"exclusions\":[" +
    exclusions +
    "]}"
  })
  "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"inventory-account\",\"entries\":[" +
  rows.join(",") +
  "]}"
}

///|
fn account_inventory_at(resource : String) -> AccessTuple {
  {
    principal: "operator",
    connection: "connection",
    resource,
    operation: "read",
  }
}

///|
test "Account observed inventory admits 1025 original entries and rejects a late duplicate" {
  let entries = Array::makei(1025, account_inventory_entry)
  let raw = admit_account_configuration(account_inventory_raw(entries)).unwrap()
  let wire = account_inventory_wire(entries)
  assert_true(wire.length() < MAX_CONFIG_INPUT_BYTES)
  let decoded = admit_account_configuration_json(wire).unwrap()
  assert_eq(raw.entry_count(), 1025)
  assert_eq(decoded.entry_count(), 1025)
  assert_eq(raw.configuration_cid(), decoded.configuration_cid())
  assert_true(decoded.retains_original_bytes(@utf8.encode(wire)))
  assert_true(
    evaluate_account(decoded, account_inventory_at("unlisted"))
    is Allow("entry-0000"),
  )
  entries.push(account_inventory_entry(1024))
  assert_true(
    admit_account_configuration(account_inventory_raw(entries))
    is Err(DuplicateEntryId("entry-1024")),
  )
}

///|
test "Account observed inventory retains all 257 selector values without widening their scope" {
  let names = Array::makei(257, index => {
    account_inventory_name("resource-", index)
  })
  let entry = {
    ..account_inventory_entry(0),
    scope: account_inventory_scope(AnyOf(names)),
  }
  let raw = admit_account_configuration(account_inventory_raw([entry])).unwrap()
  let decoded = admit_account_configuration_json(
    account_inventory_wire([entry]),
  ).unwrap()
  assert_eq(raw.configuration_cid(), decoded.configuration_cid())
  assert_true(
    evaluate_account(decoded, account_inventory_at("resource-0256"))
    is Allow("entry-0000"),
  )
  assert_true(
    evaluate_account(decoded, account_inventory_at("resource-0257"))
    is Deny(NoMatch),
  )
  names.push("resource-0256")
  assert_true(
    admit_account_configuration(
      account_inventory_raw([
        { ..entry, scope: account_inventory_scope(AnyOf(names)), },
      ]),
    )
    is Err(
      DuplicateSelectorValue("entry-0000", Scope(Resource), "resource-0256")
    ),
  )
}

///|
test "Account observed inventory retains 65 exclusions and their exact denied tuples" {
  let exclusions = Array::makei(65, index => {
    account_inventory_scope(AnyOf([account_inventory_name("resource-", index)]))
  })
  let entry = { ..account_inventory_entry(0), exclusions, }
  let raw = admit_account_configuration(account_inventory_raw([entry])).unwrap()
  let decoded = admit_account_configuration_json(
    account_inventory_wire([entry]),
  ).unwrap()
  assert_eq(raw.configuration_cid(), decoded.configuration_cid())
  assert_true(
    evaluate_account(decoded, account_inventory_at("resource-0064"))
    is Deny(NoMatch),
  )
  assert_true(
    evaluate_account(decoded, account_inventory_at("resource-0065"))
    is Allow("entry-0000"),
  )
  exclusions.push(exclusions[64])
  assert_true(
    admit_account_configuration(
      account_inventory_raw([{ ..entry, exclusions, }]),
    )
    is Err(DuplicateExclusion(_, _)),
  )
}

///|
test "Account observed inventory retains 257 original answering authorities and claims" {
  let raw = { ..account_inventory_entry(0), outcome: Delegate, }
  let account = admit_account_configuration(account_inventory_raw([raw])).unwrap()
  guard evaluate_account(account, account_inventory_at("resource"))
    is Delegate(original) else {
    fail("same original delegated match required")
  }
  let names = Array::makei(257, index => {
    account_inventory_name("authority-", index)
  })
  let prepare = (authorities : Array[String]) => {
    prepare_decision_request(
      original,
      configuration_cid=account.configuration_cid(),
      boundary=Acquisition,
      subject_cid="sha256:" + "1".repeat(64),
      context_cid="sha256:" + "2".repeat(64),
      answering_authorities=authorities,
      required_claims=names,
    )
  }
  let request = prepare(names).unwrap()
  assert_eq(request.answering_authorities(), names)
  assert_eq(request.required_claims(), names)
  assert_eq(request.subject().entry_id, "entry-0000")
  names.push("authority-0256")
  assert_true(
    prepare(names) is Err(DuplicateAnsweringAuthority("authority-0256")),
  )
}

///|
test "Account observed inventory subtracts 4097 exclusions with the same exact work and witness" {
  let region : Region = { dims: FixedArray::make(4, Cofinite([])), }
  let exclusions : Array[Region] = Array::makei(4097, index => {
    let dims = FixedArray::make(4, Cofinite([]))
    dims[2] = Finite([account_inventory_name("resource-", index)])
    { dims, }
  })
  let budget = Ref(10000000)
  guard uncovered_region(region, exclusions, 0, budget) is Some(remaining) else {
    fail("unlisted tuple must remain outside every exact exclusion")
  }
  // Each visited region costs 2 + its prior exclusion count:
  // sum(i + 2, i=0..4096) = 8,398,850, independent of the implementation.
  assert_eq(budget.val, 1601150)
  assert_true(!remaining.contains(account_inventory_at("resource-0000")))
  assert_true(!remaining.contains(account_inventory_at("resource-4096")))
  assert_true(remaining.contains(account_inventory_at("resource-5000")))
  let exhausted = try {
    ignore(uncovered_region(region, exclusions, 0, Ref(1)))
    false
  } catch {
    OverlapBudgetExhausted => true
  }
  assert_true(exhausted)
  let pairs = account_inventory_raw([
    account_inventory_entry(0),
    account_inventory_entry(1),
  ])
  assert_true(
    admit_with_overlap_budget(pairs, 0)
    is Err(OverlapCheckBudgetExceeded("entry-0000", "entry-0001")),
  )
  assert_true(admit_with_overlap_budget(pairs, 1) is Ok(_))
}
