///|
/// The exact original component metadata supplies precision, scale and parent.
fn geolocation_describe() -> String {
  (
    #|{"name":"Record__c","queryable":true,"createable":true,"updateable":true,"fields":[{"name":"Id","type":"id","nillable":false},{"name":"Location__c","type":"location","nillable":true,"createable":false,"updateable":false},{"name":"Location__Latitude__s","type":"double","nillable":true,"precision":18,"scale":15,"compoundFieldName":"Location__c","defaultedOnCreate":false,"createable":true,"updateable":true},{"name":"Location__Longitude__s","type":"double","nillable":true,"precision":18,"scale":15,"compoundFieldName":"Location__c","defaultedOnCreate":false,"createable":true,"updateable":true}]}
  )
}

///|
test "compound geolocation declaration keeps the original component decimal contracts" {
  let declaration = declared_for(geolocation_describe())
  assert_true(declaration.views[0].fields.contains("Location__c"))
  assert_true(
    declaration.catalog.contains(
      "\"Location__c\":{\"fields\":{\"latitude\":{\"nullable\":true,\"precision\":18,\"scale\":15,\"type\":\"decimal\"},\"longitude\":{\"nullable\":true,\"precision\":18,\"scale\":15,\"type\":\"decimal\"}},\"nullable\":true,\"type\":\"object\"}",
    ),
  )
}

///|
test "compound geolocation read projection uses the original parent and components" {
  let (observation, binding) = declared_observation(geolocation_describe())
  let projection = prepare_read_projection(
    observation,
    binding,
    "Record__c",
    ["Location__c"],
    256,
  ).unwrap()
  assert_eq(read_projection_fields(projection), ["Location__c"])
  assert_eq(
    read_projection_soql(projection),
    "SELECT Location__c FROM Record__c",
  )
}

///|
test "compound geolocation admits original number lexemes without binary64 rounding" {
  let (observation, binding) = declared_observation(geolocation_describe())
  let plan = prepare_read_projection(
    observation,
    binding,
    "Record__c",
    ["Location__c"],
    256,
  ).unwrap()
  let page = project_query_page(
    @utf8.encode(
      (
        #|{"totalSize":1,"done":true,"records":[{"Location__c":{"latitude":37.123456789012345,"longitude":-122.123456789012345}}]}
      ),
    ),
    plan,
    "v62.0",
    query_test_limits(),
  ).unwrap()
  let writer = @encode.writer(4096, 100, 10) catch { _ => abort("test writer") }
  @admitted.emit_checked_wire_value(
    query_page_cell(page, 0, 0).unwrap(),
    writer,
  ) catch {
    _ => abort("test checked value")
  }
  let wire = @encode.finish(writer) catch { _ => abort("test finish") }
  assert_eq(
    wire, "{\"latitude\":\"37.123456789012345\",\"longitude\":\"-122.123456789012345\"}",
  )
}

///|
test "geolocation names without original parent metadata do not supply a contract" {
  let missing = geolocation_describe().replace_all(
    old=",\"compoundFieldName\":\"Location__c\"",
    new="",
  )
  let (observation, binding) = declared_observation(missing)
  assert_true(
    prepare_read_projection(
      observation,
      binding,
      "Record__c",
      ["Location__c"],
      256,
    )
    is Err(UnsupportedReadType("Location__c")),
  )
  assert_true(!declared_for(missing).views[0].fields.contains("Location__c"))
  // The original scalar component remains independently usable.
  assert_true(
    prepare_read_projection(
      observation,
      binding,
      "Record__c",
      ["Location__Latitude__s"],
      256,
    )
    is Ok(_),
  )
}

///|
test "geolocation refuses missing component digits and changed original component meaning" {
  let (observation, binding) = declared_observation(geolocation_describe())
  let plan = prepare_read_projection(
    observation,
    binding,
    "Record__c",
    ["Location__c"],
    256,
  ).unwrap()
  for
    changed in [
      geolocation_describe().replace_all(old=",\"scale\":15", new=""),
      geolocation_describe().replace_all(old="\"scale\":15", new="\"scale\":14"),
      geolocation_describe().replace_all(
        old="\"compoundFieldName\":\"Location__c\"",
        new="\"compoundFieldName\":\"Other__c\"",
      ),
    ] {
    let (current, _) = declared_observation(changed)
    assert_true(
      recheck_read_projection(plan, current)
      is Err(SchemaChanged("Location__c")),
    )
  }
}

