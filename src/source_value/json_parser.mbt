///|
priv enum Container {
  ArrayItems(Array[Node])
  ObjectFields(Array[Field], @shape.KeyAdmission)
}

///|
priv enum Phase {
  First
  Next
  Waiting
  AfterValue
} derive(Eq)

///|
priv struct Frame {
  start : Point
  container : Container
  mut phase : Phase
  mut key : (String, Span)?
  mut skip_key : Bool
}

///|
/// Frames and path segments are pushed once per nesting level. Full paths are
/// copied only on failure, avoiding quadratic path construction on deep input.
fn Parser::document(self : Parser) -> Node raise ParseAbort {
  let document = JsonDocument::make(self)
  while true {
    if document.step() is Some(node) {
      return node
    }
  } nobreak {
    self.fail(UnexpectedEnd, self.path)
  }
}

///|
/// The synchronous and resumable entry points share this grammar state.
priv struct JsonDocument {
  parser : Parser
  frames : Array[Frame]
  mut need_value : Bool
  mut completed : Node?
}

///|
fn JsonDocument::make(parser : Parser) -> JsonDocument {
  { parser, frames: [], need_value: true, completed: None, }
}

///|
/// One parser transition. Lexical leaves use the same bounded scalar readers;
/// no container subtree is parsed by a single transition.
fn JsonDocument::step(document : JsonDocument) -> Node? raise ParseAbort {
  let self = document.parser
  let frames = document.frames
  if document.need_value {
    self.skip_space()
    if self.nodes >= self.limits.max_nodes {
      self.fail(NodeLimit, self.path)
    }
    self.nodes += 1
    let start = self.point()
    document.need_value = false
    match self.peek() {
      Some(0x5b) | Some(0x7b) => {
        if frames.length() >= self.limits.max_depth {
          self.fail(DepthLimit, self.path)
        }
        self.deepest = Int::max(self.deepest, frames.length() + 1)
        let container = if self.peek() == Some(0x5b) {
          ArrayItems([])
        } else {
          ObjectFields([], @shape.key_admission())
        }
        ignore(self.advance_scalar(self.path))
        frames.push({
          start,
          container,
          phase: First,
          key: None,
          skip_key: false,
        })
      }
      Some(0x6e) => {
        self.consume_literal("null", self.path)
        document.completed = Some({ value: Null, span: self.span(start), })
      }
      Some(0x74) => {
        self.consume_literal("true", self.path)
        document.completed = Some({ value: Bool(true), span: self.span(start), })
      }
      Some(0x66) => {
        self.consume_literal("false", self.path)
        document.completed = Some({
          value: Bool(false),
          span: self.span(start),
        })
      }
      Some(0x22) => {
        let (text, span) = self.parse_string(self.path)
        document.completed = Some({ value: String(text), span, })
      }
      Some(unit) if unit == 0x2d || is_digit(unit) =>
        document.completed = Some(self.parse_number(self.path))
      None => self.fail(UnexpectedEnd, self.path)
      _ => self.fail(UnexpectedToken, self.path)
    }
  }
  if document.completed is Some(node) {
    if frames.is_empty() {
      self.skip_space()
      if self.peek() != None {
        self.fail(TrailingContent, self.path)
      }
      return Some(node)
    }
    let parent = frames[frames.length() - 1]
    match parent.container {
      ArrayItems(items) => items.push(node)
      ObjectFields(fields, _) => {
        let (key, key_span) = parent.key.unwrap()
        if !parent.skip_key {
          fields.push({ key, key_span, value: node, })
        }
        parent.key = None
        parent.skip_key = false
      }
    }
    ignore(self.path.pop())
    parent.phase = AfterValue
    document.completed = None
  }
  let frame = frames[frames.length() - 1]
  self.skip_space()
  let closing = match frame.container {
    ArrayItems(_) => 0x5d
    ObjectFields(_, _) => 0x7d
  }
  if (frame.phase == First || frame.phase == AfterValue) &&
    self.peek() == Some(closing) {
    ignore(self.advance_scalar(self.path))
    ignore(frames.pop())
    let value = match frame.container {
      ArrayItems(items) => Array(items)
      ObjectFields(fields, _) => Object(fields)
    }
    document.completed = Some({ value, span: self.span(frame.start), })
    return None
  }
  if frame.phase == AfterValue {
    if self.peek() != Some(0x2c) {
      let issue = match frame.container {
        ArrayItems(_) => ExpectedArraySeparator
        ObjectFields(_, _) => ExpectedObjectSeparator
      }
      self.fail(issue, self.path)
    }
    ignore(self.advance_scalar(self.path))
    frame.phase = Next
    return None
  }
  match frame.container {
    ArrayItems(items) => self.path.push(Index(items.length()))
    ObjectFields(_, keys) => {
      let (key, key_span) = self.parse_string(self.path, key=true)
      self.path.push(Key(key))
      if !@shape.admit_key(keys, key) {
        if self.literal_json {
          frame.skip_key = true
        } else {
          raise ParseAbort({
            issue: DuplicateKey(key),
            source_path: self.source_path,
            location: Source(key_span),
            path: Some(self.path.copy()),
          })
        }
      }
      self.skip_space()
      if self.peek() != Some(0x3a) {
        self.fail(ExpectedColon, self.path)
      }
      ignore(self.advance_scalar(self.path))
      frame.key = Some((key, key_span))
    }
  }
  frame.phase = Waiting
  document.need_value = true
  None
}
