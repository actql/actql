///|
fn selection_reference_wire(identity : String) -> String {
  row_reference_wire().replace(old="d".repeat(64), new=identity.repeat(64))
}

///|
fn selection_row(
  identity : String,
  path : String,
  version? : String = "v1",
) -> String {
  "{\"resource\":" +
  selection_reference_wire(identity) +
  ",\"name\":" +
  Json::string(path).stringify() +
  ",\"path\":" +
  Json::string(path).stringify() +
  ",\"version\":" +
  Json::string(version).stringify() +
  ",\"media_type\":null,\"size_bytes\":3,\"modified_at\":null}"
}

///|
fn selection_read_fixture(
  selection : RowFileSelection,
  max_work? : Int = 100000,
  reports? : RowListingReports? = None,
  metadata_retention? : RowListingRetention? = None,
) -> RowSourceRead {
  let resource = @contract.read_checked(
    row_presence_cursor(
      "{\"type\":\"resource_ref\",\"resource_kind\":\"file\",\"nullable\":false}",
    ),
    { max_nodes: 256, max_depth: 16, max_text_bytes: 4096, },
  ).unwrap()
  let schema = @schema.from_presence_fields(
    [
      (@schema.Unqualified("resource"), resource, @schema.Required),
      (
        @schema.Unqualified("name"),
        @contract.primitive(@contract.StringType, nullable=false),
        @schema.Required,
      ),
      (
        @schema.Unqualified("path"),
        @contract.primitive(@contract.StringType, nullable=true),
        @schema.Required,
      ),
      (
        @schema.Unqualified("version"),
        @contract.primitive(@contract.StringType, nullable=true),
        @schema.Required,
      ),
      (
        @schema.Unqualified("media_type"),
        @contract.primitive(@contract.StringType, nullable=true),
        @schema.Required,
      ),
      (
        @schema.Unqualified("size_bytes"),
        @contract.primitive(@contract.NumberType, nullable=true),
        @schema.Required,
      ),
      (
        @schema.Unqualified("modified_at"),
        @contract.primitive(@contract.TimestampType, nullable=true),
        @schema.Required,
      ),
    ],
    max_fields=7,
    max_name_bytes=128,
  ).unwrap()
  let checked = @pipeline.check(
    row_presence_cursor("[{\"select\":[\"name\"]}]"),
    [("files", schema)],
    None,
    Some(row_presence_cursor("\"files\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 4096,
      max_nodes: 256,
      max_tokens: 256,
      max_depth: 16,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 4096,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let retention = { ..row_presence_retention(), max_work, }
  let columns = []
  for i in 0..<@schema.field_count(schema) {
    columns.push(
      @schema.field_reference_name(@schema.field_at(schema, i).unwrap()),
    )
  }
  let limits = [
    ("max_listing_items", 3L),
    ("max_examined_items", 9L),
    ("max_listing_pages", 4L),
    ("max_request_attempts", 4L),
    ("max_listing_bytes", 16384L),
    ("max_listing_duration_ms", 100L),
    ("maximum_path_length", 32L),
  ]
  let resolved = listing_rows_fixture(Some(3L), None).unwrap()
  let resolved = match reports {
    None => resolved
    Some(reports) =>
      ReportListingRows(listing_rows_resolution(resolved), reports)
  }
  let issuer = @admitted.bind_reference_issuer(
    (_, wire) => ["d", "e", "f"].any(id => wire == selection_reference_wire(id)),
    _ => true,
  )
  {
    schema,
    columns,
    declared_fields: columns.copy(),
    input: @execution.prepare_admitted_input(owner, 0, 3, retention).unwrap(),
    page_limits: {
      max_bytes: 8192,
      max_nodes: 1024,
      max_depth: 16,
      max_rows: 9,
    },
    values: { max_nodes: 1024, max_depth: 16, max_text_bytes: 8192, },
    retention,
    reference_issuer: Some(issuer),
    listing: Some(
      new_row_listing_progress(
        limits,
        resolved_rows=Some(resolved),
        selection=Some(selection),
        retention=metadata_retention,
      ),
    ),
    keyed: None,
    pages: 0L,
    rows: 0L,
    open: true,
  }
}

///|
fn selection_accept(
  read : RowSourceRead,
  rows : String,
  token : String?,
  next : String?,
  quantum : Int,
) -> Result[Int, RowSourceIssue] {
  match begin_row_listing_request(read, token, read.pages) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    begin_row_source_listing_page(
      read,
      listing_page(rows, token, next),
      read.pages,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  for i = 0; i < 100000; i = i + 1 {
    match advance_row_source_listing_page(read, quantum, read.pages) {
      Ok(ListingPageContinue(work~)) =>
        if work <= 0 || work > quantum {
          return Err(ListingProtocol)
        }
      Ok(ListingPageComplete(rows~, work~)) => {
        if work <= 0 || work > quantum {
          return Err(ListingProtocol)
        }
        return Ok(rows)
      }
      Err(issue) => return Err(issue)
    }
  }
  Err(ListingProtocol)
}

///|
test "common listing selection continues nonmatching pages and deduplicates issued Resources" {
  let mut expected_work : Int? = None
  for quantum in [1, 7, 10000] {
    let read = selection_read_fixture(
      GlobFiles(compile_listing_glob("**/*.csv", 100).unwrap()),
    )
    assert_eq(
      selection_accept(
        read,
        "[" + selection_row("f", "ignore.txt") + "]",
        None,
        Some("p1"),
        quantum,
      ).unwrap(),
      0,
    )
    assert_false(read.listing.unwrap().complete)
    let row = selection_row("d", "a.csv")
    assert_eq(
      selection_accept(
        read,
        "[" + row + "," + row + "," + selection_row("e", "b/z.csv") + "]",
        Some("p1"),
        Some("p2"),
        quantum,
      ).unwrap(),
      2,
    )
    assert_false(read.listing.unwrap().complete)
    assert_eq(
      selection_accept(read, "[]", Some("p2"), None, quantum).unwrap(),
      0,
    )
    let progress = read.listing.unwrap()
    assert_eq(progress.examined_items, 4L)
    assert_eq(progress.attempts, 3L)
    assert_eq(read.pages, 3L)
    match expected_work {
      None => expected_work = Some(progress.work)
      Some(value) => assert_eq(progress.work, value)
    }
    let captured = finish_row_source_read(read).unwrap()
    assert_eq(@execution.captured_row_count(captured), 2)
    let name = read.columns.search("name").unwrap()
    assert_true(
      @execution.captured_presence_cell(captured, 0, name)
      is Ok(@execution.Present(@admitted.Text("a.csv"))),
    )
    assert_true(
      @execution.captured_presence_cell(captured, 1, name)
      is Ok(@execution.Present(@admitted.Text("b/z.csv"))),
    )
  }
}

///|
test "exact paths use exact data spelling and require all requested observations" {
  let read = selection_read_fixture(ExactPaths(["é/%2F", "é/%2F", "b"]))
  assert_eq(
    selection_accept(
      read,
      "[" + selection_row("d", "é/%2F") + "]",
      None,
      Some("next"),
      1,
    ).unwrap(),
    1,
  )
  assert_eq(
    selection_accept(
      read,
      "[" + selection_row("e", "b") + "]",
      Some("next"),
      None,
      1,
    ).unwrap(),
    1,
  )
  assert_eq(
    @execution.captured_row_count(finish_row_source_read(read).unwrap()),
    2,
  )
  let missing = selection_read_fixture(ExactPaths(["é/%2F"]))
  assert_true(
    selection_accept(
      missing,
      "[" + selection_row("d", "é/%2F") + "]",
      None,
      None,
      1,
    )
    is Err(ListingMissingPath("é/%2F")),
  )
  assert_true(@execution.finish_admitted_input(missing.input) is Err(_))
  let empty = selection_read_fixture(ExactPaths([]))
  assert_eq(
    @execution.captured_row_count(finish_row_source_read(empty).unwrap()),
    0,
  )
  assert_eq(empty.listing.unwrap().attempts, 0L)
  assert_eq(empty.pages, 0L)
}

///|
test "excluded and duplicate listing observations remain fully admitted" {
  let conflicting = selection_read_fixture(
    GlobFiles(compile_listing_glob("*.csv", 20).unwrap()),
  )
  assert_eq(
    selection_accept(
      conflicting,
      "[" + selection_row("d", "ignore.txt") + "]",
      None,
      Some("next"),
      1,
    ).unwrap(),
    0,
  )
  assert_true(
    selection_accept(
      conflicting,
      "[" + selection_row("d", "ignore.txt", version="v2") + "]",
      Some("next"),
      None,
      1,
    )
    is Err(ListingConflictingResource(_)),
  )
  assert_true(@execution.finish_admitted_input(conflicting.input) is Err(_))
  let malformed = selection_read_fixture(
    GlobFiles(compile_listing_glob("*.csv", 20).unwrap()),
  )
  let row = selection_row("d", "ignore.txt").replace(
    old="\"size_bytes\":3",
    new="\"size_bytes\":\"bad\"",
  )
  assert_true(
    selection_accept(malformed, "[" + row + "]", None, None, 1)
    is Err(Value("size_bytes")),
  )
  assert_true(@execution.finish_admitted_input(malformed.input) is Err(_))
}

///|
test "listing page cursor stops on work exhaustion and cancellation without prefix capture" {
  let limited = selection_read_fixture(
    GlobFiles(compile_listing_glob("*.csv", 20).unwrap()),
    max_work=2,
  )
  assert_true(
    selection_accept(
      limited,
      "[" + selection_row("d", "a.csv") + "]",
      None,
      None,
      1,
    )
    is Err(ListingLimit("listing_work")),
  )
  assert_eq(limited.listing.unwrap().work, 2)
  assert_true(@execution.finish_admitted_input(limited.input) is Err(_))
  let cancelled = selection_read_fixture(
    GlobFiles(compile_listing_glob("*.csv", 20).unwrap()),
  )
  begin_row_listing_request(cancelled, None, 0L).unwrap()
  begin_row_source_listing_page(
    cancelled,
    listing_page("[" + selection_row("d", "a.csv") + "]", None, None),
    1L,
  ).unwrap()
  assert_true(
    advance_row_source_listing_page(cancelled, 3, 1L)
    is Ok(ListingPageContinue(work=3)),
  )
  assert_true(cancel_row_source_read(cancelled))
  assert_false(cancel_row_source_read(cancelled))
  assert_true(cancelled.listing.unwrap().page is None)
  assert_true(cancelled.listing.unwrap().observations.is_empty())
  assert_true(@execution.finish_admitted_input(cancelled.input) is Err(_))
}

///|
test "listing page fixed matcher and admission work has an exact one short boundary" {
  // Thirty-one glob tokens give 32 states. For a 31-scalar path, the matcher
  // spends 32 * (2 * 31 + 1) = 2016 units. Admission, selector setup, append
  // and terminal confirmation add four units, independently totaling 2020.
  // This allowance also admits the seven metadata values on the ordinary
  // input owner; a ten-unit fixture would fail that separate retention bound.
  for quantum in [1, 7, 1000] {
    let pattern = "a" + "?".repeat(30)
    let path = "a".repeat(31)
    let read = selection_read_fixture(
      GlobFiles(compile_listing_glob(pattern, 31).unwrap()),
      max_work=2020,
    )
    assert_eq(
      selection_accept(
        read,
        "[" + selection_row("d", path) + "]",
        None,
        None,
        quantum,
      ).unwrap(),
      1,
    )
    assert_eq(read.listing.unwrap().work, 2020)
    assert_eq(
      @execution.captured_row_count(finish_row_source_read(read).unwrap()),
      1,
    )
    let short = selection_read_fixture(
      GlobFiles(compile_listing_glob(pattern, 31).unwrap()),
      max_work=2019,
    )
    assert_true(
      selection_accept(
        short,
        "[" + selection_row("d", path) + "]",
        None,
        None,
        quantum,
      )
      is Err(ListingLimit("listing_work")),
    )
    assert_eq(short.listing.unwrap().work, 2019)
    assert_true(@execution.finish_admitted_input(short.input) is Err(_))
  }
}
