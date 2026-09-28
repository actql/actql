///|
pub(all) enum Resource {
  Tokens
  LiteralBytes
  Work
} derive(Eq, Debug)

///|
pub(all) struct LexicalLimits {
  max_source_bytes : Int
  max_tokens : Int
  max_literal_bytes : Int
  max_work : Int
}

///|
pub(all) enum Issue {
  InvalidLimits
  Syntax(String)
  Source(@origin.Issue)
  Lexical(LexicalIssue)
  Limit(Resource)
} derive(Debug)

///|
pub(all) struct Diagnostic {
  issue : Issue
  span : @span.Span?
} derive(Debug)

///|
priv suberror LimitAbort {
  LimitAbort(Resource, Int)
}

///|
priv struct Budget {
  caps : Array[Int]
  used : Array[Int]
}

///|
fn resource_index(resource : Resource) -> Int {
  match resource {
    Tokens => 0
    LiteralBytes => 1
    Work => 2
  }
}

///|
fn Budget::charge(
  self : Budget,
  resource : Resource,
  amount : Int,
  at : Int,
) -> Unit raise LimitAbort {
  let i = resource_index(resource)
  if amount < 0 || amount > self.caps[i] - self.used[i] {
    raise LimitAbort(resource, at)
  }
  self.used[i] += amount
}

///|
struct Tokens {
  document : @origin.Document
  tokens : Array[Token]
  usage : Array[Int]
}

///|
pub fn usage(tokens : Tokens, resource : Resource) -> Int {
  tokens.usage[resource_index(resource)]
}

///|
pub fn tokenize(
  text : String,
  limits : LexicalLimits,
  source_path? : String = "<query>",
) -> Result[Tokens, Diagnostic] {
  let caps = [limits.max_tokens, limits.max_literal_bytes, limits.max_work]
  if limits.max_source_bytes < 0 || caps.any(n => n < 0 || n == 2147483647) {
    return Err({ issue: InvalidLimits, span: None, })
  }
  let document = match
    @origin.document(text, limits.max_source_bytes, source_path~) {
    Ok(d) => d
    Err(e) => return Err({ issue: Source(e), span: None, })
  }
  let budget : Budget = { caps, used: [0, 0, 0], }
  let scanner : Scanner = { text, budget, offset: 0, byte_offset: 0, }
  let tokens : Array[Token] = []
  try {
    while true {
      let t = scanner.next()
      tokens.push(t)
      if t.value == End {
        break
      }
    }
    Ok({ document, tokens, usage: budget.used, })
  } catch {
    LexicalAbort(issue, at) =>
      Err({
        issue: Lexical(issue),
        span: @origin.position(document, at).map(_ => {
          @origin.span(@origin.range(document, at, at).unwrap())
        }),
      })
    LimitAbort(resource, at) =>
      Err({
        issue: Limit(resource),
        span: @origin.position(document, at).map(_ => {
          @origin.span(@origin.range(document, at, at).unwrap())
        }),
      })
    _ => Err({ issue: Lexical(UnexpectedToken), span: None, })
  }
}

///|
pub fn tokenize_bytes(
  bytes : Bytes,
  limits : LexicalLimits,
  source_path? : String = "<query>",
) -> Result[Tokens, Diagnostic] {
  if bytes.length() > limits.max_source_bytes {
    return Err({ issue: Source(@origin.InputLimit), span: None, })
  }
  let text = @utf8.decode(bytes[:], ignore_bom=false) catch {
    _ => return Err({ issue: Source(@origin.InvalidUtf8), span: None, })
  }
  tokenize(text, limits, source_path~)
}

///|
pub fn token_count(tokens : Tokens) -> Int {
  tokens.tokens.length()
}

///|
pub fn token_at(tokens : Tokens, index : Int) -> Token? {
  if index < 0 || index >= tokens.tokens.length() {
    None
  } else {
    Some(tokens.tokens[index])
  }
}

///|
pub fn token_origin(tokens : Tokens, index : Int) -> @origin.Origin? {
  match token_at(tokens, index) {
    Some(t) => Some(@origin.range(tokens.document, t.start, t.end).unwrap())
    None => None
  }
}
