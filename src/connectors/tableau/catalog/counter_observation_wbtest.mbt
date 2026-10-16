// Independent provider observations, not Common signed64 type/operation
// acceptance, permission, funding, an installed Source or a signed view-data row.

///|
fn usage_counter_body(lexeme : String) -> Bytes {
  @utf8.encode(
    "{\"pagination\":{\"pageNumber\":\"1\",\"pageSize\":\"100\",\"totalAvailable\":\"1\"},\"views\":[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"counter\",\"usage\":{\"totalViewCount\":" +
    lexeme +
    "}}]}",
  )
}

///|
test "provider usage integers remain exact above binary64 and through signed64 maximum" {
  let cases = [
    (
      "0", 0L, "2cd9311f1f984d8384d71c06ba623a3b92089e52bb207a9bd30305835f86b844",
    ),
    (
      "1", 1L, "996b4efeec5436bb156c12cdb1fa1bf323993948359b27c49505342d7f08ea22",
    ),
    (
      "9007199254740991", 9007199254740991L, "66abaa08c6245ef199a3bef8322025a7c264f23b1777b19d2a64c1a2f303c1e4",
    ),
    (
      "9007199254740992", 9007199254740992L, "7ed0d952fd6bb09f64cce31964062cb1eb061cee3183d08ea5cd76536c0cefea",
    ),
    (
      "9007199254740993", 9007199254740993L, "a01bb079059577f7c2f0d35a9a8bdbd162a3c56774627ef50ce13445c1c64224",
    ),
    (
      "9223372036854775807", 9223372036854775807L, "a2b2af776cbc6717827e4f34b62c759b41343e1f48b0b0d9e531792c661a0e1b",
    ),
  ]
  for (original, expected, original_hash) in cases {
    let page = admit_catalog_page(
      catalog_request(Views),
      200,
      usage_counter_body("\"" + original + "\""),
      catalog_limits(),
    ).unwrap()
    assert_eq(catalog_page_rows(page)[0].view_count, Some(expected))
    assert_eq(
      catalog_page_rows(page)[0].view_count.unwrap().to_string(),
      original,
    )
    assert_eq(catalog_page_response_sha256(page), original_hash)
  }
}

///|
test "distinct adjacent integers at two to the fifty third never collapse into one observation" {
  let lower = admit_catalog_page(
    catalog_request(Views),
    200,
    usage_counter_body("\"9007199254740992\""),
    catalog_limits(),
  ).unwrap()
  let upper = admit_catalog_page(
    catalog_request(Views),
    200,
    usage_counter_body("\"9007199254740993\""),
    catalog_limits(),
  ).unwrap()
  assert_eq(catalog_page_rows(lower)[0].view_count, Some(9007199254740992L))
  assert_eq(catalog_page_rows(upper)[0].view_count, Some(9007199254740993L))
  assert_true(
    catalog_page_rows(lower)[0].view_count !=
    catalog_page_rows(upper)[0].view_count,
  )
  assert_true(
    catalog_page_response_sha256(lower) != catalog_page_response_sha256(upper),
  )
}

///|
test "provider counter overflow and negative usage refuse without saturating or wrapping" {
  // A negative integer can belong to a future signed view-data column, but
  // never to this existing nonnegative usage-counter contract.
  for
    spelling in [
      "-1", "-9223372036854775808", "-9223372036854775809", "9223372036854775808",
      "18446744073709551615",
    ] {
    assert_true(
      admit_catalog_page(
        catalog_request(Views),
        200,
        usage_counter_body("\"" + spelling + "\""),
        catalog_limits(),
      )
      is Err(InvalidResponse),
    )
  }
}

///|
test "JSON numbers and noncanonical counter strings cannot masquerade as exact observations" {
  for
    lexeme in [
      "0", "1", "9007199254740992", "9007199254740993", "9223372036854775807", "\"00\"",
      "\"+1\"", "\"1.0\"", "\"1e0\"", "\" 1\"", "\"1 \"", "\"NaN\"", "\"Infinity\"",
      "null", "true", "{}", "[]",
    ] {
    assert_true(
      admit_catalog_page(
        catalog_request(Views),
        200,
        usage_counter_body(lexeme),
        catalog_limits(),
      )
      is Err(InvalidResponse),
    )
  }
}

///|
test "an invalid nonfirst integer observation refuses the complete provider page" {
  let rows = [
    catalog_fixture_row(
      1,
      extra=",\"usage\":{\"totalViewCount\":\"9223372036854775807\"}",
    ),
    catalog_fixture_row(
      2,
      extra=",\"usage\":{\"totalViewCount\":\"9223372036854775808\"}",
    ),
  ]
  assert_true(
    admit_catalog_page(
      catalog_request(Views),
      200,
      catalog_fixture(Views, rows, total="2"),
      catalog_limits(),
    )
    is Err(InvalidResponse),
  )
}

///|
test "the maximum counter observation still obeys original exact byte admission" {
  let bytes = usage_counter_body("\"9223372036854775807\"")
  let limits = catalog_limits()
  assert_true(
    admit_catalog_page(catalog_request(Views), 200, bytes, {
      ..limits,
      max_bytes: bytes.length(),
    })
    is Ok(_),
  )
  assert_true(
    admit_catalog_page(catalog_request(Views), 200, bytes, {
      ..limits,
      max_bytes: bytes.length() - 1,
    })
    is Err(CapacityExceeded),
  )
}
