///|
priv struct ScalarLine {
  text : String
  more : Bool
  newline : Bool
}

///|
fn Parser::yaml_block_scalar(
  self : Parser,
  parent_indent : Int,
) -> String raise ParseAbort {
  let folded = self.yaml_take() == 0x3e
  let mut indicator = 0
  let mut chomp = 0
  for i = 0; i < 2; i = i + 1 {
    let unit = self.yaml_at(0)
    if unit >= 0x31 && unit <= 0x39 && indicator == 0 {
      indicator = unit - 0x30
      ignore(self.yaml_take())
    } else if (unit == 0x2b || unit == 0x2d) && chomp == 0 {
      chomp = unit
      ignore(self.yaml_take())
    } else {
      break
    }
  }
  let separated = self.yaml_at(0) == 0x20 || self.yaml_at(0) == 0x09
  self.yaml_horizontal()
  if self.yaml_at(0) == 0x23 && separated {
    while self.yaml_at(0) >= 0 && !yaml_break(self.yaml_at(0)) {
      ignore(self.yaml_take())
    }
  }
  if self.yaml_at(0) < 0 {
    return ""
  }
  if !yaml_break(self.yaml_at(0)) {
    self.fail(InvalidYamlScalar, self.path)
  }
  self.yaml_newline()
  let base = if indicator > 0 && parent_indent < 0 { 0 } else { parent_indent }
  let mut indent = base + indicator
  let mut largest_blank = 0
  if indicator == 0 {
    let mut i = self.offset
    while i < self.source.length() {
      let start = i
      while i < self.source.length() && self.source[i].to_int() == 0x20 {
        i += 1
      }
      let spaces = i - start
      if i >= self.source.length() || yaml_break(self.source[i].to_int()) {
        if spaces > largest_blank {
          largest_blank = spaces
        }
        if i >= self.source.length() {
          break
        }
        let cr = self.source[i].to_int() == 0x0d
        i += 1
        if cr && i < self.source.length() && self.source[i].to_int() == 0x0a {
          i += 1
        }
      } else {
        indent = if spaces > base { spaces } else { base + 1 }
        break
      }
    }
    if indent <= base {
      // With no non-empty line, the longest blank line determines indentation.
      indent = if largest_blank > base { largest_blank } else { base + 1 }
    }
    if largest_blank > indent {
      self.fail(InvalidYamlIndentation, self.path)
    }
  }
  let lines : Array[ScalarLine] = []
  while self.yaml_at(0) >= 0 {
    if self.yaml_marker(0x2d) || self.yaml_marker(0x2e) {
      break
    }
    let mut spaces = 0
    while self.yaml_at(spaces) == 0x20 {
      spaces += 1
    }
    let unit = self.yaml_at(spaces)
    let blank = unit < 0 || yaml_break(unit)
    if !blank && spaces < indent {
      break
    }
    let drop = if spaces < indent { spaces } else { indent }
    for i = 0; i < drop; i = i + 1 {
      ignore(self.yaml_take())
    }
    let text = StringBuilder()
    while self.yaml_at(0) >= 0 && !yaml_break(self.yaml_at(0)) {
      text.write_char(self.yaml_take().unsafe_to_char())
    }
    let newline = self.yaml_at(0) >= 0
    if newline {
      self.yaml_newline()
    }
    let value = text.to_string()
    lines.push({
      text: value,
      more: value.length() > 0 &&
      (value[0].to_int() == 0x20 || value[0].to_int() == 0x09),
      newline,
    })
  }
  let output = StringBuilder()
  for i, line in lines {
    output.write_string(line.text)
    if !line.newline {
      continue
    }
    if !folded {
      output.write_char('\n')
      continue
    }
    if line.text == "" {
      let mut folded_break = false
      if i > 0 && lines[i - 1].text != "" && !lines[i - 1].more {
        let mut next = i + 1
        while next < lines.length() && lines[next].text == "" {
          next += 1
        }
        folded_break = next < lines.length() && !lines[next].more
      }
      if !folded_break {
        output.write_char('\n')
      }
    } else if i + 1 < lines.length() &&
      lines[i + 1].text != "" &&
      !line.more &&
      !lines[i + 1].more {
      output.write_char(' ')
    } else {
      output.write_char('\n')
    }
  }
  let raw = output.to_string()
  let mut end = raw.length()
  while end > 0 && raw[end - 1].to_int() == 0x0a {
    end -= 1
  }
  let value = if chomp == 0x2b {
    raw
  } else if chomp == 0x2d || end == 0 || end == raw.length() {
    raw[:end].to_owned()
  } else {
    raw[:end].to_owned() + "\n"
  }
  value
}
