///|
fn eligibility_catalog(properties : String) -> FormFieldCatalog {
  form_test_catalog(
    body="{\"revision\":\"7\",\"properties\":" + properties + "}",
  )
}

///|
fn eligibility_write(
  catalog : FormFieldCatalog,
  code : String,
) -> Result[RecordWriteValues, RecordWriteIssue] {
  prepare_record_write_values(
    catalog,
    [(code, write_text("requested"))],
    write_test_limits(),
  )
}

///|
test "automatic Text expressions cannot become intended record writes" {
  let catalog = eligibility_catalog(
    (
      #|{"manual":{"type":"SINGLE_LINE_TEXT","code":"manual","expression":""},"calculated":{"type":"SINGLE_LINE_TEXT","code":"calculated","expression":"\"server value\""}}
    ),
  )
  assert_true(eligibility_write(catalog, "manual") is Ok(_))
  assert_true(
    eligibility_write(catalog, "calculated")
    is Err(FieldUnavailable("calculated")),
  )
  // The same field remains an original read observation, not a lost field.
  assert_eq(
    form_field_named(catalog, ["calculated"]).unwrap().native_type,
    "SINGLE_LINE_TEXT",
  )
}

///|
test "Lookup mapping endpoints are not writable while the original lookup input remains separate" {
  let catalog = eligibility_catalog(
    (
      #|{"copied":{"type":"SINGLE_LINE_TEXT","code":"copied","expression":""},"lookup":{"type":"SINGLE_LINE_TEXT","code":"lookup","expression":"","lookup":{"fieldMappings":[{"field":"copied","relatedField":"source"}]}},"independent":{"type":"MULTI_LINE_TEXT","code":"independent"}}
    ),
  )
  assert_true(
    eligibility_write(catalog, "copied") is Err(FieldUnavailable("copied")),
  )
  assert_true(eligibility_write(catalog, "lookup") is Ok(_))
  assert_true(eligibility_write(catalog, "independent") is Ok(_))
}

///|
test "unknown Text calculation metadata does not acquire a writable proof" {
  for extra in ["", ",\"expression\":null", ",\"expression\":false"] {
    let catalog = eligibility_catalog(
      "{\"field\":{\"type\":\"SINGLE_LINE_TEXT\",\"code\":\"field\"" +
      extra +
      "}}",
    )
    assert_true(form_field_named(catalog, ["field"]) is Some(_))
    assert_true(
      eligibility_write(catalog, "field") is Err(FieldUnavailable("field")),
    )
  }
}

///|
test "inaccessible or incomplete Lookup mappings preserve reads but cannot prove writable targets" {
  for
    lookup in [
      "null", "{}", "{\"fieldMappings\":null}", "{\"fieldMappings\":[{\"relatedField\":\"source\"}]}",
    ] {
    let catalog = eligibility_catalog(
      "{\"field\":{\"type\":\"MULTI_LINE_TEXT\",\"code\":\"field\"},\"lookup\":{\"type\":\"SINGLE_LINE_TEXT\",\"code\":\"lookup\",\"expression\":\"\",\"lookup\":" +
      lookup +
      "}}",
    )
    assert_true(form_field_named(catalog, ["field"]) is Some(_))
    assert_true(
      eligibility_write(catalog, "field") is Err(FieldUnavailable("field")),
    )
  }
}

///|
test "both documented empty Lookup mapping representations preserve independent writes" {
  for mappings in ["[]", "\"\""] {
    let catalog = eligibility_catalog(
      "{\"field\":{\"type\":\"MULTI_LINE_TEXT\",\"code\":\"field\"},\"lookup\":{\"type\":\"SINGLE_LINE_TEXT\",\"code\":\"lookup\",\"expression\":\"\",\"lookup\":{\"fieldMappings\":" +
      mappings +
      "}}}",
    )
    assert_true(eligibility_write(catalog, "field") is Ok(_))
  }
}

///|
test "same revision Form recheck retains calculation and Lookup mapping evidence" {
  let original = eligibility_catalog(
    (
      #|{"field":{"type":"SINGLE_LINE_TEXT","code":"field","expression":""},"lookup":{"type":"SINGLE_LINE_TEXT","code":"lookup","expression":"","lookup":{"fieldMappings":[]}}}
    ),
  )
  for
    properties in [
      (
        #|{"field":{"type":"SINGLE_LINE_TEXT","code":"field","expression":"\"server\""},"lookup":{"type":"SINGLE_LINE_TEXT","code":"lookup","expression":"","lookup":{"fieldMappings":[]}}}
      ),
      (
        #|{"field":{"type":"SINGLE_LINE_TEXT","code":"field","expression":""},"lookup":{"type":"SINGLE_LINE_TEXT","code":"lookup","expression":"","lookup":{"fieldMappings":[{"field":"field","relatedField":"source"}]}}}
      ),
    ] {
    assert_true(
      recheck_original_record_form(
        original,
        @utf8.encode("{\"revision\":\"7\",\"properties\":" + properties + "}"),
        form_test_limits(),
      )
      is Err(ForeignCatalog),
    )
  }
}
