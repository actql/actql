///|
// Exact rejected input from the first physical Adoption attempt. Array order
// remains an Account wire requirement; the fixture must not relax admission.
let native_relation_account_original : String =
  #|{"account_id":"operator","entries":[{"connection":{"any_of":["cli"]},"entry_id":"fixture-run-control","exclusions":[],"operation":{"any_of":["read","submit","cancel"]},"outcome":"allow","principal":{"any_of":["machine-user"]},"resource":{"any_of":["run"]}},{"connection":{"any_of":["native-file-fixture"]},"entry_id":"fixture-records-read","exclusions":[],"operation":{"any_of":["read"]},"outcome":"allow","principal":{"any_of":["machine-user"]},"resource":{"any_of":["records"]}}],"version":"actql-execution-account-config/0.1"}

///|
// Independently authored ordering of the same two entries and selector sets.
let native_relation_account_canonical : String =
  #|{"account_id":"operator","entries":[{"connection":{"any_of":["native-file-fixture"]},"entry_id":"fixture-records-read","exclusions":[],"operation":{"any_of":["read"]},"outcome":"allow","principal":{"any_of":["machine-user"]},"resource":{"any_of":["records"]}},{"connection":{"any_of":["cli"]},"entry_id":"fixture-run-control","exclusions":[],"operation":{"any_of":["cancel","read","submit"]},"outcome":"allow","principal":{"any_of":["machine-user"]},"resource":{"any_of":["run"]}}],"version":"actql-execution-account-config/0.1"}

///|
test "Native relation Account original bytes refuse before adoption" {
  assert_eq(
    admit_account_configuration_json(native_relation_account_original).map(_ => {
      ()
    }),
    Err(NonCanonicalOrder("$.entries[1].entry_id")),
  )
  let entry_order_only : String =
    #|{"account_id":"operator","entries":[{"connection":{"any_of":["native-file-fixture"]},"entry_id":"fixture-records-read","exclusions":[],"operation":{"any_of":["read"]},"outcome":"allow","principal":{"any_of":["machine-user"]},"resource":{"any_of":["records"]}},{"connection":{"any_of":["cli"]},"entry_id":"fixture-run-control","exclusions":[],"operation":{"any_of":["read","submit","cancel"]},"outcome":"allow","principal":{"any_of":["machine-user"]},"resource":{"any_of":["run"]}}],"version":"actql-execution-account-config/0.1"}
  assert_eq(
    admit_account_configuration_json(entry_order_only).map(_ => ()),
    Err(NonCanonicalOrder("$.entries[1].operation.any_of[2]")),
  )
}

///|
test "Native relation canonical Account retains only separate Run and Source grants" {
  let admitted = admit_account_configuration_json(
    native_relation_account_canonical,
  ).unwrap()
  assert_eq(admitted.entry_count(), 2)
  for operation in ["cancel", "read", "submit"] {
    assert_true(
      evaluate_account(admitted, {
        principal: "machine-user",
        connection: "cli",
        resource: "run",
        operation,
      })
      is Allow(_),
    )
  }
  assert_true(
    evaluate_account(admitted, {
      principal: "machine-user",
      connection: "native-file-fixture",
      resource: "records",
      operation: "read",
    })
    is Allow(_),
  )
  for
    (principal, connection, resource, operation) in [
      ("operator", "cli", "run", "read"),
      ("machine-user", "cli", "records", "read"),
      ("machine-user", "native-file-fixture", "run", "read"),
      ("machine-user", "native-file-fixture", "records", "submit"),
      ("machine-user", "native-file-fixture", "records", "cancel"),
      ("machine-user", "different", "records", "read"),
      ("machine-user", "native-file-fixture", "different", "read"),
      ("machine-user", "cli", "run", "resolve"),
    ] {
    assert_true(
      evaluate_account(admitted, { principal, connection, resource, operation, })
      is Deny(_),
    )
  }
}
