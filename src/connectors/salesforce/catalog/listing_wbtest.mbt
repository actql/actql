///|
fn list_limits() -> ListLimits {
  {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
    max_resources: 20,
    max_selected: 20,
    max_name_units: 1000,
  }
}

///|
fn listed() -> Bytes {
  let body =
    #|{"sobjects":[{"name":"Account","queryable":true,"createable":false,"updateable":false},{"name":"ActQL_Test_Record__c","queryable":true,"createable":true,"updateable":true}]}
  @utf8.encode(body)
}

///|
test "listing retains observed resources without inventing permission" {
  let listing = project_resource_listing(listed(), list_limits()).unwrap()
  assert_eq(listing.visible_count, 2)
  assert_false(listing.truncated)
  assert_eq(listing.selected.length(), 2)
  assert_eq(listing.selected[0].name, "Account")
  assert_false(listing.selected[0].createable)
  assert_true(listing.selected[1].createable)
  assert_true(
    select_described_resource(listing, "Hidden__c", None) is Err(NotVisible),
  )
  assert_true(
    select_described_resource(listing, "ActQL_Test_Record__c", None)
    is Err(DescribeRequired),
  )
  let resource = project_describe(described(), "ActQL_Test_Record__c", limits()).unwrap()
  assert_eq(
    select_described_resource(listing, "ActQL_Test_Record__c", Some(resource)).unwrap().name,
    "ActQL_Test_Record__c",
  )
  assert_true(
    select_described_resource(listing, "Account", Some(resource))
    is Err(DescribeMismatch),
  )
  let conflicting_body =
    #|{"sobjects":[{"name":"ActQL_Test_Record__c","queryable":true,"createable":false,"updateable":true}]}
  let conflicting = project_resource_listing(
    @utf8.encode(conflicting_body),
    list_limits(),
  ).unwrap()
  assert_true(
    select_described_resource(
      conflicting,
      "ActQL_Test_Record__c",
      Some(resource),
    )
    is Err(DescribeMismatch),
  )
}

///|
test "truncated listing does not claim unseen resources are absent" {
  let listing = project_resource_listing(listed(), {
    ..list_limits(),
    max_selected: 1,
  }).unwrap()
  assert_true(listing.truncated)
  assert_eq(listing.visible_count, 2)
  assert_eq(listing.selected.length(), 1)
  assert_true(
    select_described_resource(listing, "ActQL_Test_Record__c", None)
    is Err(ListingTruncated),
  )
  assert_true(
    select_described_resource(listing, "Account", None) is Err(DescribeRequired),
  )
}

///|
test "listing rejects malformed and unbounded observations" {
  assert_true(
    project_resource_listing(listed(), { ..list_limits(), max_bytes: 5, })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_resource_listing(listed(), {
      ..list_limits(),
      max_resources: 1,
      max_selected: 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_resource_listing(listed(), { ..list_limits(), max_selected: 21, })
    is Err(InvalidLimits),
  )
  let duplicate_body =
    #|{"sobjects":[{"name":"Account"},{"name":"Account"}]}
  let duplicate = @utf8.encode(duplicate_body)
  assert_true(
    project_resource_listing(duplicate, list_limits())
    is Err(DuplicateResource("Account")),
  )
  let malformed_body =
    #|{"sobjects":[{"name":"Account","queryable":"yes"}]}
  let malformed = @utf8.encode(malformed_body)
  assert_true(
    project_resource_listing(malformed, list_limits()) is Err(InvalidResponse),
  )
}
