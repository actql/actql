///|
#export_name("salesforceIssuedBroadPlan")
pub fn salesforce_issued_broad_plan(
  attempt : @salesforce_host.SalesforceBroadAttempt,
) -> @catalog.ReadProjection {
  @salesforce_host.salesforce_broad_attempt_plan(attempt)
}

///|
#export_name("salesforceIssuedBroadBegin")
pub fn salesforce_issued_broad_begin(
  attempt : @salesforce_host.SalesforceBroadAttempt,
  api_version : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_locator_units : Int,
  max_pages : Int,
  max_total_rows : Int64,
  max_capture_rows : Int,
  max_capture_nodes : Int,
  max_capture_text_bytes : Int,
  max_capture_depth : Int,
  max_capture_work : Int,
) -> Bool raise SalesforceCatalogBridgeIssue {
  match
    @salesforce_host.begin_issued_salesforce_broad_read(
      attempt,
      api_version,
      { max_bytes, max_nodes, max_depth, max_rows, max_locator_units, },
      max_pages,
      max_total_rows,
      max_capture_rows,
      {
        max_nodes: max_capture_nodes,
        max_text_bytes: max_capture_text_bytes,
        max_depth: max_capture_depth,
        max_work: max_capture_work,
      },
    ) {
    Ok(_) => true
    Err(issue) => raise BroadAttempt(issue)
  }
}

///|
#export_name("salesforceIssuedBroadNextPath")
pub fn salesforce_issued_broad_next_path(
  attempt : @salesforce_host.SalesforceBroadAttempt,
) -> String? raise SalesforceCatalogBridgeIssue {
  match @salesforce_host.salesforce_broad_attempt_next_path(attempt) {
    Ok(path) => path
    Err(issue) => raise BroadAttempt(issue)
  }
}

///|
#export_name("salesforceIssuedBroadAcceptPage")
pub fn salesforce_issued_broad_accept_page(
  attempt : @salesforce_host.SalesforceBroadAttempt,
  path : String,
  body : Bytes,
) -> @catalog.QueryPage raise SalesforceCatalogBridgeIssue {
  match
    @salesforce_host.accept_issued_salesforce_broad_page(attempt, path, body) {
    Ok(page) => page
    Err(issue) => raise BroadAttempt(issue)
  }
}

///|
#export_name("salesforceIssuedBroadComplete")
pub fn salesforce_issued_broad_complete(
  attempt : @salesforce_host.SalesforceBroadAttempt,
) -> Bool {
  @salesforce_host.salesforce_broad_attempt_read_complete(attempt)
}

///|
#export_name("salesforceIssuedBroadRowCount")
pub fn salesforce_issued_broad_row_count(
  attempt : @salesforce_host.SalesforceBroadAttempt,
) -> Int64 raise SalesforceCatalogBridgeIssue {
  match @salesforce_host.salesforce_broad_attempt_read_row_count(attempt) {
    Ok(rows) => rows
    Err(issue) => raise BroadAttempt(issue)
  }
}

///|
#export_name("salesforceIssuedBroadFinish")
pub fn salesforce_issued_broad_finish(
  attempt : @salesforce_host.SalesforceBroadAttempt,
) -> Bool raise SalesforceCatalogBridgeIssue {
  match @salesforce_host.finish_issued_salesforce_broad_read(attempt) {
    Ok(_) => true
    Err(issue) => raise BroadAttempt(issue)
  }
}

///|
#export_name("salesforceIssuedBroadAbort")
pub fn salesforce_issued_broad_abort(
  attempt : @salesforce_host.SalesforceBroadAttempt,
) -> Unit {
  @salesforce_host.abort_salesforce_broad_attempt(attempt)
}
