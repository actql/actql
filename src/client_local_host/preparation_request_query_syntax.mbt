///|
// Domain DATA on the existing Request, not a new Resource or cleanup owner.
priv struct ClientRequestQuerySyntax {
  document : String
  format : @frontend.Format
  source_path : String
  quote : (Int64, Int64)
  // Reuse the existing outcome slot for the original success or failure.
  mut query : Result[@query_syntax.Query, ClientRequestQuerySyntaxIssue]?
  mut known_work : Int64
  mut counters_complete : Bool
  mut lowering : ClientRequestQueryLowering?
}

///|
pub(all) suberror ClientRequestQuerySyntaxIssue {
  Request(ClientRequestPreparationIssue)
  Frontend(@frontend.Issue)
  Work(@resources.PreparationWorkIssue)
  Overflow
}

///|
// One coarse input-proportional envelope for the original document index,
// decoded token/identifier storage, syntax records and live parsing overlap.
// The original borrowed source String is not another owned input. This uses
// the existing shared representation tariff, not a wrapper census or a heap
// measurement. Catalog/Context/lowering and external backing are separate.
fn request_query_syntax_data_bytes(document : String) -> Int64? {
  let units = document.length().to_int64() + 1L
  @execution.preparation_representation_cost({
    record_headers: 4L * units,
    reference_slots: 12L * units,
    scalar_words: 20L * units,
    owned_utf16_units: 4L * units,
    owned_wire_bytes: 4L * units,
  })
}

///|
/// The completed immutable query original, not a currentness/Run permission.
/// No external callback or constructor is entered by this DATA projection.
pub fn[I] prepared_request_query_syntax(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[@query_syntax.Query, ClientRequestQuerySyntaxIssue] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(Request(ForeignOriginal))
  }
  guard owner.phase == QuerySyntaxParsed &&
    owner.query_syntax is Some(selected) &&
    selected.query is Some(Ok(query)) else {
    return Err(Request(WrongPhase))
  }
  Ok(query)
}

///|
/// Original declared counter DATA, including an explicitly incomplete prefix.
/// This does not report total preparation work, physical stop or permission.
pub fn[I] request_query_syntax_work(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[(Int64, Bool), ClientRequestQuerySyntaxIssue] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(Request(ForeignOriginal))
  }
  guard (owner.phase == QuerySyntaxParsed || owner.phase == QuerySyntaxFailed) &&
    owner.query_syntax is Some(selected) else {
    return Err(Request(WrongPhase))
  }
  Ok((selected.known_work, selected.counters_complete))
}

///|
/// Fund and parse the selected SQL/Pipe syntax on this SAME original Request.
/// A declined grow retains its original document/format/quote. The successful
/// query is the original next lowerer's input, not a checked/runnable Program.
pub fn[I] parse_request_query_syntax(
  owner : ClientRequestPreparation[I],
  input : I,
  document : String,
  format : @frontend.Format,
  source_path? : String = "<source>",
) -> Result[@query_syntax.Query, ClientRequestQuerySyntaxIssue] {
  if !request_intent_input_ready(owner) ||
    (owner.phase != Open && owner.phase != QuerySyntaxQuoted) {
    return Err(Request(WrongPhase))
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(Request(ForeignOriginal))
  }
  let source = if owner.source_input is Some(_) {
    guard request_source_input_original(owner) is Some(source) else {
      return Err(Request(ForeignOriginal))
    }
    let parts = match @publication_host.client_source_input_parts(source) {
      Err(issue) => return Err(Request(SourceInput(Source(issue))))
      Ok(parts) => parts
    }
    if parts.0 != document || parts.1 != format {
      return Err(Request(ForeignOriginal))
    }
    Some(source)
  } else {
    None
  }
  if format != @frontend.Sql && format != @frontend.Text {
    return Err(Frontend(@frontend.InvalidFormat))
  }
  if owner.phase == Open {
    guard request_query_syntax_data_bytes(document) is Some(bytes) else {
      return Err(Overflow)
    }
    let (r, e) = match
      @resources.preparation_capacity_working_extents(owner.capacity, input) {
      Err(issue) => return Err(Request(Capacity(issue)))
      Ok(value) => value
    }
    guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
      @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
      return Err(Overflow)
    }
    owner.query_syntax = Some({
      document,
      format,
      source_path,
      quote: (r, e),
      query: None,
      known_work: 0L,
      counters_complete: false,
      lowering: None,
    })
    owner.phase = QuerySyntaxQuoted
  }
  guard owner.query_syntax is Some(selected) &&
    selected.document == document &&
    selected.format == format &&
    selected.source_path == source_path else {
    return Err(Request(ForeignOriginal))
  }
  owner.phase = Selecting
  match
    @resources.reserve_working_preparation_phase(
      owner.capacity,
      input,
      selected.quote.0,
      selected.quote.1,
    ) {
    Err(issue) => {
      owner.phase = QuerySyntaxQuoted
      return Err(Request(Capacity(issue)))
    }
    Ok(_) => ()
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.LexicalScan,
      @frontend.query_syntax_work_limit(),
    ) {
    Err(issue) => {
      owner.phase = QuerySyntaxFailed
      return Err(Work(issue))
    }
    Ok(value) => value
  }
  // The existing parser observer reports actual work after its own guards.
  // A Source wrapper's pre-work refusal cannot manufacture a parser call.
  let calls = Ref(0L)
  let (outcome, known, complete) = match source {
    None =>
      @frontend.observe_parse_query(
        selected.document,
        selected.format,
        source_path=selected.source_path,
        calls_out=Some(calls),
      )
    Some(source) =>
      match
        @publication_host.observe_client_source_input_query(
          source,
          source_path=selected.source_path,
          calls_out=Some(calls),
        ) {
        Ok(observed) => observed
        Err(issue) => {
          let closed = @resources.finish_preparation_phase_work64(work)
          owner.phase = QuerySyntaxFailed
          match closed {
            Err(failure) => return Err(Work(failure))
            Ok(_) => {
              let result = Err(
                ClientRequestQuerySyntaxIssue::Request(
                  SourceInput(Source(issue)),
                ),
              )
              selected.query = Some(result)
              return result
            }
          }
        }
      }
  }
  owner._observed_query_parse_calls += calls.val
  selected.known_work = known
  selected.counters_complete = complete
  let charged = @resources.spend_preparation_phase_work64(work, known)
  let closed = @resources.finish_preparation_phase_work64(work)
  owner.phase = QuerySyntaxFailed
  match charged {
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  match closed {
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  let result = outcome.map_err(issue => {
    ClientRequestQuerySyntaxIssue::Frontend(issue)
  })
  selected.query = Some(result)
  if result is Ok(_) {
    owner.phase = QuerySyntaxParsed
  }
  result
}
