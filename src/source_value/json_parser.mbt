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
}

///|
/// Frames and path segments are pushed once per nesting level. Full paths are
/// copied only on failure, avoiding quadratic path construction on deep input.
fn Parser::document(self : Parser) -> Node raise ParseAbort {
  let frames : Array[Frame] = []
  let mut need_value = true
  let mut completed : Node? = None
  while true {
    if need_value {
      self.skip_space()
      if self.nodes >= self.limits.max_nodes {
        self.fail(NodeLimit, self.path)
      }
      self.nodes += 1
      let start = self.point()
      need_value = false
      match self.peek() {
        Some(0x5b) | Some(0x7b) => {
          if frames.length() >= self.limits.max_depth {
            self.fail(DepthLimit, self.path)
          }
          let container = if self.peek() == Some(0x5b) {
            ArrayItems([])
          } else {
            ObjectFields([], @shape.key_admission())
          }
          ignore(self.advance_scalar(self.path))
          frames.push({ start, container, phase: First, key: None, })
        }
        Some(0x6e) => {
          self.consume_literal("null", self.path)
          completed = Some({ value: Null, span: self.span(start), })
        }
        Some(0x74) => {
          self.consume_literal("true", self.path)
          completed = Some({ value: Bool(true), span: self.span(start), })
        }
        Some(0x66) => {
          self.consume_literal("false", self.path)
          completed = Some({ value: Bool(false), span: self.span(start), })
        }
        Some(0x22) => {
          let (text, span) = self.parse_string(self.path)
          completed = Some({ value: String(text), span, })
        }
        Some(unit) if unit == 0x2d || is_digit(unit) =>
          completed = Some(self.parse_number(self.path))
        None => self.fail(UnexpectedEnd, self.path)
        _ => self.fail(UnexpectedToken, self.path)
      }
    }
    if completed is Some(node) {
      if frames.is_empty() {
        self.skip_space()
        if self.peek() != None {
          self.fail(TrailingContent, self.path)
        }
        return node
      }
      let parent = frames[frames.length() - 1]
      match parent.container {
        ArrayItems(items) => items.push(node)
        ObjectFields(fields, _) => {
          let (key, key_span) = parent.key.unwrap()
          fields.push({ key, key_span, value: node, })
          parent.key = None
        }
      }
      ignore(self.path.pop())
      parent.phase = AfterValue
      completed = None
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
      completed = Some({ value, span: self.span(frame.start), })
      continue
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
      continue
    }
    match frame.container {
      ArrayItems(items) => self.path.push(Index(items.length()))
      ObjectFields(_, keys) => {
        let (key, key_span) = self.parse_string(self.path)
        self.path.push(Key(key))
        if !@shape.admit_key(keys, key) {
          raise ParseAbort({
            issue: DuplicateKey(key),
            source_path: self.source_path,
            location: Source(key_span),
            path: Some(self.path.copy()),
          })
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
    need_value = true
  } nobreak {
    self.fail(UnexpectedEnd, self.path)
  }
}
