///|
fn local_supplied_ranking_schema() -> String {
  "{\"additional_properties\":false,\"fields\":{" +
  "\"id\":{\"nullable\":false,\"type\":\"number\"}," +
  "\"q\":{\"nullable\":false,\"type\":\"number\"}," +
  "\"score\":{\"nullable\":false,\"type\":\"number\"}}," +
  "\"nullable\":false,\"type\":\"object\"}"
}

///|
fn local_supplied_ranking_schema_snapshots() -> String {
  let body = fn(source : String) {
    "{\"output_carrier\":\"relation\",\"schema\":" +
    local_supplied_ranking_schema() +
    ",\"score_contracts\":{\"score\":{" +
    "\"domain\":\"unit.v1\",\"normalization\":\"unit.v1\"," +
    "\"range\":[0,1]}},\"source_ref\":\"" +
    source +
    "\",\"version\":\"actql-local-input-schema/0.1\"}"
  }
  "[" +
  body("source:local/ranked/right") +
  "," +
  body("source:local/ranked/left") +
  "]"
}

///|
fn local_supplied_ranking_program(policy? : String = "\"max\"") -> String {
  let input = "{\"carrier\":\"relation\",\"schema\":{" +
    "\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"q\":{\"type\":\"number\",\"nullable\":false}," +
    "\"score\":{\"type\":\"number\",\"nullable\":false}}}"
  "{\"version\":\"actql/0.1\",\"id\":\"supplied-ranking\"," +
  "\"params\":{\"minimum\":{\"type\":\"number\"," +
  "\"nullable\":false}},\"stages\":[{" +
  "\"id\":\"a\",\"inputs\":{\"remote\":{\"connector\":" +
  "\"crm/main\",\"resource\":\"r\"}},\"steps\":[{" +
  "\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{" +
  "\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{" +
  "\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}},{" +
  "\"id\":\"ranked\",\"inputs\":{\"left\":" +
  input +
  ",\"right\":" +
  input +
  "},\"from\":\"left\",\"steps\":[{\"merge_rankings\":{" +
  "\"with\":\"right\",\"by\":[\"q\"]," +
  "\"candidate\":\"id\",\"score\":\"score\",\"k\":2," +
  "\"score_policy\":" +
  policy +
  ",\"score_contract\":{" +
  "\"domain\":\"unit.v1\",\"normalization\":\"unit.v1\"," +
  "\"range\":[0,1]}},\"as\":\"out\"}],\"results\":{" +
  "\"r\":{\"from\":\"out\",\"fields\":[" +
  "\"q\",\"id\",\"rank\",\"score\"]}}},{" +
  "\"id\":\"consumer-a\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"ranked\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":[\"q\",\"id\",\"rank\",\"score\"]," +
  "\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":[\"q\",\"id\",\"rank\",\"score\"]}}},{" +
  "\"id\":\"consumer-b\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"ranked\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":[\"score\",\"id\"],\"as\":\"out\"}]," +
  "\"results\":{\"r\":{\"from\":\"out\",\"fields\":[" +
  "\"score\",\"id\"]}}}],\"results\":{" +
  "\"ranked\":{\"from\":{\"stage\":\"ranked\"," +
  "\"result\":\"r\"}}}}"
}

///|
fn local_carrier_vectors_program(variant? : String = "normalize") -> String {
  if variant == "ranking_max" ||
    variant == "ranking_weighted" ||
    variant == "ranking_rrf" ||
    variant == "ranking_rrf_repeated" ||
    variant == "ranking_rrf_filter" {
    return local_vector_ranking_program(variant)
  }
  if variant == "nearest" ||
    variant == "nearest_filter" ||
    variant == "nearest_filter_reversed" ||
    variant == "nearest_vectors_filter" ||
    variant == "nearest_vectors" ||
    variant == "nearest_relation_vectors" ||
    variant == "nearest_vectors_relation" ||
    variant == "nearest_cosine" ||
    variant == "nearest_l2" ||
    variant == "nearest_inferred" ||
    variant == "nearest_k1" ||
    variant == "nearest_klarge" ||
    variant == "nearest_empty" ||
    variant == "nearest_empty_queries" {
    return local_vector_nearest_program(variant)
  }
  let relation_pool = variant == "relation_pool" ||
    variant == "relation_pool_composite"
  let pooled = variant == "pool" ||
    variant == "pool_normalize" ||
    variant == "pool_shared" ||
    variant == "pool_filter" ||
    relation_pool
  let scored = variant == "score_shared" ||
    variant == "score_parameter" ||
    variant == "score_filter"
  let source_fields = "[\"id\",\"code\",\"group\",\"embedding\"]"
  let result_fields = if pooled {
    "[\"group\",\"embedding\",\"member_count\"]"
  } else if scored {
    "[\"id\",\"embedding\",\"score\"]"
  } else {
    "[\"id\",\"embedding\"]"
  }
  let second_fields = if pooled {
    "[\"member_count\",\"embedding\",\"group\"]"
  } else if scored {
    "[\"score\",\"embedding\",\"id\"]"
  } else {
    "[\"embedding\",\"id\"]"
  }
  let kernel = if variant == "score" {
    "{\"score_vectors\":{\"query\":[1,0],\"metric\":\"dot\"}}"
  } else if variant == "score_parameter" {
    "{\"score_vectors\":{\"query\":{\"$param\":\"q\"}," + "\"metric\":\"dot\"}}"
  } else if variant == "pool" {
    "{\"pool_vectors\":{\"by\":[\"group\"],\"method\":\"sum\"}}"
  } else if variant == "pool_normalize" {
    "{\"pool_vectors\":{\"by\":[\"group\"],\"method\":\"sum\"}}," +
    "{\"normalize_vectors\":true}"
  } else {
    "{\"normalize_vectors\":true}"
  }
  let source_tail = if relation_pool {
    let keys = if variant == "relation_pool_composite" {
      "[\"id\",\"code\"]"
    } else {
      "[\"id\"]"
    }
    ", {\"from\":\"out\",\"assert_rows\":{\"unique_by\":" +
    keys +
    "}," +
    "\"as\":\"keyed\"}"
  } else {
    ""
  }
  let source_result = if relation_pool { "keyed" } else { "out" }
  let vector_prefix = if relation_pool {
    ""
  } else {
    "{\"from\":\"rows\",\"to_vectors\":{" +
    "\"id\":\"id\",\"vector\":\"embedding\"}},"
  }
  let relation_vector = if relation_pool {
    "{\"pool_vectors\":{\"vector\":\"embedding\"," +
    "\"by\":[\"group\"],\"method\":\"sum\"}}"
  } else {
    kernel
  }
  let parameters = if variant == "score_parameter" {
    "{\"minimum\":{\"type\":\"number\",\"nullable\":false}," +
    "\"q\":{\"type\":\"array\",\"items\":{\"type\":\"number\"}," +
    "\"length\":2}}"
  } else {
    "{\"minimum\":{\"type\":\"number\",\"nullable\":false}}"
  }
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":" +
  parameters +
  "," +
  "\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":{" +
  "\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{" +
  "\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{" +
  "\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{" +
  "\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}},{" +
  "\"id\":\"values\",\"inputs\":{},\"steps\":[{\"values\":{" +
  "\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}," +
  "\"code\":{\"type\":\"string\",\"nullable\":false}," +
  "\"group\":{\"type\":\"number\",\"nullable\":false}," +
  "\"embedding\":{\"type\":\"vector\",\"dimensions\":2," +
  "\"nullable\":false}},\"rows\":[{\"id\":1,\"code\":\"😀\"," +
  "\"group\":1,\"embedding\":[3,4]},{\"id\":2,\"code\":\"é\"," +
  "\"group\":1," +
  "\"embedding\":[0,5]}]}," +
  "\"as\":\"out\"}" +
  source_tail +
  "],\"results\":{\"r\":{\"from\":\"" +
  source_result +
  "\"," +
  "\"fields\":" +
  source_fields +
  "}}},{\"id\":\"vectors\",\"inputs\":{" +
  "\"rows\":{\"result\":{\"stage\":\"values\",\"result\":\"r\"}}}," +
  "\"steps\":[" +
  (if variant == "normalize_shared" {
    "{\"from\":\"rows\",\"to_vectors\":{" +
    "\"id\":\"id\",\"vector\":\"embedding\"}," +
    "\"as\":\"source\"},{\"from\":\"source\"," +
    "\"normalize_vectors\":true,\"as\":\"normalized\"}," +
    "{\"from\":\"normalized\",\"score_vectors\":{" +
    "\"query\":[1,0],\"metric\":\"dot\"}," +
    "\"as\":\"same_carrier\"},{\"from\":\"normalized\"," +
    "\"vectors\":true,\"as\":\"out\"}"
  } else if variant == "score_shared" {
    "{\"from\":\"rows\",\"to_vectors\":{" +
    "\"id\":\"id\",\"vector\":\"embedding\"}," +
    "\"as\":\"source\"},{\"from\":\"source\"," +
    "\"score_vectors\":{\"query\":[0,1],\"metric\":\"dot\"}," +
    "\"as\":\"scored\"},{\"from\":\"scored\"," +
    "\"normalize_vectors\":true,\"as\":\"same_carrier\"}," +
    "{\"from\":\"scored\",\"vectors\":true,\"as\":\"out\"}"
  } else if variant == "pool_shared" {
    "{\"from\":\"rows\",\"to_vectors\":{" +
    "\"id\":\"id\",\"vector\":\"embedding\"}," +
    "\"as\":\"source\"},{\"from\":\"source\"," +
    "\"pool_vectors\":{\"by\":[\"group\"],\"method\":\"sum\"}," +
    "\"as\":\"pooled\"},{\"from\":\"pooled\"," +
    "\"normalize_vectors\":true,\"as\":\"same_carrier\"}," +
    "{\"from\":\"pooled\",\"vectors\":true,\"as\":\"out\"}"
  } else if variant == "bridge_only" ||
    variant == "bridge_filter" ||
    variant == "normalize_filter" ||
    variant == "score_filter" ||
    variant == "pool_filter" ||
    variant == "bridge_select" ||
    variant == "bridge_derive" ||
    variant == "bridge_take" {
    "{\"from\":\"rows\",\"to_vectors\":{" +
    "\"id\":\"id\",\"vector\":\"embedding\"}," +
    "\"as\":\"source\"}," +
    (if variant == "normalize_filter" {
      "{\"from\":\"source\",\"normalize_vectors\":true," +
      "\"as\":\"normalized\"},"
    } else if variant == "score_filter" {
      "{\"from\":\"source\",\"score_vectors\":{" +
      "\"query\":[1,0],\"metric\":\"dot\"}," +
      "\"as\":\"scored\"},"
    } else if variant == "pool_filter" {
      "{\"from\":\"source\",\"pool_vectors\":{" +
      "\"by\":[\"group\"],\"method\":\"sum\"}," +
      "\"as\":\"pooled\"},"
    } else {
      ""
    }) +
    "{\"from\":\"" +
    (if variant == "normalize_filter" {
      "normalized"
    } else if variant == "score_filter" {
      "scored"
    } else if variant == "pool_filter" {
      "pooled"
    } else {
      "source"
    }) +
    "\"," +
    "\"vectors\":true,\"as\":" +
    (if variant != "bridge_only" { "\"projected\"}" } else { "\"out\"}" }) +
    (if variant != "bridge_only" {
      ",{" +
      "\"from\":\"projected\"," +
      (if variant == "bridge_select" {
        "\"select\":[\"id\",\"embedding\"]"
      } else if variant == "bridge_derive" {
        "\"derive\":{\"copy\":\"id\"}"
      } else if variant == "bridge_take" {
        "\"take\":2"
      } else {
        "\"filter\":\"true\""
      }) +
      ",\"as\":\"out\"}"
    } else {
      ""
    })
  } else {
    vector_prefix + relation_vector + ",{\"vectors\":true,\"as\":\"out\"}"
  }) +
  "]," +
  "\"results\":{\"r\":{\"from\":\"out\",\"fields\":" +
  result_fields +
  "}}},{\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"vectors\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":" +
  result_fields +
  ",\"as\":\"out\"}],\"results\":{\"r\":{" +
  "\"from\":\"out\",\"fields\":" +
  result_fields +
  "}}},{" +
  "\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"vectors\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":" +
  second_fields +
  ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":" +
  second_fields +
  "}}}],\"results\":{\"source\":{\"from\":{" +
  "\"stage\":\"a\",\"result\":\"r\"}}}}"
}

///|
fn nearest_publication_cid(variant : String) -> String {
  if variant == "nearest_l2" {
    "sha256:6fd5e80b9824a60178c6d632a29a3ade2037dd531c4ab3a7731511da70341685"
  } else if variant == "nearest_inferred" {
    "sha256:9fceff97e3f1c2985ffcdb1e8167ad34c6b592525de45530dd84f7ef740aec89"
  } else if variant == "nearest_k1" {
    "sha256:cd5ca17c629007382b00c09734661c5827adfcd3c9f5e2e2efcd688ff5648d0c"
  } else if variant == "nearest_klarge" {
    "sha256:5634ee66e92ec13e0d328d95045fd9706fe46b3c879e19f5a33a18b8ec7bad46"
  } else if variant == "nearest_empty" || variant == "nearest_empty_queries" {
    "sha256:d2889f6d3b43fe20f75149d13eb0585918c94cf3a5b0520f5f9e1525b0846f3d"
  } else {
    "sha256:6d303cfa8e4881cd9d7066c505a353c00e1509ccc247bc03332331fa09e8aaff"
  }
}

///|
fn ranking_publication_cid(variant : String) -> String {
  if variant == "ranking_rrf_repeated" {
    "sha256:c899349a78ca0ef0bfea1d49f419358d615bd190ec9509e5f95d50d48514a14c"
  } else {
    "sha256:1cc59701e6c8d10ddf972c511d5f8f643bac488916a95f656f2d0c6f9f7c925a"
  }
}

///|
fn local_vector_ranking_program(variant : String) -> String {
  let rrf = variant == "ranking_rrf" ||
    variant == "ranking_rrf_repeated" ||
    variant == "ranking_rrf_filter"
  let repeated = variant == "ranking_rrf_repeated"
  let schema = if rrf {
    "{\"q\":{\"type\":\"number\",\"nullable\":false}," +
    "\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"rank\":{\"type\":\"number\",\"nullable\":false}}"
  } else {
    "{\"q\":{\"type\":\"number\",\"nullable\":false}," +
    "\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"score\":{\"type\":\"number\",\"nullable\":false}}"
  }
  let left_rows = if rrf {
    "[{\"q\":1,\"id\":1,\"rank\":1},{\"q\":1,\"id\":2," +
    "\"rank\":2},{\"q\":2,\"id\":1,\"rank\":1}]"
  } else {
    "[{\"q\":1,\"id\":1,\"score\":0.75},{\"q\":1," +
    "\"id\":2,\"score\":0.5},{\"q\":2,\"id\":1," +
    "\"score\":0.25}]"
  }
  let right_rows = if rrf {
    "[{\"q\":1,\"id\":3,\"rank\":1},{\"q\":1,\"id\":1," +
    "\"rank\":2},{\"q\":2,\"id\":1,\"rank\":1}]"
  } else {
    "[{\"q\":1,\"id\":1,\"score\":0.5},{\"q\":1," +
    "\"id\":3,\"score\":0.25},{\"q\":2,\"id\":1," +
    "\"score\":0.75}]"
  }
  let options = if rrf {
    "\"rank\":\"rank\",\"score_policy\":{\"rrf\":{" +
    "\"rank_constant\":1,\"weights\":" +
    (if repeated { "[1,1,2]" } else { "[1,1]" }) +
    ",\"rank_window\":2}}"
  } else {
    let policy = if variant == "ranking_weighted" {
      "{\"weighted_sum\":{\"left\":0.5,\"right\":0.5}}"
    } else {
      "\"max\""
    }
    "\"score\":\"score\",\"score_policy\":" +
    policy +
    ",\"score_contract\":{\"domain\":\"unit.v1\"," +
    "\"range\":[0,1],\"normalization\":\"unit.v1\"}"
  }
  let fields = "[\"q\",\"id\",\"score\",\"rank\"]"
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":{" +
  "\"minimum\":{\"type\":\"number\",\"nullable\":false}}," +
  "\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":{" +
  "\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{" +
  "\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{" +
  "\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{\"r\":{" +
  "\"from\":\"captured\",\"fields\":[\"id\"]}}},{" +
  "\"id\":\"left\",\"inputs\":{},\"steps\":[{\"values\":{" +
  "\"schema\":" +
  schema +
  ",\"rows\":" +
  left_rows +
  "},\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":" +
  (if rrf { "[\"q\",\"id\",\"rank\"]" } else { "[\"q\",\"id\",\"score\"]" }) +
  "}}},{\"id\":\"right\",\"inputs\":{},\"steps\":[{\"values\":{" +
  "\"schema\":" +
  schema +
  ",\"rows\":" +
  right_rows +
  "},\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":" +
  (if rrf { "[\"q\",\"id\",\"rank\"]" } else { "[\"q\",\"id\",\"score\"]" }) +
  "}}},{\"id\":\"fusion\",\"inputs\":{\"left\":{\"result\":{" +
  "\"stage\":\"left\",\"result\":\"r\"}},\"right\":{\"result\":{" +
  "\"stage\":\"right\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"from\":\"left\",\"merge_rankings\":{\"with\":" +
  (if repeated {
    "[\"right\",\"right\"]"
  } else if rrf {
    "[\"right\"]"
  } else {
    "\"right\""
  }) +
  ",\"by\":[\"q\"],\"candidate\":\"id\"," +
  options +
  ",\"k\":2},\"as\":\"out\"}" +
  (if variant == "ranking_rrf_filter" {
    ",{\"from\":\"out\",\"filter\":\"q = 1\",\"as\":\"filtered\"}"
  } else {
    ""
  }) +
  "],\"results\":{\"r\":{\"from\":\"" +
  (if variant == "ranking_rrf_filter" { "filtered" } else { "out" }) +
  "\",\"fields\":" +
  fields +
  "}}},{\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"fusion\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":" +
  fields +
  ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":" +
  fields +
  "}}},{\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"fusion\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":[\"rank\",\"score\",\"id\",\"q\"]," +
  "\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":[\"rank\",\"score\",\"id\",\"q\"]}}}]," +
  "\"results\":{\"source\":{\"from\":{\"stage\":\"a\"," +
  "\"result\":\"r\"}}}}"
}

///|
fn local_vector_nearest_program(variant : String) -> String {
  let inferred = variant == "nearest_inferred"
  let filtered = variant == "nearest_filter" ||
    variant == "nearest_filter_reversed" ||
    variant == "nearest_vectors_filter"
  let candidate_vectors = variant == "nearest_vectors" ||
    variant == "nearest_vectors_filter" ||
    variant == "nearest_vectors_relation"
  let query_vectors = variant == "nearest_vectors" ||
    variant == "nearest_vectors_filter" ||
    variant == "nearest_relation_vectors"
  let identity_type = if inferred { "string" } else { "number" }
  let vector_schema = "{\"id\":{\"type\":\"" +
    identity_type +
    "\",\"nullable\":false}," +
    "\"embedding\":{\"type\":\"vector\",\"dimensions\":2," +
    "\"nullable\":false}}"
  let ranking_fields = "[\"query_id\",\"candidate_id\",\"score\",\"rank\"]"
  let candidate_rows = if variant == "nearest_empty" {
    "[]"
  } else if inferred {
    "[{\"id\":\"b\",\"embedding\":[1,0]},{\"id\":\"a\"," +
    "\"embedding\":[1,0]},{\"id\":\"c\",\"embedding\":[0,1]}]"
  } else {
    "[{\"id\":2,\"embedding\":[1,0]},{\"id\":1," +
    "\"embedding\":[1,0]},{\"id\":3,\"embedding\":[0,1]}]"
  }
  let query_rows = if variant == "nearest_empty_queries" {
    "[]"
  } else if inferred {
    "[{\"id\":\"t\",\"embedding\":[1,0]},{\"id\":\"q\"," +
    "\"embedding\":[0,1]}]"
  } else {
    "[{\"id\":20,\"embedding\":[1,0]},{\"id\":10," + "\"embedding\":[0,1]}]"
  }
  let candidate_roles = if inferred || candidate_vectors {
    ""
  } else {
    "\"candidate_id\":\"id\",\"candidate_vector\":\"embedding\","
  }
  let query_roles = if inferred || query_vectors {
    ""
  } else {
    "\"query_id\":\"id\",\"query_vector\":\"embedding\","
  }
  let candidate_input = if candidate_vectors {
    "candidate_vectors"
  } else {
    "candidates"
  }
  let query_input = if query_vectors { "query_vectors" } else { "queries" }
  let nearest_result = if filtered { "filtered" } else { "out" }
  let nearest_inputs = if variant == "nearest_filter_reversed" {
    "\"queries\":{\"result\":{\"stage\":\"queries\",\"result\":\"r\"}}," +
    "\"candidates\":{\"result\":{\"stage\":\"candidates\",\"result\":\"r\"}}"
  } else {
    "\"candidates\":{\"result\":{\"stage\":\"candidates\",\"result\":\"r\"}}," +
    "\"queries\":{\"result\":{\"stage\":\"queries\",\"result\":\"r\"}}"
  }
  let candidate_bridge = if candidate_vectors {
    "{\"from\":\"candidates\",\"to_vectors\":{" +
    "\"id\":\"id\",\"vector\":\"embedding\"}," +
    "\"as\":\"candidate_vectors\"},"
  } else {
    ""
  }
  let query_bridge = if query_vectors {
    "{\"from\":\"queries\",\"to_vectors\":{" +
    "\"id\":\"id\",\"vector\":\"embedding\"}," +
    "\"as\":\"query_vectors\"},"
  } else {
    ""
  }
  let identity_tail = if inferred {
    ",{\"from\":\"out\",\"assert_rows\":{\"unique_by\":[\"id\"]}," +
    "\"as\":\"keyed\"}"
  } else {
    ""
  }
  let source_result = if inferred { "keyed" } else { "out" }
  let metric = if variant == "nearest_cosine" {
    "cosine"
  } else if variant == "nearest_l2" {
    "l2"
  } else {
    "dot"
  }
  let k = if variant == "nearest_k1" {
    "1"
  } else if variant == "nearest_klarge" {
    "5"
  } else {
    "2"
  }
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":{" +
  "\"minimum\":{\"type\":\"number\",\"nullable\":false}}," +
  "\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":{" +
  "\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{" +
  "\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{" +
  "\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{" +
  "\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}},{" +
  "\"id\":\"candidates\",\"inputs\":{},\"steps\":[{\"values\":{" +
  "\"schema\":" +
  vector_schema +
  ",\"rows\":" +
  candidate_rows +
  "},\"as\":\"out\"}" +
  identity_tail +
  "],\"results\":{\"r\":{\"from\":\"" +
  source_result +
  "\",\"fields\":[\"id\",\"embedding\"]}}},{" +
  "\"id\":\"queries\",\"inputs\":{},\"steps\":[{\"values\":{" +
  "\"schema\":" +
  vector_schema +
  ",\"rows\":" +
  query_rows +
  "},\"as\":\"out\"}" +
  identity_tail +
  "],\"results\":{\"r\":{\"from\":\"" +
  source_result +
  "\",\"fields\":[\"id\"," +
  "\"embedding\"]}}},{\"id\":\"nearest\",\"inputs\":{" +
  nearest_inputs +
  "},\"steps\":[" +
  candidate_bridge +
  query_bridge +
  "{\"from\":\"" +
  candidate_input +
  "\",\"nearest\":{\"queries\":\"" +
  query_input +
  "\"," +
  candidate_roles +
  query_roles +
  "\"metric\":\"" +
  metric +
  "\",\"k\":" +
  k +
  "}," +
  "\"as\":\"out\"}" +
  (if filtered {
    ", {\"from\":\"out\",\"filter\":\"query_id = 20\",\"as\":\"filtered\"}"
  } else {
    ""
  }) +
  "],\"results\":{\"r\":{\"from\":\"" +
  nearest_result +
  "\"," +
  "\"fields\":" +
  ranking_fields +
  "}}},{\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"nearest\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":" +
  ranking_fields +
  ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":" +
  ranking_fields +
  "}}},{\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"nearest\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":[\"rank\",\"score\",\"candidate_id\",\"query_id\"]," +
  "\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":[\"rank\",\"score\",\"candidate_id\",\"query_id\"]}}}]," +
  "\"results\":{\"source\":{\"from\":{\"stage\":\"a\"," +
  "\"result\":\"r\"}}}}"
}

///|
fn local_vector_expression_program() -> String {
  let schema = "{\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"left\":{\"type\":\"vector\",\"dimensions\":2," +
    "\"nullable\":false},\"right\":{\"type\":\"vector\"," +
    "\"dimensions\":2,\"nullable\":false}}"
  let fields = "[\"id\",\"score\",\"joined\"]"
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":{" +
  "\"minimum\":{\"type\":\"number\",\"nullable\":false}}," +
  "\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":{" +
  "\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{" +
  "\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{" +
  "\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{" +
  "\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}},{" +
  "\"id\":\"vector_values\",\"inputs\":{},\"steps\":[{\"values\":{" +
  "\"schema\":" +
  schema +
  ",\"rows\":[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{" +
  "\"id\":2,\"left\":[2,1],\"right\":[4,3]}]},\"as\":\"out\"}]," +
  "\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"," +
  "\"left\",\"right\"]}}},{\"id\":\"vector_score\",\"inputs\":{" +
  "\"rows\":{\"result\":{\"stage\":\"vector_values\"," +
  "\"result\":\"r\"}}},\"steps\":[{\"derive\":{\"score\":{" +
  "\"vector_score\":{\"left\":{\"field\":\"left\"}," +
  "\"right\":{\"field\":\"right\"},\"metric\":\"dot\"}}}," +
  "\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":[\"id\",\"left\",\"right\",\"score\"]}}},{" +
  "\"id\":\"vectors\",\"inputs\":{\"rows\":{\"result\":{" +
  "\"stage\":\"vector_score\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"derive\":{" +
  "\"joined\":{\"vector_concat\":[{\"field\":\"right\"},{" +
  "\"field\":\"left\"}]}},\"as\":\"out\"}],\"results\":{" +
  "\"r\":{\"from\":\"out\",\"fields\":" +
  fields +
  "}}},{\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"vectors\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":" +
  fields +
  ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":" +
  fields +
  "}}},{\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"vectors\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":[\"joined\",\"score\",\"id\"],\"as\":\"out\"}]," +
  "\"results\":{\"r\":{\"from\":\"out\",\"fields\":[" +
  "\"joined\",\"score\",\"id\"]}}}],\"results\":{\"source\":{" +
  "\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}"
}

///|
fn carrier_vectors_storage_limits() -> @record_storage.Limits {
  {
    max_input_records: 10,
    max_records: 10,
    max_fields_per_record: 10,
    max_value_bytes: 1000,
    max_total_value_bytes: 10000,
    max_retained_value_bytes: 10000,
    max_value_nodes: 100,
    max_value_depth: 10,
    max_contract_work: 1000,
    max_work: 1000,
    max_workspace_slots: 1000,
  }
}

///|
fn run_standard_vectors_provider(variant : String) -> Unit raise {
  let relation_pool = variant == "relation_pool" ||
    variant == "relation_pool_composite"
  let pooled = variant == "pool" ||
    variant == "pool_normalize" ||
    variant == "pool_shared" ||
    relation_pool
  let scored = variant == "score_shared" || variant == "score_parameter"
  let (run, issuer) = captured_graph_fixture(
    local_carrier_vectors_chain=true,
    local_carrier_vectors_variant=variant,
    // Values and the asserted Relation remain live across the pool input.
    ledger_limits=if relation_pool {
      Some({
        planning_work: 10000,
        attempts: 10,
        holdings: 10,
        transfer_bytes: 300000L,
        retained_bytes: 134217728L,
        execution_bytes: 134217728L,
      })
    } else {
      None
    },
    managed_publication=variant == "bridge_only" ||
      variant == "normalize_shared" ||
      variant == "score_shared" ||
      variant == "pool_shared",
    parameter_json=if variant == "score_parameter" {
      "{\"minimum\":1,\"q\":[0,1]}"
    } else {
      "{\"minimum\":1}"
    },
  )
  if variant == "bridge_only" ||
    variant == "normalize_shared" ||
    variant == "score_shared" ||
    variant == "pool_shared" {
    assert_true(
      @strategy.configure_captured_managed_identity_policy(
        run, true, false, false, false,
      ),
    )
  }
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
  let vector_task = if relation_pool { 3 } else { 2 }
  let cleanup_attempts = Ref(0)
  let provider = delayed_cleanup_provider(
    @local_veca_provider.provider(
      carrier_vectors_storage_limits(),
      4096L,
      @execution.generated_sequence_capacity(
        sequences[vector_task - 1],
        limits.local_execution,
        limits.guards,
      ).unwrap(),
    ),
    cleanup_attempts,
  )
  let modules = @builtin.configure_compute_modules(
    @host_driver.open_dispatch_driver(run),
    registry,
    1,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_local=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          sequences,
          managed_providers: [provider],
          managed_capacity: limits.capacity,
          execution: limits.local_execution,
          measurement: limits.guards,
          max_work: limits.candidate_work,
        },
        _ => @strategy.RunIssue::ForeignCandidate,
        _ => @strategy.RunIssue::ForeignCandidate,
      ),
    ),
  ).unwrap()
  let installed = @builtin.configured_local_module(modules).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_columns: 10,
      },
      row: {
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_text_bytes: 3000,
      },
      max_batch_bytes: 3000,
    },
    None,
  ).unwrap()

  let values_live = Ref(true)
  let (values_ops, values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    values_live,
  )
  let values_rows = local_managed_test_rows(values_ops)
  let (assertion_ops, vector_input, assertion_live) = if relation_pool {
    let live = Ref(true)
    let (ops, output) = run_local_managed_test_task(
      installed,
      run,
      2,
      [values],
      [values_rows],
      2,
      live,
      execution_quantum=1,
      require_provider=true,
    )
    assert_eq(local_managed_test_rows(ops), values_rows)
    (Some(ops), output, Some(live))
  } else {
    (None, values, None)
  }
  let vector_input_rows = if relation_pool {
    local_managed_test_rows(assertion_ops.unwrap())
  } else {
    values_rows
  }
  let vectors_live = Ref(true)
  let vector_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (vectors_ops, vectors) = run_local_managed_test_task(
    installed,
    run,
    vector_task,
    [vector_input],
    [vector_input_rows],
    vector_task,
    vectors_live,
    obligations=vector_obligations,
  )
  let vector_rows = local_managed_test_rows(vectors_ops)
  // Successful settlement observed pending cleanup; output retention and
  // the unreclaimed provider workspace remain independently accounted.
  assert_eq(cleanup_attempts.val, 1)
  assert_true(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes >
    0L,
  )
  let expected_rows = if pooled { 1 } else { 2 }
  assert_eq(vector_rows.length(), expected_rows)
  if variant == "pool_normalize" {
    assert_true(
      vector_rows[0].contains(
        "\"embedding\":[0.3162277638912201,0.9486833214759827]",
      ),
    )
  }
  if relation_pool {
    assert_true(vector_rows[0].contains("\"embedding\":[3,9]"))
    assert_true(vector_rows[0].contains("\"member_count\":2"))
  }
  assert_true(
    vector_rows[0].contains(
      if pooled {
        "\"group\":1"
      } else if scored {
        "\"id\":2"
      } else {
        "\"id\":1"
      },
    ),
  )
  assert_true(vector_rows[0].contains("\"embedding\""))
  if variant == "bridge_only" {
    assert_eq(vector_rows, [
      "{\"code\":\"😀\",\"embedding\":[3,4],\"group\":1,\"id\":1}", "{\"code\":\"é\",\"embedding\":[0,5],\"group\":1,\"id\":2}",
    ])
    let published = @execution.managed_obligations_identities(
      vector_obligations,
    ).filter(requirement => {
      requirement.domain == @execution.LogicalRelation &&
      requirement.subject == @execution.NamedResult
    })
    assert_eq(published.length(), 1)
    match
      @execution.managed_completed_identity_requirement_status(
        vectors,
        published[0],
      ) {
      Some(@execution.EstablishedSourceRetained(contract, _)) =>
        assert_eq(
          contract,
          @execution.logical_relation_canonical_contract_cid(),
        )
      _ => fail("bridge output did not establish publication identity")
    }
  } else if variant == "normalize_shared" {
    assert_eq(vector_rows, [
      "{\"code\":\"😀\",\"embedding\":[0.6000000238418579,0.800000011920929],\"group\":1,\"id\":1}",
      "{\"code\":\"é\",\"embedding\":[0,1],\"group\":1,\"id\":2}",
    ])
    let published = @execution.managed_obligations_identities(
      vector_obligations,
    ).filter(requirement => {
      requirement.domain == @execution.LogicalRelation &&
      requirement.subject == @execution.NamedResult
    })
    assert_eq(published.length(), 1)
    assert_eq(
      @execution.managed_completed_identity_requirement_status(
        vectors,
        published[0],
      ),
      Some(
        @execution.EstablishedSourceRetained(
          @execution.logical_relation_canonical_contract_cid(),
          "sha256:4dcae0e6f3da74f61a0e6c3177bae62ac85ed202e6af740c4f672ffc61c2623a",
        ),
      ),
    )
  } else if variant == "score_shared" {
    assert_eq(vector_rows, [
      "{\"code\":\"é\",\"embedding\":[0,5],\"group\":1,\"id\":2,\"score\":5}", "{\"code\":\"😀\",\"embedding\":[3,4],\"group\":1,\"id\":1,\"score\":4}",
    ])
    let published = @execution.managed_obligations_identities(
      vector_obligations,
    ).filter(requirement => {
      requirement.domain == @execution.LogicalRelation &&
      requirement.subject == @execution.NamedResult
    })
    assert_eq(published.length(), 1)
    assert_eq(
      @execution.managed_completed_identity_requirement_status(
        vectors,
        published[0],
      ),
      Some(
        @execution.EstablishedSourceRetained(
          @execution.logical_relation_canonical_contract_cid(),
          "sha256:aeb34ab94d8916124de5af23a6bf39b6eff947099c6c6fbf486763662fd794e5",
        ),
      ),
    )
  } else if variant == "pool_shared" {
    assert_eq(vector_rows, [
      "{\"embedding\":[3,9],\"group\":1,\"member_count\":2}",
    ])
    let published = @execution.managed_obligations_identities(
      vector_obligations,
    ).filter(requirement => {
      requirement.domain == @execution.LogicalRelation &&
      requirement.subject == @execution.NamedResult
    })
    assert_eq(published.length(), 1)
    assert_eq(
      @execution.managed_completed_identity_requirement_status(
        vectors,
        published[0],
      ),
      Some(
        @execution.EstablishedSourceRetained(
          @execution.logical_relation_canonical_contract_cid(),
          "sha256:b986e2eec797d867269e0bf0abbf453d05eb90d845fc5b402fc1beb50464b05f",
        ),
      ),
    )
  }

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    vector_task + 1,
    [vectors],
    [vector_rows],
    vector_task + 1,
    first_live,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    vector_task + 2,
    [vectors],
    [vector_rows],
    vector_task + 2,
    second_live,
  )
  assert_eq(local_managed_test_rows(first_ops).length(), expected_rows)
  assert_eq(local_managed_test_rows(second_ops).length(), expected_rows)

  first_live.val = false
  @strategy.close_captured_task_output(run, vector_task + 1)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(vectors))

  second_live.val = false
  @strategy.close_captured_task_output(run, vector_task + 2)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  vectors_live.val = false
  @strategy.close_captured_task_output(run, vector_task)
  (vectors_ops.close)()
  assert_true((vectors_ops.cleanup_refresh)())
  assert_eq(cleanup_attempts.val, 2)
  if assertion_ops is Some(ops) {
    assertion_live.unwrap().val = false
    @strategy.close_captured_task_output(run, 2)
    (ops.close)()
    (ops.cleanup_refresh)() |> ignore
  }
  values_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (values_ops.close)()
  (values_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}

///|
fn run_standard_host_mixed_vectors_relation_path(
  variant : String,
  execution_quantum? : Int = 0,
) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_carrier_vectors_chain=true,
    local_carrier_vectors_variant=variant,
    managed_publication=true,
    ledger_limits=Some({
      planning_work: 30000,
      attempts: 20,
      holdings: 20,
      transfer_bytes: 800000L,
      retained_bytes: 96000000L,
      execution_bytes: 402653184L,
    }),
  )
  let transformed = variant == "normalize_filter" ||
    variant == "score_filter" ||
    variant == "pool_filter"
  let task_offset = if transformed { 1 } else { 0 }
  assert_eq(
    @strategy.graph_task_count(@strategy.captured_dag_graph(run)),
    7 + task_offset,
  )
  assert_true(
    @strategy.configure_captured_managed_identity_policy(
      run, true, false, false, false,
    ),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
  if variant == "bridge_take" {
    let mut bounded_take = false
    for position in 0..<@execution.generated_sequence_step_count(sequences[3]) {
      if @execution.generated_sequence_step_at(sequences[3], position)
        is Some(@lower.RowStep(candidate)) &&
        @lower.kernel_take(candidate) is Some(_) &&
        @lower.node_at(
          @lower.bound_preparation(
            @execution.generated_sequence_owner(sequences[3]),
          ),
          position,
        )
        is Some(node) {
        bounded_take = @lower.order_node_id(node) is None
      }
    }
    assert_true(bounded_take)
  }
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      sequences[1],
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let modules = @builtin.configure_compute_modules(
    @host_driver.open_dispatch_driver(run),
    registry,
    1,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_local=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          sequences,
          managed_providers: [provider],
          managed_capacity: limits.capacity,
          execution: limits.local_execution,
          measurement: limits.guards,
          max_work: limits.candidate_work,
        },
        _ => @strategy.RunIssue::ForeignCandidate,
        _ => @strategy.RunIssue::ForeignCandidate,
      ),
    ),
  ).unwrap()
  let installed = @builtin.configured_local_module(modules).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_columns: 10,
      },
      row: {
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_text_bytes: 3000,
      },
      max_batch_bytes: 3000,
    },
    None,
  ).unwrap()
  let values_live = Ref(true)
  let (values_ops, values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    values_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let values_rows = local_managed_test_rows(values_ops)
  let (bridge_ops, bridge, bridge_material) = run_local_managed_carrier_test_task(
    installed,
    run,
    2,
    [@local_driver.local_managed_relation_output(values)],
    [values_rows],
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let transformed_output = if transformed {
    Some(
      run_local_managed_carrier_test_task(
        installed,
        run,
        3,
        [@local_driver.local_managed_carrier_output(bridge, bridge_material)],
        [],
        obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
      ),
    )
  } else {
    None
  }
  let (projection_carrier, projection_material) = match transformed_output {
    Some((_, completed, material)) => (completed, material)
    None => (bridge, bridge_material)
  }
  let projected_live = Ref(true)
  let (projected_ops, projected) = run_local_managed_test_task(
    installed,
    run,
    3 + task_offset,
    [],
    [],
    3 + task_offset,
    projected_live,
    carrier_inputs=[(projection_carrier, projection_material)],
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let projected_rows = local_managed_test_rows(projected_ops)
  if variant == "normalize_filter" {
    assert_eq(projected_rows, [
      "{\"code\":\"😀\",\"embedding\":[0.6000000238418579,0.800000011920929],\"group\":1,\"id\":1}",
      "{\"code\":\"é\",\"embedding\":[0,1],\"group\":1,\"id\":2}",
    ])
  } else if variant == "score_filter" {
    assert_eq(projected_rows, [
      "{\"code\":\"😀\",\"embedding\":[3,4],\"group\":1,\"id\":1,\"score\":3}",
      "{\"code\":\"é\",\"embedding\":[0,5],\"group\":1,\"id\":2,\"score\":0}",
    ])
  } else if variant == "pool_filter" {
    assert_eq(projected_rows, [
      "{\"embedding\":[3,9],\"group\":1,\"member_count\":2}",
    ])
  }
  let filtered_live = Ref(true)
  let (filtered_ops, filtered) = run_local_managed_test_task(
    installed,
    run,
    4 + task_offset,
    [projected],
    [projected_rows],
    4 + task_offset,
    filtered_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
    execution_quantum~,
  )
  let filtered_rows = local_managed_test_rows(filtered_ops)
  if variant == "bridge_derive" {
    assert_true(filtered_rows[0].contains("\"copy\":1"))
    assert_true(filtered_rows[1].contains("\"copy\":2"))
  } else if variant == "bridge_select" {
    assert_true(filtered_rows[0].contains("\"id\":1"))
    assert_true(filtered_rows[1].contains("\"id\":2"))
    assert_false(filtered_rows[0].contains("\"code\""))
  } else {
    assert_eq(filtered_rows, projected_rows)
  }
  let expected_count = if variant == "pool_filter" { 1 } else { 2 }
  assert_eq(filtered_rows.length(), expected_count)
  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    5 + task_offset,
    [filtered],
    [filtered_rows],
    5 + task_offset,
    first_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    6 + task_offset,
    [filtered],
    [filtered_rows],
    6 + task_offset,
    second_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  assert_eq(local_managed_test_rows(first_ops).length(), expected_count)
  assert_eq(local_managed_test_rows(second_ops).length(), expected_count)
  first_live.val = false
  @strategy.close_captured_task_output(run, 5 + task_offset)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(filtered))
  second_live.val = false
  @strategy.close_captured_task_output(run, 6 + task_offset)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  filtered_live.val = false
  @strategy.close_captured_task_output(run, 4 + task_offset)
  (filtered_ops.close)()
  (filtered_ops.cleanup_refresh)() |> ignore
  projected_live.val = false
  @strategy.close_captured_task_output(run, 3 + task_offset)
  (projected_ops.close)()
  (projected_ops.cleanup_refresh)() |> ignore
  if transformed_output is Some((transformed_ops, _, _)) {
    @strategy.close_captured_task_output(run, 3)
    (transformed_ops.close)()
    (transformed_ops.cleanup_refresh)() |> ignore
  }
  @strategy.close_captured_task_output(run, 2)
  (bridge_ops.close)()
  (bridge_ops.cleanup_refresh)() |> ignore
  values_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (values_ops.close)()
  (values_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "standard Host composes Vectors projection and Relation filter" {
  run_standard_host_mixed_vectors_relation_path("bridge_filter")
}

///|
test "standard Host retains normalized Vectors before Relation filtering" {
  run_standard_host_mixed_vectors_relation_path("normalize_filter")
}

///|
test "standard Host retains scored Vectors before Relation filtering" {
  run_standard_host_mixed_vectors_relation_path("score_filter")
}

///|
test "standard Host retains pooled Vectors before Relation filtering" {
  run_standard_host_mixed_vectors_relation_path("pool_filter")
}

///|
test "standard Host composes Vectors projection and Relation select" {
  run_standard_host_mixed_vectors_relation_path("bridge_select")
}

///|
test "standard Host composes Vectors projection and Relation derive" {
  run_standard_host_mixed_vectors_relation_path("bridge_derive")
}

///|
test "standard Host composes Vectors projection and Relation take" {
  for quantum in [1, 2, 7, 1024] {
    run_standard_host_mixed_vectors_relation_path(
      "bridge_take",
      execution_quantum=quantum,
    )
  }
}

///|
fn run_standard_nearest_provider(variant : String) -> Unit raise {
  let inferred = variant == "nearest_inferred"
  let filtered_variant = variant == "nearest_filter" ||
    variant == "nearest_filter_reversed" ||
    variant == "nearest_vectors_filter"
  let carrier_filtered = variant == "nearest_vectors_filter"
  let query_values_task = if inferred { 3 } else { 2 }
  let nearest_task = if inferred || carrier_filtered { 5 } else { 3 }
  let (run, issuer) = captured_graph_fixture(
    local_carrier_vectors_chain=true,
    local_carrier_vectors_variant=variant,
    managed_publication=true,
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 10,
      holdings: 20,
      transfer_bytes: 300000L,
      // Both inferred inputs retain Values and assertion generations.
      retained_bytes: if inferred {
        134217728L
      } else {
        64000000L
      },
      execution_bytes: 134217728L,
    }),
  )
  if carrier_filtered {
    assert_eq(@strategy.graph_task_count(@strategy.captured_dag_graph(run)), 9)
  }
  assert_true(
    @strategy.configure_captured_managed_identity_policy(
      run, true, false, false, false,
    ),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      sequences[nearest_task - 1],
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let modules = @builtin.configure_compute_modules(
    @host_driver.open_dispatch_driver(run),
    registry,
    1,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_local=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          sequences,
          managed_providers: [provider],
          managed_capacity: limits.capacity,
          execution: limits.local_execution,
          measurement: limits.guards,
          max_work: limits.candidate_work,
        },
        _ => @strategy.RunIssue::ForeignCandidate,
        _ => @strategy.RunIssue::ForeignCandidate,
      ),
    ),
  ).unwrap()
  let installed = @builtin.configured_local_module(modules).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_columns: 10,
      },
      row: {
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_text_bytes: 3000,
      },
      max_batch_bytes: 3000,
    },
    None,
  ).unwrap()

  let candidates_live = Ref(true)
  let candidates_obligations = @strategy.captured_next_managed_obligations(
    run, 10,
  ).unwrap()
  let (candidate_values_ops, candidate_values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    candidates_live,
    obligations=if inferred {
      @execution.process_managed_obligations(
        @strategy.graph_task_owner(@strategy.captured_dag_graph(run), 1).unwrap(),
      )
    } else {
      candidates_obligations
    },
  )
  let candidate_values_rows = local_managed_test_rows(candidate_values_ops)
  let (candidate_assert_ops, candidates, candidate_assert_live) = if inferred {
    let live = Ref(true)
    let (ops, output) = run_local_managed_test_task(
      installed,
      run,
      2,
      [candidate_values],
      [candidate_values_rows],
      2,
      live,
      obligations=candidates_obligations,
      execution_quantum=1,
      require_provider=true,
    )
    assert_eq(local_managed_test_rows(ops), candidate_values_rows)
    (Some(ops), output, Some(live))
  } else {
    (None, candidate_values, None)
  }
  let candidate_rows = if inferred {
    local_managed_test_rows(candidate_assert_ops.unwrap())
  } else {
    candidate_values_rows
  }
  let queries_live = Ref(true)
  let queries_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (query_values_ops, query_values) = run_local_managed_test_task(
    installed,
    run,
    query_values_task,
    [],
    [],
    query_values_task,
    queries_live,
    obligations=if inferred {
      @execution.process_managed_obligations(
        @strategy.graph_task_owner(
          @strategy.captured_dag_graph(run),
          query_values_task,
        ).unwrap(),
      )
    } else {
      queries_obligations
    },
  )
  let query_values_rows = local_managed_test_rows(query_values_ops)
  let (query_assert_ops, queries, query_assert_live) = if inferred {
    let live = Ref(true)
    let (ops, output) = run_local_managed_test_task(
      installed,
      run,
      4,
      [query_values],
      [query_values_rows],
      4,
      live,
      obligations=queries_obligations,
      execution_quantum=1,
      require_provider=true,
    )
    assert_eq(local_managed_test_rows(ops), query_values_rows)
    (Some(ops), output, Some(live))
  } else {
    (None, query_values, None)
  }
  let query_rows = if inferred {
    local_managed_test_rows(query_assert_ops.unwrap())
  } else {
    query_values_rows
  }
  let carrier_bridges = if carrier_filtered {
    let candidate_bridge = run_local_managed_carrier_test_task(
      installed,
      run,
      3,
      [@local_driver.local_managed_relation_output(candidates)],
      [candidate_rows],
      obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
    )
    let query_bridge = run_local_managed_carrier_test_task(
      installed,
      run,
      4,
      [@local_driver.local_managed_relation_output(queries)],
      [query_rows],
      obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
    )
    Some((candidate_bridge, query_bridge))
  } else {
    None
  }
  let nearest_live = Ref(true)
  let nearest_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let nearest_outputs = if variant == "nearest_filter_reversed" {
    [queries, candidates]
  } else {
    [candidates, queries]
  }
  let nearest_input_rows = if variant == "nearest_filter_reversed" {
    [query_rows, candidate_rows]
  } else {
    [candidate_rows, query_rows]
  }
  let (nearest_ops, nearest) = match carrier_bridges {
    Some((candidate_bridge, query_bridge)) =>
      run_local_managed_test_task(
        installed,
        run,
        nearest_task,
        [],
        [],
        nearest_task,
        nearest_live,
        obligations=nearest_obligations,
        carrier_inputs=[
          (candidate_bridge.1, candidate_bridge.2),
          (query_bridge.1, query_bridge.2),
        ],
      )
    None =>
      run_local_managed_test_task(
        installed,
        run,
        nearest_task,
        nearest_outputs,
        nearest_input_rows,
        nearest_task,
        nearest_live,
        obligations=nearest_obligations,
      )
  }
  let nearest_rows = local_managed_test_rows(nearest_ops)
  let expected = if variant == "nearest_empty" ||
    variant == "nearest_empty_queries" {
    []
  } else if variant == "nearest_k1" {
    [
      "{\"candidate_id\":3,\"query_id\":10,\"rank\":1,\"score\":1}", "{\"candidate_id\":1,\"query_id\":20,\"rank\":1,\"score\":1}",
    ]
  } else if variant == "nearest_klarge" {
    [
      "{\"candidate_id\":3,\"query_id\":10,\"rank\":1,\"score\":1}", "{\"candidate_id\":1,\"query_id\":10,\"rank\":2,\"score\":0}",
      "{\"candidate_id\":2,\"query_id\":10,\"rank\":3,\"score\":0}", "{\"candidate_id\":1,\"query_id\":20,\"rank\":1,\"score\":1}",
      "{\"candidate_id\":2,\"query_id\":20,\"rank\":2,\"score\":1}", "{\"candidate_id\":3,\"query_id\":20,\"rank\":3,\"score\":0}",
    ]
  } else if variant == "nearest_inferred" {
    [
      "{\"candidate_id\":\"c\",\"query_id\":\"q\"," + "\"rank\":1,\"score\":1}",
      "{\"candidate_id\":\"a\",\"query_id\":\"q\"," + "\"rank\":2,\"score\":0}",
      "{\"candidate_id\":\"a\",\"query_id\":\"t\"," + "\"rank\":1,\"score\":1}",
      "{\"candidate_id\":\"b\",\"query_id\":\"t\"," + "\"rank\":2,\"score\":1}",
    ]
  } else if variant == "nearest_l2" {
    [
      "{\"candidate_id\":3,\"query_id\":10,\"rank\":1,\"score\":0}",
      "{\"candidate_id\":1,\"query_id\":10,\"rank\":2," +
      "\"score\":-1.4142135623730951}",
      "{\"candidate_id\":1,\"query_id\":20,\"rank\":1,\"score\":0}",
      "{\"candidate_id\":2,\"query_id\":20,\"rank\":2,\"score\":0}",
    ]
  } else {
    [
      "{\"candidate_id\":3,\"query_id\":10,\"rank\":1,\"score\":1}", "{\"candidate_id\":1,\"query_id\":10,\"rank\":2,\"score\":0}",
      "{\"candidate_id\":1,\"query_id\":20,\"rank\":1,\"score\":1}", "{\"candidate_id\":2,\"query_id\":20,\"rank\":2,\"score\":1}",
    ]
  }
  assert_eq(nearest_rows, expected)
  let filtered = if filtered_variant {
    let live = Ref(true)
    let obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
    let (operations, completed) = run_local_managed_test_task(
      installed,
      run,
      nearest_task + 1,
      [nearest],
      [nearest_rows],
      nearest_task + 1,
      live,
      obligations~,
      execution_quantum=1,
      require_provider=true,
    )
    let rows = local_managed_test_rows(operations)
    assert_eq(rows, [
      "{\"candidate_id\":1,\"query_id\":20,\"rank\":1,\"score\":1}", "{\"candidate_id\":2,\"query_id\":20,\"rank\":2,\"score\":1}",
    ])
    Some((operations, completed, rows, obligations, live))
  } else {
    None
  }
  let (
    producer_ops,
    producer,
    producer_rows,
    producer_obligations,
    producer_live,
  ) = match filtered {
    Some(value) => value
    None =>
      (nearest_ops, nearest, nearest_rows, nearest_obligations, nearest_live)
  }
  let producer_task = if filtered is Some(_) {
    nearest_task + 1
  } else {
    nearest_task
  }
  let published = @execution.managed_obligations_identities(
    producer_obligations,
  ).filter(requirement => {
    requirement.domain == @execution.LogicalRelation &&
    requirement.subject == @execution.NamedResult
  })
  assert_eq(published.length(), 1)
  match
    @execution.managed_completed_identity_requirement_status(
      producer,
      published[0],
    ) {
    Some(@execution.EstablishedSourceRetained(contract, cid)) => {
      assert_eq(contract, @execution.logical_relation_canonical_contract_cid())
      if !filtered_variant {
        assert_eq(cid, nearest_publication_cid(variant))
      }
    }
    _ => fail("nearest output did not establish publication identity")
  }

  let first_live = Ref(true)
  let first_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    producer_task + 1,
    [producer],
    [producer_rows],
    producer_task + 1,
    first_live,
    obligations=first_obligations,
  )
  let second_live = Ref(true)
  let second_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    producer_task + 2,
    [producer],
    [producer_rows],
    producer_task + 2,
    second_live,
    obligations=second_obligations,
  )
  assert_eq(local_managed_test_rows(first_ops).length(), producer_rows.length())
  assert_eq(
    local_managed_test_rows(second_ops).length(),
    producer_rows.length(),
  )

  first_live.val = false
  @strategy.close_captured_task_output(run, producer_task + 1)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(producer))

  second_live.val = false
  @strategy.close_captured_task_output(run, producer_task + 2)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  producer_live.val = false
  @strategy.close_captured_task_output(run, producer_task)
  (producer_ops.close)()
  (producer_ops.cleanup_refresh)() |> ignore
  if filtered is Some(_) {
    nearest_live.val = false
    @strategy.close_captured_task_output(run, nearest_task)
    (nearest_ops.close)()
    (nearest_ops.cleanup_refresh)() |> ignore
  }
  if query_assert_ops is Some(ops) {
    query_assert_live.unwrap().val = false
    @strategy.close_captured_task_output(run, 4)
    (ops.close)()
    (ops.cleanup_refresh)() |> ignore
  }
  if carrier_bridges is Some((candidate_bridge, query_bridge)) {
    @strategy.close_captured_task_output(run, 4)
    (query_bridge.0.close)()
    (query_bridge.0.cleanup_refresh)() |> ignore
    @strategy.close_captured_task_output(run, 3)
    (candidate_bridge.0.close)()
    (candidate_bridge.0.cleanup_refresh)() |> ignore
  }
  queries_live.val = false
  @strategy.close_captured_task_output(run, query_values_task)
  (query_values_ops.close)()
  (query_values_ops.cleanup_refresh)() |> ignore
  if candidate_assert_ops is Some(ops) {
    candidate_assert_live.unwrap().val = false
    @strategy.close_captured_task_output(run, 2)
    (ops.close)()
    (ops.cleanup_refresh)() |> ignore
  }
  candidates_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (candidate_values_ops.close)()
  (candidate_values_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}

