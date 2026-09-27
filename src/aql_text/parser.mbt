///|
pub(all) enum Issue {
  InvalidLimits
  ResourceLimit(Resource)
  OriginalSource(@origin.Issue)
  Lexical(LexicalIssue)
  Expected(String)
  Json(@source.ParseIssue)
  Construction(@builder.Issue)
  Admission(@syntax.SyntaxError)
} derive(Debug)

///|
pub(all) struct Diagnostic {
  issue : Issue
  span : @span.Span?
} derive(Debug)

///|
priv suberror Abort {
  Abort(Issue, Int)
}

///|
pub(all) struct Limits {
  frontend : FrontendLimits
  construction : @builder.Limits
  max_stages : Int
}

///|
struct Parsed {
  program : @syntax.Program
  source : @builder.Source
  usage : Array[Int]
}

///|
pub fn program(parsed : Parsed) -> @syntax.Program {
  parsed.program
}

///|
pub fn source(parsed : Parsed) -> @builder.Source {
  parsed.source
}

///|
pub fn parse_bytes(
  bytes : Bytes,
  limits : Limits,
  source_path? : String = "<aql>",
) -> Result[Parsed, Diagnostic] {
  if bytes.length() > limits.construction.source.max_input_bytes {
    return Err({ issue: OriginalSource(@origin.InputLimit), span: None, })
  }
  let text = @utf8.decode(bytes[:], ignore_bom=false) catch {
    _ => return Err({ issue: OriginalSource(@origin.InvalidUtf8), span: None, })
  }
  parse(text, limits, source_path~)
}

///|
priv struct Parser {
  scanner : Scanner
  builder : @builder.Builder
  limits : Limits
  mut lookahead : Token?
  mut remaining_json_nodes : Int
  mut syntax_depth : Int
}

///|
fn Parser::token(self : Parser) -> Token raise {
  match self.lookahead {
    Some(t) => t
    None => {
      let t = self.scanner.next()
      self.lookahead = Some(t)
      t
    }
  }
}

///|
fn Parser::take(self : Parser) -> Token raise {
  let token = self.token()
  self.lookahead = None
  token
}

///|
fn ascii_keyword(word : String, expected : String) -> Bool {
  if word.length() != expected.length() {
    return false
  }
  for i in 0..<word.length() {
    let n = word[i].to_int()
    let upper = if n >= 0x61 && n <= 0x7a { n - 32 } else { n }
    if upper != expected[i].to_int() {
      return false
    }
  }
  true
}

///|
fn Parser::keyword(self : Parser, expected : String) -> Token raise {
  let t = self.take()
  if t.value is Word(word) && ascii_keyword(word, expected) {
    t
  } else {
    raise Abort(Expected(expected), t.start)
  }
}

///|
fn Parser::symbol(self : Parser, expected : Int) -> Token raise {
  let t = self.take()
  if t.value != Symbol(expected) {
    raise Abort(Expected(expected.unsafe_to_char().to_string()), t.start)
  }
  t
}

///|
fn Parser::name(self : Parser) -> (String, Token) raise {
  let t = self.take()
  self.scanner.budget.charge(Symbols, 1, t.start)
  if t.value is Word(word) {
    for
      keyword in [
        "AQL", "PROGRAM", "META", "PARAMS", "BINDINGS", "STAGE", "AFTER", "ACCEPTED",
        "COMPLETED", "INPUT", "FROM", "STEP", "DATA", "OP", "RESULT", "EFFECT", "EFFECTS",
      ] {
      if ascii_keyword(word, keyword) {
        raise Abort(Expected("quoted keyword name"), t.start)
      }
    }
  }
  match t.value {
    Word(s) | QuotedName(s) | Text(s) =>
      match @canonical.normalize_nfc_lf(s) {
        Ok(name) => (name, t)
        Err(_) => raise Abort(Expected("Unicode name"), t.start)
      }
    _ => raise Abort(Expected("name"), t.start)
  }
}

///|
fn Parser::origin(
  self : Parser,
  start : Int,
  end : Int,
  generated? : Bool = true,
) -> @origin.Origin raise Abort {
  match
    @origin.range(
      self.scanner.document,
      start,
      end,
      kind=if generated { Generated } else { Authored },
    ) {
    Ok(o) => o
    Err(e) => raise Abort(OriginalSource(e), start)
  }
}

///|
fn Parser::node(
  self : Parser,
  value : @builder.Value,
  start : Int,
  end : Int,
) -> @builder.Node raise {
  self.scanner.budget.charge(LoweringWork, 1, start)
  match @builder.add(self.builder, value, self.origin(start, end)) {
    Ok(n) => n
    Err(e) => raise Abort(Construction(e), start)
  }
}

///|
fn Parser::field(
  self : Parser,
  key : String,
  value : @builder.Node,
  token : Token,
) -> @builder.Field raise {
  self.scanner.budget.charge(GeneratedFields, 1, token.start)
  { key, value, origin: self.origin(token.start, token.end), }
}

