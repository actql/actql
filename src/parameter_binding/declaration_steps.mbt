///|
/// Constructor boundaries of the SAME semantic read, not grants or proofs.
/// Header/type/default reservation remains the caller's responsibility. An
/// input phase is observed, never supplied back as authority to this reader.
pub(all) enum DeclarationReadPhase {
  DeclarationHeader
  DeclarationType
  DeclarationValue
  DeclarationComplete
} derive(Eq, Debug)

///|
priv enum DeclarationReadState {
  AwaitingHeader
  ReadingDeclaration(DeclarationReadBody)
  ReadCompleted(Result[Declarations, Issue])
}

///|
// Only immutable admitted input and already completed original facts. This
// private traversal belongs to DeclarationReadInput, not another Resource Owner.
priv struct DeclarationReadBody {
  object : @decode.ObjectView
  names : Array[String]
  entries : Array[Declaration]
  mut current : @decode.Cursor?
  mut syntax : @contract.ParameterSyntax?
  mut index : Int
}

///|
pub fn declaration_read_phase(
  original : DeclarationReadInput,
) -> DeclarationReadPhase {
  match original.state {
    AwaitingHeader => DeclarationHeader
    ReadingDeclaration(body) =>
      if body.syntax is Some(_) {
        DeclarationValue
      } else {
        DeclarationType
      }
    ReadCompleted(_) => DeclarationComplete
  }
}

///|
/// Borrow the SAME original cursor already selected by the preceding step.
/// No Map lookup, child construction, type read or external current callback.
pub fn declaration_read_type_cursor(
  original : DeclarationReadInput,
) -> @decode.Cursor? {
  match original.state {
    ReadingDeclaration(body) =>
      if body.syntax is None {
        body.current
      } else {
        None
      }
    _ => None
  }
}

///|
/// Borrow the SAME completed ParameterSyntax before metadata/default work.
/// The original checked ParameterType supplies Decimal and other actual Value
/// constructor facts. It is never inferred again from the default or names.
pub fn declaration_read_pending_syntax(
  original : DeclarationReadInput,
) -> @contract.ParameterSyntax? {
  match original.state {
    ReadingDeclaration(body) => body.syntax
    _ => None
  }
}

///|
/// Advance one original constructor boundary AFTER its complete reservation.
/// This performs no Resource mutation, permission/current callback or input
/// preflight. An original first refusal completes the reader; no partial
/// Declarations escape. Completed repeats are callback-free and do no work.
pub fn advance_declaration_read(original : DeclarationReadInput) -> Unit {
  try {
    match original.state {
      AwaitingHeader => declaration_read_header(original)
      ReadingDeclaration(body) =>
        match body.syntax {
          None => declaration_read_type(original, body)
          Some(syntax) => declaration_read_value(original, body, syntax)
        }
      ReadCompleted(_) => ()
    }
  } catch {
    Abort(issue) => original.state = ReadCompleted(Err(issue))
  }
}

///|
fn declaration_read_header(original : DeclarationReadInput) -> Unit raise Abort {
  let entries : Array[Declaration] = []
  match original.root {
    None =>
      original.state = ReadCompleted(Ok({ entries, usage: original.usage, }))
    Some(root) => {
      let object = decoded(@decode.open_object(root))
      let names = decoded(@decode.object_field_names(root))
      if names.is_empty() {
        invalid(root, EmptyDeclarations)
      }
      if names.length() > original.limits.max_parameters {
        invalid(root, ParameterLimit)
      }
      names.sort_by(@canonical.compare_utf16)
      // Every name comes from this SAME immutable admitted object's fields;
      // lookup retains its original Cursor including NULL. The original non-null
      // requirement stays after this entry's name check, never in the header.
      let current = @decode.lookup(object, names[0])
      original.state = ReadingDeclaration({
        object,
        names,
        entries,
        current,
        syntax: None,
        index: 0,
      })
    }
  }
}

///|
fn declaration_read_type(
  original : DeclarationReadInput,
  body : DeclarationReadBody,
) -> Unit raise Abort {
  let name = body.names[body.index]
  if !valid_name(name) {
    match
      @decode.closed_object(
        original.root.unwrap(),
        body.names.filter(n => n != name),
      ) {
      Err(location) =>
        raise Abort(
          ParameterIssue(InvalidName, path=location.path, span=location.span),
        )
      Ok(_) => invalid(original.root.unwrap(), InvalidName)
    }
  }
  let cursor = decoded(@decode.require_non_null_cursor(body.current.unwrap()))
  let syntax = match
    @contract.read_parameter_syntax(cursor, {
      max_nodes: original.limits.max_nodes,
      max_depth: original.limits.max_depth,
      max_text_bytes: original.limits.max_text_bytes,
    }) {
    Ok(value) => value
    Err(issue) => raise Abort(Contract(issue))
  }
  body.syntax = Some(syntax)
}

///|
fn declaration_read_value(
  original : DeclarationReadInput,
  body : DeclarationReadBody,
  syntax : @contract.ParameterSyntax,
) -> Unit raise Abort {
  if syntax.metadata is Some(meta) {
    metadata(meta)
  }
  let default_value = match syntax.default_value {
    None => None
    Some(cursor) =>
      Some(
        check_value(cursor, syntax.parameter_type, {
          max_nodes: original.limits.max_nodes,
          max_depth: original.limits.max_depth,
          max_text_bytes: original.limits.max_text_bytes,
        }),
      )
  }
  body.entries.push({
    name: body.names[body.index],
    source: body.current.unwrap(),
    parameter_type: syntax.parameter_type,
    metadata: syntax.metadata,
    default_cursor: syntax.default_value,
    default_value,
  })
  body.index += 1
  if body.index == body.names.length() {
    original.state = ReadCompleted(
      Ok({ entries: body.entries, usage: original.usage, }),
    )
  } else {
    body.current = @decode.lookup(body.object, body.names[body.index])
    body.syntax = None
  }
}