///|
fn run_standard_ranking_provider(variant : String) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_carrier_vectors_chain=true,
    local_carrier_vectors_variant=variant,
    managed_publication=true,
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 10,
      holdings: 20,
      transfer_bytes: 300000L,
      retained_bytes: 64000000L,
      execution_bytes: 134217728L,
    }),
  )
  assert_true(
    @strategy.configure_captured_managed_identity_policy(
      run, true, false, false, false,
    ),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      sequences[3],
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let modules = @builtin.configure_compute_modules(
    @host_driver.open_dispatch_driver(run),
    registry,
    1,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_local=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          sequences,
          managed_providers: [provider],
          managed_capacity: limits.capacity,
          execution: limits.local_execution,
          measurement: limits.guards,
          max_work: limits.candidate_work,
        },
        _ => @strategy.RunIssue::ForeignCandidate,
        _ => @strategy.RunIssue::ForeignCandidate,
      ),
    ),
  ).unwrap()
  let installed = @builtin.configured_local_module(modules).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_columns: 10,
      },
      row: {
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_text_bytes: 3000,
      },
      max_batch_bytes: 3000,
    },
    None,
  ).unwrap()

  if variant == "ranking_rrf_filter" {
    assert_eq(@local_driver.local_dispatch_rejection(installed, 3), None)
  }

  let left_live = Ref(true)
  let left_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (left_ops, left) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    left_live,
    obligations=left_obligations,
  )
  let left_rows = local_managed_test_rows(left_ops)
  let right_live = Ref(true)
  let right_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (right_ops, right) = run_local_managed_test_task(
    installed,
    run,
    2,
    [],
    [],
    2,
    right_live,
    obligations=right_obligations,
  )
  let right_rows = local_managed_test_rows(right_ops)
  let fusion_live = Ref(true)
  let fusion_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (fusion_ops, fusion) = run_local_managed_test_task(
    installed,
    run,
    3,
    [left, right],
    [left_rows, right_rows],
    3,
    fusion_live,
    obligations=fusion_obligations,
  )
  let fused_rows = local_managed_test_rows(fusion_ops)
  let expected = if variant == "ranking_rrf_repeated" {
    [
      "{\"id\":1,\"q\":1,\"rank\":1,\"score\":1.5}", "{\"id\":3,\"q\":1,\"rank\":2,\"score\":1.5}",
      "{\"id\":1,\"q\":2,\"rank\":1,\"score\":2}",
    ]
  } else {
    [
      "{\"id\":1,\"q\":1,\"rank\":1,\"score\":0.8333333333333333}", "{\"id\":3,\"q\":1,\"rank\":2,\"score\":0.5}",
      "{\"id\":1,\"q\":2,\"rank\":1,\"score\":1}",
    ]
  }
  assert_eq(fused_rows, expected)
  let filtered = if variant == "ranking_rrf_filter" {
    let live = Ref(true)
    let obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
    let (operations, completed) = run_local_managed_test_task(
      installed,
      run,
      4,
      [fusion],
      [fused_rows],
      4,
      live,
      obligations~,
      execution_quantum=1,
      require_provider=true,
    )
    let rows = local_managed_test_rows(operations)
    assert_eq(rows, [
      "{\"id\":1,\"q\":1,\"rank\":1,\"score\":0.8333333333333333}", "{\"id\":3,\"q\":1,\"rank\":2,\"score\":0.5}",
    ])
    Some((operations, completed, rows, obligations, live))
  } else {
    None
  }
  let (
    producer_ops,
    producer,
    producer_rows,
    producer_obligations,
    producer_live,
  ) = match filtered {
    Some(value) => value
    None => (fusion_ops, fusion, fused_rows, fusion_obligations, fusion_live)
  }
  let producer_task = if filtered is Some(_) { 4 } else { 3 }
  let published = @execution.managed_obligations_identities(
    producer_obligations,
  ).filter(requirement => {
    requirement.domain == @execution.LogicalRelation &&
    requirement.subject == @execution.NamedResult
  })
  assert_eq(published.length(), 1)
  match
    @execution.managed_completed_identity_requirement_status(
      producer,
      published[0],
    ) {
    Some(@execution.EstablishedSourceRetained(contract, cid)) => {
      assert_eq(contract, @execution.logical_relation_canonical_contract_cid())
      if variant != "ranking_rrf_filter" {
        assert_eq(cid, ranking_publication_cid(variant))
      }
    }
    _ => fail("ranking output did not establish publication identity")
  }

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    producer_task + 1,
    [producer],
    [producer_rows],
    producer_task + 1,
    first_live,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    producer_task + 2,
    [producer],
    [producer_rows],
    producer_task + 2,
    second_live,
  )
  assert_eq(local_managed_test_rows(first_ops).length(), producer_rows.length())
  assert_eq(
    local_managed_test_rows(second_ops).length(),
    producer_rows.length(),
  )

  first_live.val = false
  @strategy.close_captured_task_output(run, producer_task + 1)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(producer))

  second_live.val = false
  @strategy.close_captured_task_output(run, producer_task + 2)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  producer_live.val = false
  @strategy.close_captured_task_output(run, producer_task)
  (producer_ops.close)()
  (producer_ops.cleanup_refresh)() |> ignore
  if filtered is Some(_) {
    fusion_live.val = false
    @strategy.close_captured_task_output(run, 3)
    (fusion_ops.close)()
    (fusion_ops.cleanup_refresh)() |> ignore
  }
  right_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (right_ops.close)()
  (right_ops.cleanup_refresh)() |> ignore
  left_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (left_ops.close)()
  (left_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "standard Host runs bounded vector normalization provider" {
  run_standard_vectors_provider("normalize")
}

///|
test "standard Host runs the vector bridge through two consumers" {
  run_standard_vectors_provider("bridge_only")
}

///|
test "standard Host shares normalized Vectors with a Carrier consumer" {
  run_standard_vectors_provider("normalize_shared")
}

///|
test "standard Host shares scored Vectors with a Carrier consumer" {
  run_standard_vectors_provider("score_shared")
}

///|
test "standard Host resolves a parameterized vector score query" {
  run_standard_vectors_provider("score_parameter")
}

///|
test "standard Host runs RRF ranking fusion with two consumers" {
  run_standard_ranking_provider("ranking_rrf")
}

///|
test "standard Host filters bounded ranking in the same Stage" {
  run_standard_ranking_provider("ranking_rrf_filter")
}

///|
test "scored ranking fusion rejects undeclared value columns" {
  for variant in ["ranking_max", "ranking_weighted"] {
    let rejected = try {
      ignore(
        query_checked_program_fixture(
          local_carrier_vectors_chain=true,
          local_carrier_vectors_variant=variant,
          managed_publication=true,
        ),
      )
      false
    } catch {
      @program_check.LocalConstructionFailure::Source(_) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "standard Host preserves repeated RRF input occurrences" {
  run_standard_ranking_provider("ranking_rrf_repeated")
}

///|
test "standard Host runs bounded vector scoring provider" {
  run_standard_vectors_provider("score")
}

///|
test "standard Host runs bounded vector pooling provider" {
  run_standard_vectors_provider("pool")
}

///|
test "standard Host composes pooling and normalization" {
  run_standard_vectors_provider("pool_normalize")
}

///|
test "standard Host shares pooled Vectors with a Carrier consumer" {
  run_standard_vectors_provider("pool_shared")
}

///|
test "standard Host pools author-visible Relation input" {
  run_standard_vectors_provider("relation_pool")
}

///|
test "standard Host encodes composite Relation pool identity" {
  run_standard_vectors_provider("relation_pool_composite")
}

///|
test "standard Host runs exact nearest with two consumers" {
  run_standard_nearest_provider("nearest")
}

///|
test "standard Host filters selected nearest in the same Stage" {
  run_standard_nearest_provider("nearest_filter")
}

///|
test "standard Host keeps reversed selected nearest input ports" {
  run_standard_nearest_provider("nearest_filter_reversed")
}

///|
test "standard Host runs nearest with two Vectors inputs" {
  run_standard_nearest_provider("nearest_vectors")
}

///|
test "standard Host retains selected nearest from two Vectors inputs" {
  run_standard_nearest_provider("nearest_vectors_filter")
}

///|
test "standard Host runs nearest with Relation and Vectors inputs" {
  run_standard_nearest_provider("nearest_relation_vectors")
}

///|
test "standard Host runs nearest with Vectors and Relation inputs" {
  run_standard_nearest_provider("nearest_vectors_relation")
}

///|
test "standard Host runs exact cosine nearest" {
  run_standard_nearest_provider("nearest_cosine")
}

///|
test "standard Host runs exact negative-L2 nearest" {
  run_standard_nearest_provider("nearest_l2")
}

///|
test "standard Host completes nearest Relation roles" {
  run_standard_nearest_provider("nearest_inferred")
}

///|
test "standard Host enforces nearest k prefix" {
  run_standard_nearest_provider("nearest_k1")
}

///|
test "standard Host caps nearest k at candidate count" {
  run_standard_nearest_provider("nearest_klarge")
}

///|
test "standard Host validates empty nearest corpus" {
  run_standard_nearest_provider("nearest_empty")
}

///|
test "standard Host validates empty nearest queries" {
  run_standard_nearest_provider("nearest_empty_queries")
}

///|
fn direct_nearest_vector_carrier(
  text_identity? : Bool = false,
) -> @carrier_contract.Carrier {
  @carrier_contract.vectors(
    @carrier_contract.rows(
      [
        (
          @schema.Unqualified("id"),
          Some(
            @value_contract.primitive(
              if text_identity {
                @value_contract.StringType
              } else {
                @value_contract.NumberType
              },
              nullable=false,
            ),
          ),
        ),
        (
          @schema.Unqualified("embedding"),
          Some(@value_contract.vector_contract(2.0, nullable=false).unwrap()),
        ),
      ],
      field_set=@carrier_contract.Closed,
      max_fields=2,
      max_name_bytes=11,
    ).unwrap(),
    ids=[@schema.Unqualified("id")],
    components=@schema.Unqualified("embedding"),
    max_identity_fields=1,
  ).unwrap()
}

///|
fn direct_nearest_relation_carrier(
  text_identity? : Bool = false,
) -> @carrier_contract.Carrier {
  guard direct_nearest_vector_carrier(text_identity~)
    is @carrier_contract.VectorValue(vectors) else {
    abort("vectors")
  }
  @carrier_contract.relation(@carrier_contract.vector_records(vectors))
}

///|
fn direct_nearest_bind(
  checked : @pipeline.CheckedPipeline,
) -> @lower.BoundPrepared {
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn direct_nearest_vector_owner(
  text_identity? : Bool = false,
) -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check_carriers(
      input_cursor(
        "[{\"from\":\"rows\",\"to_vectors\":{" +
        "\"id\":\"id\",\"vector\":\"embedding\"}}]",
      ),
      [("rows", direct_nearest_relation_carrier(text_identity~))],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn direct_nearest_owner(
  candidates : @lower.BoundPrepared,
  queries : @lower.BoundPrepared,
  candidate_relation? : Bool = false,
  query_relation? : Bool = false,
) -> @lower.BoundPrepared {
  let candidate_roles = if candidate_relation {
    ",\"candidate_id\":\"id\",\"candidate_vector\":\"embedding\""
  } else {
    ""
  }
  let query_roles = if query_relation {
    ",\"query_id\":\"id\",\"query_vector\":\"embedding\""
  } else {
    ""
  }
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"from\":\"candidates\",\"nearest\":{" +
        "\"queries\":\"queries\",\"metric\":\"dot\",\"k\":2" +
        candidate_roles +
        query_roles +
        "}}]",
      ),
      [
        (
          "candidates",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(candidates)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "queries",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(queries)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(input_cursor("\"candidates\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn reordered_nearest_owner(
  candidates : @lower.BoundPrepared,
  queries : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"from\":\"candidates\",\"nearest\":{\"queries\":\"queries\"," +
        "\"metric\":\"dot\",\"k\":2}}]",
      ),
      [
        (
          "queries",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(queries)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "candidates",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(candidates)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(input_cursor("\"candidates\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn mixed_step_nearest_owner(
  candidate_rows : @lower.BoundPrepared,
  queries : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"from\":\"candidate_rows\",\"to_vectors\":{\"id\":\"id\"," +
        "\"vector\":\"embedding\"},\"as\":\"candidate_vectors\"}," +
        "{\"from\":\"candidate_vectors\",\"nearest\":{\"queries\":\"queries\"," +
        "\"metric\":\"dot\",\"k\":2}}]",
      ),
      [
        (
          "queries",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(queries)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "candidate_rows",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(candidate_rows)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(input_cursor("\"candidate_rows\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn run_selected_nearest_provider(
  owner : @lower.BoundPrepared,
  step : Int,
  inputs : Array[@local_connector.ManagedProviderInput],
  expected : Array[(Double, Double)],
) -> Unit raise {
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(owner),
    step,
  ).unwrap()
  let limits = dispatch_test_limits()
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let execution = @local_connector.start_managed_provider_with_inputs(
    provider, generated, inputs, 10, 1000,
  ).unwrap()
  let mut output = None
  while output is None {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(value, ..) => output = Some(value)
      @local_connector.CarrierComplete(_, ..) =>
        fail("nearest returned a Carrier")
      @local_connector.Failed(_, ..) => fail("selected nearest provider failed")
      @local_connector.Waiting(..) =>
        fail("synchronous provider unexpectedly waited")
      @local_connector.Settling(_, ..) =>
        fail("synchronous provider unexpectedly requested settlement")
      @local_connector.Stopped(..) => fail("selected nearest provider stopped")
    }
  }
  let result = output.unwrap()
  assert_eq(@execution.completed_row_count(result), expected.length())
  for index, pair in expected {
    assert_true(
      @execution.completed_cell(result, index, 0) is Some(Number(value)) &&
      value == pair.0,
    )
    assert_true(
      @execution.completed_cell(result, index, 1) is Some(Number(value)) &&
      value == pair.1,
    )
  }
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
}

///|
fn direct_nearest_relation_owner(rows : String) -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check(
      input_cursor(
        "[{\"values\":{\"schema\":{" +
        "\"id\":{\"type\":\"number\",\"nullable\":false}," +
        "\"embedding\":{\"type\":\"vector\",\"dimensions\":2," +
        "\"nullable\":false}},\"rows\":" +
        rows +
        "},\"as\":\"rows\"}]",
      ),
      [],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn direct_nearest_relation_output(
  owner : @lower.BoundPrepared,
) -> @execution.CompletedOutput raise {
  let completed = @execution.execute_generated_sequence(
    task_test_generated(owner),
    [],
    compute_test_limits(),
  ).unwrap()
  @execution.completed_output(completed, @pipeline.Step(0)).unwrap()
}

///|
fn direct_rows_to_vectors_owner(
  source : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"from\":\"rows\",\"to_vectors\":{" +
        "\"id\":\"id\",\"vector\":\"embedding\"}}]",
      ),
      [
        (
          "rows",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(source)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(input_cursor("\"rows\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn direct_vectors_projection_owner(
  source : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"from\":\"rows\",\"to_vectors\":{\"id\":\"id\"," +
        "\"vector\":\"embedding\"}},{\"vectors\":true}]",
      ),
      [
        (
          "rows",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(source)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(input_cursor("\"rows\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
test "rows to Vectors admits exact work and workspace and reclaims partial output" {
  let source_owner = direct_nearest_relation_owner(
    "[{\"id\":1,\"embedding\":[1,2]}," + "{\"id\":2,\"embedding\":[3,4]}]",
  )
  let source = direct_nearest_relation_output(source_owner)
  let owner = direct_rows_to_vectors_owner(source_owner)
  let input = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  // Each row costs two identity nodes, nine record nodes, and three copy
  // units. Four slots per retained record overlap two scratch fields and
  // four new slots during the second append.
  for
    (work, slots, outcome) in [
      (28, 10, "complete"),
      (27, 10, "work"),
      (28, 9, "workspace"),
    ] {
    let execution = @local_bridge.start_rows_to_vectors(
      @bounded.control(),
      prepared_sequence(owner),
      0,
      input,
      {
        ..carrier_vectors_storage_limits(),
        max_work: work,
        max_workspace_slots: slots,
      },
      4096L,
      fn() { true },
    ).unwrap()
    let mut terminal = false
    let mut polls = 0
    while !terminal {
      polls += 1
      assert_true(polls < 40)
      match @local_bridge.advance_rows_to_vectors(execution, 1).unwrap() {
        @local_bridge.Continue(..) => ()
        @local_bridge.Complete(output, ..) => {
          assert_eq(outcome, "complete")
          assert_true(
            @records.completed_storage(output) is Some(storage) &&
            @record_storage.construction_work(storage) == 28 &&
            @record_storage.retained_workspace_slots(storage) == 8,
          )
          assert_true(@records.discard_completed(output))
          terminal = true
        }
        @local_bridge.Failed(
          @local_bridge.Output(@records.Storage(@record_storage.WorkLimit)),
          ..
        ) => {
          assert_eq(outcome, "work")
          terminal = true
        }
        @local_bridge.Failed(
          @local_bridge.Output(@records.Storage(@record_storage.WorkspaceLimit)),
          ..
        ) => {
          assert_eq(outcome, "workspace")
          terminal = true
        }
        _ => abort("unexpected rows-to-Vectors result")
      }
    }
    assert_eq(@local_bridge.cleanup_rows_to_vectors(execution), Ok(true))
    assert_eq(@local_bridge.cleanup_rows_to_vectors(execution), Ok(false))
    assert_true(@execution.completed_output_available(source))
  }

  let control = @bounded.control()
  let cancelled = @local_bridge.start_rows_to_vectors(
    control,
    prepared_sequence(owner),
    0,
    input,
    carrier_vectors_storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let mut first_row = false
  let mut polls = 0
  while !first_row {
    polls += 1
    assert_true(polls < 20)
    match @local_bridge.advance_rows_to_vectors(cancelled, 1).unwrap() {
      @local_bridge.Continue(progress~, ..) => first_row = progress > 0L
      _ => abort("rows-to-Vectors did not yield after its first row")
    }
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_bridge.advance_rows_to_vectors(cancelled, 1).unwrap()
    is @local_bridge.Stopped(_, ..),
  )
  assert_eq(@local_bridge.cleanup_rows_to_vectors(cancelled), Ok(true))
  assert_true(@execution.completed_output_available(source))
}

///|
test "Vectors projection production entrypoint enforces value and width limits" {
  let source_owner = direct_nearest_relation_owner(
    "[{\"id\":1,\"embedding\":[1,2]},{\"id\":2,\"embedding\":[3,4]}]",
  )
  let source = direct_nearest_relation_output(source_owner)
  let owner = direct_vectors_projection_owner(source_owner)
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let encoding = @local_bridge.start_rows_to_vectors(
    @bounded.control(),
    sequence,
    0,
    external,
    carrier_vectors_storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let mut vectors = None
  for _ in 0..<40 {
    if vectors is Some(_) {
      break
    }
    match @local_bridge.advance_rows_to_vectors(encoding, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Complete(output, ..) => vectors = Some(output)
      _ => abort("rows-to-Vectors setup failed")
    }
  }
  let vectors = vectors.unwrap()
  assert_eq(@local_bridge.cleanup_rows_to_vectors(encoding), Ok(true))
  let projection_input = @records.prepare_step_read(owner, 1, 0, vectors).unwrap()
  let exact = @local_bridge.start_vectors_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    projection_input,
    2,
    { max_nodes: 10, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    2,
    1000,
    [external],
    control_work_limit=Some(10),
  ).unwrap()
  let mut exact_done = false
  for _ in 0..<20 {
    if exact_done {
      break
    }
    match @local_bridge.advance_vectors_to_rows(exact, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Complete(output, work~, ..) => {
        assert_eq(work, 10L)
        assert_eq(@execution.completed_row_count(output), 2)
        assert_true(
          @execution.completed_output_matches_inputs(output, [external]),
        )
        exact_done = true
      }
      _ => abort("exact Vectors projection failed")
    }
  }
  assert_true(exact_done)
  assert_eq(@local_bridge.cleanup_vectors_to_rows(exact), Ok(true))
  let one_short_work = @local_bridge.start_vectors_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    projection_input,
    2,
    { max_nodes: 10, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    2,
    1000,
    [external],
    control_work_limit=Some(9),
  ).unwrap()
  let mut work_failed = false
  for _ in 0..<20 {
    if work_failed {
      break
    }
    match @local_bridge.advance_vectors_to_rows(one_short_work, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Failed(@local_bridge.ControlWorkLimit, work~, ..) => {
        assert_eq(work, 9L)
        work_failed = true
      }
      _ => abort("one-short Vectors projection did not reject work")
    }
  }
  assert_true(work_failed)
  assert_eq(@local_bridge.cleanup_vectors_to_rows(one_short_work), Ok(true))
  let one_short_width = @local_bridge.start_vectors_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    projection_input,
    2,
    { max_nodes: 10, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    1,
    1000,
    [external],
  )
  assert_true(
    one_short_width is Err(@local_bridge.Completion(@execution.Limit)),
  )
  let one_short_value = @local_bridge.start_vectors_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    projection_input,
    2,
    { max_nodes: 9, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    2,
    1000,
    [external],
  ).unwrap()
  let mut value_failed = false
  for _ in 0..<20 {
    if value_failed {
      break
    }
    match @local_bridge.advance_vectors_to_rows(one_short_value, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Failed(
        @local_bridge.RelationOutput(@execution.CaptureLimit),
        ..
      ) => value_failed = true
      _ => abort("one-short Vectors projection did not reject output")
    }
  }
  assert_true(value_failed)
  assert_eq(@local_bridge.cleanup_vectors_to_rows(one_short_value), Ok(true))
  let control = @bounded.control()
  let cancelled = @local_bridge.start_vectors_to_rows(
    control,
    task_test_completion(owner),
    sequence,
    1,
    projection_input,
    2,
    { max_nodes: 10, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    2,
    1000,
    [external],
  ).unwrap()
  assert_true(
    @local_bridge.advance_vectors_to_rows(cancelled, 1).unwrap()
    is @local_bridge.Continue(..),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_bridge.advance_vectors_to_rows(cancelled, 1).unwrap()
    is @local_bridge.Stopped(_, ..),
  )
  assert_eq(@local_bridge.cleanup_vectors_to_rows(cancelled), Ok(true))
  assert_true(@records.completed_available(vectors))
  assert_true(@records.discard_completed(vectors))
  assert_true(@execution.completed_output_available(source))
}

///|
fn direct_vector_expression_source_owner() -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check(
      input_cursor(
        "[{\"values\":{\"schema\":{" +
        "\"id\":{\"type\":\"number\",\"nullable\":false}," +
        "\"left\":{\"type\":\"vector\",\"dimensions\":2," +
        "\"nullable\":false},\"right\":{\"type\":\"vector\"," +
        "\"dimensions\":2,\"nullable\":false}},\"rows\":[" +
        "{\"id\":1,\"left\":[1,2],\"right\":[3,4]}," +
        "{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]}," +
        "\"as\":\"rows\"}]",
      ),
      [],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn direct_vector_expression_owner(
  source : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"derive\":{\"score\":{\"vector_score\":{" +
      "\"left\":{\"field\":\"left\"},\"right\":{" +
      "\"field\":\"right\"},\"metric\":\"dot\"}}," +
      "\"joined\":{\"vector_concat\":[{\"field\":\"right\"}," +
      "{\"field\":\"left\"}]}}}]",
    ),
    [
      (
        "rows",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(source)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(input_cursor("\"rows\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
    expression_profiles={ text_time: false, veca: true, },
  ).unwrap()
}

///|
fn direct_vector_expression_read(
  owner : @lower.BoundPrepared,
  source : @lower.BoundPrepared,
  output : @execution.CompletedOutput,
) -> @execution.ProducerRead {
  @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source, output).unwrap(),
    1000,
    10000,
  ).unwrap()
}

///|
test "registered VecA provider bounds row expressions and cancellation" {
  let source = direct_vector_expression_source_owner()
  let owner = direct_vector_expression_owner(source)
  let output = direct_nearest_relation_output(source)
  let generated = task_test_generated(owner)
  let limits = dispatch_test_limits()
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let compatibility = @local_connector.start_managed_provider(
    provider,
    generated,
    [direct_vector_expression_read(owner, source, output)],
    10,
    1000,
  ).unwrap()
  assert_true(
    @local_connector.advance_managed_provider(compatibility, 1).unwrap()
    is @local_connector.Failed(_),
  )
  assert_true(
    @local_connector.cleanup_managed_provider(compatibility).unwrap_or(false),
  )
  let execution = @local_connector.start_managed_provider_with_execution(
    provider,
    generated,
    [direct_vector_expression_read(owner, source, output)],
    10,
    1000,
    limits.local_execution,
  ).unwrap()
  let mut completed = None
  let mut advances = 0
  while completed is None {
    advances += 1
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(value, ..) => completed = Some(value)
      @local_connector.CarrierComplete(_, ..) =>
        fail("vector expression returned a Carrier")
      @local_connector.Failed(_, ..) => fail("vector expression failed")
      @local_connector.Waiting(..) =>
        fail("synchronous provider unexpectedly waited")
      @local_connector.Settling(_, ..) =>
        fail("synchronous provider unexpectedly requested settlement")
      @local_connector.Stopped(..) => fail("vector expression stopped")
    }
  }
  assert_true(advances > 1)
  let result = completed.unwrap()
  let schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    @pipeline.Step(0),
  ).unwrap()
  let columns : Map[String, Int] = Map([])
  for column in 0..<@schema.field_count(schema) {
    columns.set(
      @schema.reference_name(@schema.field_at(schema, column).unwrap().name),
      column,
    )
  }
  assert_eq(@execution.completed_row_count(result), 2)
  assert_true(
    @execution.completed_cell(result, 0, columns.get("score").unwrap())
    is Some(Number(11.0)),
  )
  assert_true(
    @execution.completed_cell(result, 0, columns.get("joined").unwrap())
    is Some(Captured(@admitted.Vector(joined))) &&
    @admitted.element_count(joined) == 4,
  )
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )

  let cancelled = @local_connector.start_managed_provider_with_execution(
    provider,
    generated,
    [direct_vector_expression_read(owner, source, output)],
    10,
    1000,
    limits.local_execution,
  ).unwrap()
  assert_true(
    @local_connector.advance_managed_provider(cancelled, 1).unwrap()
    is @local_connector.Continue(_),
  )
  assert_true(@local_connector.cancel_managed_provider(cancelled))
  assert_true(
    @local_connector.advance_managed_provider(cancelled, 1).unwrap()
    is @local_connector.Stopped(_),
  )
  assert_true(@local_connector.managed_provider_stopped(cancelled))
  assert_true(
    @local_connector.cleanup_managed_provider(cancelled).unwrap_or(false),
  )
  assert_true(@execution.completed_output_available(output))
}

///|
fn direct_ranking_carrier() -> @carrier_contract.Carrier {
  let number = @value_contract.primitive(
    @value_contract.NumberType,
    nullable=false,
  )
  @carrier_contract.relation(
    @carrier_contract.rows(
      [
        (@schema.Unqualified("q"), Some(number)),
        (@schema.Unqualified("id"), Some(number)),
        (@schema.Unqualified("score"), Some(number)),
      ],
      field_set=@carrier_contract.Closed,
      max_fields=3,
      max_name_bytes=8,
    ).unwrap(),
  )
}

///|
fn direct_ranking_owner() -> @lower.BoundPrepared {
  let contract = "{\"domain\":\"unit.v1\",\"range\":[0,1]," +
    "\"normalization\":\"unit.v1\"}"
  let ranking = @vector.declare_ranking_score(
    input_cursor(contract),
    direct_ranking_carrier(),
    @schema.Unqualified("score"),
    { max_work: 1000, max_nodes: 1000, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor("[{\"select\":[\"q\",\"id\",\"score\"]}]"),
      [("rows", @pipeline.RankingInput(ranking))],
      None,
      Some(input_cursor("\"rows\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn direct_ranking_fusion_owner(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
  policy : String,
) -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"merge_rankings\":{\"with\":\"right\"," +
        "\"by\":[\"q\"],\"candidate\":\"id\"," +
        "\"score\":\"score\",\"k\":2,\"score_policy\":" +
        policy +
        ",\"score_contract\":{\"domain\":\"unit.v1\"," +
        "\"range\":[0,1],\"normalization\":\"unit.v1\"}}}]",
      ),
      [
        (
          "left",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(left)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "right",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(right)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(input_cursor("\"left\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn supplied_ranking_fusion_owner(policy : String) -> @lower.BoundPrepared {
  let contract = "{\"domain\":\"unit.v1\",\"range\":[0,1]," +
    "\"normalization\":\"unit.v1\"}"
  let ranking = @vector.declare_ranking_score(
    input_cursor(contract),
    direct_ranking_carrier(),
    @schema.Unqualified("score"),
    { max_work: 1000, max_nodes: 1000, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"merge_rankings\":{\"with\":\"right\"," +
        "\"by\":[\"q\"],\"candidate\":\"id\"," +
        "\"score\":\"score\",\"k\":2,\"score_policy\":" +
        policy +
        ",\"score_contract\":{\"domain\":\"unit.v1\"," +
        "\"range\":[0,1],\"normalization\":\"unit.v1\"}}}]",
      ),
      [
        ("left", @pipeline.RankingInput(ranking)),
        ("right", @pipeline.RankingInput(ranking)),
      ],
      None,
      Some(input_cursor("\"left\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn mixed_ranking_fusion_owner(
  left : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let contract = "{\"domain\":\"unit.v1\",\"range\":[0,1]," +
    "\"normalization\":\"unit.v1\"}"
  let ranking = @vector.declare_ranking_score(
    input_cursor(contract),
    direct_ranking_carrier(),
    @schema.Unqualified("score"),
    { max_work: 1000, max_nodes: 1000, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"merge_rankings\":{\"with\":\"right\"," +
        "\"by\":[\"q\"],\"candidate\":\"id\"," +
        "\"score\":\"score\",\"k\":2,\"score_policy\":\"max\"," +
        "\"score_contract\":" +
        contract +
        "}}]",
      ),
      [
        (
          "left",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(left)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        ("right", @pipeline.RankingInput(ranking)),
      ],
      None,
      Some(input_cursor("\"left\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn supplied_ranking_rows(
  owner : @lower.BoundPrepared,
  input : Int,
  rows : Array[(Double, Double, Double)],
) -> @execution.SuppliedRelationRead {
  let captured = @execution.capture_input(
    owner,
    input,
    rows.map(row => {
      input_cursor(
        "{\"q\":" +
        row.0.to_string() +
        ",\"id\":" +
        row.1.to_string() +
        ",\"score\":" +
        row.2.to_string() +
        "}",
      )
    }),
    max_rows=100,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
  ).unwrap()
  @execution.prepare_supplied_relation_read(owner, input, captured, fn() {
    true
  }).unwrap()
}

///|
fn direct_ranking_number(
  owner : @lower.BoundPrepared,
  column : Int,
  value : Double,
) -> @admitted.CheckedValue {
  let schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    @pipeline.Step(0),
  ).unwrap()
  let contract = @schema.field_at(schema, column).unwrap().contract
  @admitted.admit(contract, input_cursor(value.to_string()), {
    max_nodes: 1,
    max_depth: 1,
    max_text_bytes: 0,
  }).unwrap()
}

///|
fn direct_ranking_output(
  owner : @lower.BoundPrepared,
  rows : Array[(Double, Double, Double)],
) -> @execution.CompletedOutput raise {
  let values = @execution.prepare_admitted_output(
    owner,
    @pipeline.Step(0),
    100,
    { max_nodes: 10000, max_text_bytes: 10000, max_depth: 10, max_work: 10000, },
  ).unwrap()
  let schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    @pipeline.Step(0),
  ).unwrap()
  for row in rows {
    let cells = Array::makei(@schema.field_count(schema), column => {
      let name = @schema.reference_name(
        @schema.field_at(schema, column).unwrap().name,
      )
      let value = if name == "q" {
        row.0
      } else if name == "id" {
        row.1
      } else {
        row.2
      }
      direct_ranking_number(owner, column, value)
    })
    @execution.append_admitted_output(values, cells).unwrap()
  }
  let rows = @execution.finish_admitted_output(values).unwrap()
  let completion = @execution.prepare_trusted_output_port(
    task_test_completion(owner),
    @pipeline.Step(0),
    1000,
    10000,
    (proof : @execution.AdmittedOutputRows) => {
      if physical_equal(proof, rows) {
        Some(rows)
      } else {
        None
      }
    },
  ).unwrap()
  @execution.complete_trusted_output(completion, rows).unwrap()
}

///|
fn direct_nullable_ranking_carrier() -> @carrier_contract.Carrier {
  let number = @value_contract.primitive(
    @value_contract.NumberType,
    nullable=false,
  )
  let nullable_number = @value_contract.primitive(
    @value_contract.NumberType,
    nullable=true,
  )
  let nullable_text = @value_contract.primitive(
    @value_contract.StringType,
    nullable=true,
  )
  @carrier_contract.relation(
    @carrier_contract.rows(
      [
        (@schema.Unqualified("q"), Some(nullable_number)),
        (@schema.Unqualified("segment"), Some(nullable_text)),
        (@schema.Unqualified("id"), Some(number)),
        (@schema.Unqualified("score"), Some(number)),
        (@schema.Unqualified("priority"), Some(nullable_text)),
      ],
      field_set=@carrier_contract.Closed,
      max_fields=5,
      max_name_bytes=23,
    ).unwrap(),
  )
}

///|
fn direct_nullable_ranking_owner() -> @lower.BoundPrepared {
  let contract = "{\"domain\":\"unit.v1\",\"range\":[0,1]," +
    "\"normalization\":\"unit.v1\"}"
  let ranking = @vector.declare_ranking_score(
    input_cursor(contract),
    direct_nullable_ranking_carrier(),
    @schema.Unqualified("score"),
    { max_work: 1000, max_nodes: 1000, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"select\":[\"q\",\"segment\",\"id\",\"score\"," + "\"priority\"]}]",
      ),
      [("rows", @pipeline.RankingInput(ranking))],
      None,
      Some(input_cursor("\"rows\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn direct_nullable_ranking_fusion_owner(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
  policy : String,
) -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"merge_rankings\":{\"with\":\"right\"," +
        "\"by\":[\"q\",\"segment\"],\"candidate\":\"id\"," +
        "\"score\":\"score\",\"tie_break\":[\"priority\"]," +
        "\"k\":3,\"score_policy\":" +
        policy +
        ",\"score_contract\":{\"domain\":\"unit.v1\"," +
        "\"range\":[0,1],\"normalization\":\"unit.v1\"}}}]",
      ),
      [
        (
          "left",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(left)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "right",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(right)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(input_cursor("\"left\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn direct_nullable_ranking_output(
  owner : @lower.BoundPrepared,
  rows : Array[(Double?, String?, Double, Double, String?)],
  text_limit? : Int = 10,
) -> @execution.CompletedOutput raise {
  let values = @execution.prepare_admitted_output(
    owner,
    @pipeline.Step(0),
    100,
    { max_nodes: 10000, max_text_bytes: 10000, max_depth: 10, max_work: 10000, },
  ).unwrap()
  let schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    @pipeline.Step(0),
  ).unwrap()
  for row in rows {
    let cells = Array::makei(@schema.field_count(schema), column => {
      let field = @schema.field_at(schema, column).unwrap()
      let name = @schema.reference_name(field.name)
      if name == "segment" || name == "priority" {
        let item = if name == "segment" { row.1 } else { row.4 }
        @admitted.admit(
          field.contract,
          input_cursor(
            match item {
              Some(value) => "\"" + value + "\""
              None => "null"
            },
          ),
          { max_nodes: 1, max_depth: 1, max_text_bytes: text_limit, },
        ).unwrap()
      } else if name == "q" {
        @admitted.admit(
          field.contract,
          input_cursor(
            match row.0 {
              Some(value) => value.to_string()
              None => "null"
            },
          ),
          { max_nodes: 1, max_depth: 1, max_text_bytes: 0, },
        ).unwrap()
      } else {
        direct_ranking_number(
          owner,
          column,
          if name == "id" {
            row.2
          } else {
            row.3
          },
        )
      }
    })
    @execution.append_admitted_output(values, cells).unwrap()
  }
  let rows = @execution.finish_admitted_output(values).unwrap()
  let completion = @execution.prepare_trusted_output_port(
    task_test_completion(owner),
    @pipeline.Step(0),
    1000,
    10000,
    (proof : @execution.AdmittedOutputRows) => {
      if physical_equal(proof, rows) {
        Some(rows)
      } else {
        None
      }
    },
  ).unwrap()
  @execution.complete_trusted_output(completion, rows).unwrap()
}

///|
fn run_direct_ranking_provider(
  policy : String,
  expected : Array[(Double, Double, Double, Double)],
) -> Unit raise {
  let left = direct_ranking_owner()
  let right = direct_ranking_owner()
  let owner = direct_ranking_fusion_owner(left, right, policy)
  let left_output = direct_ranking_output(left, [
    (1.0, 1.0, 0.75),
    (1.0, 2.0, 0.5),
    (2.0, 1.0, 0.25),
  ])
  let right_output = direct_ranking_output(right, [
    (1.0, 1.0, 0.5),
    (1.0, 3.0, 0.5),
    (2.0, 1.0, 0.75),
  ])
  let inputs = [
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, left, left_output).unwrap(),
      1000,
      10000,
    ).unwrap(),
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 1, right, right_output).unwrap(),
      1000,
      10000,
    ).unwrap(),
  ]
  let generated = task_test_generated(owner)
  let limits = dispatch_test_limits()
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let execution = @local_connector.start_managed_provider(
    provider, generated, inputs, 10, 1000,
  ).unwrap()
  let mut output = None
  while output is None {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(value, ..) => output = Some(value)
      @local_connector.CarrierComplete(_, ..) =>
        fail("ranking fusion returned a Carrier")
      @local_connector.Failed(_, ..) => fail("ranking provider failed")
      @local_connector.Waiting(..) =>
        fail("synchronous provider unexpectedly waited")
      @local_connector.Settling(_, ..) =>
        fail("synchronous provider unexpectedly requested settlement")
      @local_connector.Stopped(..) => fail("ranking provider stopped")
    }
  }
  let result = output.unwrap()
  let output_schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    @pipeline.Step(0),
  ).unwrap()
  let columns = Array::make(4, -1)
  for column in 0..<@schema.field_count(output_schema) {
    let name = @schema.reference_name(
      @schema.field_at(output_schema, column).unwrap().name,
    )
    let index = if name == "q" {
      0
    } else if name == "id" {
      1
    } else if name == "rank" {
      2
    } else {
      3
    }
    columns[index] = column
  }
  assert_eq(@execution.completed_row_count(result), expected.length())
  for row, values in expected {
    for index, value in [values.0, values.1, values.2, values.3] {
      assert_true(
        @execution.completed_cell(result, row, columns[index])
        is Some(Number(actual)) &&
        actual == value,
      )
    }
  }
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
}

///|
test "ranking detects an in-flight input loss before completion" {
  let left = direct_ranking_owner()
  let right = direct_ranking_owner()
  let owner = direct_ranking_fusion_owner(left, right, "\"max\"")
  let left_output = direct_ranking_output(left, [(1.0, 1.0, 0.75)])
  let right_output = direct_ranking_output(right, [(1.0, 2.0, 0.5)])
  let right_live = Ref(true)
  let restricted = @execution.restrict_completed_output(right_output, fn() {
    right_live.val
  })
  let inputs = [
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, left, left_output).unwrap(),
      1000,
      10000,
    ).unwrap(),
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 1, right, restricted).unwrap(),
      1000,
      10000,
    ).unwrap(),
  ]
  let generated = task_test_generated(owner)
  let limits = dispatch_test_limits()
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let execution = @local_connector.start_managed_provider(
    provider, generated, inputs, 10, 1000,
  ).unwrap()
  assert_true(
    @local_connector.advance_managed_provider(execution, 1).unwrap()
    is @local_connector.Continue(work=1L, ..),
  )
  right_live.val = false
  let mut failed = false
  for _ in 0..<4 {
    if !failed {
      match @local_connector.advance_managed_provider(execution, 1).unwrap() {
        @local_connector.Continue(work~, ..) => assert_true(work > 0L)
        @local_connector.Failed(_, ..) => failed = true
        @local_connector.Complete(_, ..) =>
          fail("ranking published after an input was lost")
        @local_connector.CarrierComplete(_, ..) =>
          fail("ranking returned a Carrier")
        @local_connector.Waiting(..) =>
          fail("synchronous provider unexpectedly waited")
        @local_connector.Settling(_, ..) =>
          fail("synchronous provider unexpectedly requested settlement")
        @local_connector.Stopped(..) => fail("ranking stopped without failure")
      }
    }
  }
  assert_true(failed)
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
}

///|
fn run_direct_nullable_ranking_provider(
  policy : String,
  expected_scores : Array[Double],
) -> Unit raise {
  let left = direct_nullable_ranking_owner()
  let right = direct_nullable_ranking_owner()
  let owner = direct_nullable_ranking_fusion_owner(left, right, policy)
  let left_output = direct_nullable_ranking_output(left, [
    (None, None, 1.0, 0.8, Some("x")),
    (None, None, 2.0, 0.6, None),
    (None, None, 3.0, 0.6, Some("a")),
    (None, Some("a"), 4.0, 0.9, Some("b")),
    (Some(1.0), None, 5.0, 0.9, Some("b")),
  ])
  let right_output = direct_nullable_ranking_output(right, [
    (None, None, 1.0, 0.6, Some("x")),
    (None, None, 2.0, 0.4, None),
    (None, None, 3.0, 0.4, Some("a")),
    (None, Some("a"), 4.0, 0.7, Some("b")),
    (Some(1.0), None, 5.0, 0.7, Some("b")),
  ])
  let inputs = [
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, left, left_output).unwrap(),
      1000,
      10000,
    ).unwrap(),
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 1, right, right_output).unwrap(),
      1000,
      10000,
    ).unwrap(),
  ]
  let generated = task_test_generated(owner)
  let limits = dispatch_test_limits()
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let execution = @local_connector.start_managed_provider(
    provider, generated, inputs, 10, 1000,
  ).unwrap()
  let mut output = None
  while output is None {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(value, ..) => output = Some(value)
      @local_connector.CarrierComplete(_, ..) =>
        fail("nullable ranking returned a Carrier")
      @local_connector.Failed(_, ..) => fail("nullable ranking failed")
      @local_connector.Waiting(..) =>
        fail("synchronous provider unexpectedly waited")
      @local_connector.Settling(_, ..) =>
        fail("synchronous provider unexpectedly requested settlement")
      @local_connector.Stopped(..) => fail("nullable ranking stopped")
    }
  }
  let result = output.unwrap()
  let schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    @pipeline.Step(0),
  ).unwrap()
  let columns : Map[String, Int] = Map([])
  for column in 0..<@schema.field_count(schema) {
    columns.set(
      @schema.reference_name(@schema.field_at(schema, column).unwrap().name),
      column,
    )
  }
  assert_eq(@execution.completed_row_count(result), 5)
  for row, candidate in [1.0, 3.0, 2.0, 4.0, 5.0] {
    assert_true(
      @execution.completed_cell(result, row, columns.get("id").unwrap())
      is Some(Number(actual)) &&
      actual == candidate,
    )
    assert_true(
      @execution.completed_cell(result, row, columns.get("score").unwrap())
      is Some(Number(actual)) &&
      actual == expected_scores[row],
    )
  }
  for row in 0..<3 {
    assert_true(
      @execution.completed_cell(result, row, columns.get("q").unwrap())
      is Some(Null),
    )
    assert_true(
      @execution.completed_cell(result, row, columns.get("segment").unwrap())
      is Some(Null),
    )
  }
  assert_true(
    @execution.completed_cell(result, 3, columns.get("q").unwrap())
    is Some(Null),
  )
  assert_true(
    @execution.completed_cell(result, 3, columns.get("segment").unwrap())
    is Some(Text("a")),
  )
  assert_true(
    @execution.completed_cell(result, 4, columns.get("q").unwrap())
    is Some(Number(1.0)),
  )
  assert_true(
    @execution.completed_cell(result, 4, columns.get("segment").unwrap())
    is Some(Null),
  )
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
}

///|
test "registered VecA provider authenticates maximum ranking scores" {
  run_direct_ranking_provider("\"max\"", [
    (1.0, 1.0, 1.0, 0.75),
    (1.0, 2.0, 2.0, 0.5),
    (2.0, 1.0, 1.0, 0.75),
  ])
}

///|
test "registered VecA provider authenticates weighted ranking scores" {
  run_direct_ranking_provider(
    "{\"weighted_sum\":{\"left\":0.5,\"right\":0.5}}",
    [(1.0, 1.0, 1.0, 0.625), (1.0, 2.0, 2.0, 0.25), (2.0, 1.0, 1.0, 0.5)],
  )
}

///|
test "registered VecA provider orders nullable business ties" {
  run_direct_nullable_ranking_provider("\"max\"", [0.8, 0.6, 0.6, 0.9, 0.9])
  run_direct_nullable_ranking_provider(
    "{\"weighted_sum\":{\"left\":0.5,\"right\":0.5}}",
    [0.7, 0.5, 0.5, 0.8, 0.8],
  )
}

///|
test "registered VecA provider preserves supplied score authority" {
  for policy in ["\"max\"", "{\"weighted_sum\":{\"left\":0.5,\"right\":0.5}}"] {
    let owner = supplied_ranking_fusion_owner(policy)
    let inputs = [
      supplied_ranking_rows(owner, 0, [(1.0, 1.0, 0.75), (1.0, 2.0, 0.5)]),
      supplied_ranking_rows(owner, 1, [(1.0, 1.0, 0.5), (1.0, 3.0, 0.5)]),
    ]
    let generated = task_test_generated(owner)
    let limits = dispatch_test_limits()
    let provider = @local_veca_provider.provider(
      carrier_vectors_storage_limits(),
      4096L,
      @execution.generated_sequence_capacity(
        generated,
        limits.local_execution,
        limits.guards,
      ).unwrap(),
    )
    let execution = @local_connector.start_managed_provider_with_inputs(
      provider,
      generated,
      inputs.map(@local_connector.managed_provider_supplied_relation_input),
      10,
      1000,
    ).unwrap()
    let mut output = None
    while output is None {
      match @local_connector.advance_managed_provider(execution, 1).unwrap() {
        @local_connector.Continue(work~, ..) => assert_true(work > 0L)
        @local_connector.Complete(value, ..) => output = Some(value)
        @local_connector.CarrierComplete(_, ..) => fail("ranking Carrier")
        @local_connector.Failed(_, ..) => fail("ranking failed")
        @local_connector.Waiting(..) =>
          fail("synchronous provider unexpectedly waited")
        @local_connector.Settling(_, ..) =>
          fail("synchronous provider unexpectedly requested settlement")
        @local_connector.Stopped(..) => fail("ranking stopped")
      }
    }
    let result = output.unwrap()
    assert_eq(@execution.completed_row_count(result), 2)
    let fixed_inputs = inputs.map(@execution.fixed_supplied_relation_read)
    let capacity : @connector.FixedComputeCapacity = {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 10,
      max_value_bytes: 1000,
      common_fragment: None,
    }
    let request = @connector.prepare_selected_fixed_compute_request_with_inputs(
      owner, 0, fixed_inputs, capacity,
    ).unwrap()
    assert_eq(@connector.fixed_compute_request_input_count(request), 2)
    assert_true(@connector.fixed_compute_request_has_supplied_input(request))
    let request_inputs = @connector.fixed_compute_request_inputs(request)
    assert_eq(request_inputs.length(), 2)
    for index in 0..<2 {
      assert_true(
        @execution.fixed_relation_read_same(
          request_inputs[index],
          fixed_inputs[index],
        ),
      )
    }
    let registry = search_registry()
    let candidate = @local_connector.local_fixed_compute_candidate(
      @connector.capability_registration_at(registry, 0).unwrap(),
      request,
      generated,
      [],
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
      100,
    ).unwrap()
    guard @connector.choose_fixed_compute_candidate(
        registry,
        request,
        [@connector.prepared_compute_candidate(candidate)],
        Some([0]),
        100,
      ).unwrap()
      is Proposed(choice) else {
      fail("supplied ranking candidate")
    }
    assert_true(
      @local_connector.execute_local_fixed_compute(
        choice,
        candidate,
        compute_test_limits(),
        measurement={
          max_work: 10000,
          max_bytes: 10000,
          max_nodes: 10000,
          max_depth: 100,
        },
      )
      is Err(@connector.UnsupportedInputShape),
    )
    assert_true(
      @connector.prepare_selected_fixed_compute_request_with_inputs(
        owner,
        0,
        [fixed_inputs[1], fixed_inputs[0]],
        capacity,
      )
      is Err(@connector.UnsupportedInputShape),
    )
    assert_true(
      @connector.prepare_selected_fixed_compute_request_with_inputs(
        owner,
        0,
        fixed_inputs,
        { ..capacity, max_rows: 1, },
      )
      is Err(@connector.CommonInputRows),
    )
    let anchored = @execution.anchor_completed_output_fixed_inputs(
      result,
      Some(0),
      fixed_inputs,
    ).unwrap()
    assert_true(
      @execution.completed_output_matches_fixed_inputs(
        anchored,
        Some(0),
        fixed_inputs,
      ),
    )
    assert_false(
      @execution.completed_output_matches_fixed_inputs(anchored, Some(0), [
        fixed_inputs[1],
        fixed_inputs[0],
      ]),
    )
    let rebound = @execution.fixed_supplied_relation_read(
      supplied_ranking_rows(owner, 0, [(1.0, 1.0, 0.75)]),
    )
    assert_false(
      @execution.completed_output_matches_fixed_inputs(anchored, Some(0), [
        rebound,
        fixed_inputs[1],
      ]),
    )
    let output_schema = @pipeline.schema_at(
      @lower.pipeline(@lower.bound_preparation(owner)),
      @pipeline.Step(0),
    ).unwrap()
    let columns : Map[String, Int] = Map([], capacity=4)
    for column in 0..<@schema.field_count(output_schema) {
      columns.set(
        @schema.reference_name(
          @schema.field_at(output_schema, column).unwrap().name,
        ),
        column,
      )
    }
    let scores = if policy == "\"max\"" { [0.75, 0.5] } else { [0.625, 0.25] }
    for row in 0..<2 {
      for
        (name, expected) in [
          ("q", 1.0),
          ("id", (row + 1).to_double()),
          ("rank", (row + 1).to_double()),
          ("score", scores[row]),
        ] {
        assert_true(
          @execution.completed_cell(result, row, columns.get(name).unwrap())
          is Some(Number(actual)) &&
          actual == expected,
        )
      }
    }
    assert_true(@local_connector.managed_provider_stopped(execution))
    assert_true(
      @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
    )

    let cancelled = @local_connector.start_managed_provider_with_inputs(
      provider,
      generated,
      inputs.map(@local_connector.managed_provider_supplied_relation_input),
      10,
      1000,
    ).unwrap()
    assert_true(
      @local_connector.advance_managed_provider(cancelled, 1).unwrap()
      is @local_connector.Continue(work~, ..) &&
      work > 0L,
    )
    assert_true(@local_connector.cancel_managed_provider(cancelled))
    assert_false(@local_connector.managed_provider_stopped(cancelled))
    assert_false(@local_connector.cleanup_managed_provider(cancelled).unwrap())
    assert_true(inputs.all(@execution.supplied_relation_read_available))
    assert_true(
      @local_connector.advance_managed_provider(cancelled, 1).unwrap()
      is @local_connector.Stopped(_),
    )
    assert_true(@local_connector.managed_provider_stopped(cancelled))
    assert_true(@local_connector.cleanup_managed_provider(cancelled).unwrap())
    assert_true(inputs.all(@execution.supplied_relation_read_available))
  }
}

///|
test "fixed Compute retains ordered completed and supplied input identities" {
  let left = direct_ranking_owner()
  let owner = mixed_ranking_fusion_owner(left)
  let output = direct_ranking_output(left, [(1.0, 1.0, 0.75)])
  let completed = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, left, output).unwrap(),
    1000,
    10000,
  ).unwrap()
  let supplied = supplied_ranking_rows(owner, 1, [(1.0, 2.0, 0.5)])
  let expected = [
    @execution.fixed_completed_relation_read(completed),
    @execution.fixed_supplied_relation_read(supplied),
  ]
  let capacity : @connector.FixedComputeCapacity = {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 10,
    max_value_bytes: 1000,
    common_fragment: None,
  }
  let request = @connector.prepare_selected_fixed_compute_request_with_inputs(
    owner, 0, expected, capacity,
  ).unwrap()
  assert_eq(@connector.fixed_compute_request_input_count(request), 2)
  assert_true(@connector.fixed_compute_request_has_supplied_input(request))
  let exported = @connector.fixed_compute_request_inputs(request)
  assert_eq(exported.length(), 2)
  for index in 0..<2 {
    assert_true(
      @execution.fixed_relation_read_same(exported[index], expected[index]),
    )
    assert_true(
      @execution.fixed_relation_read_same(
        @connector.fixed_compute_request_input(request, index).unwrap(),
        expected[index],
      ),
    )
  }
  assert_true(exported[0] is @execution.CompletedRelation(_))
  assert_true(exported[1] is @execution.SuppliedRelation(_))
  exported.clear()
  assert_eq(@connector.fixed_compute_request_inputs(request).length(), 2)
  assert_true(
    @connector.prepare_selected_fixed_compute_request_with_inputs(
      owner,
      0,
      [expected[1], expected[0]],
      capacity,
    )
    is Err(@connector.UnsupportedInputShape),
  )
  let registry = search_registry()
  assert_true(
    @duckdb_compute.duckdb_fixed_compute_candidate(
      @connector.capability_registration_at(registry, 1).unwrap(),
      request,
      "owned_input",
      native_compile_limits(),
      [],
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
      100,
    )
    is Err(Request(UnsupportedInputShape)),
  )
}

///|
test "supplied scored ranking uses bounded materializing execution" {
  for cancel in [false, true] {
    let owner = supplied_ranking_fusion_owner("\"max\"")
    let inputs = [
      supplied_ranking_rows(owner, 0, [(1.0, 1.0, 0.75), (1.0, 2.0, 0.5)]),
      supplied_ranking_rows(owner, 1, [(1.0, 1.0, 0.5), (1.0, 3.0, 0.5)]),
    ]
    let generated = task_test_generated(owner)
    let limits = dispatch_test_limits()
    let measurement : @execution.FixedInputGuardMeasureLimits = {
      max_work: 10000,
      max_bytes: 10000,
      max_nodes: 10000,
      max_depth: 100,
    }
    let provider = @local_veca_provider.provider(
      carrier_vectors_storage_limits(),
      4096L,
      @execution.generated_sequence_capacity(
        generated,
        limits.local_execution,
        limits.guards,
      ).unwrap(),
    )
    let request = @connector.prepare_selected_fixed_compute_request_with_inputs(
      owner,
      0,
      inputs.map(input => @execution.fixed_supplied_relation_read(input)),
      {
        contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
        max_rows: 10,
        max_value_bytes: 1000,
        common_fragment: None,
      },
    ).unwrap()
    let registry = search_registry()
    let candidate = @local_connector.local_fixed_compute_candidate(
      @connector.capability_registration_at(registry, 0).unwrap(),
      request,
      generated,
      [],
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
      100,
    ).unwrap()
    guard @connector.choose_fixed_compute_candidate(
        registry,
        request,
        [@connector.prepared_compute_candidate(candidate)],
        Some([0]),
        100,
      ).unwrap()
      is Proposed(choice) else {
      fail("supplied ranking candidate")
    }
    let prepared = @local_connector.prepare_local_materializing_execution(
      choice,
      candidate,
      limits.local_execution,
      measurement,
      @local_connector.local_default_import_limits(
        limits.local_execution,
        measurement,
      ),
      _ => @strategy.RunIssue::Compute(InvalidLimits),
      family_providers=[provider],
    ).unwrap()
    let (attempt, lifecycle) = @connector.start_prepared_execution_lifecycle(
      prepared,
    ).unwrap()
    let mut advances = 0
    while true {
      let step = @local_connector.advance_local_materializing_attempt(
        attempt, 1,
      ).unwrap()
      assert_true(step.work <= 1L)
      advances += 1
      if cancel {
        assert_true(step.work > 0L)
        assert_false(step.complete)
        assert_true(
          @local_connector.cancel_local_materializing_attempt(attempt),
        )
        assert_false(@local_connector.local_materializing_stopped(attempt))
        assert_true(inputs.all(@execution.supplied_relation_read_available))
        assert_true(
          @local_connector.advance_local_materializing_attempt(attempt, 1)
          is Err(State),
        )
        assert_true(@local_connector.local_materializing_stopped(attempt))
        assert_true(
          @local_connector.local_materializing_completed_output(attempt) is None,
        )
        assert_true(inputs.all(@execution.supplied_relation_read_available))
        break
      }
      if step.complete {
        break
      }
      assert_true(step.work > 0L)
      assert_true(advances < 10000)
    }
    if !cancel {
      assert_true(advances > 1)
      (lifecycle.settled)()
      let output = @local_connector.local_materializing_completed_output(
        attempt,
      ).unwrap()
      assert_eq(@execution.completed_row_count(output), 2)
    }
    assert_true(@local_connector.local_materializing_stopped(attempt))
    @local_connector.close_local_materializing_attempt(attempt)
  }
}

///|
test "standard Host executes supplied scored rankings through two consumers" {
  for
    (policy, expected_ranked, expected_first, expected_second) in [
      (
        "\"max\"",
        [
          "{\"id\":1,\"q\":1,\"rank\":1,\"score\":0.75}", "{\"id\":2,\"q\":1,\"rank\":2,\"score\":0.5}",
        ],
        [
          "{\"q\":1,\"id\":1,\"rank\":1,\"score\":0.75}", "{\"q\":1,\"id\":2,\"rank\":2,\"score\":0.5}",
        ],
        ["{\"score\":0.75,\"id\":1}", "{\"score\":0.5,\"id\":2}"],
      ),
      (
        "{\"weighted_sum\":{\"left\":0.5,\"right\":0.5}}",
        [
          "{\"id\":1,\"q\":1,\"rank\":1,\"score\":0.625}", "{\"id\":2,\"q\":1,\"rank\":2,\"score\":0.25}",
        ],
        [
          "{\"q\":1,\"id\":1,\"rank\":1,\"score\":0.625}", "{\"q\":1,\"id\":2,\"rank\":2,\"score\":0.25}",
        ],
        ["{\"score\":0.625,\"id\":1}", "{\"score\":0.25,\"id\":2}"],
      ),
    ] {
    let (run, issuer) = captured_graph_fixture(
      local_supplied_ranking_chain=true,
      local_supplied_ranking_policy=policy,
      supplied_local_rows=[
        (
          1,
          0,
          [
            "{\"q\":1,\"id\":1,\"score\":0.75}", "{\"q\":1,\"id\":2,\"score\":0.5}",
          ],
        ),
        (
          1,
          1,
          [
            "{\"q\":1,\"id\":1,\"score\":0.5}", "{\"q\":1,\"id\":3,\"score\":0.5}",
          ],
        ),
      ],
    )
    assert_true(
      @strategy.configure_captured_managed_identity_policy(
        run, true, false, false, false,
      ),
    )
    let registry = search_registry()
    let limits = dispatch_test_limits()
    let sequences = dispatch_test_generated(run)
    let provider = @local_veca_provider.provider(
      carrier_vectors_storage_limits(),
      4096L,
      @execution.generated_sequence_capacity(
        sequences[1],
        limits.local_execution,
        limits.guards,
      ).unwrap(),
    )
    let modules = @builtin.configure_compute_modules(
      @host_driver.open_dispatch_driver(run),
      registry,
      1,
      _ => @strategy.RunIssue::ForeignCandidate,
      with_local=Some(
        (
          @connector.capability_registration_at(registry, 0).unwrap(),
          {
            sequences,
            managed_providers: [provider],
            managed_capacity: limits.capacity,
            execution: limits.local_execution,
            measurement: limits.guards,
            max_work: limits.candidate_work,
          },
          _ => @strategy.RunIssue::ForeignCandidate,
          _ => @strategy.RunIssue::ForeignCandidate,
        ),
      ),
    ).unwrap()
    let installed = @builtin.configured_local_module(modules).unwrap()
    @local_driver.configure_local_retained_inputs(
      installed,
      {
        max_rows: 100,
        values: limits.local_execution.rows.input_values,
        wire: {
          ..retained_attempt_wire_limits(),
          max_bytes: 3000,
          max_nodes: 300,
          max_depth: 10,
          max_columns: 10,
        },
        row: {
          max_bytes: 3000,
          max_nodes: 300,
          max_depth: 10,
          max_text_bytes: 3000,
        },
        max_batch_bytes: 3000,
      },
      None,
    ).unwrap()

    assert_eq(@strategy.next_captured_task(run), Some(1))
    let ranked_live = Ref(true)
    let obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
    let (ranked_ops, ranked) = run_local_managed_test_task(
      installed,
      run,
      1,
      [],
      [],
      1,
      ranked_live,
      obligations~,
    )
    let ranked_rows = local_managed_test_rows(ranked_ops)
    assert_eq(ranked_rows, expected_ranked)
    let publication = @execution.managed_obligations_identities(obligations).filter(requirement => {
        requirement.domain == @execution.LogicalRelation &&
        requirement.subject == @execution.NamedResult
      },
    )
    assert_eq(publication.length(), 1)
    assert_true(
      @execution.managed_completed_identity_requirement_status(
        ranked,
        publication[0],
      )
      is Some(@execution.EstablishedSourceRetained(_, _)),
    )

    let first_live = Ref(true)
    let (first_ops, first) = run_local_managed_test_task(
      installed,
      run,
      2,
      [ranked],
      [ranked_rows],
      2,
      first_live,
    )
    let second_live = Ref(true)
    let (second_ops, second) = run_local_managed_test_task(
      installed,
      run,
      3,
      [ranked],
      [ranked_rows],
      3,
      second_live,
    )
    assert_eq(local_managed_test_rows(first_ops), expected_first)
    assert_eq(local_managed_test_rows(second_ops), expected_second)

    first_live.val = false
    @strategy.close_captured_task_output(run, 2)
    (first_ops.close)()
    assert_true((first_ops.cleanup_refresh)())
    assert_false(@execution.managed_completed_output_available(first))
    assert_true(@execution.managed_completed_output_available(second))
    assert_true(@execution.managed_completed_output_available(ranked))

    second_live.val = false
    @strategy.close_captured_task_output(run, 3)
    (second_ops.close)()
    assert_true((second_ops.cleanup_refresh)())
    ranked_live.val = false
    @strategy.close_captured_task_output(run, 1)
    (ranked_ops.close)()
    assert_true((ranked_ops.cleanup_refresh)())
    @strategy.stop_captured_dag(run)
    @strategy.close_captured_task_output(run, 0)
    @strategy.refresh_captured_retention(run)
    let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_eq(usage.reserved_execution_bytes, 0L)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.held_bytes, 0L)
    @mock.close_mock_query_issuer(issuer)
  }
}

///|
fn direct_rrf_carrier() -> @carrier_contract.Carrier {
  let number = @value_contract.primitive(
    @value_contract.NumberType,
    nullable=false,
  )
  let nullable_number = @value_contract.primitive(
    @value_contract.NumberType,
    nullable=true,
  )
  @carrier_contract.relation(
    @carrier_contract.rows(
      [
        (@schema.Unqualified("q"), Some(nullable_number)),
        (@schema.Unqualified("id"), Some(number)),
        (@schema.Unqualified("rank"), Some(number)),
      ],
      field_set=@carrier_contract.Closed,
      max_fields=3,
      max_name_bytes=7,
    ).unwrap(),
  )
}

///|
fn direct_nullable_rrf_output(
  owner : @lower.BoundPrepared,
  rows : Array[(Double?, Double, Double)],
) -> @execution.CompletedOutput raise {
  let values = @execution.prepare_admitted_output(
    owner,
    @pipeline.Step(0),
    100,
    { max_nodes: 10000, max_text_bytes: 10000, max_depth: 10, max_work: 10000, },
  ).unwrap()
  let schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    @pipeline.Step(0),
  ).unwrap()
  for row in rows {
    let cells = Array::makei(@schema.field_count(schema), column => {
      let field = @schema.field_at(schema, column).unwrap()
      let name = @schema.reference_name(field.name)
      if name == "q" {
        @admitted.admit(
          field.contract,
          input_cursor(
            match row.0 {
              Some(value) => value.to_string()
              None => "null"
            },
          ),
          { max_nodes: 1, max_depth: 1, max_text_bytes: 0, },
        ).unwrap()
      } else {
        direct_ranking_number(
          owner,
          column,
          if name == "id" {
            row.1
          } else {
            row.2
          },
        )
      }
    })
    @execution.append_admitted_output(values, cells).unwrap()
  }
  let rows = @execution.finish_admitted_output(values).unwrap()
  let completion = @execution.prepare_trusted_output_port(
    task_test_completion(owner),
    @pipeline.Step(0),
    1000,
    10000,
    (proof : @execution.AdmittedOutputRows) => {
      if physical_equal(proof, rows) {
        Some(rows)
      } else {
        None
      }
    },
  ).unwrap()
  @execution.complete_trusted_output(completion, rows).unwrap()
}

///|
fn direct_rrf_owner() -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor("[{\"select\":[\"q\",\"id\",\"rank\"]}]"),
      [
        (
          "rows",
          @pipeline.RankingInput(@vector.ranking_relation(direct_rrf_carrier())),
        ),
      ],
      None,
      Some(input_cursor("\"rows\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn direct_rrf_fusion_owner(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"merge_rankings\":{\"with\":\"right\"," +
        "\"by\":[\"q\"],\"candidate\":\"id\",\"rank\":\"rank\"," +
        "\"k\":2,\"score_policy\":{\"rrf\":{" +
        "\"rank_constant\":1,\"weights\":[1,1]," +
        "\"rank_window\":2}}}}]",
      ),
      [
        (
          "left",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(left)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "right",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(right)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(input_cursor("\"left\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn run_direct_invalid_rrf(
  left_rows : Array[(Double, Double, Double)],
) -> Unit raise {
  let left = direct_rrf_owner()
  let right = direct_rrf_owner()
  let owner = direct_rrf_fusion_owner(left, right)
  let left_output = direct_ranking_output(left, left_rows)
  let right_output = direct_ranking_output(right, [
    (1.0, 3.0, 1.0),
    (1.0, 1.0, 2.0),
  ])
  let inputs = [
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, left, left_output).unwrap(),
      1000,
      10000,
    ).unwrap(),
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 1, right, right_output).unwrap(),
      1000,
      10000,
    ).unwrap(),
  ]
  let generated = task_test_generated(owner)
  let limits = dispatch_test_limits()
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let execution = @local_connector.start_managed_provider(
    provider, generated, inputs, 10, 1000,
  ).unwrap()
  let mut failed = false
  while !failed {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Failed(_, ..) => failed = true
      @local_connector.Complete(_, ..) => fail("invalid RRF completed")
      @local_connector.CarrierComplete(_, ..) =>
        fail("invalid RRF returned a Carrier")
      @local_connector.Waiting(..) =>
        fail("synchronous provider unexpectedly waited")
      @local_connector.Settling(_, ..) =>
        fail("synchronous provider unexpectedly requested settlement")
      @local_connector.Stopped(..) => fail("invalid RRF stopped")
    }
  }
  assert_true(@execution.completed_output_available(left_output))
  assert_true(@execution.completed_output_available(right_output))
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
}

///|
fn run_direct_nullable_rrf() -> Unit raise {
  let left = direct_rrf_owner()
  let right = direct_rrf_owner()
  let owner = direct_rrf_fusion_owner(left, right)
  let inputs = [
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(
        owner,
        0,
        left,
        direct_nullable_rrf_output(left, [
          (None, 1.0, 1.0),
          (Some(1.0), 2.0, 1.0),
        ]),
      ).unwrap(),
      1000,
      10000,
    ).unwrap(),
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(
        owner,
        1,
        right,
        direct_nullable_rrf_output(right, [
          (None, 1.0, 1.0),
          (Some(1.0), 3.0, 1.0),
        ]),
      ).unwrap(),
      1000,
      10000,
    ).unwrap(),
  ]
  let generated = task_test_generated(owner)
  let limits = dispatch_test_limits()
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let execution = @local_connector.start_managed_provider(
    provider, generated, inputs, 10, 1000,
  ).unwrap()
  let mut output = None
  while output is None {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(value, ..) => output = Some(value)
      @local_connector.CarrierComplete(_, ..) => fail("RRF returned a Carrier")
      @local_connector.Failed(_, ..) => fail("nullable RRF failed")
      @local_connector.Waiting(..) =>
        fail("synchronous provider unexpectedly waited")
      @local_connector.Settling(_, ..) =>
        fail("synchronous provider unexpectedly requested settlement")
      @local_connector.Stopped(..) => fail("nullable RRF stopped")
    }
  }
  let result = output.unwrap()
  let output_schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    @pipeline.Step(0),
  ).unwrap()
  let columns : Map[String, Int] = Map([])
  for column in 0..<@schema.field_count(output_schema) {
    columns.set(
      @schema.reference_name(
        @schema.field_at(output_schema, column).unwrap().name,
      ),
      column,
    )
  }
  assert_eq(@execution.completed_row_count(result), 3)
  for row, candidate in [1.0, 2.0, 3.0] {
    assert_true(
      @execution.completed_cell(result, row, columns.get("id").unwrap())
      is Some(Number(actual)) &&
      actual == candidate,
    )
  }
  assert_true(
    @execution.completed_cell(result, 0, columns.get("q").unwrap())
    is Some(Null),
  )
  for row in 1..<3 {
    assert_true(
      @execution.completed_cell(result, row, columns.get("q").unwrap())
      is Some(Number(1.0)),
    )
  }
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
}

///|
test "registered VecA provider rejects duplicate RRF candidates" {
  run_direct_invalid_rrf([(1.0, 1.0, 1.0), (1.0, 1.0, 2.0)])
}

///|
test "registered VecA provider rejects noncontiguous RRF ranks" {
  run_direct_invalid_rrf([(1.0, 1.0, 1.0), (1.0, 2.0, 3.0)])
}

///|
test "registered VecA provider groups nullable RRF keys" {
  run_direct_nullable_rrf()
}

///|
test "ranking bounds scratch and output assembly within quantum" {
  let left = direct_rrf_owner()
  let right = direct_rrf_owner()
  let owner = direct_rrf_fusion_owner(left, right)
  let left_output = direct_ranking_output(left, [
    (1.0, 1.0, 1.0),
    (1.0, 2.0, 2.0),
  ])
  let right_output = direct_ranking_output(right, [
    (1.0, 3.0, 1.0),
    (1.0, 4.0, 2.0),
  ])
  let inputs = [
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, left, left_output).unwrap(),
      1000,
      10000,
    ).unwrap(),
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 1, right, right_output).unwrap(),
      1000,
      10000,
    ).unwrap(),
  ]
  let control = @bounded.control()
  let execution = @local_veca.start_ranking(
    control,
    task_test_completion(owner),
    prepared_sequence(owner),
    0,
    inputs,
    10,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    1000,
    1000,
    10000,
  ).unwrap()
  assert_eq(@local_veca.ranking_scratch_slots(execution), 0)
  let mut last_work = 0L
  let mut scratch_started = false
  for _ in 0..<100 {
    if !scratch_started {
      match @local_veca.advance_ranking(execution, 1).unwrap() {
        @local_veca.RankingContinue(work~, ..) => {
          assert_eq(work - last_work, 1L)
          last_work = work
          scratch_started = @local_veca.ranking_scratch_slots(execution) > 0
          if scratch_started {
            assert_eq(@local_veca.ranking_scratch_slots(execution), 1)
          }
        }
        _ => fail("ranking completed before scratch initialization")
      }
    }
  }
  assert_true(scratch_started)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_veca.advance_ranking(execution, 1).unwrap()
    is @local_veca.RankingStopped(@bounded.Cancelled, ..),
  )
  assert_eq(@local_veca.cleanup_ranking(execution), Ok(true))
  assert_eq(@local_veca.ranking_scratch_slots(execution), 0)
  assert_true(@execution.producer_read_available(inputs[0]))
  assert_true(@execution.producer_read_available(inputs[1]))
  assert_true(@execution.completed_output_available(left_output))
  assert_true(@execution.completed_output_available(right_output))

  let output_control = @bounded.control()
  let output_execution = @local_veca.start_ranking(
    output_control,
    task_test_completion(owner),
    prepared_sequence(owner),
    0,
    inputs,
    10,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    1000,
    1000,
    10000,
  ).unwrap()
  let mut output_started = false
  let mut output_work = 0L
  for _ in 0..<1000 {
    if !output_started {
      match @local_veca.advance_ranking(output_execution, 1).unwrap() {
        @local_veca.RankingContinue(work~, ..) => {
          assert_eq(work - output_work, 1L)
          output_work = work
          output_started = @local_veca.ranking_output_field_slots(
              output_execution,
            ) >
            0
          if output_started {
            assert_eq(
              @local_veca.ranking_output_field_slots(output_execution),
              1,
            )
          }
        }
        _ => fail("ranking completed before output field assembly")
      }
    }
  }
  assert_true(output_started)
  assert_true(@bounded.request_cancel(output_control))
  assert_true(
    @local_veca.advance_ranking(output_execution, 1).unwrap()
    is @local_veca.RankingStopped(@bounded.Cancelled, ..),
  )
  assert_eq(@local_veca.cleanup_ranking(output_execution), Ok(true))
  assert_eq(@local_veca.ranking_output_field_slots(output_execution), 0)
  assert_true(@execution.producer_read_available(inputs[0]))
  assert_true(@execution.producer_read_available(inputs[1]))
}

///|
test "ranking yields within long group and tie comparisons" {
  let prefix = String::make(512, 'x')
  let segment = prefix + "s"
  let left = direct_nullable_ranking_owner()
  let right = direct_nullable_ranking_owner()
  let left_output = direct_nullable_ranking_output(
    left,
    [
      (None, Some(segment), 1.0, 0.5, Some(prefix + "a")),
      (None, Some(segment), 2.0, 0.5, Some(prefix + "b")),
    ],
    text_limit=513,
  )
  let right_output = direct_nullable_ranking_output(
    right,
    [
      (None, Some(segment), 1.0, 0.5, Some(prefix + "a")),
      (None, Some(segment), 2.0, 0.5, Some(prefix + "b")),
    ],
    text_limit=513,
  )
  for policy in ["\"max\"", "{\"weighted_sum\":{\"left\":0.5,\"right\":0.5}}"] {
    let owner = direct_nullable_ranking_fusion_owner(left, right, policy)
    let inputs = [
      @execution.prepare_producer_read(
        owner,
        @execution.bind_completed_input(owner, 0, left, left_output).unwrap(),
        1000,
        10000,
      ).unwrap(),
      @execution.prepare_producer_read(
        owner,
        @execution.bind_completed_input(owner, 1, right, right_output).unwrap(),
        1000,
        10000,
      ).unwrap(),
    ]
    let limits : @execution.ValueLimits = {
      max_nodes: 1000,
      max_text_bytes: 10000,
      max_depth: 10,
      max_work: 10000,
    }
    // Independently count four 1038-unit input rows, record sorts 1048+2590,
    // duplicate checks 1033, candidate folds 3600, output sort 1032, and
    // two emitted rows plus finalization 528. Total control work is 13983.
    // Workspace: 4*11+4 + 4*8+4 + (2+2*2) + (3+28) = 121.
    for
      (quantum, control_limit) in [
        (1, 13983),
        (7, 13983),
        (256, 13983),
        (1, 13982),
      ] {
      let execution = @local_veca.start_ranking(
        @bounded.control(),
        task_test_completion(owner),
        prepared_sequence(owner),
        0,
        inputs,
        10,
        limits,
        121,
        1000,
        10000,
        control_work_limit=Some(control_limit),
      ).unwrap()
      let mut terminal = false
      for _ in 0..<15000 {
        if terminal {
          break
        }
        match @local_veca.advance_ranking(execution, quantum).unwrap() {
          @local_veca.RankingContinue(work~, ..) => assert_true(work > 0L)
          @local_veca.RankingComplete(output, work~, ..) => {
            assert_eq(control_limit, 13983)
            assert_eq(work, 13983L)
            assert_eq(@execution.completed_row_count(output), 2)
            let schema = @pipeline.schema_at(
              @lower.pipeline(@lower.bound_preparation(owner)),
              @pipeline.Step(0),
            ).unwrap()
            for row in 0..<2 {
              for column in 0..<@schema.field_count(schema) {
                let name = @schema.reference_name(
                  @schema.field_at(schema, column).unwrap().name,
                )
                let cell = @execution.completed_cell(output, row, column)
                if name == "q" {
                  assert_true(cell is Some(Null))
                } else if name == "segment" {
                  assert_true(cell is Some(Text(actual)) && actual == segment)
                } else {
                  let expected = if name == "score" {
                    0.5
                  } else {
                    (row + 1).to_double()
                  }
                  assert_true(
                    cell is Some(Number(actual)) && actual == expected,
                  )
                }
              }
            }
            terminal = true
          }
          @local_veca.RankingFailed(@local_veca.RankingWorkLimit, work~, ..) => {
            assert_eq(control_limit, 13982)
            assert_eq(work, 13982L)
            terminal = true
          }
          _ => fail("long ranking missed its typed boundary")
        }
      }
      assert_true(terminal)
      assert_true(@local_veca.ranking_stopped(execution))
      assert_eq(@local_veca.cleanup_ranking(execution), Ok(true))
      assert_eq(@local_veca.ranking_comparison_units(execution), 0)
      assert_eq(@local_veca.ranking_scratch_slots(execution), 0)
      assert_eq(@local_veca.ranking_output_field_slots(execution), 0)
      assert_true(@execution.completed_output_available(left_output))
      assert_true(@execution.completed_output_available(right_output))
    }
    assert_true(
      @local_veca.start_ranking(
        @bounded.control(),
        task_test_completion(owner),
        prepared_sequence(owner),
        0,
        inputs,
        10,
        limits,
        120,
        1000,
        10000,
      )
      is Err(@local_veca.RankingWorkspaceLimit),
    )
    let control = @bounded.control()
    let execution = @local_veca.start_ranking(
      control,
      task_test_completion(owner),
      prepared_sequence(owner),
      0,
      inputs,
      10,
      limits,
      121,
      1000,
      10000,
      control_work_limit=Some(13983),
    ).unwrap()
    for _ in 0..<1000 {
      if @local_veca.ranking_comparison_units(execution) == 257 {
        break
      }
      assert_true(
        @local_veca.advance_ranking(execution, 1).unwrap()
        is @local_veca.RankingContinue(progress=0L, ..),
      )
    }
    assert_eq(@local_veca.ranking_comparison_units(execution), 257)
    assert_true(@bounded.request_cancel(control))
    assert_false(@local_veca.ranking_stopped(execution))
    assert_eq(
      @local_veca.cleanup_ranking(execution),
      Err(@local_veca.RankingExecutionIssue(@bounded.NotStopped)),
    )
    assert_eq(@local_veca.ranking_comparison_units(execution), 257)
    assert_true(@execution.producer_read_available(inputs[0]))
    assert_true(@execution.producer_read_available(inputs[1]))
    assert_true(
      @local_veca.advance_ranking(execution, 1).unwrap()
      is @local_veca.RankingStopped(@bounded.Cancelled, progress=0L, ..),
    )
    assert_eq(@local_veca.cleanup_ranking(execution), Ok(true))
    assert_eq(@local_veca.ranking_comparison_units(execution), 0)
    assert_eq(@local_veca.cleanup_ranking(execution), Ok(false))
    assert_true(@execution.completed_output_available(left_output))
    assert_true(@execution.completed_output_available(right_output))
  }
}

///|
test "ranking producer path admits exact work and workspace" {
  let left = direct_rrf_owner()
  let right = direct_rrf_owner()
  let owner = direct_rrf_fusion_owner(left, right)
  let left_output = direct_ranking_output(left, [
    (1.0, 1.0, 1.0),
    (1.0, 2.0, 2.0),
  ])
  let right_output = direct_ranking_output(right, [
    (1.0, 3.0, 1.0),
    (1.0, 4.0, 2.0),
  ])
  let inputs = [
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, left, left_output).unwrap(),
      1000,
      10000,
    ).unwrap(),
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 1, right, right_output).unwrap(),
      1000,
      10000,
    ).unwrap(),
  ]
  let limits : @execution.ValueLimits = {
    max_nodes: 1000,
    max_text_bytes: 1000,
    max_depth: 10,
    max_work: 10000,
  }
  let exact = @local_veca.start_ranking(
    @bounded.control(),
    task_test_completion(owner),
    prepared_sequence(owner),
    0,
    inputs,
    10,
    limits,
    103,
    1000,
    10000,
    control_work_limit=Some(166),
  ).unwrap()
  let mut exact_done = false
  for _ in 0..<1000 {
    if exact_done {
      break
    }
    match @local_veca.advance_ranking(exact, 1).unwrap() {
      @local_veca.RankingContinue(work~, ..) => assert_true(work > 0L)
      @local_veca.RankingComplete(output, work~, ..) => {
        assert_eq(work, 166L)
        assert_eq(@execution.completed_row_count(output), 2)
        exact_done = true
      }
      _ => fail("exact ranking boundary failed")
    }
  }
  assert_true(exact_done)
  assert_eq(@local_veca.cleanup_ranking(exact), Ok(true))
  assert_true(@execution.completed_output_available(left_output))
  assert_true(@execution.completed_output_available(right_output))
  let one_short_work = @local_veca.start_ranking(
    @bounded.control(),
    task_test_completion(owner),
    prepared_sequence(owner),
    0,
    inputs,
    10,
    limits,
    103,
    1000,
    10000,
    control_work_limit=Some(165),
  ).unwrap()
  let mut work_failed = false
  for _ in 0..<1000 {
    if work_failed {
      break
    }
    match @local_veca.advance_ranking(one_short_work, 1).unwrap() {
      @local_veca.RankingContinue(work~, ..) => assert_true(work > 0L)
      @local_veca.RankingFailed(@local_veca.RankingWorkLimit, work~, ..) => {
        assert_eq(work, 165L)
        work_failed = true
      }
      _ => fail("one-short ranking work was accepted")
    }
  }
  assert_true(work_failed)
  assert_eq(@local_veca.cleanup_ranking(one_short_work), Ok(true))
  assert_true(@execution.completed_output_available(left_output))
  assert_true(@execution.completed_output_available(right_output))
  assert_true(
    @local_veca.start_ranking(
      @bounded.control(),
      task_test_completion(owner),
      prepared_sequence(owner),
      0,
      inputs,
      10,
      limits,
      102,
      1000,
      10000,
    )
    is Err(@local_veca.RankingWorkspaceLimit),
  )
}

///|
test "registered ranking provider enforces exact work and workspace" {
  let left = direct_rrf_owner()
  let right = direct_rrf_owner()
  let owner = direct_rrf_fusion_owner(left, right)
  let left_output = direct_ranking_output(left, [
    (1.0, 1.0, 1.0),
    (1.0, 2.0, 2.0),
  ])
  let right_output = direct_ranking_output(right, [
    (1.0, 3.0, 1.0),
    (1.0, 4.0, 2.0),
  ])
  let inputs = [
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, left, left_output).unwrap(),
      1000,
      10000,
    ).unwrap(),
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 1, right, right_output).unwrap(),
      1000,
      10000,
    ).unwrap(),
  ]
  let generated = task_test_generated(owner)
  let limits = dispatch_test_limits()
  let capacity = @execution.generated_sequence_capacity(
    generated,
    limits.local_execution,
    limits.guards,
  ).unwrap()
  // Four three-field input rows cost 32 units; four stable sort passes cost
  // 88 (six additional record comparisons and two output comparisons);
  // duplicate/rank validation costs 12; fusion-boundary comparisons add 3;
  // four two-input folds cost 16;
  // four output visits, two four-field rows, and finalization cost 15.
  // Workspace is 4*9 + 4 + 4*6 + 4 + (2+2*2) + (1+28) = 103 slots.
  // The extra 12 fixed slots cover the borrowed comparison cursor and counter.
  for
    (work, slots, outcome, quantum) in [
      (166, 103, "complete", 1),
      (166, 103, "complete", 7),
      (166, 103, "complete", 256),
      (165, 103, "work", 1),
      (166, 102, "workspace", 1),
    ] {
    let provider = @local_veca_provider.provider(
      {
        ..carrier_vectors_storage_limits(),
        max_work: work,
        max_workspace_slots: slots,
      },
      4096L,
      capacity,
    )
    let execution = @local_connector.start_managed_provider(
      provider, generated, inputs, 10, 1000,
    ).unwrap()
    let mut terminal = false
    let mut charged = 0L
    for _ in 0..<1000 {
      if terminal {
        break
      }
      match
        @local_connector.advance_managed_provider(execution, quantum).unwrap() {
        @local_connector.Continue(work~, ..) => {
          assert_true(work > 0L)
          charged += work
        }
        @local_connector.Complete(output, work~, ..) => {
          assert_eq(outcome, "complete")
          charged += work
          assert_eq(@execution.completed_row_count(output), 2)
          terminal = true
        }
        @local_connector.Failed(_, work~, ..) => {
          charged += work
          assert_true(outcome != "complete")
          terminal = true
        }
        _ => fail("ranking provider stopped unexpectedly")
      }
    }
    assert_true(terminal)
    assert_eq(
      charged,
      if outcome == "workspace" {
        0L
      } else if outcome == "work" {
        165L
      } else {
        166L
      },
    )
    assert_true(@local_connector.managed_provider_stopped(execution))
    assert_true(@local_connector.cleanup_managed_provider(execution).unwrap())
    assert_true(@execution.completed_output_available(left_output))
    assert_true(@execution.completed_output_available(right_output))
  }
}

