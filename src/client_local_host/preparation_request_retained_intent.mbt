///|
// Private views of this Request's own parsed intent. They perform no Resource,
// current, permission or provider operation and cannot supply an input grant.
let submitted_request_source_reader : @source.JsonDataReader[@source.Node?] = {
  kind: value => {
    match value {
      None => 6
      Some(node) =>
        match node.value {
          @source.Null => 0
          @source.Bool(_) => 1
          @source.Number(_) => 2
          @source.String(_) => 3
          @source.Array(_) => 4
          @source.Object(_) => 5
        }
    }
  },
  boolean: value => {
    match value {
      Some({ value: @source.Bool(value), .. }) => value
      _ => false
    }
  },
  number_text: value => {
    match value {
      Some({ value: @source.Number(value), .. }) => value.to_string()
      _ => ""
    }
  },
  text: value => {
    match value {
      Some({ value: @source.String(value), .. }) => value
      _ => ""
    }
  },
  keys: value => {
    match value {
      Some({ value: @source.Object(fields), .. }) => {
        let keys = FixedArray::make(fields.length(), "")
        for index, field in fields {
          keys[index] = field.key
        }
        keys
      }
      _ => []
    }
  },
  length: value => {
    match value {
      Some({ value: @source.Array(values), .. }) => values.length()
      _ => 0
    }
  },
  field: (value, key) => {
    match value {
      Some({ value: @source.Object(fields), .. }) => {
        let mut selected : @source.Node? = None
        for field in fields {
          if field.key == key {
            selected = Some(field.value)
            break
          }
        }
        selected
      }
      Some({ value: @source.Array(values), .. }) => {
        let index = @string.parse_int(key) catch { _ => -1 }
        values.get(index)
      }
      _ => None
    }
  },
}

///|
/// The retained-intent entrance preserves the existing Request's distinctions
/// between input, custody and typed semantic refusal.
pub(all) enum ClientRequestRetainedIntentIssue {
  InvalidInput
  Preparation(ClientRequestPreparationIssue)
  Request(ClientRequestTerminalIssue)
}

///|
/// Admit the same canonical intent under the original Request before invoking
/// the existing Program or Source checker. The returned limits belong to that
/// check; the caller still owns policy callbacks and subsequent compilation.
pub fn[I] check_request_retained_submitted_intent(
  owner : ClientRequestPreparation[I],
  input : I,
  intent : @publication_host.ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  public_primary~ : Bool,
) -> Result[
  @publication_host.ClientProgramPreparationLimits,
  ClientRequestRetainedIntentIssue,
] {
  match retain_request_submitted_intent(owner, input, intent) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  let limits = match reserve_request_retained_intent_source(owner, input) {
    Err(issue) => return Err(Preparation(issue))
    Ok(value) => value
  }
  let source = match
    @source.parse_json_bytes_preserving(
      @utf8.encode(@publication_host.client_submitted_intent_wire(intent)),
      {
        max_input_bytes: limits.max_input_bytes,
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
      },
    ) {
    Err(_) => return Err(InvalidInput)
    Ok(value) => value
  }
  let reader = submitted_request_source_reader
  let source = Some(source)
  let kind = (reader.text)((reader.field)(source, "kind"))
  // Program and Source select the same observed default inventory. The Source
  // entrance selects it once below, after retaining its original document.
  let program_limits = if kind == "program" {
    match request_default_program_preparation_limits(owner, input) {
      Err(issue) => return Err(Request(issue))
      Ok(value) => value
    }
  } else {
    @publication_host.client_standard_program_preparation_limits()
  }
  let supplied = (reader.field)(source, "parameters")
  let supplied = if (reader.kind)(supplied) == 0 {
    None
  } else {
    Some(supplied)
  }
  let selected = (reader.field)(source, "input")
  let effect_limits = {
    ..@publication_host.client_standard_effect_computation_limits(),
    program: program_limits,
  }
  let prepared = if kind == "program" {
    prepare_request_native_computation_check(
      owner,
      input,
      selected,
      reader,
      environment,
      publication,
      [],
      program_limits,
      effect_limits,
      supplied~,
    )
  } else if kind == "aql" {
    prepare_request_default_source_computation_check(
      owner,
      input,
      selected,
      reader,
      environment,
      publication,
      [],
      program_limits.values_max_rows,
      effect_limits,
      supplied~,
      // The installed caller retains its original result convention.
      public_primary~,
    )
  } else {
    return Err(InvalidInput)
  }
  match prepared {
    Err(issue) => return Err(Request(issue))
    Ok(_) => ()
  }
  Ok(program_limits)
}
