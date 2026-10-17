///|
fn form_test_limits() -> FormFieldLimits {
  {
    max_bytes: 20000,
    max_nodes: 2000,
    max_depth: 24,
    max_fields: 100,
    max_name_units: 1000,
  }
}

///|
fn form_test_body() -> String {
  (
    #|{"revision":"7","properties":{"customer_code":{"type":"SINGLE_LINE_TEXT","code":"customer_code","label":"Customer label","required":true,"unique":true},"memo":{"type":"MULTI_LINE_TEXT","code":"memo","required":false},"amount":{"type":"NUMBER","code":"amount","required":false,"unique":false,"displayScale":"3"},"choice":{"type":"MULTI_SELECT","code":"choice","options":{"日本":{"label":"日本","index":"1"},"e\u0301":{"label":"e\u0301","index":0}}},"lines":{"type":"SUBTABLE","code":"lines","fields":{"item":{"type":"SINGLE_LINE_TEXT","code":"item","required":true},"value":{"type":"CALC","code":"value","format":"NUMBER","displayScale":""}}}}}
  )
}

///|
fn form_test_catalog(
  body? : String = form_test_body(),
  app_id? : String = "12",
) -> FormFieldCatalog {
  project_form_fields(@utf8.encode(body), app_id, form_test_limits()).unwrap()
}

///|
test "original Form Fields retain app label revision field codes and numeric display metadata" {
  let body = form_test_body()
  let catalog = form_test_catalog()
  assert_eq(catalog.app_id, "12")
  assert_eq(catalog.revision, "7")
  assert_eq(catalog.response_sha256, @sha.hex(@utf8.encode(body)))
  assert_eq(form_field_paths(catalog).length(), 7)
  let key = form_field_named(catalog, ["customer_code"]).unwrap()
  assert_eq(key.code, "customer_code")
  assert_eq(key.required, Some(true))
  assert_eq(key.unique, Some(true))
  assert_true(form_field_named(catalog, ["Customer label"]) is None)
  let amount = form_field_named(catalog, ["amount"]).unwrap()
  assert_eq(amount.native_type, "NUMBER")
  assert_eq(amount.display_scale, Some("3"))
  assert_eq(amount.unique, Some(false))
  let calculation = form_field_named(catalog, ["lines", "value"]).unwrap()
  assert_eq(calculation.calculation_format, Some("NUMBER"))
  assert_eq(calculation.display_scale, Some(""))
}

///|
test "original subtable paths and exact Unicode options survive immutable projection" {
  let catalog = form_test_catalog()
  assert_true(form_field_named(catalog, ["item"]) is None)
  assert_true(form_field_named(catalog, ["lines", "item"]) is Some(_))
  let paths = form_field_paths(catalog)
  paths[0][0] = "foreign"
  paths.push(["injected"])
  assert_true(form_field_named(catalog, ["customer_code"]) is Some(_))
  assert_true(form_field_named(catalog, ["foreign"]) is None)
  let choice = form_field_named(catalog, ["choice"]).unwrap()
  let options = form_field_options(choice).unwrap()
  assert_eq(options, ["日本", "é"])
  options[0] = "changed"
  options.push("injected")
  assert_eq(form_field_options(choice).unwrap(), ["日本", "é"])
  assert_true(
    form_field_options(form_field_named(catalog, ["memo"]).unwrap()) is None,
  )
}

///|
test "only positively enforced original top level field metadata supplies a unique key" {
  let catalog = form_test_catalog()
  assert_true(require_form_unique_key(catalog, "customer_code") is Ok(_))
  assert_true(require_form_unique_key(catalog, "amount") is Err(UniqueKeyUnconfirmed))
  assert_true(require_form_unique_key(catalog, "memo") is Err(UniqueKeyUnconfirmed))
  assert_true(require_form_unique_key(catalog, "Customer label") is Err(FieldUnavailable))
  assert_true(require_form_unique_key(catalog, "item") is Err(FieldUnavailable))
  for unique in ["false", "null", "\"true\""] {
    let body = "{\"revision\":\"7\",\"properties\":{\"key\":{\"type\":\"SINGLE_LINE_TEXT\",\"code\":\"key\",\"unique\":" +
      unique + "}}}"
    if unique == "false" {
      assert_true(require_form_unique_key(form_test_catalog(body~), "key") is Err(UniqueKeyUnconfirmed))
    } else {
      assert_true(project_form_fields(@utf8.encode(body), "12", form_test_limits()) is Err(InvalidField("key")))
    }
  }
  let readonly = form_test_catalog(body=(
    #|{"revision":"7","properties":{"computed":{"type":"CALC","code":"computed","unique":true}}}
  ))
  assert_true(require_form_unique_key(readonly, "computed") is Err(UniqueKeyUnconfirmed))
}

