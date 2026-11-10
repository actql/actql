///|
test "HubSpot property recheck bounds sequential key scratch before native metadata" {
  let profile = response_metadata_profile()
  // New authored enum/Unicode metadata, not a real account or retained body.
  // Unknown fields still traverse the original full parser/admission path.
  let descriptions = String::make(20000, 'x')
  let properties = Array::makei(16, index => {
    "{\"name\":\"phase_" +
    index.to_string() +
    "\",\"type\":\"enumeration\",\"fieldType\":\"select\",\"options\":[" +
    "{\"value\":\"caf\\u00e9\"},{\"value\":\"e\\u0301\"}]," +
    "\"e\\u0301\":{\"description\":\"" +
    descriptions +
    "\"}}"
  })
  let body = @utf8.encode("{\"results\":[" + properties.join(",") + "]}")
  assert_true(body.length() > 320000 && body.length() < profile[0])
  let quote = source_property_recheck_construction_capacity(
    profile,
    body.length(),
  ).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(quote)
  let execution = @execution.execution_capacity_execution_bytes(quote)
  println(
    "HubSpot new enum/Unicode body=\{body.length()} phase-peak=\{retained}",
  )
  // This is a fixed component residual, not a new installed policy or a grant.
  let ledger = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 1000000L,
    retained_bytes: 268435456L,
    execution_bytes: 268435456L,
  }).unwrap()
  let reservation = match
    @resources.reserve_capacity(ledger, retained, execution) {
    Ok(value) => value
    Err(_) =>
      fail("Sequential metadata constructor exceeds fixed component residual")
  }
  let limits : PropertyLimits = {
    max_bytes: profile[0],
    max_nodes: profile[1],
    max_depth: profile[2],
    max_properties: profile[3],
    max_name_units: profile[4],
  }
  let original = project_properties(body, "companies", limits).unwrap()
  recheck_property_catalog(original, original, profile[3]).unwrap()
  assert_eq(property_names(original).length(), 16)
  @resources.settle_capacity(ledger, reservation).unwrap()
  // Preserve BOTH constructor envelopes, rather than dropping parser scratch.
  let n = Int::min(body.length(), profile[1])
  let parsed = initialization_decoded_construction(
    body.length(),
    n,
    profile[2],
    true,
  ).unwrap()
  let projection = initialization_collection_units(
    property_projection_construction_extent(n, profile[3]).unwrap(),
  )
  assert_true(
    retained >= @execution.preparation_representation_cost(parsed).unwrap(),
  )
  assert_true(
    retained >= @execution.preparation_representation_cost(projection).unwrap(),
  )
  let short = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 1000000L,
    retained_bytes: retained - 1L,
    execution_bytes: execution,
  }).unwrap()
  assert_true(@resources.reserve_capacity(short, retained, execution) is Err(_))
  // Key normalization and duplicate failure remain active inside unknown data.
  let duplicate = @utf8.encode(
    "{\"results\":[],\"unselected\":{\"\\u00e9\":0,\"e\\u0301\":1}}",
  )
  assert_true(project_properties(duplicate, "companies", limits) is Err(_))
  let tiny = { ..limits, max_nodes: 8, }
  assert_true(
    project_properties(body, "companies", tiny) is Err(BudgetExceeded),
  )
  // No earlier response peak is spent by success or by the next-prefix quote.
  let account = b"{\"portalId\":41}"
  let first = source_read_construction_capacity(profile, 37264, [
    account.length(),
    body.length(),
  ]).unwrap()
  let later = source_read_construction_capacity(profile, 37264, [
    account.length(),
    body.length(),
    1,
  ]).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(later) >
    @execution.execution_capacity_retained_bytes(first),
  )
}

///|
test "HubSpot property parser phase remains funded at full response bound" {
  let profile = response_metadata_profile()
  // At the full response bound the parser phase dominates. Always subtracting
  // scratch would underfund that phase, even though the enum body fits.
  let largest = source_property_recheck_construction_capacity(
    profile,
    profile[0],
  ).unwrap()
  let largest_parser = initialization_decoded_construction(
    profile[0],
    profile[1],
    profile[2],
    true,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(largest) >=
    @execution.preparation_representation_cost(largest_parser).unwrap(),
  )
  assert_true(
    source_property_recheck_construction_capacity(profile, 0) is Some(_),
  )
}
