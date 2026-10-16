///|
fn catalog_limits() -> CatalogResponseLimits {
  { max_bytes: 65536, max_nodes: 4096, max_depth: 16, max_rows: 100, }
}

///|
fn catalog_request(kind : CatalogKind, number? : Int = 1) -> CatalogPageRequest {
  prepare_catalog_page_request(
    kind, "3.29", "11111111-1111-1111-1111-111111111111", number, 256,
  ).unwrap()
}

///|
fn catalog_fixture_row(index : Int, extra? : String = "") -> String {
  let decimal = index.to_string()
  let tail = (if index < 10 {
      "00000000000"
    } else if index < 100 {
      "0000000000"
    } else {
      "000000000"
    }) +
    decimal
  "{\"id\":\"00000000-0000-0000-0000-" +
  tail +
  "\",\"name\":\"row-" +
  decimal +
  "\"" +
  extra +
  "}"
}

///|
fn catalog_fixture(
  kind : CatalogKind,
  rows : Array[String],
  number? : String = "1",
  total? : String = "1",
  size? : String = "100",
  direct? : Bool = false,
) -> Bytes {
  let (plural, singular) = catalog_names(kind)
  let array = "[" + rows.join(",") + "]"
  @utf8.encode(
    "{\"pagination\":{\"pageNumber\":\"" +
    number +
    "\",\"pageSize\":\"" +
    size +
    "\",\"totalAvailable\":\"" +
    total +
    "\"},\"" +
    plural +
    "\":" +
    (if direct { array } else { "{\"" + singular + "\":" + array + "}" }) +
    "}",
  )
}

///|
test "four exact source endpoints keep selected site version and the 100-row profile" {
  let cases = [
    (Workbooks, "workbooks"),
    (DataSources, "datasources"),
    (Views, "views"),
    (Flows, "flows"),
  ]
  for (kind, resource) in cases {
    let request = catalog_request(kind)
    assert_eq(catalog_page_method(request), "GET")
    assert_eq(
      catalog_page_path(request),
      "/api/3.29/sites/11111111-1111-1111-1111-111111111111/" +
      resource +
      "?pageSize=100&pageNumber=1" +
      (if kind == Views { "&includeUsageStatistics=true" } else { "" }),
    )
  }
}

///|
test "page selectors reject path injection malformed versions IDs and nonpositive pages" {
  for api in ["", "3", ".29", "03.29", "3.029", "3.29?x=1", "3.29/flows"] {
    assert_true(
      prepare_catalog_page_request(
        Workbooks,
        api,
        "11111111-1111-1111-1111-111111111111",
        1,
        256,
      )
      is Err(InvalidSelection),
    )
  }
  for
    site in ["", "analytics", "../site", "11111111-1111-1111-1111-11111111111z"] {
    assert_true(
      prepare_catalog_page_request(Workbooks, "3.29", site, 1, 256)
      is Err(InvalidSelection),
    )
  }
  for number in [0, -1] {
    assert_true(
      prepare_catalog_page_request(
        Workbooks,
        "3.29",
        "11111111-1111-1111-1111-111111111111",
        number,
        256,
      )
      is Err(InvalidSelection),
    )
  }
}

///|
test "request path exact capacity and one byte less are distinguished" {
  let request = catalog_request(Views)
  let bytes = catalog_page_path(request).length()
  assert_true(
    prepare_catalog_page_request(
      Views,
      "3.29",
      "11111111-1111-1111-1111-111111111111",
      1,
      bytes,
    )
    is Ok(_),
  )
  assert_true(
    prepare_catalog_page_request(
      Views,
      "3.29",
      "11111111-1111-1111-1111-111111111111",
      1,
      bytes - 1,
    )
    is Err(CapacityExceeded),
  )
  assert_true(
    prepare_catalog_page_request(
      Views,
      "3.29",
      "11111111-1111-1111-1111-111111111111",
      1,
      0,
    )
    is Err(InvalidLimits),
  )
}

///|
test "all four catalog kinds retain exact IDs names and optional missing facts" {
  for kind in [Workbooks, DataSources, Views, Flows] {
    let body = catalog_fixture(kind, [catalog_fixture_row(1)])
    let page = admit_catalog_page(
      catalog_request(kind),
      200,
      body,
      catalog_limits(),
    ).unwrap()
    assert_eq(catalog_page_total_available(page), 1L)
    let rows = catalog_page_rows(page)
    assert_eq(rows.length(), 1)
    assert_eq(rows[0].id, "00000000-0000-0000-0000-000000000001")
    assert_eq(rows[0].name, "row-1")
    assert_eq(rows[0].tags, None)
    assert_eq(rows[0].has_extract, None)
    assert_eq(rows[0].view_count, None)
    assert_eq(rows[0].updated_at, None)
    assert_true(next_catalog_page(page, 256) is Ok(None))
  }
}

