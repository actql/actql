///|
// Existing bounded source/owned-tree/Resource readers, not a Run state machine,
// restoration issuer or another resource Owner. Each child is retired at the
// same transition that transfers its output borrow to the next existing codec.
priv enum OriginalCurrentDecodePhase {
  Parsing(@source.JsonParse)
  Admitting(@decode.Admission)
  Reading(@resources.OriginalCurrentStateDocumentRead)
  Retired
}

///|
// All five fields, source/owned trees, transition overlap and output document
// belong to the original installing envelope BEFORE construction. Work is a
// local codec bound, not a conversion into Model or Ledger planning work.
struct OriginalModelCurrentStateDecode {
  mut park : @publication_host.ClientModelResourcePark?
  mut phase : OriginalCurrentDecodePhase
  mut remaining : Int
  tree_limits : @decode.Limits
  reader_work : Int
}

///|
pub(all) enum OriginalModelCurrentStateDecodeIssue {
  Original(@resources.OriginalReadIssue)
  Parse(@source.ParseError)
  Admission(@decode.Issue)
  Read(@resources.OriginalCurrentStateReadIssue)
  InvalidBounds
  InvalidQuantum
  InvalidRecord
  WorkLimit
  Terminal
} derive(Eq, Debug)

///|
pub enum OriginalModelCurrentStateDecodePoll {
  CurrentDecodeContinue(work~ : Int)
  CurrentDecodeComplete(@resources.OriginalCurrentStateDocument, work~ : Int)
  CurrentDecodeFailed(OriginalModelCurrentStateDecodeIssue, work~ : Int)
}

///|
pub fn start_original_model_current_state_decode(
  active : Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  wire : String,
  parse_limits : @source.ParseLimits,
  tree_limits : @decode.Limits,
  max_work : Int,
) -> Result[
  OriginalModelCurrentStateDecode,
  OriginalModelCurrentStateDecodeIssue,
] {
  guard original_model_resource_park_current(active, scope, park) is Some(_) &&
    active.run_binding is Some(bound) &&
    active.plan is Some(plan) else {
    return Err(Original(@resources.ChangedOriginalState))
  }
  let bounds = match
    @publication_host.client_model_current_state_read_bounds(
      park,
      scope,
      bound.compiled,
      bound.definition,
      plan,
    ) {
    Ok(bounds) => bounds
    Err(_) => return Err(Original(@resources.ChangedOriginalState))
  }
  if tree_limits.max_nodes < 0 ||
    tree_limits.max_depth < 0 ||
    tree_limits.max_string_bytes < 0 ||
    tree_limits.max_total_string_bytes < 0 ||
    max_work < 0 {
    return Err(InvalidBounds)
  }
  if max_work < bounds.reader_work {
    return Err(WorkLimit)
  }
  let parse = match
    @source.start_json_parse(wire, parse_limits, data_keys=true) {
    Ok(parse) => parse
    Err(issue) => return Err(Parse(issue))
  }
  Ok({
    park: Some(park),
    phase: Parsing(parse),
    remaining: max_work,
    tree_limits,
    reader_work: bounds.reader_work,
  })
}

///|
pub fn cancel_original_model_current_state_decode(
  value : OriginalModelCurrentStateDecode,
) -> Unit {
  match value.phase {
    Parsing(child) => @source.cancel_json_parse(child)
    Admitting(child) => @decode.cancel_admission(child)
    Reading(child) =>
      @resources.cancel_original_current_state_document_read(child)
    Retired => ()
  }
  value.phase = Retired
  value.park = None
}

///|
fn fail_original_current_decode(
  value : OriginalModelCurrentStateDecode,
  issue : OriginalModelCurrentStateDecodeIssue,
  work : Int,
) -> OriginalModelCurrentStateDecodePoll {
  cancel_original_model_current_state_decode(value)
  CurrentDecodeFailed(issue, work~)
}

