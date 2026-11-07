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
/// Original body borrow selected by the SAME Request checker/compiler. Neither
/// variant creates another preparation, body, permission or cleanup Owner.
pub enum NativeClientSubmittedRequestBody {
  Program(@resources.PreparationBodyBorrow[@host.PreparedClientProgram])
  Effect(@resources.PreparationBodyBorrow[@host.PreparedClientEffectComputation])
}

///|
/// Return the original typed borrow, preserving the Resource result. This is
/// neither physical retirement nor permission to abort a live child.
pub fn return_native_client_submitted_request_body(
  body : NativeClientSubmittedRequestBody,
) -> Result[Bool, @resources.PreparationCapacityIssue] {
  match body {
    Program(original) => @resources.return_preparation_body_borrow(original)
    Effect(original) => @resources.return_preparation_body_borrow(original)
  }
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
    NativeClientSubmittedRequestBody,
  ),
  NativeClientSubmittedPreparationIssue,
] {
  prepare_native_client_submitted_request_input(
    owner, intent, intent, environment, publication,
  )
}

///|
/// SAME original producer input, selected and backed before its file/intent
/// constructor. The existing typed intent remains actual input DATA; this
/// overload changes no issuer, permission, checker/compiler or cleanup owner.
pub fn[I] prepare_native_client_submitted_request_input(
  owner : @local.ClientRequestPreparation[I],
  input : I,
  intent : @host.ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
) -> Result[
  (
    NativeClientSubmittedPreparation,
    NativeClientSubmittedRequestBody,
  ),
  NativeClientSubmittedPreparationIssue,
] {
  match
    check_native_client_submitted_request_input(
      owner, input, intent, environment, publication,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let kind = match
    @local.finish_request_checked_computation(
      owner, input, environment, publication,
    ) {
    Err(issue) => return Err(Request(issue))
    Ok(value) => value
  }
  // Common already compiled and continued to the selected body capacity.
  // Do not check, compile or continue it a second time at this Native handoff.
  match kind {
    @local.Pure => {
      let borrow = match @local.borrow_request_program_plan_input(owner, input) {
        Err(issue) => return Err(RequestPreparation(issue))
        Ok(value) => value
      }
      let original = @resources.preparation_body_borrow_value(borrow).unwrap()
      Ok(({
        intent_cid: @host.client_submitted_intent_cid(intent),
        preparation: Computation(original),
      }, Program(borrow)))
    }
    @local.Effect => {
      let borrow = match @local.borrow_request_effect_plan_input(owner, input) {
        Err(issue) => return Err(RequestPreparation(issue))
        Ok(value) => value
      }
      let original = @resources.preparation_body_borrow_value(borrow).unwrap()
      Ok(({
        intent_cid: @host.client_submitted_intent_cid(intent),
        preparation: EffectComputation(original),
      }, Effect(borrow)))
    }
  }
}

///|
/// Same original Request intake and semantic checker, before compilation or
/// eventual body selection. Static check/explain callers keep this parent and
/// its original outcome; neither a second parser nor a Run is issued here.
pub fn[I] check_native_client_submitted_request_input(
  owner : @local.ClientRequestPreparation[I],
  input : I,
  intent : @host.ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
) -> Result[Unit, NativeClientSubmittedPreparationIssue] {
  match @local.retain_request_submitted_intent(owner, input, intent) {
    Err(issue) => return Err(RequestPreparation(issue))
    Ok(_) => ()
  }
  let limits = match
    @local.reserve_request_retained_intent_source(owner, input) {
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
  // A structured Program uses its observed native inventory. Source carries
  // a document in Text: that envelope is not the document's node inventory.
  // Preserve the existing Native Source policy rather than treating the outer
  // captured Text as a new structural restriction on its authored document.
  let program_limits = if kind == "program" {
    match @local.request_default_program_preparation_limits(owner, input) {
      Err(issue) => return Err(Request(issue))
      Ok(value) => value
    }
  } else {
    let standard = @host.client_standard_program_preparation_limits()
    let selected = (reader.field)(source, "input")
    let document = (reader.field)(selected, "text")
    if (reader.kind)(document) == 3 {
      let bound = (reader.text)(document).length().to_int64() * 3L + 128L
      if bound >= 2147483519L {
        return Err(SubmittedInputLimit)
      }
      // Keep the existing Source node/depth policy. Byte storage follows the
      // actual immutable document; a Text never fabricates structural nodes.
      // Preserve the old floor for generated Query/contract material as well.
      let source = standard.checking.input.source
      let tree = standard.checking.input.tree
      let bytes = Int::max(source.max_input_bytes, bound.to_int())
      {
        ..standard,
        checking: {
          ..standard.checking,
          input: {
            ..standard.checking.input,
            source: { ..source, max_input_bytes: bytes, },
            tree: {
              ..tree,
              max_string_bytes: Int::max(tree.max_string_bytes, bytes),
              max_total_string_bytes: Int::max(
                tree.max_total_string_bytes,
                bytes,
              ),
            },
          },
        },
      }
    } else {
      standard
    }
  }
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
    @local.prepare_request_native_computation_check(
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
    @local.prepare_request_native_source_computation_check(
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
      // Preserve this installed Native entry's configured primary. The new
      // SDK public Source convention remains the Core default, separately.
      public_primary=false,
    )
  } else {
    return Err(InvalidSubmittedInput)
  }
  prepared.map_err(issue => Request(issue))
}
