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
  identifiers : Map[String, String]
}

///|
// Lexemes retain decoded spelling and original spans. Grammar-owned names use
// the common identifier contract, separately from STRING data values.
fn Tokens::identifier(self : Tokens, decoded : String) -> String {
  self.identifiers.get(decoded).unwrap()
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
  scan_tokens(text, limits, source_path, false)
}

///|
// Routing validates the source envelope but lets the selected parser own
// its body grammar, including structural JSON string escapes.
fn scan_tokens(
  text : String,
  limits : LexicalLimits,
  source_path : String,
  first_only : Bool,
  query_route? : Bool? = None,
  read_document? : (String, Int, String) -> Result[
    @origin.Document,
    @origin.Issue,
  ] = (text, max_bytes, path) => {
    @origin.document(text, max_bytes, source_path=path)
  },
) -> Result[Tokens, Diagnostic] {
  let caps = [limits.max_tokens, limits.max_literal_bytes, limits.max_work]
  if limits.max_source_bytes < 0 || caps.any(n => n < 0 || n == 2147483647) {
    return Err({ issue: InvalidLimits, span: None, })
  }
  let document = match
    read_document(text, limits.max_source_bytes, source_path) {
    Ok(d) => d
    Err(e) => return Err({ issue: Source(e), span: None, })
  }
  let budget : Budget = { caps, used: [0, 0, 0], }
  let scanner : Scanner = { text, budget, offset: 0, byte_offset: 0, }
  let tokens : Array[Token] = []
  let identifiers : Map[String, String] = Map([])
  try {
    while true {
      let t = scanner.next()
      match t.value {
        QuotedName(decoded) | Parameter(decoded) =>
          if !identifiers.contains(decoded) {
            // Normalize once per spelling, after escape decoding and before
            // any clause resolves it. Bound input work and NFC byte expansion.
            budget.charge(Work, decoded.length(), t.start)
            let identifier = match @canonical.normalize_nfc_lf(decoded) {
              Ok(value) => value
              Err(_) => raise LexicalAbort(InvalidScalar, t.start)
            }
            let extra = @utf8.encode(identifier).length() -
              @utf8.encode(decoded).length()
            if extra > 0 {
              budget.charge(LiteralBytes, extra, t.start)
            }
            identifiers[decoded] = identifier
          }
        _ => ()
      }
      tokens.push(t)
      // A selected query keeps this scanner, budget and source document. A
      // rejected first-token route must not inspect a foreign body's grammar.
      let rejected_route = tokens.length() == 1 &&
        (match query_route {
          Some(sql_only) =>
            !query_head(t) ||
            (sql_only && t.value != Symbol(40) && !sql_head(t))
          None => false
        })
      if first_only || rejected_route || t.value == End {
        break
      }
    }
    Ok({ document, tokens, usage: budget.used, identifiers, })
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
