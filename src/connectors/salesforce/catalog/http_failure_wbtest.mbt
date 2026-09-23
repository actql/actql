///|
test "Salesforce catalog failure classification separates rate and permission" {
  let rate_body =
    #|[{"message":"API limit exceeded","errorCode":"REQUEST_LIMIT_EXCEEDED"}]
  let permission_body =
    #|[{"message":"denied","errorCode":"INSUFFICIENT_ACCESS"}]
  assert_true(
    catalog_http_failure(403, @utf8.encode(rate_body), 1000) is RateLimited,
  )
  assert_true(
    catalog_http_failure(403, @utf8.encode(permission_body), 1000)
    is PermissionDenied,
  )
  assert_true(
    catalog_http_failure(429, @utf8.encode(permission_body), 1000)
    is RateLimited,
  )
  assert_true(
    catalog_http_failure(401, @utf8.encode(rate_body), 1000) is PermissionDenied,
  )
  assert_true(
    catalog_http_failure(503, @utf8.encode(rate_body), 1000)
    is ProviderUnavailable,
  )
  assert_true(
    catalog_http_failure(404, @utf8.encode(rate_body), 1000) is InvalidMetadata,
  )
}

///|
test "untrusted or oversized error bodies do not override HTTP denial" {
  let malformed =
    #|REQUEST_LIMIT_EXCEEDED
  assert_true(
    catalog_http_failure(403, @utf8.encode(malformed), 1000) is PermissionDenied,
  )
  let rate_body =
    #|[{"errorCode":"REQUEST_LIMIT_EXCEEDED"}]
  assert_true(
    catalog_http_failure(403, @utf8.encode(rate_body), 5) is PermissionDenied,
  )
  assert_true(
    catalog_http_failure(403, @utf8.encode(rate_body), -1) is PermissionDenied,
  )
}