///|
test "documented direct array and named collection forms project the same rows" {
  for kind in [Workbooks, DataSources, Views, Flows] {
    let request = catalog_request(kind)
    let first = admit_catalog_page(
      request,
      200,
      catalog_fixture(kind, [catalog_fixture_row(1)]),
      catalog_limits(),
    ).unwrap()
    let second = admit_catalog_page(
      request,
      200,
      catalog_fixture(kind, [catalog_fixture_row(1)], direct=true),
      catalog_limits(),
    ).unwrap()
    assert_eq(catalog_page_rows(first), catalog_page_rows(second))
    assert_true(
      catalog_page_response_sha256(first) !=
      catalog_page_response_sha256(second),
    )
  }
}

///|
test "project owner tags and canonical timestamps keep their separate provider facts" {
  let extra = ",\"project\":{\"id\":\"22222222-2222-2222-2222-222222222222\",\"name\":\"Finance\"}," +
    "\"owner\":{\"id\":\"33333333-3333-3333-3333-333333333333\"}," +
    "\"createdAt\":\"2026-10-01T00:00:00Z\",\"updatedAt\":\"2026-10-02T01:02:03Z\"," +
    "\"tags\":[{\"label\":\"approved\"}],\"contentUrl\":\"Finance/sheets/Churn\""
  let page = admit_catalog_page(
    catalog_request(Workbooks),
    200,
    catalog_fixture(Workbooks, [catalog_fixture_row(1, extra~)]),
    catalog_limits(),
  ).unwrap()
  let row = catalog_page_rows(page)[0]
  assert_eq(row.project_id, Some("22222222-2222-2222-2222-222222222222"))
  assert_eq(row.project_name, Some("Finance"))
  assert_eq(row.owner_id, Some("33333333-3333-3333-3333-333333333333"))
  assert_eq(row.tags, Some(["approved"]))
  assert_eq(row.created_at, Some("2026-10-01T00:00:00Z"))
  assert_eq(row.updated_at, Some("2026-10-02T01:02:03Z"))
  assert_eq(row.content_url, Some("Finance/sheets/Churn"))
}

///|
test "extract and usage facts accept exact provider scalar spellings without truthiness" {
  for spelling in ["true", "\"true\""] {
    let page = admit_catalog_page(
      catalog_request(DataSources),
      200,
      catalog_fixture(DataSources, [
        catalog_fixture_row(
          1,
          extra=",\"type\":\"hyper\",\"hasExtracts\":" + spelling,
        ),
      ]),
      catalog_limits(),
    ).unwrap()
    assert_eq(catalog_page_rows(page)[0].has_extract, Some(true))
    assert_eq(catalog_page_rows(page)[0].datasource_type, Some("hyper"))
  }
  let page = admit_catalog_page(
    catalog_request(Views),
    200,
    catalog_fixture(Views, [
      catalog_fixture_row(1, extra=",\"usage\":{\"totalViewCount\":\"0\"}"),
    ]),
    catalog_limits(),
  ).unwrap()
  assert_eq(catalog_page_rows(page)[0].view_count, Some(0L))
  for spelling in ["1", "\"TRUE\"", "\"yes\""] {
    assert_true(
      admit_catalog_page(
        catalog_request(DataSources),
        200,
        catalog_fixture(DataSources, [
          catalog_fixture_row(1, extra=",\"hasExtracts\":" + spelling),
        ]),
        catalog_limits(),
      )
      is Err(InvalidResponse),
    )
  }
}

///|
test "known empty tags stay distinct from missing and explicit null metadata" {
  for extra in [",\"tags\":[]", ",\"tags\":{\"tag\":[]}"] {
    let page = admit_catalog_page(
      catalog_request(Flows),
      200,
      catalog_fixture(Flows, [catalog_fixture_row(1, extra~)]),
      catalog_limits(),
    ).unwrap()
    assert_eq(catalog_page_rows(page)[0].tags, Some([]))
  }
  let page = admit_catalog_page(
    catalog_request(Flows),
    200,
    catalog_fixture(Flows, [catalog_fixture_row(1, extra=",\"tags\":null")]),
    catalog_limits(),
  ).unwrap()
  assert_eq(catalog_page_rows(page)[0].tags, None)
}

