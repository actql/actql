///|
test "GoogleSQL translate instr spellings and authored optional children remain exact" {
  assert_eq(
    emit("TRANSLATE(s,@f,@t)"),
    "{\"translate\":[{\"field\":\"s\"},{\"$param\":\"f\"},{\"$param\":\"t\"}]}",
  )
  assert_eq(
    emit("translate(s,@f,@t)"),
    "{\"translate\":[{\"field\":\"s\"},{\"$param\":\"f\"},{\"$param\":\"t\"}]}",
  )
  assert_eq(
    emit("tRaNsLaTe(s,@f,@t)"),
    "{\"translate\":[{\"field\":\"s\"},{\"$param\":\"f\"},{\"$param\":\"t\"}]}",
  )
  assert_eq(
    emit("`TRANSLATE`(s,@f,@t)"),
    "{\"translate\":[{\"field\":\"s\"},{\"$param\":\"f\"},{\"$param\":\"t\"}]}",
  )
  assert_eq(
    emit("INSTR(s,@t)"),
    "{\"instr\":[{\"field\":\"s\"},{\"$param\":\"t\"}]}",
  )
  assert_eq(
    emit("INSTR(s,@t,@p)"),
    "{\"instr\":[{\"field\":\"s\"},{\"$param\":\"t\"},{\"$param\":\"p\"}]}",
  )
  assert_eq(
    emit("INSTR(s,@t,@p,@o)"),
    "{\"instr\":[{\"field\":\"s\"},{\"$param\":\"t\"},{\"$param\":\"p\"},{\"$param\":\"o\"}]}",
  )
  assert_eq(
    emit("instr(s,@t)"),
    "{\"instr\":[{\"field\":\"s\"},{\"$param\":\"t\"}]}",
  )
  assert_eq(
    emit("instr(s,@t,@p)"),
    "{\"instr\":[{\"field\":\"s\"},{\"$param\":\"t\"},{\"$param\":\"p\"}]}",
  )
  assert_eq(
    emit("instr(s,@t,@p,@o)"),
    "{\"instr\":[{\"field\":\"s\"},{\"$param\":\"t\"},{\"$param\":\"p\"},{\"$param\":\"o\"}]}",
  )
  assert_eq(
    emit("iNsTr(s,@t)"),
    "{\"instr\":[{\"field\":\"s\"},{\"$param\":\"t\"}]}",
  )
  assert_eq(
    emit("iNsTr(s,@t,@p)"),
    "{\"instr\":[{\"field\":\"s\"},{\"$param\":\"t\"},{\"$param\":\"p\"}]}",
  )
  assert_eq(
    emit("iNsTr(s,@t,@p,@o)"),
    "{\"instr\":[{\"field\":\"s\"},{\"$param\":\"t\"},{\"$param\":\"p\"},{\"$param\":\"o\"}]}",
  )
  assert_eq(
    emit("`INSTR`(s,@t)"),
    "{\"instr\":[{\"field\":\"s\"},{\"$param\":\"t\"}]}",
  )
  assert_eq(
    emit("`INSTR`(s,@t,@p)"),
    "{\"instr\":[{\"field\":\"s\"},{\"$param\":\"t\"},{\"$param\":\"p\"}]}",
  )
  assert_eq(
    emit("`INSTR`(s,@t,@p,@o)"),
    "{\"instr\":[{\"field\":\"s\"},{\"$param\":\"t\"},{\"$param\":\"p\"},{\"$param\":\"o\"}]}",
  )
  assert_true(
    lower(fixture("TRANSLATE()"), _ => None, limits())
    is Err({ issue: InvalidArguments, .. }),
  )
  assert_true(
    lower(fixture("TRANSLATE('a','b')"), _ => None, limits())
    is Err({ issue: InvalidArguments, .. }),
  )
  assert_true(
    lower(fixture("TRANSLATE('a','b','c','d')"), _ => None, limits())
    is Err({ issue: InvalidArguments, .. }),
  )
  assert_true(
    lower(fixture("INSTR()"), _ => None, limits())
    is Err({ issue: InvalidArguments, .. }),
  )
  assert_true(
    lower(fixture("INSTR('a')"), _ => None, limits())
    is Err({ issue: InvalidArguments, .. }),
  )
  assert_true(
    lower(fixture("INSTR('a','b',1,1,1)"), _ => None, limits())
    is Err({ issue: InvalidArguments, .. }),
  )
  assert_true(
    lower(fixture("ACTQL.TRANSLATE('a','b')"), _ => None, limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
  assert_true(
    same_scalar_function(
      scalar_identity_name("translate"),
      scalar_identity_name("TRANSLATE", quoted=true),
    ),
  )
  assert_true(
    lower(fixture("ACTQL.INSTR('a','b')"), _ => None, limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
  assert_true(
    same_scalar_function(
      scalar_identity_name("instr"),
      scalar_identity_name("INSTR", quoted=true),
    ),
  )
  assert_false(
    same_scalar_function(
      scalar_identity_name("TRANSLATE"),
      scalar_identity_name("INSTR"),
    ),
  )
}
