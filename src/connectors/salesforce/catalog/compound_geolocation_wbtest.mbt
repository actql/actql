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
