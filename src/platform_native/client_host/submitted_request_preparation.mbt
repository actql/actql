///|
// Private views of this caller's own parsed intent. They perform no Resource,
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
/// The ordinary Native command's SAME intent and retained Request. The shared
/// source preflight funds original native decoding before this caller enters
/// it; the shared checker/compiler then consumes that original input once.
/// Failure leaves all Request/physical duties on the already retained parent.
pub fn prepare_native_client_submitted_request(
  owner : @local.ClientRequestPreparation[@host.ClientSubmittedIntent],
  intent : @host.ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
) -> Result[
  (
    NativeClientSubmittedPreparation,
    @resources.PreparationBodyBorrow[@host.PreparedClientProgram],
  ),
  NativeClientSubmittedPreparationIssue,
] {
  match @local.retain_request_submitted_intent(owner, intent, intent) {
    Err(issue) => return Err(RequestPreparation(issue))
    Ok(_) => ()
  }
  let program_limits = match
    @local.request_default_program_preparation_limits(owner, intent) {
    Err(issue) => return Err(Request(issue))
    Ok(value) => value
  }
  let limits = match
    @local.reserve_request_retained_intent_source(owner, intent) {
    Err(issue) => return Err(RequestPreparation(issue))
    Ok(value) => value
  }
  let source = match
    @source.parse_json_bytes_preserving(
      @utf8.encode(@host.client_submitted_intent_wire(intent)),
      {
        max_input_bytes: limits.max_input_bytes,
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
      },
    ) {
    Err(_) => return Err(InvalidSubmittedInput)
    Ok(value) => value
  }
  let reader = submitted_request_source_reader
  let source = Some(source)
  let kind = (reader.text)((reader.field)(source, "kind"))
  let supplied = (reader.field)(source, "parameters")
  let supplied = if (reader.kind)(supplied) == 0 {
    None
  } else {
    Some(supplied)
  }
  let selected = (reader.field)(source, "input")
  let effect_limits = {
    ..@host.client_standard_effect_computation_limits(),
    program: program_limits,
  }
  let prepared = if kind == "program" {
    @local.prepare_request_native_computation(
      owner,
      intent,
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
    @local.prepare_request_native_source_computation(
      owner,
      intent,
      selected,
      reader,
      environment,
      publication,
      [],
      program_limits,
      effect_limits,
      supplied~,
    )
  } else {
    return Err(InvalidSubmittedInput)
  }
  match prepared {
    Err(issue) => return Err(Request(issue))
    Ok(@local.Effect) => return Err(RequestBranchUnavailable)
    Ok(@local.Pure) => ()
  }
  let borrow = match @local.borrow_request_program_plan_input(owner, intent) {
    Err(issue) => return Err(RequestPreparation(issue))
    Ok(value) => value
  }
  let original = @resources.preparation_body_borrow_value(borrow).unwrap()
  Ok(
    (
      {
        intent_cid: @host.client_submitted_intent_cid(intent),
        preparation: Computation(original),
      },
      borrow,
    ),
  )
}
