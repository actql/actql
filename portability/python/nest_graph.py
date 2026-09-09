"""Independent canonical nest lowering for the declared golden fixture subset.

No compiler, generated graph, JavaScript, or ActQL package is imported. Input
is authored closed local Relations, one nest, one Result, and a capacity policy.
Canonical JSON here deliberately admits only NFC strings and safe integers
(including the non-ASCII/numeric-name vectors); it is not a binary64 oracle.
"""
import copy
import hashlib
import json
import sys
import unicodedata
from pathlib import Path


def canonical(value):
    if isinstance(value, str):
        assert unicodedata.normalize("NFC", value) == value
        return json.dumps(value, ensure_ascii=False)
    if value is None or isinstance(value, bool):
        return json.dumps(value)
    if isinstance(value, int):
        assert abs(value) <= 9007199254740991
        return str(value)
    if isinstance(value, list):
        return "[" + ",".join(canonical(v) for v in value) + "]"
    if isinstance(value, dict):
        keys = sorted(value, key=lambda k: k.encode("utf-16-be"))
        return "{" + ",".join(canonical(k) + ":" + canonical(value[k]) for k in keys) + "}"
    raise ValueError("outside canonical golden value subset")


def cid(value):
    return "sha256:" + hashlib.sha256(canonical(value).encode()).hexdigest()


def seal(body, field):
    return dict(body, **{field: cid(body)})