///|
test "field name correspondence required flags option names and table structure are not invented" {
  for
    properties in [
      "{\"field\":{\"type\":\"SINGLE_LINE_TEXT\",\"code\":\"label\"}}", "{\"field\":{\"type\":\"SINGLE_LINE_TEXT\",\"code\":\"field\",\"required\":null}}",
      "{\"field\":{\"type\":\"SINGLE_LINE_TEXT\",\"code\":\"field\",\"required\":\"false\"}}",
      "{\"field\":{\"type\":\"NUMBER\",\"code\":\"field\",\"displayScale\":3}}",
      "{\"field\":{\"type\":\"SUBTABLE\",\"code\":\"field\"}}", "{\"field\":{\"type\":\"SUBTABLE\",\"code\":\"field\",\"fields\":null}}",
      "{\"field\":{\"type\":\"DROP_DOWN\",\"code\":\"field\",\"options\":{\"key\":{\"label\":\"different\"}}}}",
    ] {
    let body = "{\"revision\":\"7\",\"properties\":" + properties + "}"
    assert_true(
      project_form_fields(@utf8.encode(body), "12", form_test_limits())
      is Err(InvalidField("field")),
    )
  }
  let metadata = form_test_catalog(
    body=(
      #|{"revision":"7","properties":{"future":{"type":"FUTURE_KIND","code":"future"}}}
    ),
  )
  assert_eq(
    form_field_named(metadata, ["future"]).unwrap().native_type,
    "FUTURE_KIND",
  )
  assert_eq(form_field_named(metadata, ["future"]).unwrap().required, None)
  assert_true(
    require_form_unique_key(metadata, "future") is Err(UniqueKeyUnconfirmed),
  )
}

///|
test "duplicate JSON properties malformed complete responses and revisions refuse" {
  for
    body in [
      "{\"revision\":\"7\",\"properties\":{},\"properties\":{}}", "{\"revision\":\"7\",\"properties\":{\"field\":{},\"field\":{}}}",
      "{\"revision\":7,\"properties\":{}}", "{\"revision\":\"\",\"properties\":{}}",
      "{\"revision\":\"7\",\"properties\":[]}", "{\"revision\":\"7\",\"properties\":{}} trailing",
    ] {
    assert_true(
      project_form_fields(@utf8.encode(body), "12", form_test_limits())
      is Err(_),
    )
  }
}

///|
test "caller byte node depth field and total code bounds refuse without partial catalog" {
  let body = @utf8.encode(form_test_body())
  let original = form_test_limits()
  for
    limits in [
      { ..original, max_bytes: body.length() - 1, },
      { ..original, max_nodes: 2, },
      { ..original, max_depth: 2, },
      { ..original, max_fields: 6, },
      { ..original, max_name_units: 2, },
    ] {
    assert_true(project_form_fields(body, "12", limits) is Err(BudgetExceeded))
  }
  for
    limits in [
      { ..original, max_bytes: 0, },
      { ..original, max_nodes: 0, },
      { ..original, max_depth: 0, },
      { ..original, max_fields: 0, },
      { ..original, max_name_units: 0, },
    ] {
    assert_true(project_form_fields(body, "12", limits) is Err(InvalidLimits))
  }
  assert_true(
    project_form_fields(body, "not-an-app-id", original) is Err(InvalidResponse),
  )
}

///|
test "pure field correspondence checks original app revision and every retained definition fact" {
  let original = form_test_catalog()
  assert_true(
    form_field_definition_matches(original, form_test_catalog(), [
      "customer_code",
    ]),
  )
  assert_true(
    !form_field_definition_matches(original, form_test_catalog(app_id="13"), [
      "customer_code",
    ]),
  )
  for
    body in [
      form_test_body().replace(
        old="\"revision\":\"7\"",
        new="\"revision\":\"8\"",
      ),
      form_test_body().replace(old="\"unique\":true", new="\"unique\":false"),
      form_test_body().replace(
        old="\"required\":true",
        new="\"required\":false",
      ),
      form_test_body().replace(
        old="\"type\":\"SINGLE_LINE_TEXT\"",
        new="\"type\":\"MULTI_LINE_TEXT\"",
      ),
    ] {
    assert_true(
      !form_field_definition_matches(original, form_test_catalog(body~), [
        "customer_code",
      ]),
    )
  }
  assert_true(!form_field_definition_matches(original, original, ["foreign"]))
}