///|
fn Parser::named_json(
  self : Parser,
  object_required? : Bool = true,
) -> @builder.Field raise {
  let (name, token) = self.name()
  ignore(self.symbol(0x3d))
  let value = self.json_body(object_required~)
  ignore(self.symbol(0x3b))
  self.field(name, value, token)
}

///|
fn Parser::stage(self : Parser, start : Token) -> @builder.Node raise {
  self.syntax_depth = 2
  self.scanner.budget.charge(SyntaxDepth, 2, start.start)
  let (id, id_token) = self.name()
  let fields = [
    self.field(
      "id",
      self.node(String(id), id_token.start, id_token.end),
      id_token,
    ),
  ]
  if self.token().value is Word(word) && ascii_keyword(word, "AFTER") {
    ignore(self.take())
    let t = self.take()
    let after = match t.value {
      Word(w) if ascii_keyword(w, "ACCEPTED") => "accepted"
      Word(w) if ascii_keyword(w, "COMPLETED") => "completed"
      _ => raise Abort(Expected("ACCEPTED or COMPLETED"), t.start)
    }
    fields.push(
      self.field("after", self.node(String(after), t.start, t.end), t),
    )
  }
  ignore(self.symbol(0x7b))
  let inputs : Array[@builder.Field] = []
  let drafts : Array[StepDraft] = []
  let result_bodies : Array[(String, Token, JsonBody)] = []
  let effects : Array[@builder.Field] = []
  let mut explicit_effects = false
  let mut computed = false
  while self.token().value != Symbol(0x7d) {
    let t = self.take()
    self.scanner.budget.charge(SyntaxNodes, 1, t.start)
    match t.value {
      Word(w) if ascii_keyword(w, "INPUT") => {
        if computed {
          raise Abort(Expected("INPUT before computation"), t.start)
        }
        inputs.push(self.named_json(object_required=false))
      }
      Word(w) if ascii_keyword(w, "DATA") => {
        computed = true
        drafts.push(Data(self.read_data()))
      }
      Word(w) if ascii_keyword(w, "STEP") => {
        computed = true
        drafts.push(Explicit(self.read_json()))
        ignore(self.symbol(0x3b))
      }
      Word(w) if ascii_keyword(w, "RESULT") => {
        let (name, token) = self.name()
        ignore(self.symbol(0x3d))
        result_bodies.push((name, token, self.read_json()))
        ignore(self.symbol(0x3b))
      }
      Word(w) if ascii_keyword(w, "EFFECT") => {
        if explicit_effects {
          raise Abort(Expected("EFFECT or empty EFFECTS, not both"), t.start)
        }
        effects.push(self.named_json())
      }
      Word(w) if ascii_keyword(w, "EFFECTS") => {
        if explicit_effects || effects.length() != 0 {
          raise Abort(Expected("single empty EFFECTS declaration"), t.start)
        }
        ignore(self.symbol(0x7b))
        ignore(self.symbol(0x7d))
        ignore(self.symbol(0x3b))
        explicit_effects = true
      }
      Word(w) if ascii_keyword(w, "META") => {
        fields.push(self.field("meta", self.json_body(), t))
        ignore(self.symbol(0x3b))
      }
      Word(w) if ascii_keyword(w, "FROM") => {
        if computed {
          raise Abort(Expected("initial FROM before computation"), t.start)
        }
        let (name, n) = self.name()
        if !inputs.any(f => f.key == name) {
          raise Abort(Expected("declared INPUT name"), n.start)
        }
        fields.push(
          self.field("from", self.node(String(name), n.start, n.end), t),
        )
        ignore(self.symbol(0x3b))
      }
      _ => raise Abort(Expected("stage declaration"), t.start)
    }
  }
  let end = self.take().end
  let reserved : Map[String, Bool] = Map([])
  let aliases : Map[String, String] = Map([])
  for f in inputs {
    reserved[f.key] = true
    aliases[f.key] = f.key
  }
  for draft in drafts {
    match draft {
      Explicit(body) => {
        if raw_text(raw_field(body.node, "as")) is Some(name) {
          self.scanner.budget.charge(Symbols, 1, body.start)
          reserved[name] = true
        }
        reserve_references(body, None, reserved, self.scanner.budget)
      }
      Data(data) => {
        reserved[data.name] = true
        if data.input is Some((name, _)) {
          reserved[name] = true
        }
        for op in data.operations {
          reserve_references(
            op.body,
            Some(op.name),
            reserved,
            self.scanner.budget,
          )
        }
      }
    }
  }
  for (_, _, body) in result_bodies {
    reserve_references(body, None, reserved, self.scanner.budget)
  }
  let steps = self.lower_steps(drafts, aliases, reserved)
  let results : Array[@builder.Field] = []
  for (name, token, body) in result_bodies {
    results.push(
      self.field(
        name,
        self.lower_json(resolve_body(body, None, aliases, self.scanner.budget)),
        token,
      ),
    )
  }
  fields.push(
    self.field("inputs", self.node(Object(inputs), start.start, end), start),
  )
  fields.push(
    self.field("steps", self.node(Array(steps), start.start, end), start),
  )
  fields.push(
    self.field("results", self.node(Object(results), start.start, end), start),
  )
  if explicit_effects || effects.length() != 0 {
    fields.push(
      self.field("effects", self.node(Object(effects), start.start, end), start),
    )
  }
  self.node(Object(fields), start.start, end)
}

