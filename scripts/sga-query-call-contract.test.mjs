import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import test from 'node:test';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

// Independent sorted JSON for these normative JSON bodies. This test does
// not import a product canonicalizer, manifest writer or compiler output.
function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value).sort().map(key =>
      `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

const cid = body => `sha256:${digest(Buffer.from(canonical(body), 'utf8'))}`;
const fileDigest = path => digest(readFileSync(path));

test('SGA query grammar pin matches an independent normative preimage', () => {
  const language = readFileSync('docs/spec/language.md', 'utf8');
  const inventory = language.split('<a id="operation-inventory"></a>')[1]
    .split('<a id="relation-operations"></a>')[0];
  const operations = inventory.split('\n').filter(line => line.startsWith('|'))
    .flatMap(line => [...line.split('|')[2].matchAll(/\[`([a-z_]+)`\]\(#[a-z-]+\)/g)]
      .map(match => match[1])).sort();
  assert.equal(new Set(operations).size, operations.length);
  // The canonical constructor replaces the retired spelling rather than
  // adding a second Graph representation to the current inventory.
  assert.equal(operations.length, 72);
  assert.ok(operations.includes('graph'));
  const protocol = read('spec/contracts/actql-protocol-schemas.json');
  const program = protocol.artifact_schemas.executable_plan.properties
    .execution_material.properties.program;
  const expression = read('spec/contracts/actql-expressions.json');
  const expressionRules = '<a id="expression-text"></a>' + language
    .split('<a id="expression-text"></a>')[1]
    .split('<a id="predicates"></a>')[0];
  const currentBody = {
    version: 'actql-grammar-manifest/0.1',
    source_grammar_cid: cid(program),
    operations,
    expression_contract_cid: cid(expression),
    expression_text_grammar_sha256: fileDigest(expression.grammar),
    expression_text_rules_sha256: digest(Buffer.from(expressionRules, 'utf8')),
    structural_text_grammar_sha256: fileDigest('spec/grammar/actql-text-0.1.ebnf'),
    structural_text_rules_sha256: fileDigest('docs/spec/structural-text.md'),
    query_text_grammar_sha256: fileDigest('spec/grammar/actql-query-0.1.ebnf'),
    query_text_rules_sha256: fileDigest('docs/spec/query-text.md'),
  };
  const manifest = read('spec/manifests/actql-grammar-0.1.json');
  const {grammar_manifest_cid: currentCid, ...currentPreimage} = manifest;
  assert.deepEqual(currentPreimage, currentBody);
  assert.equal(currentCid, cid(currentBody));
  const frozen = JSON.parse(execFileSync('git', ['show',
    'f503f2afa804a05e58ea430af1782319c007bfc9:spec/manifests/actql-grammar-0.1.json'],
  {encoding: 'utf8'}));
  const {grammar_manifest_cid: _frozenCid, ...frozenPreimage} = frozen;
  const body = {...frozenPreimage, query_text_grammar_sha256:
    '165db9942f8928d4867288e6616079844df827722d58c7481a4170b858fb6f71', query_text_rules_sha256:
    '4b2ba4eae5f58ec4834ac3fdea39df0fc636fb385baae0b1e2f5d5475bc2c966'};
  // Literal expectations bind the independent normative preimage above, not
  // generated runtime output. Label selection changes the Program schema
  // role, combined with the adopted Frontend text rules. Retain both
  // parents' historical rule digests rather than rebinding their identities.
  assert.equal(body.query_text_grammar_sha256,
    '165db9942f8928d4867288e6616079844df827722d58c7481a4170b858fb6f71');
  assert.equal(body.query_text_rules_sha256,
    '4b2ba4eae5f58ec4834ac3fdea39df0fc636fb385baae0b1e2f5d5475bc2c966');
  assert.equal(body.source_grammar_cid,
    'sha256:3b20a88d6009d131def226ea623d38cbba3c5a3929c752de85ceb6fd1ade6938');
  // Historical manifests retain the pre-alignment expression law rather than
  // being relabeled with the new shared membership meaning.
  // Retain the complete pre-typed-JSON main normative preimage.
  // Literal predecessor pins are immutable; no current runtime supplies them.
  const beforeTypedJsonBody = {"version":"actql-grammar-manifest/0.1","source_grammar_cid":"sha256:487b95656a825703baa75f2e108ac94d3d8a38fa113bb2ef12a3532cac2654ae","operations":["analytic","append","apply_graph_delta","asof_join","assert_rows","calendar_bucket","calendar_series","components","cross_join","dedupe_events","dedupe_rows","degree","derive","distinct","drop","edge_rows","events","except","filter","graft_graph","graph","graph_bounds","graph_diff","graphs_equal","group","infer","intersect","interval_join","join","json_pick","lag","match_edges","match_nodes","mean_graphs","merge_rankings","nearest","nest","node_rows","normalize_graph","normalize_vectors","pivot","pool_vectors","property_graph","reach","rename","row_window","score_vectors","search_candidates","select","sequence","serialize","session","shortest_path","sort","subgraph","subtract_graphs","take","text_rank","time_series","to_events","to_vectors","top_k","top_k_by","traverse","union_graphs","unnest","unpivot","values","vectors","watermark_events","watermark_rows","window_events","window_group"],"expression_contract_cid":"sha256:e14e1d9434909f1d0a68dc0441a6260c07476d662d237517d548de4dff0ac50f","expression_text_grammar_sha256":"af7d4d19de39d888daff8195773a8599c8246602d41e450da6975e336de96fd7","expression_text_rules_sha256":"997601c137dc1ef2d6d63585d5930aae7f5c39efb54aa56ffbe59b068e2f68c2","structural_text_grammar_sha256":"0f6a0337a350348efbe20e23fe658ce1e56297d407ba9dac3ec2eaf008849a56","structural_text_rules_sha256":"209cde18dff4cc5b8b7cdd6749a3329b0bcf6a8fe6c7243977c0c5f169e49762","query_text_grammar_sha256":"7cd11ce7c1e58b585756ef3c8ac0eb078cf2bbb7003086263f665e26251b7f0e","query_text_rules_sha256":"d91710b1985ec0156bc9ca905d0ac3d8a86eac24a99ac19a6b5755be091f6561"};
  const beforeMembershipBody = {...beforeTypedJsonBody, expression_contract_cid:
    'sha256:399d4593f8212a2239a0a3e3ca552653ad711010a180207f967cf546012fc1cb'};
  assert.equal(beforeMembershipBody.expression_contract_cid,
    'sha256:399d4593f8212a2239a0a3e3ca552653ad711010a180207f967cf546012fc1cb');
  const historicalBody = {...beforeMembershipBody, query_text_rules_sha256: 'e4639cbce44c77135b0f162475ca653b9774ef593a4c02434f6ea30b34ff2eb2'};
  assert.equal(cid({...historicalBody, source_grammar_cid:
    'sha256:50527c1472e91aa673ad57bcd43141b0e679a2de24cc6bf19efb9e8e32c2607a'}),
    'sha256:cb357b785390fb3e581a6ece8e61d49d9d93676666df77dd18a2d7f72f381bff');
  assert.equal(cid({...historicalBody, source_grammar_cid:
    'sha256:f80202113bbde534d6e2f20451da9c486092c710320c67535b4bc1c0fb513d9f'}),
    'sha256:2422e7815a6d6f6cbc2dd4289da3ba5d98eeb58545c356d45e897627e7ac3a8e');
  assert.equal(cid({...historicalBody, source_grammar_cid:
    'sha256:31be8958c4486232811be583c3674b8aacfa1cdcd300a35e12ad67dc023e1ef4'}),
    'sha256:b17d94092c747a21caea0eb25ea01d48160d3ed3cacafc0e5a6e1de79307325c');
  assert.equal(cid({...historicalBody, source_grammar_cid:
    'sha256:5cfed3155edea075796e6be985026b6f3d5b59ecc6937540d86c6af7ffc77351'}),
    'sha256:ae383655950a9e0f2d292ffd546e6bf9eb5cb1e9a9d72e86f6086bb917f681b6');
  assert.equal(cid({...historicalBody, source_grammar_cid:
    'sha256:e9b7efcdee0ef6c06bfb6cbc7805f595e030ecbd79e5afeb0ffa17b755710b7a'}),
    'sha256:caad49cf67bec4b67c2cb6beed69e7c9f71a80b19f2e8e04535d0d7f1c12cd90');
  assert.equal(cid({...beforeMembershipBody, query_text_rules_sha256:
    '803a87b786e68fe64cc79a49abe359659dc32f5373168ae868b310d2dbb47927'}),
    'sha256:d18da5382cb511e80f179cb24090bec8e6ce5db6601e1acd49727ef31bc947d7');
  assert.equal(cid({...beforeMembershipBody, query_text_rules_sha256:
    '803a87b786e68fe64cc79a49abe359659dc32f5373168ae868b310d2dbb47927',
    source_grammar_cid: 'sha256:e9b7efcdee0ef6c06bfb6cbc7805f595e030ecbd79e5afeb0ffa17b755710b7a'}),
    'sha256:4ac81bd72c110d09c286a0f2d4c5d68d4340a2e6843d75deabd8dbbd9fb26b77');
  assert.equal(cid({...beforeMembershipBody, query_text_rules_sha256:
    '54640d82b50522dd101ab384a777c316ad2227fc59cd7ea711fec1fe6d127ba0'}),
    'sha256:542afdc74f52bbb3d9fa721434c2ac54641e01995eb46abee1dbd44252898374');
  assert.equal(cid({...beforeMembershipBody, query_text_rules_sha256:
    '65b078b5222afb74121a0785ffc2f3b3acba8642dbbb67e56477cb924fe20933'}),
    'sha256:d0207424274d6a5549eff6c16cd7cfa5a1e63e66c627c23bb63f24ec82154180');
  assert.equal(cid({...beforeMembershipBody, query_text_rules_sha256:
    '65b078b5222afb74121a0785ffc2f3b3acba8642dbbb67e56477cb924fe20933',
    source_grammar_cid: 'sha256:e9b7efcdee0ef6c06bfb6cbc7805f595e030ecbd79e5afeb0ffa17b755710b7a'}),
    'sha256:37e9fadf9ae65bc194ad17b790ce208450550defcdbfb8354ef3c5c9c0cf4f6d');
  // Preserve main's node-emission profile as an independent predecessor.
  assert.equal(cid({...beforeMembershipBody, query_text_rules_sha256:
    'a303762cd3b49d16c2e40a58487db008a6ed5fb9b262518b76d3056c9abbced7'}),
    'sha256:8ac5a6bdc47a98eca02efae3ca1ceadc613bc930bb523c0013fc73a9bb81dcdc');
  // Preserve the pre-merge source profile and each adopted parent identity.
  assert.equal(cid({...beforeMembershipBody, query_text_rules_sha256:
    'e8cadac5455ca0f70f70dd7af77ca5636dad1d99bccff4d3f2e5cdd7d5f4ccab'}),
    'sha256:6eadd94b7226575a88196089cb8a63fe54e0a01630d1dfbf7252806f3474d36e');
  assert.equal(cid({...beforeMembershipBody, query_text_rules_sha256:
    '6528f75c6ecd4e3038077c5aff724f3651c23b8310232c363245774cecda6511'}),
    'sha256:eb1e2c6f90ed75c3bd443ce1a5f91097c41e13e7a6cc08ccc04bdbdf57476c10');
  assert.equal(cid({...beforeMembershipBody, query_text_rules_sha256:
    '865a688d16fef349a3dce0851dd2ba9db2117a2ab58540df24860f42fe43eda9'}),
    'sha256:064c917539e8fdbf2e0de59a9cfd553e9d645623a56d39ea710f6e2e348193c2');
  assert.equal(cid({...beforeMembershipBody, query_text_rules_sha256:
    '1591310fc6d0f8e53b01dcb646a5f22e717f53a825a00d8600c6aa3e31cb008b'}),
    'sha256:2afc5d41a26a51589b3ad3b647c08dae6ebdb8f135834c227ab97bfd6197bf8a');
  // Both merge parents retain their original normative identity inputs.
  assert.equal(cid({...beforeTypedJsonBody, query_text_rules_sha256:
    '6e19ee2d70f3c97104b0faff22b8f5d8e37ab021bff6555555bb018bac0f564a'}),
    'sha256:efd71d7d2e6495894932d871a093f184332c4c1a8f0350ad9d42d47e391176a0');
  assert.equal(cid(beforeMembershipBody),
    'sha256:cb47f1587dd7cb896f57d56d2aab4eacca6cd6fb673ab8f258b777947b142f14');
  // Preserve both parent manifests using their authored normative inputs.
  assert.equal(cid({...beforeTypedJsonBody, query_text_grammar_sha256: body.query_text_grammar_sha256, query_text_rules_sha256: '5189df0c79fa8e99c29985dbc87d3360c0338262ec38ad6401957a1a43354992'}),
    'sha256:a2fb073e8a80ea2647ac70c61b567c4ba00e692119e5bed3e389622b2920bfa7');
  assert.equal(cid({...beforeTypedJsonBody, query_text_rules_sha256: '96919df5ec9dee76c7f435ff6045b61fd85a6ac086fa047bc8e07c397dc05678'}),
    'sha256:c7db9149ce04b3f85a273f97b5e4b1647e62e352484fb56309f5a347744fe37b');
  assert.equal(cid({...beforeTypedJsonBody, query_text_rules_sha256: '307eec47455ab088c6eed268b8a48b4e32f681858a05c95f2320dbbab4250736'}), 'sha256:b43a9bd5a9e433dd164afd4760f583cee1d29e63e8eb65200dc9adbfd54bc095');
  assert.equal(cid({...beforeTypedJsonBody, query_text_grammar_sha256: body.query_text_grammar_sha256, query_text_rules_sha256: 'b12ac087aef64a20a59dc1ff0cf663372c5fe7076efc30234b1826c3f46b08b3'}), 'sha256:e36194fdba1c86643169c8f10888a05a39ecc0fea7e1189ac1dfaaf1f4ac01f0');
  assert.equal(cid(beforeTypedJsonBody),
    'sha256:cf717bd4a252742b0f29f3badb6b0bd1a876833879fc30e6fefec15f95506fb5');
  const priorTypedBody = {...beforeTypedJsonBody,
    source_grammar_cid: 'sha256:cefbc719deb477390be03d777795035462f2c8ba55352560d88ee30a74302cef',
    expression_contract_cid: 'sha256:800ab1eed12a3bcf98779493833081bc636c6ea108adbe1b57a57c01512b2f67', query_text_rules_sha256:
    '6e19ee2d70f3c97104b0faff22b8f5d8e37ab021bff6555555bb018bac0f564a'};
  assert.equal(cid(priorTypedBody),
    'sha256:e891f9c133e66fbc4649b0cea7968f431e3285fd7f265f3304701eb0110e6816');
  assert.equal(cid({...beforeMembershipBody,query_text_rules_sha256:priorTypedBody.query_text_rules_sha256}),
    'sha256:88b3e10e85fa88630900251773eb7b2fe5eb00e0714f3668843145fd82e68a8c');
  assert.equal(cid({...beforeTypedJsonBody, query_text_rules_sha256:
    '96919df5ec9dee76c7f435ff6045b61fd85a6ac086fa047bc8e07c397dc05678'}),
    'sha256:c7db9149ce04b3f85a273f97b5e4b1647e62e352484fb56309f5a347744fe37b');
  assert.equal(cid({...priorTypedBody, query_text_rules_sha256:
    'd91710b1985ec0156bc9ca905d0ac3d8a86eac24a99ac19a6b5755be091f6561'}),
    'sha256:cbf544dd2f03bbf120cb4181a861e3ee5bad66c73680414f563c13ecba2254a6');
  assert.equal(cid({...priorTypedBody, query_text_rules_sha256:
    '96919df5ec9dee76c7f435ff6045b61fd85a6ac086fa047bc8e07c397dc05678'}),
    'sha256:a5d5cf748d303dd303d92b2dede9e60d23ee5fc8439173fd916a2d8d1c702fb6');
  const expected = 'sha256:f97f4aab9869f21b5d8c75e13bed93c69fa671602020167f68eb196bc65e1ead';
  assert.equal(cid(historicalBody),
    'sha256:2a5854a264c13c65bf7c2ecbc6f59f9ec09e0c590aacc1c8aed6ec247da80067');
  assert.equal(cid({...beforeMembershipBody, query_text_rules_sha256:
    '803a87b786e68fe64cc79a49abe359659dc32f5373168ae868b310d2dbb47927',
    source_grammar_cid: 'sha256:5cfed3155edea075796e6be985026b6f3d5b59ecc6937540d86c6af7ffc77351'}),
    'sha256:d825ab855369e92f2e4da5e9af19567cdc89e431784b09d19c3b57ef2e9f301a');
  assert.equal(cid(body), expected);
  // Preserve the statistical-signature predecessor before adding union routing.
  assert.equal(cid({...beforeTypedJsonBody, query_text_grammar_sha256: '165db9942f8928d4867288e6616079844df827722d58c7481a4170b858fb6f71', query_text_rules_sha256:
    'ae044114d8ced801e803b2857da3f5055ad91308c341741fe64cdb6ab700d0b7'}),
    'sha256:cfb9547ce2d09997b65f3dc9496985e80c9e51210333b8dc7d5d911a0c3bb29d');
  // Preserve union routing before connecting binary subtraction.
  assert.equal(cid({...beforeTypedJsonBody, query_text_grammar_sha256: '165db9942f8928d4867288e6616079844df827722d58c7481a4170b858fb6f71', query_text_rules_sha256:
    'bd1e6623508c4ff49006df452a5ab4e77f74f78b19e2fd5a4ca392d7615da08a'}),
    'sha256:8cef04355f736983a0fcb4ce73551596ce04f370be0ab9c1d4400f81263842ae');
  // Retain the Graph subtraction parent's normative preimage.
  assert.equal(cid({...beforeTypedJsonBody, query_text_grammar_sha256: '165db9942f8928d4867288e6616079844df827722d58c7481a4170b858fb6f71', query_text_rules_sha256:
    'eab7d4fa147eef8d62760111ec8064eee60befb81ea4239c6ffe2161f2ac5cb2'}),
    'sha256:f6691d7e84028f06cef976870509421ba61d6f6310f7f32171f8ad5cf6ad422e');
  assert.equal(cid({...beforeTypedJsonBody, query_text_grammar_sha256: '165db9942f8928d4867288e6616079844df827722d58c7481a4170b858fb6f71',
    query_text_rules_sha256:'af2bb27cffada1e7c28c6407d82af77921f843e8e457b023442941ea6b5ebf85'}),
    'sha256:76c09e292bf9def41ddb0d40fe5bf59b60483e1a6c2ebde654a54bb3153c4ead');
  assert.equal(cid({...body, query_text_rules_sha256:
    'af2bb27cffada1e7c28c6407d82af77921f843e8e457b023442941ea6b5ebf85'}),
    'sha256:75eff2143c075f817ae4bc93022b34f3b6a84a48092cb8ec4726a42b791c5c52');
  // Preserve the exact sole-Graph predecessor rather than deriving history
  // from the current Program schema or qualified-star grammar.
  const soleGraph = {
    ...currentBody,
    source_grammar_cid: 'sha256:c6d41701c5ef0653a17d1472cfed07a657f3f655de70aa9c9a24b343fe571947',
    query_text_grammar_sha256: 'f1e8e656c38e31aefa3113f58f1e9c175b5f76f6ecd9a00e767f8f0523ea4c06',
    query_text_rules_sha256: 'e073701e0ba2126603b448877323cec95ad4955614c43b31aa8b472cf57c9619',
  };
  assert.equal(cid(soleGraph), 'sha256:3fe450061e6884fc773ecda7492de02dd27a15219a6832e8e490a096e29b1c9a');
  const currentExpected = 'sha256:efa41daa81570153a600aa1459bf498135d4ac67b1df4555651d6ff879229062';
  assert.equal(frozen.query_text_rules_sha256, '60fc20eff142de49153b71ddd2ff0a68b405ee860e2336728fecf67f69fca42a');
  assert.equal(currentBody.query_text_grammar_sha256, '7fbe8e64052773d288c04c39d3f1e6930ca43060cf1de1f01faffac5d52d7f0c');
  assert.equal(currentBody.query_text_rules_sha256, '2a53290cbfe58e8f5a9bb50066b45746ecf2f1bb6d14b15dda53318a170b55ed');
  assert.equal(cid(currentBody), currentExpected);
  const {grammar_manifest_cid, ...pinned} = read('spec/manifests/actql-grammar-0.1.json');
  assert.deepEqual(pinned, currentBody);
  assert.equal(grammar_manifest_cid, currentExpected);
  for (const field of ['query_text_grammar_sha256', 'query_text_rules_sha256']) {
    assert.notEqual(cid({...currentBody, [field]: '0'.repeat(64)}), currentExpected);
  }
});
