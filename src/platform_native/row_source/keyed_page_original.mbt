///|
/// Bind this SAME Source's confirmed raw Store child and actual admitted
/// page. The caller retains the returned immutable metadata before Journal
/// persistence; this entry itself issues neither adoption nor COMMIT/ACK.
pub fn NativeRelationFileCapture::prepare_keyed_page_original(
  self : Self,
  max_rows : Int,
  values : @execution.ValueLimits,
  payload_wire : @execution.RowWireLimits,
  logical_wire : @execution.RowWireLimits,
  schema : @execution.RelationSchemaIdentityLimits,
  max_work : Int,
  workspace : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientKeyedNativeCapturedPage,
  NativeRelationFileFailure,
] {
  if self.advancing {
    return Err(self.fail(Unavailable))
  }
  let raw = match self.keyed_raw_response() {
    Ok(value) => value
    Err(issue) => return Err(self.fail(issue))
  }
  guard self.retained_keyed_original() &&
    self.phase is Captured &&
    self.keyed_result is Some(capture) &&
    self.content is Some(content) &&
    content.input is Some(input) &&
    content.captured_page is None else {
    return Err(self.fail(Unavailable))
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  let at = (input.now_utc)()
  guard self.retained_keyed_original() &&
    self.phase is Captured &&
    self.content is Some(same) &&
    physical_equal(same, content) &&
    content.captured_page is None else {
    return Err(self.fail(Unavailable))
  }
  let page = match
    @publication_host.prepare_client_keyed_native_captured_page(
      input.request,
      capture,
      raw,
      at,
      max_rows,
      values,
      payload_wire,
      logical_wire,
      schema,
      max_work,
      workspace,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(self.fail(Lookup(issue)))
  }
  guard self.retained_keyed_original() &&
    self.phase is Captured &&
    self.content is Some(same) &&
    physical_equal(same, content) &&
    content.captured_page is None else {
    return Err(self.fail(Unavailable))
  }
  content.captured_page = Some(page)
  Ok(page)
}

///|
/// Pure original association for the Host's SAME captured Read transaction.
/// It does not enter the execution domain, call current or authorize Source I/O.
pub fn NativeRelationFileCapture::keyed_captured_page_matches(
  self : Self,
  page : @publication_host.ClientKeyedNativeCapturedPage,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @publication_host.ClientInferPlanGraph,
) -> Bool {
  guard self.retained_keyed_original() &&
    self.phase is Captured &&
    self.content is Some(content) &&
    content.input is Some(input) &&
    content.captured_page is Some(same) &&
    physical_equal(same, page) else {
    return false
  }
  @publication_host.client_keyed_native_captured_page_matches(
    page,
    input.request,
    request,
    compiled,
    definition,
    graph,
  )
}
