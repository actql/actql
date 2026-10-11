///|
fn catalog_operation_configuration(
  verb : @http.NativeHttpMethod,
  limit : Int,
) -> NativeCredentialOperation {
  {
    resource_origin: "https://provider.example",
    operation: "salesforce:catalog:describe",
    path: "/services/data/v61.0/sobjects/Account/describe",
    secret_path: "/private/provider-token",
    verb,
    max_request_bytes: limit,
  }
}

///|
test "Resource admission rejects the former Catalog GET body allowance" {
  assert_false(
    valid_operation(catalog_operation_configuration(@http.Get, 65536)),
  )
  assert_true(valid_operation(catalog_operation_configuration(@http.Get, 0)))
  assert_false(valid_operation(catalog_operation_configuration(@http.Get, 1)))
  assert_false(valid_operation(catalog_operation_configuration(@http.Get, -1)))
}

///|
test "Bodyless Catalog selection does not relax Resource configuration checks" {
  let operation = catalog_operation_configuration(@http.Get, 0)
  assert_false(
    valid_operation({ ..operation, resource_origin: "http://provider.example", }),
  )
  assert_false(valid_operation({ ..operation, operation: "", }))
  assert_false(
    valid_operation({ ..operation, path: "//foreign.example/describe", }),
  )
  assert_false(valid_operation({ ..operation, secret_path: "", }))
  assert_true(
    valid_operation(catalog_operation_configuration(@http.Post, 65536)),
  )
  assert_false(
    valid_operation(catalog_operation_configuration(@http.Post, 65537)),
  )
}