///|
test "empty catalog requires an explicit empty array and matching zero total" {
  for kind in [Workbooks, DataSources, Views, Flows] {
    let page = admit_catalog_page(
      catalog_request(kind),
      200,
      catalog_fixture(kind, [], total="0"),
      catalog_limits(),
    ).unwrap()
    assert_eq(catalog_page_rows(page), [])
    assert_true(next_catalog_page(page, 256) is Ok(None))
  }
  for
    body in [
      "{\"pagination\":{\"pageNumber\":\"1\",\"pageSize\":\"100\",\"totalAvailable\":\"0\"}}",
      "{\"pagination\":{\"pageNumber\":\"1\",\"pageSize\":\"100\",\"totalAvailable\":\"0\"},\"workbooks\":null}",
      "{\"pagination\":{\"pageNumber\":\"1\",\"pageSize\":\"100\",\"totalAvailable\":\"0\"},\"workbooks\":{}}",
    ] {
    assert_true(
      admit_catalog_page(
        catalog_request(Workbooks),
        200,
        @utf8.encode(body),
        catalog_limits(),
      )
      is Err(InvalidResponse),
    )
  }
}

///|
test "continuation advances only the original kind site version and page" {
  let rows = Array::makei(100, i => catalog_fixture_row(i))
  let page = admit_catalog_page(
    catalog_request(Views),
    200,
    catalog_fixture(Views, rows, total="101"),
    catalog_limits(),
  ).unwrap()
  let next = next_catalog_page(page, 256).unwrap().unwrap()
  assert_eq(
    catalog_page_path(next),
    "/api/3.29/sites/11111111-1111-1111-1111-111111111111/views?pageSize=100&pageNumber=2&includeUsageStatistics=true",
  )
  let last = admit_catalog_page(
    next,
    200,
    catalog_fixture(Views, [catalog_fixture_row(100)], number="2", total="101"),
    catalog_limits(),
  ).unwrap()
  assert_true(next_catalog_page(last, 256) is Ok(None))
  assert_true(next_catalog_page(page, 10) is Err(CapacityExceeded))
}

///|
test "mismatched selected page or page size cannot supply a continuation" {
  for (number, size) in [("2", "100"), ("1", "99"), ("0", "100")] {
    assert_true(
      admit_catalog_page(
        catalog_request(Workbooks),
        200,
        catalog_fixture(Workbooks, [catalog_fixture_row(1)], number~, size~),
        catalog_limits(),
      )
      is Err(ForeignPage),
    )
  }
}

///|
test "truncated or impossible pagination refuses rather than implying a complete source" {
  for total in ["0", "2", "101"] {
    assert_true(
      admit_catalog_page(
        catalog_request(Workbooks),
        200,
        catalog_fixture(Workbooks, [catalog_fixture_row(1)], total~),
        catalog_limits(),
      )
      is Err(InvalidResponse),
    )
  }
  assert_true(
    admit_catalog_page(
      catalog_request(Workbooks, number=2),
      200,
      catalog_fixture(Workbooks, [], number="2", total="100"),
      catalog_limits(),
    )
    is Err(InvalidResponse),
  )
}

///|
test "duplicate record identity and malformed nonfirst record refuse the whole page" {
  let row = catalog_fixture_row(1)
  assert_true(
    admit_catalog_page(
      catalog_request(Workbooks),
      200,
      catalog_fixture(Workbooks, [row, row], total="2"),
      catalog_limits(),
    )
    is Err(DuplicateIdentity),
  )
  for
    bad in [
      "{}", "{\"id\":\"not-a-luid\",\"name\":\"x\"}", "{\"id\":\"22222222-2222-2222-2222-222222222222\",\"name\":3}",
    ] {
    assert_true(
      admit_catalog_page(
        catalog_request(Workbooks),
        200,
        catalog_fixture(Workbooks, [row, bad], total="2"),
        catalog_limits(),
      )
      is Err(InvalidResponse),
    )
  }
}

///|
test "malformed present metadata is never silently replaced with unknown" {
  for
    extra in [
      ",\"updatedAt\":\"yesterday\"", ",\"project\":{}", ",\"owner\":{\"id\":\"someone\"}",
      ",\"tags\":[{}]", ",\"tags\":{}", ",\"tags\":[{\"label\":3}]", ",\"contentUrl\":true",
    ] {
    assert_true(
      admit_catalog_page(
        catalog_request(Workbooks),
        200,
        catalog_fixture(Workbooks, [catalog_fixture_row(1, extra~)]),
        catalog_limits(),
      )
      is Err(InvalidResponse),
    )
  }
}