///|
fn Parser::document(self : Parser) -> @builder.Node raise {
  self.scanner.budget.charge(SyntaxDepth, 1, self.scanner.byte_offset)
  let header = self.keyword("AQL")
  let version = self.take()
  if version.value != Text("0.1") {
    raise Abort(Expected("'0.1'"), version.start)
  }
  ignore(self.symbol(0x3b))
  ignore(self.keyword("PROGRAM"))
  let id = self.take()
  self.scanner.budget.charge(Symbols, 1, id.start)
  let name = match id.value {
    Text(s) => s
    _ => raise Abort(Expected("Program string ID"), id.start)
  }
  let fields = [
    self.field(
      "version",
      self.node(String("actql/0.1"), version.start, version.end),
      version,
    ),
    self.field("id", self.node(String(name), id.start, id.end), id),
  ]
  let stages : Array[@builder.Node] = []
  let results : Array[@builder.Field] = []
  ignore(self.symbol(0x7b))
  while self.token().value != Symbol(0x7d) {
    let t = self.take()
    self.scanner.budget.charge(SyntaxNodes, 1, t.start)
    match t.value {
      Word(w) if ascii_keyword(w, "META") ||
        ascii_keyword(w, "PARAMS") ||
        ascii_keyword(w, "BINDINGS") => {
        let key = if ascii_keyword(w, "META") {
          "meta"
        } else if ascii_keyword(w, "PARAMS") {
          "params"
        } else {
          "bindings"
        }
        fields.push(self.field(key, self.json_body(), t))
        ignore(self.symbol(0x3b))
      }
      Word(w) if ascii_keyword(w, "STAGE") => {
        if stages.length() >= self.limits.max_stages {
          raise Abort(Expected("stage count within limit"), t.start)
        }
        stages.push(self.stage(t))
        self.syntax_depth = 1
      }
      Word(w) if ascii_keyword(w, "RESULT") => results.push(self.named_json())
      _ => raise Abort(Expected("Program declaration"), t.start)
    }
  }
  let end = self.take().end
  let tail = self.take()
  if tail.value != End {
    raise Abort(Expected("end of document"), tail.start)
  }
  fields.push(
    self.field("stages", self.node(Array(stages), header.start, end), header),
  )
  fields.push(
    self.field("results", self.node(Object(results), header.start, end), header),
  )
  self.node(Object(fields), header.start, end)
}

///|
pub fn parse(
  text : String,
  limits : Limits,
  source_path? : String = "<aql>",
) -> Result[Parsed, Diagnostic] {
  let limits_budget = match budget(limits.frontend) {
    Some(b) if limits.max_stages >= 0 => b
    _ => return Err({ issue: InvalidLimits, span: None, })
  }
  let document = match
    @origin.document(
      text,
      limits.construction.source.max_input_bytes,
      source_path~,
    ) {
    Ok(d) => d
    Err(e) => return Err({ issue: OriginalSource(e), span: None, })
  }
  let builder = match @builder.create(document, limits.construction) {
    Ok(b) => b
    Err(e) => return Err({ issue: Construction(e), span: None, })
  }
  let parser : Parser = {
    scanner: {
      text,
      document,
      offset: 0,
      byte_offset: 0,
      budget: limits_budget,
    },
    builder,
    limits,
    lookahead: None,
    remaining_json_nodes: limits.construction.source.max_nodes,
    syntax_depth: 1,
  }
  let outcome = try {
    limits_budget.charge(LoweringWork, @origin.input_bytes(document), 0)
    let root = parser.document()
    let source = match @builder.finish(builder, root) {
      Ok(s) => s
      Err(e) => raise Abort(Construction(e), parser.scanner.byte_offset)
    }
    let program = match
      @syntax.admit_generated_source(source, {
        source: limits.construction.source,
        tree: limits.construction.tree,
        max_stages: limits.max_stages,
      }) {
      Ok(p) => p
      Err(e) => raise Abort(Admission(e), parser.scanner.byte_offset)
    }
    Ok({ program, source, usage: limits_budget.used.copy(), })
  } catch {
    LimitAbort(resource, at) => Err((ResourceLimit(resource), at))
    Abort(issue, at) => Err((issue, at))
    LexicalAbort(issue, at) => Err((Lexical(issue), at))
    _ => Err((Expected("valid source"), parser.scanner.byte_offset))
  }
  match outcome {
    Ok(p) => Ok(p)
    Err((issue, at)) => {
      @builder.discard(builder)
      let span = match issue {
        Admission(@syntax.Decode(e)) => Some(e.span)
        Admission(@syntax.Structure(_, span~, ..)) => Some(span)
        _ =>
          match @origin.range(document, at, at) {
            Ok(o) => Some(@origin.span(o))
            Err(_) => None
          }
      }
      Err({ issue, span, })
    }
  }
}
