///|
/// Select the title by its actual property discriminant, never its display
/// name, a fragment in Retrieve page, or a fabricated data-source Catalog.
/// This original request remains DATA; its Site operation needs separate
/// current authorization and physical response/cleanup custody.
pub fn start_notion_page_title_property_item_request(
  page : OriginalNotionPage,
  limits : NotionPropertyItemLimits,
) -> Result[NotionPropertyItemRequest, NotionPropertyItemIssue] {
  if !property_item_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if !notion_page_is_original(page) {
    return Err(ForeignOriginal)
  }
  guard @decode.object_length(page.properties) is Some(count) else {
    return Err(InvalidSelection)
  }
  if page.raw.length() > limits.metadata.max_bytes ||
    count > limits.metadata.max_properties ||
    page.raw.length() >= limits.max_work {
    return Err(BudgetExceeded)
  }
  // Charge the complete retained response and every examined occurrence before
  // lookup, including unused properties and a later duplicate title.
  let mut work = limits.max_work - page.raw.length()
  let mut selected : NotionPropertyItemOrigin? = None
  for index in 0..<count {
    if work == 0 {
      return Err(BudgetExceeded)
    }
    work -= 1
    guard @decode.field_at(page.properties, index) is Some((_, cursor)) &&
      @decode.open_object(cursor) is Ok(property) &&
      @decode.lookup(property, "id") is Some(id) &&
      @decode.lookup(property, "type") is Some(kind) else {
      return Err(InvalidSelection)
    }
    let id = match metadata_text(id, limits.metadata.max_identity_bytes, true) {
      Ok(value) => value
      Err(BudgetExceeded) => return Err(BudgetExceeded)
      Err(_) => return Err(InvalidSelection)
    }
    let kind = match metadata_text(kind, limits.metadata.max_name_bytes, true) {
      Ok(value) => value
      Err(BudgetExceeded) => return Err(BudgetExceeded)
      Err(_) => return Err(InvalidSelection)
    }
    if kind == "title" {
      if selected is Some(_) {
        return Err(InvalidSelection)
      }
      guard @decode.lookup(property, "title") is Some(value) &&
        @decode.array_length(value) is Some(_) else {
        return Err(InvalidSelection)
      }
      selected = Some(PageTitleProperty(page, id, value))
    }
  }
  guard selected is Some(origin) else { return Err(InvalidSelection) }
  if work == 0 {
    return Err(BudgetExceeded)
  }
  Ok(
    new_property_item_request(origin, { ..limits, max_work: work, }, None, None),
  )
}

///|
pub fn notion_property_item_request_matches_page_title(
  request : NotionPropertyItemRequest,
  page : OriginalNotionPage,
) -> Bool {
  if !property_item_request_is_original(request) ||
    !notion_page_is_original(page) {
    return false
  }
  match request.origin {
    PageTitleProperty(original, _, _) => physical_equal(original, page)
    _ => false
  }
}

///|
/// All title pages must finish on the same original Page/property chain. A
/// terminal cursor is not exhaustive workspace membership or physical ACK.
pub fn admit_notion_completed_page_title(
  page : OriginalNotionPage,
  terminal : NotionPropertyItemPage,
  limits : @admitted.Limits,
) -> Result[(@admitted.CheckedValue, Int, Int), NotionPropertyItemIssue] {
  if !property_item_page_is_original(terminal) ||
    !notion_property_item_request_matches_page_title(terminal.request, page) {
    return Err(ForeignOriginal)
  }
  guard terminal.request.origin is PageTitleProperty(_, _, value) else {
    return Err(ForeignOriginal)
  }
  admit_property_item_chain(
    terminal,
    @contract.primitive(@contract.StringType, nullable=false),
    value,
    limits,
  )
}

///|
pub fn notion_completed_page_title_wire(
  page : OriginalNotionPage,
  terminal : NotionPropertyItemPage,
  limits : @admitted.Limits,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, NotionPropertyItemIssue] {
  let (value, _, _) = match
    admit_notion_completed_page_title(page, terminal, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @admitted.emit_checked_wire_value(value, writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}