///|
fn run_direct_nearest_provider(
  owner : @lower.BoundPrepared,
  inputs : Array[@local_connector.ManagedProviderInput],
) -> Unit raise {
  let generated = task_test_generated(owner)
  let limits = dispatch_test_limits()
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let execution = @local_connector.start_managed_provider_with_inputs(
    provider, generated, inputs, 10, 1000,
  ).unwrap()
  let mut output = None
  while output is None {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(value, ..) => output = Some(value)
      @local_connector.CarrierComplete(_, ..) =>
        fail("nearest returned a Carrier")
      @local_connector.Failed(_, ..) => fail("nearest provider failed")
      @local_connector.Waiting(..) =>
        fail("synchronous provider unexpectedly waited")
      @local_connector.Settling(_, ..) =>
        fail("synchronous provider unexpectedly requested settlement")
      @local_connector.Stopped(..) => fail("nearest provider stopped")
    }
  }
  let result = output.unwrap()
  assert_eq(@execution.completed_row_count(result), 4)
  assert_true(@execution.completed_cell(result, 0, 0) is Some(Number(3.0)))
  assert_true(@execution.completed_cell(result, 0, 1) is Some(Number(10.0)))
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
}

///|
fn run_direct_invalid_nearest_provider(
  owner : @lower.BoundPrepared,
  inputs : Array[@local_connector.ManagedProviderInput],
) -> Unit raise {
  let generated = task_test_generated(owner)
  let limits = dispatch_test_limits()
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let execution = @local_connector.start_managed_provider_with_inputs(
    provider, generated, inputs, 10, 1000,
  ).unwrap()
  let mut failed = false
  let mut polls = 0
  while !failed && polls < 100 {
    polls += 1
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Failed(_, ..) => failed = true
      @local_connector.Complete(_, ..) => fail("invalid nearest completed")
      @local_connector.CarrierComplete(_, ..) =>
        fail("invalid nearest returned a Carrier")
      @local_connector.Waiting(..) =>
        fail("synchronous provider unexpectedly waited")
      @local_connector.Settling(_, ..) =>
        fail("synchronous provider unexpectedly requested settlement")
      @local_connector.Stopped(..) => fail("invalid nearest stopped")
    }
  }
  assert_true(failed)
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
}