def lower(fixture):
    program = fixture["program"]
    assert set(program) == {"version", "id", "stages", "results"}
    assert program["version"] == "actql/0.1" and len(program["stages"]) == 1
    stage = program["stages"][0]
    assert set(stage) == {"id", "inputs", "from", "steps", "results"}
    assert program["results"] == {"main": {"from": {"stage": stage["id"], "result": "main"}}}
    p = {k: v for k, v in stage.items() if k != "id"}
    assert len(p["steps"]) in [1, 2] and list(p["results"]) == ["main"]
    prefix = p["steps"][0] if len(p["steps"]) == 2 else None
    step = p["steps"][-1]
    step_path = "$.stages[0].steps[" + str(len(p["steps"]) - 1) + "]"
    config = step["nest"]
    parent, child = p["from"], config["with"]
    contracts = fixture.get("input_contracts", p["inputs"])
    child_contract = contracts[prefix["from"] if prefix else child]
    ps, cs = contracts[parent]["schema"], child_contract["schema"]
    capacity = fixture["capacity"]
    policy_cid = cid(capacity)
    expression_cid = cid(json.loads((Path(__file__).resolve().parents[2] / "spec/contracts/actql-expressions.json").read_text()))
    stage_body = dict(version="actql-stage-semantics/0.1", expression_contract_cid=expression_cid,
                      parameters={}, parameter_references=[], bindings={}, binding_references=[],
                      local_body=dict(p, effects={}))
    stage_semantics = cid(stage_body)
    template = dict(stages=[dict(id=stage["id"], stage_semantics_cid=stage_semantics,
                                after="initial", imports={})], exports=program["results"])
    program_body = dict(version="actql-program-semantics/0.1", actql_version="actql/0.1",
                        expression_contract_cid=expression_cid, parameters={}, parameter_references=[],
                        bindings={}, binding_references=[], program_template=template)
    semantics = cid(program_body)
    definition_body = dict(version="actql-program-definition/0.1", id=program["id"], program_semantics_cid=semantics)
    definition = cid(definition_body)
    steps, bindings, limits = [], [], []
    counter = 0

    def add(op, inputs, params, name=None):
        nonlocal counter
        if name is None:
            counter += 1
            name = op.lower().replace(".", "_") + "_" + str(counter)
        steps.append(dict(id=name, op=op, params=params, **{"in": inputs}))
        return name

    def witness(unit, value, role, law, source, dependencies):
        return seal(dict(version="actql-bound-witness/0.1", unit=unit, value=value,
                         role=role, law_id=law, source=source, derivation={"op": "source"},
                         dependencies=sorted(set(dependencies))), "witness_cid")

    def host(field, unit, law):
        return witness(unit, capacity[field], "host_ceiling", law,
                       dict(kind="host_policy", policy_cid=policy_cid, field=field), [policy_cid])

    def limit(subject, unit, candidates):
        candidates = sorted(candidates, key=lambda c: c["witness_cid"])
        guards = [c["value"] for c in candidates if c["role"] == "author_guard"]
        nonguards = [c["value"] for c in candidates if c["role"] != "author_guard"]
        state = "absent" if not guards else "binding" if min(guards) < min(nonguards) else "currently_non_binding"
        result = seal(dict(version="actql-resolved-limit/0.1", subject_ref=subject, unit=unit,
                           candidates=candidates, effective_max=min(c["value"] for c in candidates),
                           author_guard_binding=state, enforcement="engine_atomic", breach="fail"), "resolved_limit_cid")
        limits.append(result)
        return result

    def bind(lim, target):
        bindings.append(seal(dict(version="actql-execution-limit-binding/0.1", target=target,
                                  **{k: lim[k] for k in ["subject_ref", "unit", "effective_max", "resolved_limit_cid"]}), "binding_cid"))

    def byte_limit(node, fields):
        fields = sorted(set(fields))
        lim = limit("nest-value:" + node + ":" + canonical(fields), "bytes",
                    [host("max_nested_value_bytes", "bytes", "actql.host.nested-value-bytes")])
        bind(lim, dict(kind="aoa_output", step_id=node, fields=fields, measure="bytes"))

    col = lambda name: {"type": "col", "path": name.split(".")}
    lit = lambda value: {"type": "lit", "value": value}
    cmp = lambda left, right: dict(type="cmp", op="eq", left=left, right=right)
    if prefix:
        assert set(prefix) == {"from", "sort", "as"} and prefix["as"] == child
        add("REL.orderByStable", [prefix["from"]], {"by": [dict(field=next(iter(t)), dir=next(iter(t.values())), nulls="last") for t in prefix["sort"]]}, prefix["as"])
    def aliases(name, schema):
        mapping = {field: "__actql_nest_ref_" + str(i) for i, field in enumerate(sorted(schema))
                   if schema[field]["type"] in ["resource_ref", "artifact_ref"]}
        exprs = {alias: col(field + (".identity_cid" if schema[field]["type"] == "resource_ref" else ".artifact_ref_cid"))
                 for field, alias in mapping.items()}
        return (add("REL.derive", [name], {"exprs": exprs}) if exprs else name), mapping
    pr, pa = aliases(parent, ps)
    cr, ca = aliases(child, cs)
    pairs = [{"left": pa.get(k["left"], k["left"]), "right": ca.get(k["right"], k["right"])} for k in config["on"]]
    def join_expr(keys):
        exprs = [cmp(col("left." + k["left"]), col("right." + k["right"])) for k in keys]
        return exprs[0] if len(exprs) == 1 else {"type": "bool", "op": "and", "args": exprs}
    projection = [(field, field) if isinstance(field, str) else (next(iter(field.values())), next(iter(field))) for field in config["fields"]]
    key = child_contract.get("primary_key")
    order = copy.deepcopy(config.get("order_by", []))
    if order and not key:
        return {"error": "ACTQL_E_ORDER_REQUIRED"}
    if not order and not prefix:
        order = [{f: "asc"} for f in (key or [s for s, _ in projection])]
    elif order and key:
        order += [{f: "asc"} for f in key if f not in {next(iter(t)) for t in order}]
    candidates = [host("max_aggregate_array_items", "array_items", "actql.host.aggregate-array-items")]
    items, empty = "__actql_nest_items", "__actql_nest_empty"
    if "max_items" in config:
        candidates.append(witness("array_items", config["max_items"], "author_guard", "actql.guard.array-aggregate",
                                  dict(kind="author_guard", source_path=step_path + ".nest." + items + ".max_items", program_definition_cid=definition), [definition]))
    array_limit = limit("array_agg:" + step_path + ".nest." + items, "array_items", candidates)
    maximum = array_limit["effective_max"]
    payload = dict(type="object", fields={target: col(source) for source, target in projection})
    agg = dict(fn="array_agg", expr=payload, max_items=maximum)
    reverse = [{"left": k["right"], "right": k["left"]} for k in pairs]
    matched = add("REL.join", [cr, pr], dict(how="semi", on=join_expr(reverse), key_pairs=reverse, null_key="no_match"))
    matched = add("REL.select", [matched], {"columns": [{"from": "left." + f, "to": f} for f in sorted(cs) + list(ca.values())]})
    if order:
        matched = add("REL.orderByStable", [matched], {"by": [dict(field=ca.get(next(iter(t)), next(iter(t))), dir=next(iter(t.values())), nulls="last") for t in order]})
    grouped = add("REL.groupBy", [matched], {"by": list(dict.fromkeys(k["right"] for k in pairs)), "aggs": {items: agg}})
    byte_limit(grouped, [items])
    bind(array_limit, dict(kind="aoa_step", step_id=grouped, field_path="params.aggs." + items + ".max_items"))
    none = add("REL.where", [child], {"expr": cmp(lit(0), lit(1))})
    proof = cid(dict(version="actql-bound-proof/0.1", unit="array_items", value=1, semantic_ref=step_path + ".nest",
                     law_id="actql.bound.nest-empty-array", program_definition_cid=definition, dependencies=[]))
    empty_limit = limit("nest-empty:" + step_path, "array_items", [witness("array_items", 1, "proven_upper_bound", "actql.bound.nest-empty-array",
                         dict(kind="program", semantic_ref=step_path + ".nest", proof_cid=proof), [definition, proof])])
    singleton = add("REL.groupBy", [none], {"by": [], "aggs": {empty: dict(agg, max_items=1)}})
    bind(empty_limit, dict(kind="aoa_step", step_id=singleton, field_path="params.aggs." + empty + ".max_items"))
    joined = add("REL.join", [pr, grouped], dict(how="left", on=join_expr(pairs), key_pairs=pairs, cardinality="many_to_one", on_duplicate="fail", null_key="no_match"))
    parent_fields = sorted(ps)
    parent_columns = [{"from": "left." + f, "to": f} for f in parent_fields]
    flat = add("REL.select", [joined], {"columns": parent_columns + [{"from": "right." + items, "to": items}]})
    attached = add("REL.join", [flat, singleton], {"how": "left", "on": cmp(lit(1), lit(1))})
    flat = add("REL.select", [attached], {"columns": parent_columns + [{"from": "left." + items, "to": items}, {"from": "right." + empty, "to": empty}]})
    into = config["into"]
    filled = add("REL.derive", [flat], {"exprs": {into: {"type": "case", "when": [{"cond": {"type": "isnull", "expr": col(items)}, "then": col(empty)}], "else": col(items)}}})
    result = add("REL.select", [filled], {"columns": parent_fields + [into]}, step["as"])
    byte_limit(result, [f for f in ps if ps[f]["type"] in ["object", "array"]] + [into])
    result_key = contracts[parent]["primary_key"]
    final = add("REL.orderByStable", [result], {"by": [dict(field=f, dir="asc", nulls="last") for f in result_key]})
    pipeline = dict(version="aoa-pipeline/0.1", sources={name: {"sort": "relation"} for name in p["inputs"]}, steps=steps, output=final)
    array_schema = dict(type="array", nullable=False, max_items=maximum,
                        items=dict(type="object", nullable=False, additional_properties=False, fields={target: cs[source] for source, target in projection}))
    shapes = [dict(name=name, carrier="relation", known_fields=parent_fields+[into], fields_complete=True, schema_evidence="typed", identity_fields=result_key, stable_order=stable, role="named_result") for name, stable in [(step["as"],False),("main",True)]]
    if prefix:
        shapes.insert(0, dict(name=child, carrier="relation", known_fields=sorted(cs), fields_complete=True, schema_evidence="typed", identity_fields=key, stable_order=True, role="named_result"))
    return dict(program_definition_cid=definition, program_semantics_cid=semantics,
                stage_semantics_cid=stage_semantics,
                identity_envelopes=dict(stage=stage_body, program=program_body, definition=definition_body), pipeline=pipeline,
                aoa_logical_cid=cid(pipeline), limit_bindings=sorted(bindings,key=lambda b:b["binding_cid"]),
                resolved_limits=sorted(limits,key=lambda b:b["resolved_limit_cid"]), inferred_shapes=shapes,
                empty_array_schema=array_schema)


if __name__ == "__main__":
    print(json.dumps([lower(f) for f in json.load(sys.stdin)], ensure_ascii=False))
