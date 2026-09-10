///|
pub type Limits = @alignment.Limits

///|
pub type Usage = @alignment.Usage

///|
pub(all) enum Operation {
  Except
  Intersect
} derive(Eq, Debug)

///|
pub(all) enum Duplicates {
  Distinct
  All
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  BudgetExceeded
  InvalidBody
  InvalidName(String)
  InvalidDuplicates
  Schema(@alignment.IssueKind)
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  source : @decode.Cursor
  path : Array[@decode.PathSegment]
  span : @span.Span
}

///|
pub(all) enum Obligation {
  ValidateInputRows
  CompareCompleteTypedRows
  PreserveEarliestLeftOccurrences
  BoundOutputByLeftInput
  ResolveComparisonResources
  ResolveIdentityAndCompleteness
} derive(Eq, Debug)

///|
struct CheckedSet {
  operation : Operation
  source : @decode.Cursor
  with_name : String
  duplicates : Duplicates
  left : @schema.Schema
  right : @schema.Schema
  aligned : @alignment.AlignedSchemas
  usage : Usage
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn[T] fail(source : @decode.Cursor, kind : IssueKind) -> T raise Stop {
  raise Stop({
    kind,
    source,
    path: @decode.cursor_path(source),
    span: @decode.cursor_span(source),
  })
}

///|
pub fn check(
  operation : Operation,
  source : @decode.Cursor,
  left : @schema.Schema,
  right : @schema.Schema,
  limits : Limits,
) -> Result[CheckedSet, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_text_bytes < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 {
      fail(source, InvalidLimits)
    }
    if limits.max_nodes < 3 || limits.max_work < 3 || limits.max_depth < 1 {
      fail(source, BudgetExceeded)
    }
    let object = match @decode.closed_object(source, ["with", "duplicates"]) {
      Ok(v) => v
      Err(_) => fail(source, InvalidBody)
    }
    let with_source = match @decode.required(object, "with") {
      Ok(v) => v
      Err(_) => fail(source, InvalidBody)
    }
    let with_name = match @decode.text(with_source) {
      Ok(v) => v
      Err(_) => fail(with_source, InvalidBody)
    }
    let mut text = limits.max_text_bytes
    for value in ["with", "duplicates", with_name] {
      match @scalar.admit_utf8_length(value, text) {
        Ok(size) => text -= size
        Err(_) => fail(with_source, BudgetExceeded)
      }
    }
    if with_name == "" ||
      @canonical.normalize_nfc_lf(with_name) != Ok(with_name) {
      fail(with_source, InvalidName(with_name))
    }
    let duplicate_source = match @decode.lookup(object, "duplicates") {
      Some(v) => v
      None => fail(source, InvalidBody)
    }
    let spelling = match @decode.text(duplicate_source) {
      Ok(v) => v
      Err(_) => fail(duplicate_source, InvalidDuplicates)
    }
    match @scalar.admit_utf8_length(spelling, text) {
      Ok(size) => text -= size
      Err(_) => fail(duplicate_source, BudgetExceeded)
    }
    let duplicates = match spelling {
      "distinct" => Distinct
      "all" => All
      _ => fail(duplicate_source, InvalidDuplicates)
    }
    let aligned = match
      @alignment.align_schemas(with_source, left, right, {
        max_work: limits.max_work - 3,
        max_text_bytes: text,
        max_nodes: limits.max_nodes - 3,
        max_depth: limits.max_depth,
      }) {
      Ok(v) => v
      Err(e) =>
        raise Stop({
          kind: match e.kind {
            @alignment.BudgetExceeded => BudgetExceeded
            _ => Schema(e.kind)
          },
          source: e.source,
          path: e.path.copy(),
          span: e.span,
        })
    }
    let used = @alignment.alignment_usage(aligned)
    Ok({
      operation,
      source,
      with_name,
      duplicates,
      left,
      right,
      aligned,
      usage: {
        work: used.work + 3,
        text_bytes: limits.max_text_bytes - text + used.text_bytes,
        nodes: 3,
      },
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
pub fn operation(value : CheckedSet) -> Operation {
  value.operation
}

///|
pub fn source(value : CheckedSet) -> @decode.Cursor {
  value.source
}

///|
pub fn with_name(value : CheckedSet) -> String {
  value.with_name
}

///|
pub fn duplicates(value : CheckedSet) -> Duplicates {
  value.duplicates
}

///|
pub fn input_schema(value : CheckedSet, side : @schema.Side) -> @schema.Schema {
  if side == Left {
    value.left
  } else {
    value.right
  }
}

///|
pub fn output_schema(value : CheckedSet) -> @schema.Schema {
  @alignment.aligned_schema(value.aligned)
}

///|
pub fn alignment(value : CheckedSet) -> Array[@alignment.Alignment] {
  @alignment.aligned_fields(value.aligned)
}

///|
pub fn usage(value : CheckedSet) -> Usage {
  value.usage
}

///|
pub fn pending_validations(_value : CheckedSet) -> Array[Obligation] {
  [
    ValidateInputRows,
    CompareCompleteTypedRows,
    PreserveEarliestLeftOccurrences,
    BoundOutputByLeftInput,
    ResolveComparisonResources,
    ResolveIdentityAndCompleteness,
  ]
}