///|
fn direct_nearest_number(value : Double) -> @admitted.CheckedValue {
  @admitted.admit(
    @value_contract.primitive(@value_contract.NumberType, nullable=false),
    input_cursor(value.to_string()),
    { max_nodes: 1, max_depth: 1, max_text_bytes: 0, },
  ).unwrap()
}

///|
fn direct_nearest_vector(text : String) -> @admitted.CheckedValue {
  @admitted.admit(
    @value_contract.vector_contract(2.0, nullable=false).unwrap(),
    input_cursor(text),
    { max_nodes: 3, max_depth: 2, max_text_bytes: 0, },
  ).unwrap()
}

///|
fn direct_nearest_material(
  owner : @lower.BoundPrepared,
  records : Array[(Double, String)],
) -> @carrier_runtime.Material {
  let output = @records.prepare_output(
    owner,
    @pipeline.Step(0),
    carrier_vectors_storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  for record in records {
    @records.append_record(output, [
      (@schema.Unqualified("id"), direct_nearest_number(record.0)),
      (@schema.Unqualified("embedding"), direct_nearest_vector(record.1)),
    ]).unwrap()
  }
  @records.completed_material(@records.finish_output(output).unwrap()).unwrap()
}

///|
test "selected nearest binds reordered Stage inputs by operation port" {
  let candidates = direct_nearest_vector_owner()
  let queries = direct_nearest_vector_owner()
  let owner = reordered_nearest_owner(candidates, queries)
  let candidate_material = direct_nearest_material(candidates, [
    (2.0, "[1,0]"),
    (1.0, "[1,0]"),
    (3.0, "[0,1]"),
  ])
  let query_material = direct_nearest_material(queries, [
    (20.0, "[1,0]"),
    (10.0, "[0,1]"),
  ])
  let candidate_view = @carrier_runtime.material_prepare_view(
    candidate_material, owner, 1, candidates,
  ).unwrap()
  let query_view = @carrier_runtime.material_prepare_view(
    query_material, owner, 0, queries,
  ).unwrap()
  run_selected_nearest_provider(
    owner,
    0,
    [
      @local_connector.managed_provider_carrier_input(candidate_view),
      @local_connector.managed_provider_carrier_input(query_view),
    ],
    [(3.0, 10.0), (1.0, 10.0), (1.0, 20.0), (2.0, 20.0)],
  )
  assert_true(@carrier_runtime.material_available(candidate_material))
  assert_true(@carrier_runtime.material_available(query_material))
  assert_true(@carrier_runtime.reclaim_material(candidate_material))
  assert_true(@carrier_runtime.reclaim_material(query_material))
}

///|
test "selected nearest retains both ports of one repeated producer" {
  let source = direct_nearest_vector_owner()
  let owner = reordered_nearest_owner(source, source)
  let material = direct_nearest_material(source, [
    (1.0, "[1,0]"),
    (2.0, "[0,1]"),
  ])
  let candidate_view = @carrier_runtime.material_prepare_view(
    material, owner, 1, source,
  ).unwrap()
  let query_view = @carrier_runtime.material_prepare_view(
    material, owner, 0, source,
  ).unwrap()
  run_selected_nearest_provider(
    owner,
    0,
    [
      @local_connector.managed_provider_carrier_input(candidate_view),
      @local_connector.managed_provider_carrier_input(query_view),
    ],
    [(1.0, 1.0), (2.0, 1.0), (2.0, 2.0), (1.0, 2.0)],
  )
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@carrier_runtime.reclaim_material(material))
}

