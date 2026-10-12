///|
// Drive the production resumable page entry point in protocol-only fixtures.
fn accept_row_source_listing_page(
  read : RowSourceRead,
  body : Bytes,
  elapsed_ms : Int64,
) -> Result[Int, RowSourceIssue] {
  match begin_row_source_listing_page(read, body, elapsed_ms) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  for attempts = 0; attempts < 100000; attempts = attempts + 1 {
    match advance_row_source_listing_page(read, 1, elapsed_ms) {
      Ok(ListingPageContinue(_)) => ()
      Ok(ListingPageComplete(rows~, ..)) => return Ok(rows)
      Err(issue) => return Err(issue)
    }
  }
  Err(ListingProtocol)
}

///|
fn listing_read_fixture(
  policy? : @capacity.Policy? = None,
  limits? : Array[(String, Int64)] = [
    ("max_listing_items", 3L),
    ("max_examined_items", 9L),
    ("max_listing_pages", 3L),
    ("max_request_attempts", 4L),
    ("max_listing_bytes", 4096L),
    ("max_listing_duration_ms", 100L),
    ("maximum_path_length", 32L),
  ],
) -> RowSourceRead {
  let (owner, schema) = row_presence_owner()
  let mut row_maximum : Int64? = None
  for (name, value) in limits {
    if name == "max_listing_items" {
      row_maximum = Some(value)
    }
  }
  let resolved = listing_rows_fixture(row_maximum, policy)
  {
    schema,
    columns: ["id", "p"],
    declared_fields: ["id", "p"],
    input: @execution.prepare_admitted_input(
      owner,
      0,
      3,
      row_presence_retention(),
    ).unwrap(),
    page_limits: {
      max_bytes: 4096,
      max_nodes: 256,
      max_depth: 16,
      max_rows: 3,
    },
    values: { max_nodes: 256, max_depth: 16, max_text_bytes: 4096, },
    retention: row_presence_retention(),
    reference_issuer: None,
    listing: Some(new_row_listing_progress(limits, resolved_rows=resolved)),
    keyed: None,
    pages: 0L,
    rows: 0L,
    open: true,
  }
}

///|
fn listing_page(
  rows : String,
  request_token : String?,
  next_token : String?,
) -> Bytes {
  let token_wire = token => {
    match token {
      Some(text) => Json::string(text).stringify()
      None => "null"
    }
  }
  @utf8.encode(
    "{\"items\":" +
    rows +
    ",\"request_token\":" +
    token_wire(request_token) +
    ",\"next_token\":" +
    token_wire(next_token) +
    "}",
  )
}

///|
test "listing completion requires terminal observation after empty continuation pages" {
  let read = listing_read_fixture()
  begin_row_listing_request(read, None, 0L).unwrap()
  assert_eq(
    accept_row_source_listing_page(
      read,
      listing_page(
        "[{\"id\":1,\"p\":7},{\"id\":2,\"p\":null},{\"id\":3}]",
        None,
        Some("p1"),
      ),
      10L,
    ).unwrap(),
    3,
  )
  assert_false(read.listing.unwrap().complete)
  begin_row_listing_request(read, Some("p1"), 20L).unwrap()
  assert_eq(
    accept_row_source_listing_page(
      read,
      listing_page("[]", Some("p1"), Some("p2")),
      30L,
    ).unwrap(),
    0,
  )
  assert_false(read.listing.unwrap().complete)
  begin_row_listing_request(read, Some("p2"), 40L).unwrap()
  assert_eq(
    accept_row_source_listing_page(
      read,
      listing_page("[]", Some("p2"), None),
      100L,
    ).unwrap(),
    0,
  )
  let captured = finish_row_source_read(read).unwrap()
  assert_eq(@execution.captured_row_count(captured), 3)
  assert_true(
    @execution.captured_presence_cell(captured, 0, 1)
    is Ok(@execution.Present(@admitted.Number(7))),
  )
  assert_true(
    @execution.captured_presence_cell(captured, 1, 1)
    is Ok(@execution.Present(@admitted.Null)),
  )
  assert_true(
    @execution.captured_presence_cell(captured, 2, 1) is Ok(@execution.Absent),
  )
  assert_eq(read.pages, 3L)
  assert_eq(read.listing.unwrap().attempts, 3L)
  assert_false(cancel_row_source_read(read))
}

///|
test "listing prefix and ordinary row entrypoints cannot manufacture completion" {
  let prefix = listing_read_fixture()
  begin_row_listing_request(prefix, None, 0L).unwrap()
  assert_eq(
    accept_row_source_listing_page(
      prefix,
      listing_page("[{\"id\":1}]", None, Some("more")),
      1L,
    ).unwrap(),
    1,
  )
  assert_true(finish_row_source_read(prefix) is Err(ListingIncomplete))
  assert_true(@execution.finish_admitted_input(prefix.input) is Err(_))
  let ordinary = listing_read_fixture()
  assert_true(
    accept_row_source_page(ordinary, @utf8.encode("[{\"id\":1}]"))
    is Err(ListingProtocol),
  )
  assert_true(@execution.finish_admitted_input(ordinary.input) is Err(_))
  let typed = listing_read_fixture()
  assert_true(
    accept_row_source_values(typed, ["id", "p"], []) is Err(ListingProtocol),
  )
  assert_true(@execution.finish_admitted_input(typed.input) is Err(_))
}

