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