///|
test "selected nearest binds mixed Step and Input by operation port" {
  let candidate_rows = direct_nearest_relation_owner(
    "[{\"id\":2,\"embedding\":[1,0]},{\"id\":1,\"embedding\":[1,0]}," +
    "{\"id\":3,\"embedding\":[0,1]}]",
  )
  let queries = direct_nearest_vector_owner()
  let owner = mixed_step_nearest_owner(candidate_rows, queries)
  let candidate_material = direct_nearest_material(owner, [
    (2.0, "[1,0]"),
    (1.0, "[1,0]"),
    (3.0, "[0,1]"),
  ])
  let query_material = direct_nearest_material(queries, [
    (20.0, "[1,0]"),
    (10.0, "[0,1]"),
  ])
  let candidate_view = @carrier_runtime.material_prepare_operation_view(
    candidate_material, owner, 1, 0, owner,
  ).unwrap()
  let query_view = @carrier_runtime.material_prepare_view(
    query_material, owner, 0, queries,
  ).unwrap()
  run_selected_nearest_provider(
    owner,
    1,
    [
      @local_connector.managed_provider_carrier_input(candidate_view),
      @local_connector.managed_provider_carrier_input(query_view),
    ],
    [(3.0, 10.0), (1.0, 10.0), (1.0, 20.0), (2.0, 20.0)],
  )
  assert_true(@carrier_runtime.material_available(candidate_material))
  assert_true(@carrier_runtime.material_available(query_material))
  assert_true(@carrier_runtime.reclaim_material(candidate_material))
  assert_true(@carrier_runtime.reclaim_material(query_material))
}