///|
test "listing protocol rejects missing foreign and repeated continuation observations" {
  let bodies = [
    "{\"items\":[]}", "{\"items\":[],\"request_token\":null,\"next_token\":null,\"extra\":0}",
    "{\"items\":[],\"request_token\":null,\"next_token\":\"\"}", "{\"items\":[],\"request_token\":\"foreign\",\"next_token\":null}",
  ]
  for body in bodies {
    let read = listing_read_fixture()
    begin_row_listing_request(read, None, 0L).unwrap()
    assert_true(
      accept_row_source_listing_page(read, @utf8.encode(body), 1L)
      is Err(ListingProtocol),
    )
    assert_false(read.open)
    assert_true(@execution.finish_admitted_input(read.input) is Err(_))
  }
  let read = listing_read_fixture()
  begin_row_listing_request(read, None, 0L).unwrap()
  assert_eq(
    accept_row_source_listing_page(
      read,
      listing_page("[{\"id\":1}]", None, Some("same")),
      1L,
    ).unwrap(),
    1,
  )
  begin_row_listing_request(read, Some("same"), 2L).unwrap()
  assert_true(
    accept_row_source_listing_page(
      read,
      listing_page("[]", Some("same"), Some("same")),
      3L,
    )
    is Err(ListingProtocol),
  )
  assert_true(@execution.finish_admitted_input(read.input) is Err(_))
  assert_true(read.listing.unwrap().tokens.is_empty())
}

///|
test "listing cumulative ceilings fail under their own quantity without publishing a prefix" {
  let original = listing_read_fixture().listing.unwrap().limits
  for
    quantity in [
      "max_listing_items", "max_examined_items", "max_listing_pages", "max_request_attempts",
    ] {
    let limits = original.map(pair => {
      if pair.0 == quantity {
        (pair.0, 1L)
      } else {
        pair
      }
    })
    let read = listing_read_fixture(limits~)
    begin_row_listing_request(read, None, 0L).unwrap()
    assert_eq(
      accept_row_source_listing_page(
        read,
        listing_page("[{\"id\":1}]", None, Some("p1")),
        1L,
      ).unwrap(),
      1,
    )
    let request = begin_row_listing_request(read, Some("p1"), 2L)
    if quantity == "max_request_attempts" {
      assert_true(
        request is Err(ListingLimit(failed_quantity)) &&
        failed_quantity == quantity,
      )
    } else {
      request.unwrap()
      let rows = if quantity == "max_listing_pages" {
        "[]"
      } else {
        "[{\"id\":2}]"
      }
      assert_true(
        accept_row_source_listing_page(
          read,
          listing_page(rows, Some("p1"), None),
          3L,
        )
        is Err(ListingLimit(failed_quantity)) &&
        failed_quantity == quantity,
      )
    }
    assert_true(@execution.finish_admitted_input(read.input) is Err(_))
    assert_false(cancel_row_source_read(read))
  }
  let timed = listing_read_fixture()
  begin_row_listing_request(timed, None, 0L).unwrap()
  assert_true(
    accept_row_source_listing_page(timed, listing_page("[]", None, None), 101L)
    is Err(ListingLimit("max_listing_duration_ms")),
  )
  let backwards = listing_read_fixture()
  begin_row_listing_request(backwards, None, 2L).unwrap()
  assert_true(
    accept_row_source_listing_page(
      backwards,
      listing_page("[]", None, None),
      1L,
    )
    is Err(ListingProtocol),
  )
  let unresolved = listing_read_fixture(limits=[("max_listing_items", 3L)])
  assert_true(
    begin_row_listing_request(unresolved, None, 0L)
    is Err(ListingLimitUnresolved("max_examined_items")),
  )
}

///|
test "listing physical bytes have an independent exact boundary including envelope metadata" {
  // The independently authored ASCII response below is exactly 51 bytes.
  let body = @utf8.encode(
    "{\"items\":[],\"request_token\":null,\"next_token\":null}",
  )
  assert_eq(body.length(), 51)
  let original = listing_read_fixture().listing.unwrap().limits
  for bound in [51L, 50L] {
    let read = listing_read_fixture(
      limits=original.map(pair => {
        if pair.0 == "max_listing_bytes" {
          (pair.0, bound)
        } else {
          pair
        }
      }),
    )
    begin_row_listing_request(read, None, 0L).unwrap()
    let observed = accept_row_source_listing_page(read, body, 1L)
    if bound == 51L {
      assert_eq(observed.unwrap(), 0)
      assert_eq(
        @execution.captured_row_count(finish_row_source_read(read).unwrap()),
        0,
      )
    } else {
      assert_true(observed is Err(ListingLimit("max_listing_bytes")))
      assert_true(@execution.finish_admitted_input(read.input) is Err(_))
    }
  }
}

///|
test "translated listing envelope keeps original physical byte accounting" {
  let body = listing_page("[]", None, Some("next"))
  let original = listing_read_fixture().listing.unwrap().limits
  let read = listing_read_fixture(
    limits=original.map(pair => {
      if pair.0 == "max_listing_bytes" {
        (pair.0, 200L)
      } else {
        pair
      }
    }),
  )
  begin_row_listing_request(read, None, 0L).unwrap()
  begin_row_source_listing_page(read, body, 1L, received_bytes=199L).unwrap()
  assert_eq(read.listing.unwrap().received_bytes, 199L)
  advance_row_source_listing_page(read, 1, 1L).unwrap() |> ignore
  begin_row_listing_request(read, Some("next"), 2L).unwrap()
  assert_true(
    begin_row_source_listing_page(
      read,
      listing_page("[]", Some("next"), None),
      3L,
      received_bytes=2L,
    )
    is Err(ListingLimit("max_listing_bytes")),
  )
  assert_false(read.open)
}