///|
test "noncanonical decimal counters fractions negatives and overflow are refused" {
  for total in ["01", "+1", "-1", "1.0", "1e0", "9223372036854775808"] {
    assert_true(
      admit_catalog_page(
        catalog_request(Workbooks),
        200,
        catalog_fixture(Workbooks, [catalog_fixture_row(1)], total~),
        catalog_limits(),
      )
      is Err(InvalidResponse),
    )
  }
}

///|
test "all response scalar budgets retain exact and one-short distinctions" {
  let body = catalog_fixture(Workbooks, [catalog_fixture_row(1)])
  let limits = catalog_limits()
  assert_true(
    admit_catalog_page(catalog_request(Workbooks), 200, body, {
      ..limits,
      max_bytes: body.length(),
    })
    is Ok(_),
  )
  assert_true(
    admit_catalog_page(catalog_request(Workbooks), 200, body, {
      ..limits,
      max_bytes: body.length() - 1,
    })
    is Err(CapacityExceeded),
  )
  assert_true(
    admit_catalog_page(catalog_request(Workbooks), 200, body, {
      ..limits,
      max_nodes: 1,
    })
    is Err(CapacityExceeded),
  )
  assert_true(
    admit_catalog_page(catalog_request(Workbooks), 200, body, {
      ..limits,
      max_depth: 1,
    })
    is Err(CapacityExceeded),
  )
  for rows in [0, 101] {
    assert_true(
      admit_catalog_page(catalog_request(Workbooks), 200, body, {
        ..limits,
        max_rows: rows,
      })
      is Err(InvalidLimits),
    )
  }
  assert_true(
    admit_catalog_page(
      catalog_request(Workbooks),
      200,
      catalog_fixture(
        Workbooks,
        [catalog_fixture_row(1), catalog_fixture_row(2)],
        total="2",
      ),
      { ..limits, max_rows: 1, },
    )
    is Err(CapacityExceeded),
  )
}

///|
test "duplicate JSON fields including ignored provider extensions refuse the complete page" {
  let bytes = @utf8.encode(
    "{\"pagination\":{\"pageNumber\":\"1\",\"pageSize\":\"100\",\"totalAvailable\":\"0\"},\"workbooks\":[],\"extra\":{\"x\":1,\"x\":2}}",
  )
  assert_true(
    admit_catalog_page(catalog_request(Workbooks), 200, bytes, catalog_limits())
    is Err(InvalidResponse),
  )
}

///|
test "non200 truncated UTF8 and unrelated collection cannot become a catalog page" {
  let body = catalog_fixture(Workbooks, [catalog_fixture_row(1)])
  for status in [201, 202, 204, 301, 401, 403, 404, 429, 500] {
    assert_true(
      admit_catalog_page(
        catalog_request(Workbooks),
        status,
        body,
        catalog_limits(),
      )
      is Err(UnexpectedStatus),
    )
  }
  assert_true(
    admit_catalog_page(
      catalog_request(Workbooks),
      200,
      @utf8.encode("{"),
      catalog_limits(),
    )
    is Err(InvalidResponse),
  )
  assert_true(
    admit_catalog_page(
      catalog_request(Workbooks),
      200,
      Bytes::from_array([0xff]),
      catalog_limits(),
    )
    is Err(InvalidResponse),
  )
  assert_true(
    admit_catalog_page(
      catalog_request(Workbooks),
      200,
      catalog_fixture(Flows, [catalog_fixture_row(1)]),
      catalog_limits(),
    )
    is Err(InvalidResponse),
  )
}

///|
test "caller row-array mutation cannot change the original pagination observation" {
  let page = admit_catalog_page(
    catalog_request(Workbooks),
    200,
    catalog_fixture(Workbooks, [catalog_fixture_row(1)]),
    catalog_limits(),
  ).unwrap()
  let rows = catalog_page_rows(page)
  rows.clear()
  assert_true(next_catalog_page(page, 256) is Ok(None))
}

///|
test "numeric JSON pagination is not rounded into the documented decimal-string profile" {
  for total in ["1", "1.000000000000000000001", "9007199254740993"] {
    let body = @utf8.encode(
      "{\"pagination\":{\"pageNumber\":\"1\",\"pageSize\":\"100\",\"totalAvailable\":" +
      total +
      "},\"workbooks\":{\"workbook\":[" +
      catalog_fixture_row(1) +
      "]}}",
    )
    assert_true(
      admit_catalog_page(
        catalog_request(Workbooks),
        200,
        body,
        catalog_limits(),
      )
      is Err(InvalidResponse),
    )
  }
}