///|
test "registered VecA provider consumes exact Vectors inputs" {
  let candidates = direct_nearest_vector_owner()
  let queries = direct_nearest_vector_owner()
  let owner = direct_nearest_owner(candidates, queries)
  let candidate_material = direct_nearest_material(candidates, [
    (2.0, "[1,0]"),
    (1.0, "[1,0]"),
    (3.0, "[0,1]"),
  ])
  let query_material = direct_nearest_material(queries, [
    (20.0, "[1,0]"),
    (10.0, "[0,1]"),
  ])
  let candidate_view = @carrier_runtime.material_prepare_view(
    candidate_material, owner, 0, candidates,
  ).unwrap()
  let query_view = @carrier_runtime.material_prepare_view(
    query_material, owner, 1, queries,
  ).unwrap()
  run_direct_nearest_provider(owner, [
    @local_connector.managed_provider_carrier_input(candidate_view),
    @local_connector.managed_provider_carrier_input(query_view),
  ])
  assert_true(@carrier_runtime.material_available(candidate_material))
  assert_true(@carrier_runtime.material_available(query_material))
  assert_true(@carrier_runtime.reclaim_material(candidate_material))
  assert_true(@carrier_runtime.reclaim_material(query_material))
}

///|
test "nearest charges incremental initialization and cumulative work" {
  let candidates = direct_nearest_vector_owner()
  let queries = direct_nearest_vector_owner()
  let owner = direct_nearest_owner(candidates, queries)
  let candidate_material = direct_nearest_material(candidates, [(1.0, "[1,0]")])
  let query_material = direct_nearest_material(queries, [(10.0, "[1,0]")])
  let generated = task_test_generated(owner)
  // Each input: one identity slot, two field reads, two identity matches,
  // one record finish, and three component checks = nine units. Two record
  // scratch slots and two uniqueness checks bring the total to 22. One
  // score scratch slot, two component folds, score finish, a 25-unit output
  // row and completion bring the independent total to 52 units. The output
  // uses two identity picks, row start, twelve scalar read/recheck units,
  // charge start, four name/value pairs and commit.
  // Workspace: two three-slot records, four score slots, three record-sort
  // slots, two identity slots, and sixteen fixed slots = 31.
  let short_candidate_view = @carrier_runtime.material_prepare_view(
    candidate_material, owner, 0, candidates,
  ).unwrap()
  let short_query_view = @carrier_runtime.material_prepare_view(
    query_material, owner, 1, queries,
  ).unwrap()
  assert_true(
    @local_veca.start_nearest_inputs_with_control_work_limit(
      @bounded.control(),
      @execution.generated_completion_preparation(generated),
      @execution.generated_prepared_sequence(generated),
      0,
      @local_veca.nearest_carrier_producer(short_candidate_view),
      @local_veca.nearest_carrier_producer(short_query_view),
      10,
      { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
      30,
      1000,
      1000,
      52,
    )
    is Err(@local_veca.NearestWorkspaceLimit),
  )
  for (ceiling, accepted) in [(52, true), (51, false)] {
    let candidate_view = @carrier_runtime.material_prepare_view(
      candidate_material, owner, 0, candidates,
    ).unwrap()
    let query_view = @carrier_runtime.material_prepare_view(
      query_material, owner, 1, queries,
    ).unwrap()
    let execution = @local_veca.start_nearest_inputs_with_control_work_limit(
      @bounded.control(),
      @execution.generated_completion_preparation(generated),
      @execution.generated_prepared_sequence(generated),
      0,
      @local_veca.nearest_carrier_producer(candidate_view),
      @local_veca.nearest_carrier_producer(query_view),
      10,
      { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
      31,
      1000,
      1000,
      ceiling,
    ).unwrap()
    let mut terminal = false
    let mut charged = 0L
    for _ in 0..<64 {
      if !terminal {
        match @local_veca.advance_nearest(execution, 1).unwrap() {
          @local_veca.NearestContinue(work~, ..) => {
            assert_eq(work - charged, 1L)
            charged = work
          }
          @local_veca.NearestComplete(output, work~, ..) => {
            assert_true(accepted)
            assert_eq(work - charged, 1L)
            charged = work
            assert_eq(@execution.completed_row_count(output), 1)
            terminal = true
          }
          @local_veca.NearestFailed(@local_veca.NearestWorkLimit, work~, ..) => {
            assert_false(accepted)
            assert_eq(work, charged)
            assert_true(@local_veca.nearest_cleanup_pending(execution))
            terminal = true
          }
          _ => fail("nearest work boundary had another result")
        }
      }
    }
    assert_true(terminal)
    assert_eq(charged, ceiling.to_int64())
    assert_true(@local_veca.nearest_stopped(execution))
    assert_eq(@local_veca.cleanup_nearest(execution), Ok(true))
  }
  assert_true(@carrier_runtime.material_available(candidate_material))
  assert_true(@carrier_runtime.material_available(query_material))
  assert_true(@carrier_runtime.reclaim_material(candidate_material))
  assert_true(@carrier_runtime.reclaim_material(query_material))
}

///|
test "nearest stops during incremental identity initialization" {
  let candidates = direct_nearest_vector_owner()
  let queries = direct_nearest_vector_owner()
  let owner = direct_nearest_owner(candidates, queries)
  let candidate_material = direct_nearest_material(candidates, [(1.0, "[1,0]")])
  let query_material = direct_nearest_material(queries, [(10.0, "[1,0]")])
  let candidate_view = @carrier_runtime.material_prepare_view(
    candidate_material, owner, 0, candidates,
  ).unwrap()
  let query_view = @carrier_runtime.material_prepare_view(
    query_material, owner, 1, queries,
  ).unwrap()
  let generated = task_test_generated(owner)
  let control = @bounded.control()
  let execution = @local_veca.start_nearest_inputs_with_control_work_limit(
    control,
    @execution.generated_completion_preparation(generated),
    @execution.generated_prepared_sequence(generated),
    0,
    @local_veca.nearest_carrier_producer(candidate_view),
    @local_veca.nearest_carrier_producer(query_view),
    10,
    { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    31,
    1000,
    1000,
    52,
  ).unwrap()
  assert_true(
    @local_veca.advance_nearest(execution, 1).unwrap()
    is @local_veca.NearestContinue(work=1L, ..),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_veca.advance_nearest(execution, 1).unwrap()
    is @local_veca.NearestStopped(_, work=1L, ..),
  )
  assert_true(@local_veca.nearest_stopped(execution))
  assert_true(@local_veca.nearest_cleanup_pending(execution))
  assert_eq(@local_veca.cleanup_nearest(execution), Ok(true))
  assert_true(@carrier_runtime.material_available(candidate_material))
  assert_true(@carrier_runtime.material_available(query_material))
  assert_true(@carrier_runtime.reclaim_material(candidate_material))
  assert_true(@carrier_runtime.reclaim_material(query_material))
}

///|
test "direct nearest Relation inputs keep exact work and workspace bounds" {
  let candidates = direct_nearest_relation_owner(
    "[{\"id\":1,\"embedding\":[1,0]}]",
  )
  let queries = direct_nearest_relation_owner(
    "[{\"id\":10,\"embedding\":[1,0]}]",
  )
  let owner = direct_nearest_owner(
    candidates,
    queries,
    candidate_relation=true,
    query_relation=true,
  )
  let candidate_output = direct_nearest_relation_output(candidates)
  let query_output = direct_nearest_relation_output(queries)
  let generated = task_test_generated(owner)
  for (ceiling, accepted) in [(52, true), (51, false)] {
    let candidate_read = @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, candidates, candidate_output).unwrap(),
      10,
      1000,
    ).unwrap()
    let query_read = @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 1, queries, query_output).unwrap(),
      10,
      1000,
    ).unwrap()
    // Two three-slot records, four score slots, three ordering slots,
    // two identity slots, and sixteen fixed slots require 31 workspace slots.
    let execution = @local_veca.start_nearest_inputs_with_control_work_limit(
      @bounded.control(),
      @execution.generated_completion_preparation(generated),
      @execution.generated_prepared_sequence(generated),
      0,
      @local_veca.nearest_relation_producer(candidate_read),
      @local_veca.nearest_relation_producer(query_read),
      10,
      { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
      31,
      1000,
      1000,
      ceiling,
    ).unwrap()
    let mut terminal = false
    let mut charged = 0L
    for _ in 0..<64 {
      if !terminal {
        match @local_veca.advance_nearest(execution, 1).unwrap() {
          @local_veca.NearestContinue(work~, ..) => {
            assert_eq(work - charged, 1L)
            charged = work
          }
          @local_veca.NearestComplete(output, work~, ..) => {
            assert_true(accepted)
            assert_eq(work - charged, 1L)
            charged = work
            assert_eq(@execution.completed_row_count(output), 1)
            terminal = true
          }
          @local_veca.NearestFailed(@local_veca.NearestWorkLimit, work~, ..) => {
            assert_false(accepted)
            assert_eq(work, charged)
            assert_true(@local_veca.nearest_cleanup_pending(execution))
            terminal = true
          }
          _ => fail("direct Relation nearest work boundary had another result")
        }
      }
    }
    assert_true(terminal)
    assert_eq(charged, ceiling.to_int64())
    assert_true(@local_veca.nearest_stopped(execution))
    assert_eq(@local_veca.cleanup_nearest(execution), Ok(true))
    assert_true(@execution.producer_read_available(candidate_read))
    assert_true(@execution.producer_read_available(query_read))
  }
  let candidate_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, candidates, candidate_output).unwrap(),
    10,
    1000,
  ).unwrap()
  let query_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 1, queries, query_output).unwrap(),
    10,
    1000,
  ).unwrap()
  assert_true(
    @local_veca.start_nearest_inputs_with_control_work_limit(
      @bounded.control(),
      @execution.generated_completion_preparation(generated),
      @execution.generated_prepared_sequence(generated),
      0,
      @local_veca.nearest_relation_producer(candidate_read),
      @local_veca.nearest_relation_producer(query_read),
      10,
      { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
      30,
      1000,
      1000,
      52,
    )
    is Err(@local_veca.NearestWorkspaceLimit),
  )
  assert_true(@execution.producer_read_available(candidate_read))
  assert_true(@execution.producer_read_available(query_read))
}