///|
pub fn advance_original_model_current_state_decode(
  active : Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  value : OriginalModelCurrentStateDecode,
  quantum : Int,
) -> OriginalModelCurrentStateDecodePoll {
  if quantum < 1 {
    return CurrentDecodeFailed(InvalidQuantum, work=0)
  }
  guard value.park is Some(original) &&
    physical_equal(original, park) &&
    original_model_resource_park_current(active, scope, park) is Some(_) &&
    active.run_binding is Some(bound) &&
    active.plan is Some(plan) else {
    // A foreign observer cannot cancel or progress someone else's codec.
    return CurrentDecodeFailed(
      Original(@resources.ChangedOriginalState),
      work=0,
    )
  }
  let mut work = 0
  while work < quantum {
    if value.remaining == 0 {
      return fail_original_current_decode(value, WorkLimit, work)
    }
    let allowance = Int::min(quantum - work, value.remaining)
    match value.phase {
      Parsing(child) => {
        let poll = match @source.advance_json_parse(child, allowance) {
          Ok(poll) => poll
          Err(_) =>
            return fail_original_current_decode(value, InvalidRecord, work)
        }
        let spent = match poll {
          @source.JsonParseContinue(work~)
          | @source.JsonParseComplete(_, work~)
          | @source.JsonParseFailed(_, work~) => work
        }
        work += spent
        value.remaining -= spent
        match poll {
          @source.JsonParseContinue(..) =>
            if spent == 0 {
              return fail_original_current_decode(value, InvalidRecord, work)
            }
          @source.JsonParseFailed(issue, ..) =>
            return fail_original_current_decode(value, Parse(issue), work)
          @source.JsonParseComplete(parsed, ..) => {
            if value.remaining == 0 {
              return fail_original_current_decode(value, WorkLimit, work)
            }
            let next = @decode.start_admission(parsed.node, value.tree_limits)
            @source.cancel_json_parse(child)
            match next {
              Err(issue) =>
                return fail_original_current_decode(
                  value,
                  Admission(issue),
                  work,
                )
              Ok(next) => value.phase = Admitting(next)
            }
          }
        }
      }
      Admitting(child) => {
        let poll = match @decode.advance_admission(child, allowance) {
          Ok(poll) => poll
          Err(_) =>
            return fail_original_current_decode(value, InvalidRecord, work)
        }
        let spent = match poll {
          @decode.AdmissionContinue(work~)
          | @decode.AdmissionComplete(_, work~)
          | @decode.AdmissionFailed(_, work~) => work
        }
        work += spent
        value.remaining -= spent
        match poll {
          @decode.AdmissionContinue(..) =>
            if spent == 0 {
              return fail_original_current_decode(value, InvalidRecord, work)
            }
          @decode.AdmissionFailed(issue, ..) =>
            return fail_original_current_decode(value, Admission(issue), work)
          @decode.AdmissionComplete(root, ..) => {
            // Keep the ENTIRE owned envelope tree through this child borrow.
            // Common document/CID and Store custody are checked separately.
            if value.remaining < value.reader_work {
              return fail_original_current_decode(value, WorkLimit, work)
            }
            let source = match @decode.open_object(root) {
              Ok(object) =>
                match @decode.field(object, "resource_state") {
                  @decode.Present(source) => source
                  _ =>
                    return fail_original_current_decode(
                      value,
                      InvalidRecord,
                      work,
                    )
                }
              _ =>
                return fail_original_current_decode(value, InvalidRecord, work)
            }
            let next = @publication_host.start_client_model_current_state_document_read(
              park,
              scope,
              bound.compiled,
              bound.definition,
              plan,
              source,
              value.reader_work,
              value.tree_limits,
            )
            @decode.cancel_admission(child)
            match next {
              Err(issue) =>
                return fail_original_current_decode(value, Read(issue), work)
              Ok(next) => value.phase = Reading(next)
            }
          }
        }
      }
      Reading(child) => {
        let poll = @resources.advance_original_current_state_document_read(
          child, allowance,
        )
        let spent = match poll {
          @resources.CurrentDocumentContinue(work~)
          | @resources.CurrentDocumentComplete(_, work~)
          | @resources.CurrentDocumentFailed(_, work~) => work
        }
        work += spent
        value.remaining -= spent
        match poll {
          @resources.CurrentDocumentContinue(..) =>
            if spent == 0 {
              return fail_original_current_decode(value, InvalidRecord, work)
            }
          @resources.CurrentDocumentFailed(issue, ..) =>
            return fail_original_current_decode(
              value,
              Read(@resources.Document(issue)),
              work,
            )
          @resources.CurrentDocumentComplete(document, ..) => {
            value.phase = Retired
            value.park = None
            return CurrentDecodeComplete(document, work~)
          }
        }
      }
      Retired => return CurrentDecodeFailed(Terminal, work~)
    }
  }
  CurrentDecodeContinue(work~)
}

///|
pub fn start_original_model_current_state_comparison(
  active : Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  document : @resources.OriginalCurrentStateDocument,
  max_work : Int,
) -> Result[
  @publication_host.ClientModelCurrentStateComparison,
  @resources.OriginalStateComparisonIssue,
] {
  guard original_model_resource_park_current(active, scope, park) is Some(_) &&
    active.run_binding is Some(bound) &&
    active.plan is Some(plan) else {
    return Err(@resources.Original(@resources.ChangedOriginalState))
  }
  @publication_host.start_client_model_current_state_comparison(
    park,
    scope,
    bound.compiled,
    bound.definition,
    plan,
    document,
    max_work,
  )
}

///|
pub fn advance_original_model_current_state_comparison(
  active : Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  value : @publication_host.ClientModelCurrentStateComparison,
  quantum : Int,
) -> Result[
  @resources.OriginalStateComparisonPoll,
  @publication_host.ClientModelReadPreparationIssue,
] {
  guard original_model_resource_park_current(active, scope, park) is Some(_) &&
    active.run_binding is Some(bound) &&
    active.plan is Some(plan) else {
    return Err(@publication_host.Resource(@resources.ChangedOriginalState))
  }
  @publication_host.advance_client_model_current_state_comparison(
    value,
    park,
    scope,
    bound.compiled,
    bound.definition,
    plan,
    quantum,
  )
}
