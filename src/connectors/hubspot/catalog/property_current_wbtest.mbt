///|
test "current property recheck follows original metadata meaning rather than raw order or labels" {
  let original = catalog(
    (
      #|{"results":[{"name":"name","type":"string","fieldType":"text","label":"Original"},{"name":"amount","type":"number","fieldType":"number"}]}
    ),
  )
  let reordered = catalog(
    (
      #|{"results":[{"name":"amount","type":"number","fieldType":"number"},{"name":"name","type":"string","fieldType":"text","label":"Renamed","future":"metadata"}]}
    ),
  )
  assert_true(original.response_sha256 != reordered.response_sha256)
  assert_eq(recheck_property_catalog(original, reordered, 2), Ok(()))
  assert_eq(
    recheck_property_catalog(original, original, 1),
    Err(BudgetExceeded),
  )
  assert_eq(recheck_property_catalog(original, original, 0), Err(InvalidLimits))
}

///|
test "current property recheck refuses changed original object fields types write and unique facts" {
  let body =
    #|{"results":[{"name":"key","type":"string","fieldType":"text","hasUniqueValue":true,"calculated":false,"archived":false,"modificationMetadata":{"readOnlyValue":false}}]}
  let original = catalog(body)
  for
    changed in [
      "{\"results\":[]}",
      "{\"results\":[{\"name\":\"other\",\"type\":\"string\",\"fieldType\":\"text\"}]}",
      body.replace(old="\"string\"", new="\"number\""),
      body.replace(old="\"text\"", new="\"textarea\""),
      body.replace(
        old="\"hasUniqueValue\":true",
        new="\"hasUniqueValue\":false",
      ),
      body.replace(old="\"calculated\":false", new="\"calculated\":true"),
      body.replace(old="\"archived\":false", new="\"archived\":true"),
      body.replace(old="\"readOnlyValue\":false", new="\"readOnlyValue\":true"),
    ] {
    assert_eq(
      recheck_property_catalog(original, catalog(changed), 10),
      Err(ForeignCatalog),
    )
  }
  assert_eq(
    recheck_property_catalog(original, catalog(body, object_type="deals"), 10),
    Err(ForeignCatalog),
  )
}

///|
test "current enum choices cannot be replaced by display labels or another option" {
  let original = catalog(
    (
      #|{"results":[{"name":"stage","type":"enumeration","fieldType":"select","options":[{"value":"original","label":"Public"}]}]}
    ),
  )
  let changed = catalog(
    (
      #|{"results":[{"name":"stage","type":"enumeration","fieldType":"select","options":[{"value":"Public","label":"original"}]}]}
    ),
  )
  assert_eq(
    recheck_property_catalog(original, changed, 10),
    Err(ForeignCatalog),
  )
}