///|
fn direct_relation_pool_source_owner() -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check(
      input_cursor(
        "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}," +
        "\"group\":{\"type\":\"number\",\"nullable\":false}," +
        "\"embedding\":{\"type\":\"vector\",\"dimensions\":2," +
        "\"nullable\":false}},\"rows\":[{\"id\":1,\"group\":1," +
        "\"embedding\":[1,2]}]},\"as\":\"source\"}," +
        "{\"from\":\"source\",\"assert_rows\":{\"unique_by\":[\"id\"]}," +
        "\"as\":\"keyed\"}]",
      ),
      [],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn direct_relation_pool_owner(
  source : @lower.BoundPrepared,
  prefix? : Bool = false,
) -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[" +
        (if prefix {
          "{\"values\":{\"schema\":{\"unused\":{\"type\":\"number\"," +
          "\"nullable\":false}},\"rows\":[]},\"as\":\"unused\"},"
        } else {
          ""
        }) +
        "{\"from\":\"rows\",\"pool_vectors\":{\"vector\":\"embedding\"," +
        "\"by\":[\"group\"],\"method\":\"sum\"}}]",
      ),
      [
        (
          "rows",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(source)),
              @pipeline.Step(1),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(input_cursor("\"rows\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn direct_relation_pool_limits(
  workspace : Int,
  work : Int,
) -> @record_storage.Limits {
  {
    max_input_records: 10,
    max_records: 10,
    max_fields_per_record: 10,
    max_value_bytes: 1000,
    max_total_value_bytes: 10000,
    max_retained_value_bytes: 10000,
    max_value_nodes: 100,
    max_value_depth: 10,
    max_contract_work: 1000,
    max_work: work,
    max_workspace_slots: workspace,
  }
}

///|
test "registered Relation pool returns a standalone Vectors generation" {
  let source = direct_relation_pool_source_owner()
  let completed = @execution.execute_generated_sequence(
    task_test_generated(source),
    [],
    compute_test_limits(),
  ).unwrap()
  let source_output = @execution.completed_output(completed, @pipeline.Step(1)).unwrap()
  for (selected, prefix) in [(false, false), (true, false), (true, true)] {
    let owner = direct_relation_pool_owner(source, prefix~)
    let read = @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, source, source_output).unwrap(),
      10,
      1000,
    ).unwrap()
    let generated = if selected {
      @execution.select_generated_sequence_step(
        task_test_generated(owner),
        if prefix {
          1
        } else {
          0
        },
      ).unwrap()
    } else {
      task_test_generated(owner)
    }
    let limits = dispatch_test_limits()
    let provider = @local_veca_provider.provider(
      direct_relation_pool_limits(18, 32),
      4096L,
      @execution.generated_sequence_capacity(
        generated,
        limits.local_execution,
        limits.guards,
      ).unwrap(),
    )
    let execution = @local_connector.start_managed_provider_with_inputs(
      provider,
      generated,
      [@local_connector.managed_provider_relation_input(read)],
      10,
      1000,
    ).unwrap()
    let mut material = None
    let mut charged = 0L
    for _ in 0..<40 {
      if material is None {
        match @local_connector.advance_managed_provider(execution, 1).unwrap() {
          @local_connector.Continue(work~, ..) => {
            assert_true(work <= 1L)
            charged += work
          }
          @local_connector.CarrierComplete(output, work~, ..) => {
            charged += work
            material = Some(output)
          }
          _ => fail("standalone Relation pool did not return Vectors")
        }
      }
    }
    let material = material.unwrap()
    assert_eq(charged, 32L)
    assert_true(@carrier_runtime.material_available(material))
    assert_true(@local_connector.managed_provider_stopped(execution))
    assert_true(@local_connector.cleanup_managed_provider(execution).unwrap())
    assert_true(@carrier_runtime.material_available(material))
    assert_true(@execution.producer_read_available(read))
    assert_true(@carrier_runtime.reclaim_material(material))
  }
}

///|
test "registered Relation pool retains exact limits and stopped cleanup" {
  let source = direct_relation_pool_source_owner()
  let owner = direct_relation_pool_owner(source)
  let completed = @execution.execute_generated_sequence(
    task_test_generated(source),
    [],
    compute_test_limits(),
  ).unwrap()
  let source_output = @execution.completed_output(completed, @pipeline.Step(1)).unwrap()
  let read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source, source_output).unwrap(),
    10,
    1000,
  ).unwrap()
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(owner),
    0,
  ).unwrap()
  let limits = dispatch_test_limits()
  let capacity = @execution.generated_sequence_capacity(
    generated,
    limits.local_execution,
    limits.guards,
  ).unwrap()
  // The same Relation kernel requires 32 work units and 18 workspace slots,
  // independently itemized in the adjacent direct-kernel boundary fixture.
  for
    (work, workspace, stopping) in [
      (31, 18, false),
      (32, 17, false),
      (32, 18, true),
    ] {
    let provider = @local_veca_provider.provider(
      direct_relation_pool_limits(workspace, work),
      4096L,
      capacity,
    )
    let execution = @local_connector.start_managed_provider_with_inputs(
      provider,
      generated,
      [@local_connector.managed_provider_relation_input(read)],
      10,
      1000,
    ).unwrap()
    let mut charged = 0L
    let mut terminal = false
    for _ in 0..<40 {
      if !terminal {
        match @local_connector.advance_managed_provider(execution, 1).unwrap() {
          @local_connector.Continue(work~, ..) => {
            assert_true(work <= 1L)
            charged += work
            if stopping {
              assert_true(@local_connector.cancel_managed_provider(execution))
              assert_false(@local_connector.managed_provider_stopped(execution))
              assert_false(
                @local_connector.cleanup_managed_provider(execution).unwrap(),
              )
              assert_true(@execution.producer_read_available(read))
            }
          }
          @local_connector.Failed(_, work~, ..) => {
            assert_false(stopping)
            charged += work
            terminal = true
          }
          @local_connector.Stopped(work~, ..) => {
            assert_true(stopping)
            charged += work
            terminal = true
          }
          _ => fail("Relation pool boundary exposed a completion")
        }
      }
    }
    assert_true(terminal)
    assert_eq(
      charged,
      if workspace == 17 {
        0L
      } else if stopping {
        1L
      } else {
        31L
      },
    )
    assert_true(@local_connector.cleanup_managed_provider(execution).unwrap())
    assert_true(@execution.producer_read_available(read))
  }
  let foreign = direct_relation_pool_owner(source)
  let foreign_read = @execution.prepare_producer_read(
    foreign,
    @execution.bind_completed_input(foreign, 0, source, source_output).unwrap(),
    10,
    1000,
  ).unwrap()
  let provider = @local_veca_provider.provider(
    direct_relation_pool_limits(18, 32),
    4096L,
    capacity,
  )
  let execution = @local_connector.start_managed_provider_with_inputs(
    provider,
    generated,
    [@local_connector.managed_provider_relation_input(foreign_read)],
    10,
    1000,
  ).unwrap()
  assert_true(
    @local_connector.advance_managed_provider(execution, 1).unwrap()
    is @local_connector.Failed(_, work=0L, ..),
  )
  assert_true(@local_connector.cleanup_managed_provider(execution).unwrap())
  assert_true(@execution.producer_read_available(read))
}

