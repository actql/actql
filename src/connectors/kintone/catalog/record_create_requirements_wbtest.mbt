///|
test "CREATE required fields use positive original flags and never substitute defaults" {
  let catalog = eligibility_catalog(
    (
      #|{"required":{"type":"SINGLE_LINE_TEXT","code":"required","expression":"","required":true,"defaultValue":"server"},"optional":{"type":"MULTI_LINE_TEXT","code":"optional","required":false,"defaultValue":"server"},"radio":{"type":"RADIO_BUTTON","code":"radio","required":true,"defaultValue":"chosen"}}
    ),
  )
  assert_eq(record_create_required_fields(catalog, 16, 100).unwrap(), [
    "required", "radio",
  ])
  let escaped = record_create_required_fields(catalog, 16, 100).unwrap()
  escaped.clear()
  assert_eq(record_create_required_fields(catalog, 16, 100).unwrap(), [
    "required", "radio",
  ])
}

///|
test "CREATE unknown requirements refuse without removing independent readable metadata" {
  let catalog = eligibility_catalog(
    (
      #|{"unknown":{"type":"MULTI_LINE_TEXT","code":"unknown","defaultValue":"server"}}
    ),
  )
  assert_true(form_field_named(catalog, ["unknown"]) is Some(_))
  assert_true(
    record_create_required_fields(catalog, 16, 100)
    is Err(FieldUnavailable("unknown")),
  )
}

///|
test "generated and positively copied fields are not required caller inputs" {
  let catalog = eligibility_catalog(
    (
      #|{"calculated":{"type":"SINGLE_LINE_TEXT","code":"calculated","expression":"\"server\"","required":true},"copied":{"type":"MULTI_LINE_TEXT","code":"copied","required":true},"lookup":{"type":"SINGLE_LINE_TEXT","code":"lookup","expression":"","required":true,"lookup":{"fieldMappings":[{"field":"copied","relatedField":"source"}]}},"recordNumber":{"type":"RECORD_NUMBER","code":"recordNumber"},"creator":{"type":"CREATOR","code":"creator"}}
    ),
  )
  assert_eq(record_create_required_fields(catalog, 16, 100).unwrap(), ["lookup"])
}

///|
test "hidden lookup destinations and unsupported required carriers remain unavailable for CREATE" {
  for
    properties in [
      (
        #|{"lookup":{"type":"SINGLE_LINE_TEXT","code":"lookup","expression":"","required":false,"lookup":null}}
      ),
      (
        #|{"number":{"type":"NUMBER","code":"number","required":true}}
      ),
      (
        #|{"table":{"type":"SUBTABLE","code":"table","fields":{"child":{"type":"MULTI_LINE_TEXT","code":"child","required":true}}}}
      ),
    ] {
    assert_true(
      record_create_required_fields(eligibility_catalog(properties), 16, 100)
      is Err(FieldUnavailable(_)),
    )
  }
  let catalog = eligibility_catalog(
    (
      #|{"number":{"type":"NUMBER","code":"number","required":false}}
    ),
  )
  assert_eq(record_create_required_fields(catalog, 16, 100).unwrap(), [])
}

///|
test "CREATE requirement inventory enforces caller field and work budgets before output" {
  let catalog = eligibility_catalog(
    (
      #|{"a":{"type":"MULTI_LINE_TEXT","code":"a","required":true},"b":{"type":"MULTI_LINE_TEXT","code":"b","required":false}}
    ),
  )
  assert_true(
    record_create_required_fields(catalog, 0, 100) is Err(InvalidLimits),
  )
  assert_true(
    record_create_required_fields(catalog, 16, 0) is Err(InvalidLimits),
  )
  assert_true(
    record_create_required_fields(catalog, 1, 100) is Err(BudgetExceeded),
  )
  assert_true(
    record_create_required_fields(catalog, 16, 3) is Err(BudgetExceeded),
  )
  assert_eq(record_create_required_fields(catalog, 2, 4).unwrap(), ["a"])
}