///|
test "geolocation provider cells preserve null and refuse incomplete extra or coerced values" {
  let (observation, binding) = declared_observation(geolocation_describe())
  let plan = prepare_read_projection(
    observation,
    binding,
    "Record__c",
    ["Location__c"],
    256,
  ).unwrap()
  let prefix = "{\"totalSize\":1,\"done\":true,\"records\":[{\"Location__c\":"
  let suffix = "}]}"
  for value in ["null", "{\"latitude\":null,\"longitude\":null}"] {
    assert_true(
      project_query_page(
        @utf8.encode(prefix + value + suffix),
        plan,
        "v62.0",
        query_test_limits(),
      )
      is Ok(_),
    )
  }
  for
    value in [
      "{\"latitude\":1}", "{\"latitude\":1,\"longitude\":2,\"altitude\":3}", "{\"latitude\":\"1\",\"longitude\":2}",
      "{\"latitude\":1000,\"longitude\":2}", "{\"latitude\":1.0000000000000001,\"longitude\":2}",
    ] {
    assert_true(
      project_query_page(
        @utf8.encode(prefix + value + suffix),
        plan,
        "v62.0",
        query_test_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "geolocation original component metadata keeps the original parse bounds and types" {
  for replacement in ["false", "17", "\"\""] {
    let body = geolocation_describe().replace_all(
      old="\"compoundFieldName\":\"Location__c\"",
      new="\"compoundFieldName\":" + replacement,
    )
    assert_true(
      project_describe(@utf8.encode(body), "Record__c", {
        max_bytes: 4096,
        max_nodes: 100,
        max_depth: 10,
        max_fields: 10,
        max_name_units: 100,
      })
      is Err(InvalidField("Location__Latitude__s")),
    )
  }
}

///|
test "geolocation nested values do not escape the original page byte node or depth limits" {
  let (observation, binding) = declared_observation(geolocation_describe())
  let plan = prepare_read_projection(
    observation,
    binding,
    "Record__c",
    ["Location__c"],
    256,
  ).unwrap()
  let wire = @utf8.encode(
    (
      #|{"totalSize":1,"done":true,"records":[{"Location__c":{"latitude":37.1,"longitude":-122.2}}]}
    ),
  )
  let limits = query_test_limits()
  for
    constrained in [
      { ..limits, max_bytes: wire.length() - 1, },
      { ..limits, max_nodes: 7, },
      { ..limits, max_depth: 2, },
    ] {
    assert_true(
      project_query_page(wire, plan, "v62.0", constrained)
      is Err(BudgetExceeded),
    )
  }
}

///|
test "geolocation writes stay on the original described component mappings" {
  let (observation, binding) = declared_observation(geolocation_describe())
  let projection = prepare_write_projection(
    observation,
    binding,
    "Record__c",
    WriteUpdateById,
    ["Location__Latitude__s", "Location__Longitude__s"],
    2,
  ).unwrap()
  let body = prepare_write_body(
    projection,
    @utf8.encode(
      (
        #|{"Location__Latitude__s":"37.100000000000000","Location__Longitude__s":"-122.200000000000000"}
      ),
    ),
    { max_bytes: 4096, max_nodes: 20, max_depth: 3, },
  ).unwrap()
  assert_eq(
    write_body_json(body),
    "{\"Location__Latitude__s\":37.100000000000000,\"Location__Longitude__s\":-122.200000000000000}",
  )
  assert_true(
    prepare_write_projection(
      observation,
      binding,
      "Record__c",
      WriteUpdateById,
      ["Location__c"],
      1,
    )
    is Err(_),
  )
}

///|
test "geolocation component writes recheck their original parent association" {
  let (observation, binding) = declared_observation(geolocation_describe())
  let plan = prepare_write_projection(
    observation,
    binding,
    "Record__c",
    WriteUpdateById,
    ["Location__Latitude__s"],
    1,
  ).unwrap()
  let changed = geolocation_describe().replace_all(
    old="\"compoundFieldName\":\"Location__c\"",
    new="\"compoundFieldName\":\"Other__c\"",
  )
  let (current, _) = declared_observation(changed)
  assert_true(
    recheck_write_projection(plan, current)
    is Err(SchemaChanged("Location__Latitude__s")),
  )
}
