///|
test "sync admits one resource while retaining another describe failure" {
  let listing = project_resource_listing(listed(), list_limits()).unwrap()
  let sync = begin_catalog_sync(listing)
  assert_eq(catalog_sync_next(sync), Some("Account"))
  assert_true(finish_catalog_sync(sync) is Err(Incomplete))
  assert_true(
    catalog_sync_unavailable(sync, "ActQL_Test_Record__c", RateLimited)
    is Err(WrongResource),
  )
  catalog_sync_unavailable(sync, "Account", PermissionDenied).unwrap()
  assert_eq(catalog_sync_next(sync), Some("ActQL_Test_Record__c"))
  catalog_sync_describe(sync, "ActQL_Test_Record__c", described(), limits()).unwrap()
  assert_eq(catalog_sync_next(sync), None)
  finish_catalog_sync(sync).unwrap()
  assert_false(catalog_sync_is_complete(sync))
  assert_true(
    catalog_sync_outcome(sync, "Account") is Some(Unavailable(PermissionDenied)),
  )
  assert_true(catalog_sync_resource(sync, "Account") is Err(DescribeRequired))
  assert_eq(
    catalog_sync_resource(sync, "ActQL_Test_Record__c").unwrap().name,
    "ActQL_Test_Record__c",
  )
  assert_true(
    catalog_sync_unavailable(sync, "Account", Cancelled) is Err(AlreadyFinished),
  )
}

///|
test "malformed describe remains incomplete rather than becoming absence" {
  let listing = project_resource_listing(listed(), list_limits()).unwrap()
  let sync = begin_catalog_sync(listing)
  let bad_body =
    #|{"name":"Contact","fields":[]}
  assert_true(
    catalog_sync_describe(sync, "Account", @utf8.encode(bad_body), limits())
    is Err(Describe(ResourceMismatch)),
  )
  assert_true(
    catalog_sync_outcome(sync, "Account") is Some(Unavailable(InvalidMetadata)),
  )
  catalog_sync_unavailable(sync, "ActQL_Test_Record__c", ProviderUnavailable).unwrap()
  finish_catalog_sync(sync).unwrap()
  assert_false(catalog_sync_is_complete(sync))
  assert_true(catalog_sync_resource(sync, "Account") is Err(DescribeRequired))
}

///|
test "cancel retains completed evidence and marks remaining resources" {
  let listing = project_resource_listing(listed(), list_limits()).unwrap()
  let sync = begin_catalog_sync(listing)
  let account_body =
    #|{"name":"Account","queryable":true,"createable":false,"updateable":false,"fields":[{"name":"Id","type":"id"}]}
  catalog_sync_describe(sync, "Account", @utf8.encode(account_body), limits()).unwrap()
  cancel_catalog_sync(sync).unwrap()
  finish_catalog_sync(sync).unwrap()
  assert_false(catalog_sync_is_complete(sync))
  assert_eq(catalog_sync_resource(sync, "Account").unwrap().name, "Account")
  assert_true(
    catalog_sync_outcome(sync, "ActQL_Test_Record__c")
    is Some(Unavailable(Cancelled)),
  )
}

///|
test "truncated listing never claims globally complete sync" {
  let listing = project_resource_listing(listed(), {
    ..list_limits(),
    max_selected: 1,
  }).unwrap()
  let sync = begin_catalog_sync(listing)
  let account_body =
    #|{"name":"Account","queryable":true,"createable":false,"updateable":false,"fields":[{"name":"Id","type":"id"}]}
  catalog_sync_describe(sync, "Account", @utf8.encode(account_body), limits()).unwrap()
  finish_catalog_sync(sync).unwrap()
  assert_false(catalog_sync_is_complete(sync))
  assert_true(
    catalog_sync_resource(sync, "ActQL_Test_Record__c") is Err(ListingTruncated),
  )
}
