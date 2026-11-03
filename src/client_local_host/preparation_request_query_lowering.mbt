///|
// One retained ordinary lowerer call on the same Request. This is DATA, not a
// second preparation owner, permission or mutable installation cache.
priv struct ClientRequestQueryLowering {
  publication : @source_publication.PreparedPublishedQueryEnvironment
  environment : @checked.CheckEnvironment
  declarations : String?
  public_primary : Bool
  binding_limits : @admitted.Limits?
  mut refusal_binding : ClientRequestQueryRefusalBinding?
  quote : (Int64, Int64)
  mut output : Result[
    (
      @frontend.Lowered,
      @checked.PreparedSourceCatalog,
      @frontend.DiagnosticSource,
    ),
    ClientRequestQueryLoweringIssue,
  ]?
}

///|
pub suberror ClientRequestQueryLoweringIssue {
  Request(ClientRequestPreparationIssue)
  Publication(@source_publication.PreparedPublicationIssue)
  WithBinding(ClientRequestQueryLoweringIssue, @parameters.Issue)
  BindingFailure(ClientRequestQueryLoweringIssue, ClientRequestPreparationIssue)
  BindingException(ClientRequestQueryLoweringIssue, QueryBindingForeignFailure)
  Overflow
}

///|
// Query text/declarations and retained Catalog sizes bound the generated
// syntax, expanded fields, maps and canonical output overlap. The Catalog is
// borrowed; its original usage is DATA, not a repeated admission or charge
// for its historical work. One shared coarse tariff replaces a helper census.
fn request_query_lowering_data_bytes(
  query : ClientRequestQuerySyntax,
  declarations : String?,
  catalog : @checked.PreparedSourceCatalog,
) -> Int64? {
  let usage = @checked.source_catalog_usage(catalog)
  let units = query.document.length().to_int64() +
    (match declarations {
      Some(value) => value.length().to_int64()
      None => 0L
    }) +
    usage.bytes.to_int64() +
    usage.nodes.to_int64() +
    1L
  request_snapshot_data_bytes(units, units)
}

///|
/// The same already parsed Query enters the existing published lowerer once.
/// A failed capacity grow retains the original immutable tuple and quote;
/// it cannot trigger a second parse, Catalog read or completed lowerer call.
/// Existing lowerer budgets retain their bounds. Syntax work observations do
/// not become a complete meter of this later semantic/construction phase.
pub fn[I] lower_request_published_query(
  owner : ClientRequestPreparation[I],
  input : I,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  environment : @checked.CheckEnvironment,
  declarations : String?,
  public_primary? : Bool = false,
  binding_limits? : @admitted.Limits? = None,
) -> Result[
  (
    @frontend.Lowered,
    @checked.PreparedSourceCatalog,
    @frontend.DiagnosticSource,
  ),
  ClientRequestQueryLoweringIssue,
] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(Request(ForeignOriginal))
  }
  guard (owner.phase == QuerySyntaxParsed || owner.phase == QueryLoweringQuoted) &&
    owner.query_syntax is Some(query) &&
    query.query is Some(Ok(parsed)) else {
    return Err(Request(WrongPhase))
  }
  let source = if owner.source_input is Some(context) {
    guard request_source_input_original(owner) is Some(source) &&
      physical_equal(context.environment, environment) else {
      return Err(Request(ForeignOriginal))
    }
    let parts = match @publication_host.client_source_input_parts(source) {
      Err(issue) => return Err(Request(SourceInput(Source(issue))))
      Ok(parts) => parts
    }
    if parts.2 != declarations {
      return Err(Request(ForeignOriginal))
    }
    Some(source)
  } else {
    None
  }
  if source is None && owner.native_parameters_ready && declarations is Some(_) {
    return Err(Request(ForeignOriginal))
  }
  if owner.phase == QuerySyntaxParsed {
    let catalog = match
      @source_publication.prepared_published_query_catalog(
        publication, environment,
      ) {
      Err(issue) => return Err(Publication(issue))
      Ok(value) => value
    }
    let control = if owner.native_query_declarations is Some(_) &&
      owner.native_parameters is Some(_) &&
      binding_limits is Some(_) {
      request_query_refusal_binding_control_bytes()
    } else {
      Some(0L)
    }
    guard request_query_lowering_data_bytes(query, declarations, catalog)
      is Some(data) &&
      control is Some(control) &&
      @execution.checked_preparation_add_product(data, control, 1L)
      is Some(bytes) else {
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
    query.lowering = Some({
      publication,
      environment,
      declarations,
      public_primary,
      binding_limits,
      refusal_binding: None,
      quote: (r, e),
      output: None,
    })
    owner.phase = QueryLoweringQuoted
  }
  guard query.lowering is Some(selected) &&
    physical_equal(selected.publication, publication) &&
    physical_equal(selected.environment, environment) &&
    selected.declarations == declarations &&
    selected.public_primary == public_primary &&
    selected.binding_limits == binding_limits else {
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
      owner.phase = QueryLoweringQuoted
      return Err(Request(Capacity(issue)))
    }
    Ok(_) => ()
  }
  let outcome = if source is Some(source) {
    @publication_host.lower_client_source_input_query(
      source,
      selected.publication,
      selected.environment,
      parsed,
      public_primary=selected.public_primary,
    ).map_err(issue => {
      ClientRequestQueryLoweringIssue::Request(SourceInput(Source(issue)))
    })
  } else if owner.native_parameters_ready {
    @source_publication.lower_prepared_query_with_declarations(
      selected.publication,
      selected.environment,
      parsed,
      owner.native_query_declarations.map(pair => pair.1),
      public_primary=selected.public_primary,
    ).map_err(issue => Publication(issue))
  } else {
    @source_publication.lower_prepared_published_parsed_query(
      selected.publication,
      selected.environment,
      parsed,
      selected.declarations,
      public_primary=selected.public_primary,
    ).map_err(issue => Publication(issue))
  }
  owner.phase = QueryLoweringFailed
  selected.output = Some(outcome)
  match outcome {
    Err(issue) => {
      if owner.native_query_declarations is None ||
        owner.native_parameters is None ||
        selected.binding_limits is None {
        return Err(issue)
      }
      match
        query_binding_protected_call(
          () => finish_request_query_refusal_binding(owner, input, selected),
          () => {
            pause_request_query_refusal_binding(selected)
            if owner.phase == Selecting {
              owner.phase = QueryLoweringFailed
            }
          },
        ) {
        Ok(Ok(Some(binding))) => Err(WithBinding(issue, binding))
        Ok(Ok(None)) => Err(issue)
        Ok(Err(failure)) => Err(BindingFailure(issue, failure))
        Err(failure) => Err(BindingException(issue, failure))
      }
    }
    Ok(output) => {
      guard output.0.program is Some(program) else {
        return Err(Request(WrongPhase))
      }
      owner.held_program = Some(program)
      owner.phase = QueryLowered
      Ok(output)
    }
  }
}

///|
/// Completed original DATA only. This performs no Catalog admission, lowerer,
/// encoding or external current callback and grants no execution permission.
pub fn[I] prepared_request_query_lowering(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[
  (
    @frontend.Lowered,
    @checked.PreparedSourceCatalog,
    @frontend.DiagnosticSource,
  ),
  ClientRequestQueryLoweringIssue,
] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(Request(ForeignOriginal))
  }
  guard owner.phase != Selecting &&
    owner.query_syntax is Some(query) &&
    query.lowering is Some(selected) &&
    selected.output is Some(Ok(output)) else {
    return Err(Request(WrongPhase))
  }
  Ok(output)
}
