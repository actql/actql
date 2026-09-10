///|
test "pooling reduces a known vector count without synthesizing an empty group" {
  for n in [0, 3] {
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[" +
        ranking_count_seed(n, "seed", false) +
        ",{\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"}},{\"pool_vectors\":{\"by\":[\"id\"],\"method\":\"mean\"}},{\"vectors\":true}]",
      ),
      [],
      None,
      None,
      limits(),
    ).unwrap()
    assert_count(p, 2, n.to_int64(), n == 0)
    assert_count(p, 3, n.to_int64(), n == 0)
  }
}

///|
test "ranking accumulation checks overflow only when a finite union bound is derivable" {
  let prefix = [
    ranking_count_seed(2, "c", false),
    ranking_count_seed(1, "q", false),
    count_rank(false),
  ]
  let mut previous = "ranking"
  for i in 0..<51 {
    let name = "double" + i.to_string()
    prefix.push(
      "{\"append\":{\"with\":\"" + previous + "\"},\"as\":\"" + name + "\"}",
    )
    previous = name
  }
  for global in [false, true] {
    let by = if global { "[]" } else { "[\"query_id\"]" }
    let fusion = "{\"merge_rankings\":{\"with\":[\"" +
      previous +
      "\",\"" +
      previous +
      "\"],\"by\":" +
      by +
      ",\"candidate\":\"candidate_id\",\"rank\":\"rank\",\"k\":1,\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"weights\":[1,1,1],\"rank_window\":10}}}}"
    let result = @pipeline_typing.check_carriers(
      cursor("[" + prefix.join(",") + "," + fusion + "]"),
      [],
      None,
      None,
      limits(),
    )
    if global {
      assert_count(result.unwrap(), prefix.length(), 1L, false)
    } else {
      assert_eq(result.unwrap_err().kind, RowBoundOverflow)
    }
  }
  let text = @contract.primitive(StringType, nullable=false)
  let external = @carrier.relation(
    @carrier.rows(
      [
        (Unqualified("query_id"), Some(text)),
        (Unqualified("candidate_id"), Some(text)),
        (
          Unqualified("rank"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=3,
      max_name_bytes=100,
    ).unwrap(),
  )
  let fusion = "{\"merge_rankings\":{\"with\":[\"" +
    previous +
    "\",\"" +
    previous +
    "\",\"external\"],\"by\":[\"query_id\"],\"candidate\":\"candidate_id\",\"rank\":\"rank\",\"k\":1,\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"weights\":[1,1,1,1],\"rank_window\":10}}}}"
  let p = @pipeline_typing.check_carriers(
    cursor("[" + prefix.join(",") + "," + fusion + "]"),
    [("external", external)],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.row_count(p, Step(prefix.length())) is None)
}

///|
fn ranking_count_seed(n : Int, name : String, lexical : Bool) -> String {
  let payload = if lexical {
    "\"text\":\"term\""
  } else {
    "\"embedding\":[1,2]"
  }
  let field = if lexical {
    "\"text\":{\"type\":\"string\",\"nullable\":false}"
  } else {
    "\"embedding\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}"
  }
  let rows = Array::makei(n, i => {
    "{\"id\":\"" + i.to_string() + "\"," + payload + "}"
  }).join(",")
  "{\"values\":{\"schema\":{\"id\":{\"type\":\"string\",\"nullable\":false}," +
  field +
  "},\"rows\":[" +
  rows +
  "]},\"as\":\"" +
  name +
  "\"}"
}

///|
fn count_rank(lexical : Bool) -> String {
  if lexical {
    "{\"text_rank\":{\"queries\":\"q\",\"candidate_id\":\"id\",\"candidate_text\":\"text\",\"query_id\":\"id\",\"query_text\":\"text\",\"tokenizer\":\"unicode_words\",\"scoring\":{\"bm25\":{\"k1\":1.2,\"b\":0.75}},\"k\":2},\"from\":\"c\",\"as\":\"ranking\"}"
  } else {
    "{\"nearest\":{\"queries\":\"q\",\"candidate_id\":\"id\",\"candidate_vector\":\"embedding\",\"query_id\":\"id\",\"query_vector\":\"embedding\",\"metric\":\"dot\",\"k\":2},\"from\":\"c\",\"as\":\"ranking\"}"
  }
}

///|
fn count_fusion(global : Bool) -> String {
  let by = if global { "[]" } else { "[\"query_id\"]" }
  "{\"merge_rankings\":{\"with\":[\"ranking\",\"ranking\"],\"by\":" +
  by +
  ",\"candidate\":\"candidate_id\",\"rank\":\"rank\",\"k\":1,\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"weights\":[1,0,2],\"rank_window\":10}}}}"
}

///|
test "ranking counts separate exact nearest from lexical reduction and union bounds" {
  for lexical in [false, true] {
    for candidates in [0, 1, 3] {
      for queries in [0, 1, 2] {
        let source = cursor(
          "[" +
          ranking_count_seed(candidates, "c", lexical) +
          "," +
          ranking_count_seed(queries, "q", lexical) +
          "," +
          count_rank(lexical) +
          "," +
          count_fusion(false) +
          "]",
        )
        let p = @pipeline_typing.check_carriers(
          source,
          [],
          None,
          None,
          limits(),
        ).unwrap()
        let n = (queries * (if candidates < 2 { candidates } else { 2 })).to_int64()
        assert_count(p, 2, n, !lexical || n == 0L)
        assert_count(p, 3, 3L * n, n == 0L)
        let u = @pipeline_typing.usage(p)
        let cap = {
          ..limits(),
          max_work: u.work,
          max_nodes: u.nodes,
          max_text_bytes: u.text_bytes,
        }
        assert_true(
          @pipeline_typing.check_carriers(source, [], None, None, cap) is Ok(_),
        )
        assert_true(
          @pipeline_typing.check_carriers(source, [], None, None, {
            ..cap,
            max_work: cap.max_work - 1,
          })
          is Err({ kind: BudgetExceeded, .. }),
        )
      }
    }
  }
}

///|
test "global ranking uses its cap while unknown partitioned input remains unknown" {
  for n in [0, 1, 3] {
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[" +
        ranking_count_seed(n, "c", false) +
        "," +
        ranking_count_seed(1, "q", false) +
        "," +
        count_rank(false) +
        "," +
        count_fusion(true) +
        "]",
      ),
      [],
      None,
      None,
      limits(),
    ).unwrap()
    assert_count(p, 3, if n == 0 { 0L } else { 1L }, n == 0)
  }
  for global in [false, true] {
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[{\"nearest\":{\"queries\":\"v\",\"metric\":\"dot\",\"k\":2},\"as\":\"ranking\"}," +
        count_fusion(global) +
        "]",
      ),
      [("v", vector_input())],
      None,
      None,
      limits(),
    ).unwrap()
    assert_true(@pipeline_typing.row_count(p, Step(0)) is None)
    if global {
      assert_count(p, 1, 1L, false)
    } else {
      assert_true(@pipeline_typing.row_count(p, Step(1)) is None)
    }
  }
}