///|
test "relation pool enforces exact work and workspace boundaries" {
  let source = direct_relation_pool_source_owner()
  let owner = direct_relation_pool_owner(source)
  let completed = @execution.execute_generated_sequence(
    task_test_generated(source),
    [],
    compute_test_limits(),
  ).unwrap()
  let source_output = @execution.completed_output(completed, @pipeline.Step(1)).unwrap()
  let read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source, source_output).unwrap(),
    10,
    1000,
  ).unwrap()
  // One five-slot record in each ordering array (10), three output fields,
  // two vector components, and three key slots require 18 workspace slots.
  assert_true(
    @local_veca.start_relation_pool(
      @bounded.control(),
      @execution.generated_prepared_sequence(task_test_generated(owner)),
      0,
      read,
      direct_relation_pool_limits(17, 1000),
      4096L,
      fn() { true },
    )
    is Err(@local_veca.PoolWorkspaceLimit),
  )
  assert_true(@execution.producer_read_available(read))
  let control = @bounded.control()
  let execution = @local_veca.start_relation_pool(
    control,
    @execution.generated_prepared_sequence(task_test_generated(owner)),
    0,
    read,
    direct_relation_pool_limits(18, 1000),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(
    @local_veca.advance_pool(execution, 1).unwrap()
    is @local_veca.PoolContinue(..),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_veca.advance_pool(execution, 1).unwrap()
    is @local_veca.PoolStopped(_, ..),
  )
  assert_eq(@local_veca.cleanup_pool(execution), Ok(true))
  assert_true(@execution.producer_read_available(read))
  // One record: setup 3, three field scans 9, group/identity checks 2,
  // identity encoding 2, component validation 2, collection/scratch 2,
  // group boundaries 2, component build/fold/finish 6, output fields 3,
  // and output commit 1. The independent total is 32 control units.
  for (ceiling, accepted) in [(32, true), (31, false)] {
    let bounded = @local_veca.start_relation_pool(
      @bounded.control(),
      @execution.generated_prepared_sequence(task_test_generated(owner)),
      0,
      read,
      direct_relation_pool_limits(18, ceiling),
      4096L,
      fn() { true },
    ).unwrap()
    let mut terminal = false
    let mut charged = 0L
    for _ in 0..<40 {
      if !terminal {
        match @local_veca.advance_pool(bounded, 1).unwrap() {
          @local_veca.PoolContinue(work~, ..) => {
            assert_eq(work - charged, 1L)
            charged = work
          }
          @local_veca.PoolComplete(output, work~, ..) => {
            assert_true(accepted)
            assert_eq(work, charged)
            charged = work
            assert_true(@records.completed_storage(output) is Some(_))
            terminal = true
          }
          @local_veca.PoolFailed(@local_veca.PoolWorkLimit, work~, ..) => {
            assert_false(accepted)
            assert_eq(work, charged)
            assert_true(@local_veca.pool_cleanup_pending(bounded))
            terminal = true
          }
          _ => fail("Relation pool work boundary had another result")
        }
      }
    }
    assert_true(terminal)
    assert_eq(charged, ceiling.to_int64())
    assert_eq(@local_veca.cleanup_pool(bounded), Ok(true))
    assert_true(@execution.producer_read_available(read))
  }
}

///|
test "fused nearest charges exact Relation inputs and reclaims cancellation" {
  let candidates = direct_nearest_relation_owner(
    "[{\"id\":1,\"embedding\":[1,0]}]",
  )
  let queries = direct_nearest_relation_owner(
    "[{\"id\":10,\"embedding\":[1,0]}]",
  )
  let owner = direct_nearest_owner(
    candidates,
    queries,
    candidate_relation=true,
    query_relation=true,
  )
  let candidate_output = direct_nearest_relation_output(candidates)
  let query_output = direct_nearest_relation_output(queries)
  let generated = task_test_generated(owner)
  for (ceiling, accepted) in [(52, true), (51, false)] {
    let candidate_read = @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, candidates, candidate_output).unwrap(),
      10,
      1000,
    ).unwrap()
    let query_read = @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 1, queries, query_output).unwrap(),
      10,
      1000,
    ).unwrap()
    let control = @bounded.control()
    let execution = @local_veca.start_nearest_inputs_with_relations_control_work_limit(
      control,
      @execution.generated_completion_preparation(generated),
      @execution.generated_prepared_sequence(generated),
      0,
      @local_veca.nearest_relation_producer(candidate_read),
      @local_veca.nearest_relation_producer(query_read),
      10,
      { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
      31,
      1000,
      1000,
      [candidate_read, query_read],
      ceiling,
    ).unwrap()
    let mut terminal = false
    let mut charged = 0L
    for _ in 0..<64 {
      if !terminal {
        match @local_veca.advance_nearest(execution, 1).unwrap() {
          @local_veca.NearestContinue(work~, ..) => {
            assert_eq(work - charged, 1L)
            charged = work
          }
          @local_veca.NearestComplete(output, work~, ..) => {
            assert_true(accepted)
            assert_eq(work - charged, 1L)
            charged = work
            assert_eq(@execution.completed_row_count(output), 1)
            terminal = true
          }
          @local_veca.NearestFailed(@local_veca.NearestWorkLimit, work~, ..) => {
            assert_false(accepted)
            assert_eq(work, charged)
            assert_true(@local_veca.nearest_cleanup_pending(execution))
            terminal = true
          }
          _ => fail("fused nearest work boundary had another result")
        }
      }
    }
    assert_true(terminal)
    assert_eq(charged, ceiling.to_int64())
    assert_true(@local_veca.nearest_stopped(execution))
    assert_eq(@local_veca.cleanup_nearest(execution), Ok(true))
    assert_true(@execution.producer_read_available(candidate_read))
    assert_true(@execution.producer_read_available(query_read))
  }
  let candidate_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, candidates, candidate_output).unwrap(),
    10,
    1000,
  ).unwrap()
  let query_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 1, queries, query_output).unwrap(),
    10,
    1000,
  ).unwrap()
  assert_true(
    @local_veca.start_nearest_inputs_with_relations_control_work_limit(
      @bounded.control(),
      @execution.generated_completion_preparation(generated),
      @execution.generated_prepared_sequence(generated),
      0,
      @local_veca.nearest_relation_producer(candidate_read),
      @local_veca.nearest_relation_producer(query_read),
      10,
      { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
      30,
      1000,
      1000,
      [candidate_read, query_read],
      52,
    )
    is Err(@local_veca.NearestWorkspaceLimit),
  )
  assert_true(@execution.producer_read_available(candidate_read))
  assert_true(@execution.producer_read_available(query_read))
  let cancel_control = @bounded.control()
  let cancel_execution = @local_veca.start_nearest_inputs_with_relations_control_work_limit(
    cancel_control,
    @execution.generated_completion_preparation(generated),
    @execution.generated_prepared_sequence(generated),
    0,
    @local_veca.nearest_relation_producer(candidate_read),
    @local_veca.nearest_relation_producer(query_read),
    10,
    { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    31,
    1000,
    1000,
    [candidate_read, query_read],
    52,
  ).unwrap()
  assert_true(
    @local_veca.advance_nearest(cancel_execution, 1).unwrap()
    is @local_veca.NearestContinue(work=1L, ..),
  )
  assert_true(@bounded.request_cancel(cancel_control))
  assert_true(
    @local_veca.advance_nearest(cancel_execution, 1).unwrap()
    is @local_veca.NearestStopped(_, work=1L, ..),
  )
  assert_true(@local_veca.nearest_cleanup_pending(cancel_execution))
  assert_eq(@local_veca.cleanup_nearest(cancel_execution), Ok(true))
  assert_true(@execution.producer_read_available(candidate_read))
  assert_true(@execution.producer_read_available(query_read))
}

///|
test "nearest validates query components with an empty Vectors corpus" {
  let candidates = direct_nearest_vector_owner()
  let queries = direct_nearest_vector_owner()
  let owner = direct_nearest_owner(candidates, queries)
  let candidate_material = direct_nearest_material(candidates, [])
  let query_material = direct_nearest_material(queries, [(10.0, "[1e39,0]")])
  let candidate_view = @carrier_runtime.material_prepare_view(
    candidate_material, owner, 0, candidates,
  ).unwrap()
  let query_view = @carrier_runtime.material_prepare_view(
    query_material, owner, 1, queries,
  ).unwrap()
  run_direct_invalid_nearest_provider(owner, [
    @local_connector.managed_provider_carrier_input(candidate_view),
    @local_connector.managed_provider_carrier_input(query_view),
  ])
  assert_true(@carrier_runtime.material_available(candidate_material))
  assert_true(@carrier_runtime.material_available(query_material))
  assert_true(@carrier_runtime.reclaim_material(candidate_material))
  assert_true(@carrier_runtime.reclaim_material(query_material))
}

///|
test "nearest validates candidate components with empty Relation queries" {
  let candidates = direct_nearest_vector_owner()
  let queries = direct_nearest_relation_owner("[]")
  let owner = direct_nearest_owner(candidates, queries, query_relation=true)
  let candidate_material = direct_nearest_material(candidates, [
    (1.0, "[1e39,0]"),
  ])
  let candidate_view = @carrier_runtime.material_prepare_view(
    candidate_material, owner, 0, candidates,
  ).unwrap()
  let query_output = direct_nearest_relation_output(queries)
  let query_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 1, queries, query_output).unwrap(),
    10,
    1000,
  ).unwrap()
  run_direct_invalid_nearest_provider(owner, [
    @local_connector.managed_provider_carrier_input(candidate_view),
    @local_connector.managed_provider_relation_input(query_read),
  ])
  assert_true(@carrier_runtime.material_available(candidate_material))
  assert_true(@carrier_runtime.reclaim_material(candidate_material))
}

///|
test "registered VecA provider rejects reversed Vectors bindings" {
  let candidates = direct_nearest_vector_owner()
  let queries = direct_nearest_vector_owner()
  let owner = direct_nearest_owner(candidates, queries)
  let candidate_material = direct_nearest_material(candidates, [(1.0, "[1,0]")])
  let query_material = direct_nearest_material(queries, [(10.0, "[1,0]")])
  let candidate_view = @carrier_runtime.material_prepare_view(
    candidate_material, owner, 0, candidates,
  ).unwrap()
  let query_view = @carrier_runtime.material_prepare_view(
    query_material, owner, 1, queries,
  ).unwrap()
  let generated = task_test_generated(owner)
  let limits = dispatch_test_limits()
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let execution = @local_connector.start_managed_provider_with_inputs(
    provider,
    generated,
    [
      @local_connector.managed_provider_carrier_input(query_view),
      @local_connector.managed_provider_carrier_input(candidate_view),
    ],
    10,
    1000,
  ).unwrap()
  assert_true(
    @local_connector.advance_managed_provider(execution, 1).unwrap()
    is @local_connector.Failed(_),
  )
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
  assert_true(@carrier_runtime.material_available(candidate_material))
  assert_true(@carrier_runtime.material_available(query_material))
  assert_true(@carrier_runtime.reclaim_material(candidate_material))
  assert_true(@carrier_runtime.reclaim_material(query_material))
}

///|
test "registered VecA provider consumes Relation and Vectors inputs" {
  let candidates = direct_nearest_relation_owner(
    "[{\"id\":2,\"embedding\":[1,0]}," +
    "{\"id\":1,\"embedding\":[1,0]}," +
    "{\"id\":3,\"embedding\":[0,1]}]",
  )
  let queries = direct_nearest_vector_owner()
  let owner = direct_nearest_owner(candidates, queries, candidate_relation=true)
  let candidate_output = direct_nearest_relation_output(candidates)
  let candidate_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, candidates, candidate_output).unwrap(),
    10,
    1000,
  ).unwrap()
  let query_material = direct_nearest_material(queries, [
    (20.0, "[1,0]"),
    (10.0, "[0,1]"),
  ])
  let query_view = @carrier_runtime.material_prepare_view(
    query_material, owner, 1, queries,
  ).unwrap()
  run_direct_nearest_provider(owner, [
    @local_connector.managed_provider_relation_input(candidate_read),
    @local_connector.managed_provider_carrier_input(query_view),
  ])
  assert_true(@carrier_runtime.material_available(query_material))
  assert_true(@carrier_runtime.reclaim_material(query_material))
}

///|
test "registered VecA provider consumes Vectors and Relation inputs" {
  let candidates = direct_nearest_vector_owner()
  let queries = direct_nearest_relation_owner(
    "[{\"id\":20,\"embedding\":[1,0]}," + "{\"id\":10,\"embedding\":[0,1]}]",
  )
  let owner = direct_nearest_owner(candidates, queries, query_relation=true)
  let candidate_material = direct_nearest_material(candidates, [
    (2.0, "[1,0]"),
    (1.0, "[1,0]"),
    (3.0, "[0,1]"),
  ])
  let candidate_view = @carrier_runtime.material_prepare_view(
    candidate_material, owner, 0, candidates,
  ).unwrap()
  let query_output = direct_nearest_relation_output(queries)
  let query_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 1, queries, query_output).unwrap(),
    10,
    1000,
  ).unwrap()
  run_direct_nearest_provider(owner, [
    @local_connector.managed_provider_carrier_input(candidate_view),
    @local_connector.managed_provider_relation_input(query_read),
  ])
  assert_true(@carrier_runtime.material_available(candidate_material))
  assert_true(@carrier_runtime.reclaim_material(candidate_material))
}
