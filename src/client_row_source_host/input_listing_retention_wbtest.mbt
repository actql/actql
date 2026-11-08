///|
test "whole listing retention charges excluded metadata and refunds only duplicate temporary rows" {
  // The original checked reference has one object plus eight scalar fields;
  // the other six metadata values spend six nodes: 15 per examined row.
  let budget : RowListingRetention = {
    max_nodes: 30,
    max_text: 20000,
    nodes: 0,
    text: 0,
  }
  let read = selection_read_fixture(
    ExactPaths(["wanted.txt"]),
    metadata_retention=Some(budget),
  )
  begin_row_listing_request(read, None, 0L).unwrap()
  assert_eq(
    accept_row_source_listing_page(
      read,
      listing_page(
        "[" + selection_row("d", "excluded.txt") + "]",
        None,
        Some("p1"),
      ),
      1L,
    ).unwrap(),
    0,
  )
  assert_eq(budget.nodes, 15)
  let original_text = budget.text
  begin_row_listing_request(read, Some("p1"), 2L).unwrap()
  assert_eq(
    accept_row_source_listing_page(
      read,
      listing_page(
        "[" + selection_row("d", "excluded.txt") + "]",
        Some("p1"),
        Some("p2"),
      ),
      3L,
    ).unwrap(),
    0,
  )
  assert_eq(budget.nodes, 15)
  assert_eq(budget.text, original_text)
  begin_row_listing_request(read, Some("p2"), 4L).unwrap()
  assert_eq(
    accept_row_source_listing_page(
      read,
      listing_page(
        "[" + selection_row("e", "wanted.txt") + "]",
        Some("p2"),
        None,
      ),
      5L,
    ).unwrap(),
    1,
  )
  assert_eq(budget.nodes, 30)
  assert_eq(
    @execution.captured_row_count(finish_row_source_read(read).unwrap()),
    1,
  )
}

///|
test "whole listing retained metadata one short fails before capture without a partial prefix" {
  for maximum in [29, 30] {
    let budget : RowListingRetention = {
      max_nodes: maximum,
      max_text: 20000,
      nodes: 0,
      text: 0,
    }
    let read = selection_read_fixture(AllFiles, metadata_retention=Some(budget))
    begin_row_listing_request(read, None, 0L).unwrap()
    let result = accept_row_source_listing_page(
      read,
      listing_page(
        "[" +
        selection_row("d", "a.txt") +
        "," +
        selection_row("e", "b.txt") +
        "]",
        None,
        None,
      ),
      1L,
    )
    if maximum == 29 {
      assert_true(result is Err(Value(_)))
      assert_true(finish_row_source_read(read) is Err(Closed))
      assert_false(read.listing.unwrap().complete)
    } else {
      assert_eq(result.unwrap(), 2)
      assert_eq(budget.nodes, 30)
      assert_eq(
        @execution.captured_row_count(finish_row_source_read(read).unwrap()),
        2,
      )
    }
  }
}
