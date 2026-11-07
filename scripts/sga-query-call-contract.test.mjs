import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
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

// Reconstruct from normative bytes, independently of the manifest writer.
function normativeGrammarBody(readBytes) {
  const language = readBytes('docs/spec/language.md').toString('utf8');
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
  const protocol = JSON.parse(readBytes('spec/contracts/actql-protocol-schemas.json'));
  const program = protocol.artifact_schemas.executable_plan.properties
    .execution_material.properties.program;
  const expression = JSON.parse(readBytes('spec/contracts/actql-expressions.json'));
  const expressionRules = '<a id="expression-text"></a>' + language
    .split('<a id="expression-text"></a>')[1]
    .split('<a id="predicates"></a>')[0];
  return {
    version: 'actql-grammar-manifest/0.1',
    source_grammar_cid: cid(program),
    operations,
    expression_contract_cid: cid(expression),
    expression_text_grammar_sha256: digest(readBytes(expression.grammar)),
    expression_text_rules_sha256: digest(Buffer.from(expressionRules, 'utf8')),
    structural_text_grammar_sha256: digest(readBytes('spec/grammar/actql-text-0.1.ebnf')),
    structural_text_rules_sha256: digest(readBytes('docs/spec/structural-text.md')),
    query_text_grammar_sha256: digest(readBytes('spec/grammar/actql-query-0.1.ebnf')),
    query_text_rules_sha256: digest(readBytes('docs/spec/query-text.md')),
  };
}

const sequenceSnapshotCid = 'sha256:2aa67a52bae3a27fec7397dfa40c0cdc63096cd988e7cfee480477386c53b2ec';

test('SGA query grammar pin matches an independent normative preimage', () => {
  const currentBody = normativeGrammarBody(path => readFileSync(path));
  const manifest = read('spec/manifests/actql-grammar-0.1.json');
  const {grammar_manifest_cid: currentCid, ...currentPreimage} = manifest;
  assert.deepEqual(currentPreimage, currentBody);
  assert.equal(currentCid, cid(currentBody));
  const {grammar_manifest_cid: preAbsCid, ...preAbsBody} =
    read('scripts/fixtures/pre-abs-values-identities.json').grammar;
  assert.equal(cid(preAbsBody), preAbsCid);
  // Historical manifests retain the pre-alignment expression law rather than
  // being relabeled with the new shared membership meaning.
  // Retain the complete pre-typed-JSON main normative preimage.
  // Literal predecessor pins are immutable; no current runtime supplies them.
  const beforeTypedJsonBody = {"version":"actql-grammar-manifest/0.1","source_grammar_cid":"sha256:487b95656a825703baa75f2e108ac94d3d8a38fa113bb2ef12a3532cac2654ae","operations":["analytic","append","apply_graph_delta","asof_join","assert_rows","calendar_bucket","calendar_series","components","cross_join","dedupe_events","dedupe_rows","degree","derive","distinct","drop","edge_rows","events","except","filter","graft_graph","graph","graph_bounds","graph_diff","graphs_equal","group","infer","intersect","interval_join","join","json_pick","lag","match_edges","match_nodes","mean_graphs","merge_rankings","nearest","nest","node_rows","normalize_graph","normalize_vectors","pivot","pool_vectors","property_graph","reach","rename","row_window","score_vectors","search_candidates","select","sequence","serialize","session","shortest_path","sort","subgraph","subtract_graphs","take","text_rank","time_series","to_events","to_vectors","top_k","top_k_by","traverse","union_graphs","unnest","unpivot","values","vectors","watermark_events","watermark_rows","window_events","window_group"],"expression_contract_cid":"sha256:e14e1d9434909f1d0a68dc0441a6260c07476d662d237517d548de4dff0ac50f","expression_text_grammar_sha256":"af7d4d19de39d888daff8195773a8599c8246602d41e450da6975e336de96fd7","expression_text_rules_sha256":"997601c137dc1ef2d6d63585d5930aae7f5c39efb54aa56ffbe59b068e2f68c2","structural_text_grammar_sha256":"0f6a0337a350348efbe20e23fe658ce1e56297d407ba9dac3ec2eaf008849a56","structural_text_rules_sha256":"209cde18dff4cc5b8b7cdd6749a3329b0bcf6a8fe6c7243977c0c5f169e49762","query_text_grammar_sha256":"7cd11ce7c1e58b585756ef3c8ac0eb078cf2bbb7003086263f665e26251b7f0e","query_text_rules_sha256":"d91710b1985ec0156bc9ca905d0ac3d8a86eac24a99ac19a6b5755be091f6561"};
  // The public pre-sole-Graph normative inputs retain these four differences
  // from the literal above; no current manifest or product supplies them.
  const frozenPreimage = {...beforeTypedJsonBody,
    source_grammar_cid: 'sha256:3b20a88d6009d131def226ea623d38cbba3c5a3929c752de85ceb6fd1ade6938',
    expression_contract_cid: 'sha256:800ab1eed12a3bcf98779493833081bc636c6ea108adbe1b57a57c01512b2f67',
    query_text_grammar_sha256: 'efdf8fd75b20465b57f66ea6db8f6e662441387c4d24ee055d5256160a040e7a',
    query_text_rules_sha256: '60fc20eff142de49153b71ddd2ff0a68b405ee860e2336728fecf67f69fca42a'};
  assert.equal(cid(frozenPreimage),
    'sha256:e8cb271a8e74c8900258d53c9443bbc6bb78694b313a282a1f2807b3ca5137d5');
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
    ...preAbsBody,
    source_grammar_cid: 'sha256:c6d41701c5ef0653a17d1472cfed07a657f3f655de70aa9c9a24b343fe571947',
    query_text_grammar_sha256: 'f1e8e656c38e31aefa3113f58f1e9c175b5f76f6ecd9a00e767f8f0523ea4c06',
    query_text_rules_sha256: 'e073701e0ba2126603b448877323cec95ad4955614c43b31aa8b472cf57c9619',
  };
  assert.equal(cid(soleGraph), 'sha256:3fe450061e6884fc773ecda7492de02dd27a15219a6832e8e490a096e29b1c9a');
  const beforeSchemaClosure = {...preAbsBody,
    source_grammar_cid: 'sha256:c6d41701c5ef0653a17d1472cfed07a657f3f655de70aa9c9a24b343fe571947',
    query_text_grammar_sha256: '446694190a1e5c1412db556a0a1f7bbff024ba08b3d6edfae56a8c461c4f93bd',
    query_text_rules_sha256: '8f25caaec8d851767a09937831cd91aac30f48fad99f2851c7dddbfcc5095d14'};
  assert.equal(cid({...beforeSchemaClosure,
    query_text_grammar_sha256: '7fbe8e64052773d288c04c39d3f1e6930ca43060cf1de1f01faffac5d52d7f0c',
    query_text_rules_sha256: '2a53290cbfe58e8f5a9bb50066b45746ecf2f1bb6d14b15dda53318a170b55ed'}),
    'sha256:1e69c47a6aba9a6bc728c10d4edbeeb1e72964e0504d82d7f54fde65293de06a');
  assert.equal(cid(beforeSchemaClosure),
    'sha256:57b2c75f3483e89a325a216c10636c5f098d8b09d190f7ce11b0895f1ac7c09a');
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: '7fbe8e64052773d288c04c39d3f1e6930ca43060cf1de1f01faffac5d52d7f0c',
    query_text_rules_sha256: '2a53290cbfe58e8f5a9bb50066b45746ecf2f1bb6d14b15dda53318a170b55ed'}),
    'sha256:efa41daa81570153a600aa1459bf498135d4ac67b1df4555651d6ff879229062');
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: '446694190a1e5c1412db556a0a1f7bbff024ba08b3d6edfae56a8c461c4f93bd',
    query_text_rules_sha256: '8f25caaec8d851767a09937831cd91aac30f48fad99f2851c7dddbfcc5095d14'}),
    'sha256:ebd855090f5f4695042910f4f0471a460929aeb4e26de36609b965b6c4623922');
  // Retain both QUALIFY predecessor preimages before combining RIGHT JOIN.
  const qualifyPredecessor = {...preAbsBody,
    query_text_grammar_sha256: '67ed2926780d3365eb2f553d88918cf7fcc99a922e9f6af7477d19fa211c1b52',
    query_text_rules_sha256: 'c0040e451571db4605aa616c148798413d07dfc834e5ee252addc8f5155c012d'};
  assert.equal(cid(qualifyPredecessor), 'sha256:3d5a575c2ca9885b0a8d0f24c8fe9cbb08dd1c2ce923937c36d7db576ea7361f');
  assert.equal(cid({...qualifyPredecessor,
    source_grammar_cid: 'sha256:c6d41701c5ef0653a17d1472cfed07a657f3f655de70aa9c9a24b343fe571947'}),
    'sha256:bec586d9fa597461b69570df1287e9a30f5c46772f4d29a7ab0e65efcb013429');
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: 'eaf5f1daf3c35ac62831f2ba92010aa047700bfef5435b1dcecec30818f6696a',
    query_text_rules_sha256: '4b2ffdf0c184c931a4d87738435532a42290d9af03e888706c5703fd78e13cf6'}),
    'sha256:436d5d5ed652cbdf5b1ddc22c50de549bcf57241022d6a0bc4b1636aa8dd61bb');
  // Named WINDOW and merged QUALIFY/RIGHT JOIN retain separate predecessor preimages.
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: '58f8fd3ce72b47ad9a6029e74ca3501646eeafb01b6509ceaea1d7bb6b62f022',
    query_text_rules_sha256: '713a059c6a666895bbef616426e0d57d61194417a12cd23b0723d6472e91c66b'}),
    'sha256:313692ca4371f8802b8593c0feae61a7ed43836dd36cefe379a6b187ecf1cb0a');
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: 'eec0bc3d94b6b54cd58ccc71d3801cb915b1c6dcf3b61ae75448984accc42bc2',
    query_text_rules_sha256: '9c44ff3295dc62f766a6752a00cc427b439f107493f4338d8fc602d5b4b10611'}),
    'sha256:edf8426fd0a6448c628b1681bbb00ff99542057cb1346d6b85d67869e0720fa0');
  // Preserve the reviewed WINDOW/QUALIFY/JOIN-star preimages.
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: '0b961eacd150b63d3abb62fb974eda40310ed39e0406faf73e18f52a0bf01eb5',
    query_text_rules_sha256: '3d73570fdf8243e613f9ec554225f445e6df5a0051bba2739467c00697cbc4f2'}),
    'sha256:4a4edbe3ea73b23bebe2220bed00e52a41797a81d781020a5f3522d2e7e54c53');
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: 'eec0bc3d94b6b54cd58ccc71d3801cb915b1c6dcf3b61ae75448984accc42bc2',
    query_text_rules_sha256: '78db317bfc2ece17f8343e4141c2b9fd5dca2ff6bf0ffc2229e2386cc5f5a20f'}),
    'sha256:b61090c3267de06917642327d2f3acce9bb2a5a419de2279e994644ec77e3f63');
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: 'eaf5f1daf3c35ac62831f2ba92010aa047700bfef5435b1dcecec30818f6696a',
    query_text_rules_sha256: '4e05cc33de7da0c3d38727908d969a015db00acfbc5ffbbc7df0fe5b54c27678'}),
    'sha256:6788acd1b4d3d2771311442d3ddbf881680d319c79cb0ebe46e4f333341c2835');
  // Retain complete predecessor bytes rather than reusing the new edge grammar.
  const beforeAnyDirection = {...preAbsBody,
    query_text_grammar_sha256: '0b961eacd150b63d3abb62fb974eda40310ed39e0406faf73e18f52a0bf01eb5'};
  assert.equal(cid({...beforeAnyDirection,
    query_text_rules_sha256: 'cdaef72756f3e36f2e1603ba8c02b6fb16772be1a1cbcdc19bfd5df837135e39'}),
    'sha256:1995b1527e69dfc30daff86098b01d0fcef393d703c58e4fbf4f6fa980bf890c');
  assert.equal(cid({...beforeAnyDirection,
    query_text_rules_sha256: '3b07aa84502eaf96081dbadc38eaa73324e7fa648d4d056c8d69adc19c52b0e2'}),
    'sha256:a395e9d881fd75019ff99db18016a4cf72f19f14f52856b8f313462e0489c09a');
  assert.equal(cid({...beforeAnyDirection,
    query_text_rules_sha256: 'c0c91e6b436646fb05e0e22d29ae3e05dbe6f7be451cf069cc807f479177ca3c'}),
    'sha256:675ce07e2792ad6736f526ffb894e987463ff1eee7f94dfd8e391bcfbfc3dd20');
  // Freeze the complete full-edge predecessor before adding abbreviations.
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: 'c7f9802419d92bf1f53ee28edf277d9ed8b5f628733d78355d54c448fc106c98',
    query_text_rules_sha256: 'f0b099fa9773e872b430f691cfe54523e74f5ef8bd1da352d9ab41acd763fb50'}),
    'sha256:3766a009afd7d8e22904ace1507becb871c62c5fb0dd969f7ee0886c17892c55');
  // Keep the ARRAY constructor profile's exact normative predecessor.
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: '2023c8b252f362a5233ba8a9eb08c1765e9770e70249e52dde81e826654abb58',
    query_text_rules_sha256: 'd7c0e3eb9184cb53c37ea0640dffb1492d07baa184c2f255a4ea5e72d77013ee'}),
    'sha256:eb7c8d7239e90b612a3bca095d29d74a828e47187609a893ff4d7406ac6512a6');
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: '2023c8b252f362a5233ba8a9eb08c1765e9770e70249e52dde81e826654abb58',
    query_text_rules_sha256: 'd89b03d3746695b09c641b9200458e9c352c1b34138b3a4adf198ba366f7604f'}),
    'sha256:4ce6abb00008cc0752dda4797487ef815287e30d21bc6e1ae5fca3941f7005a9');
  // Retain the abbreviated-edge grammar before connecting finite bound forms.
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: '5f0a569b54a83d942d0e9f686a1f58881f91f007a024edb20ceab14890ab1941',
    query_text_rules_sha256: 'bd2c35846681c920ee1d402566aa53e38d6372d20d9cbffa585003ad3eda9b74'}),
    'sha256:e855c6be158d29cc88c3e1e7fd01eb1940cbc6a1301c49414fbe024c20a4bea3');
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: '6b4d8903da723dbb5cc57f9d7a472701d853393771c995fbb84a05b2feb553a9',
    query_text_rules_sha256: '21b55f49ca04705e30d2c3d0600e3d2f4c14c7dec534b7dfa85350c8def3e789'}),
    'sha256:3fe077253a1f7ec230316eb1d6cca21d464c5292ea63f95f19ca53052b03ee9f');
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: 'd321f2a0709aace01b032d25e6697ed4fdc3f6ca6aed7fec2ebabeba551febff',
    query_text_rules_sha256: '40e119d1a33b72c82cdccbd90c7042bfe3593313f35d503998fdffa95660ee26'}),
    'sha256:883c032ce81e5a9f4a192a1d3c5af36bfa48a3d108945f832d9e1c4e7c13b135');
  // Preserve the integrated ARRAY/finite Graph normative predecessor.
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: '987ab8dafe80bd6765856455245ff30525b2041b4e246fd20d16b076b0f74cca',
    query_text_rules_sha256: '7c1751cd8cd3d3ddde325ba408ad8be6f4578f785496a7c89c234522e3264e4d'}),
    'sha256:422c4edd4dd34bbf715e3d464a07f8654e51af7bf5bba74c93a13aa6de999968');
  // Preserve complete adopted predecessors before allowing grouping-only Pipe.
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: '987ab8dafe80bd6765856455245ff30525b2041b4e246fd20d16b076b0f74cca',
    query_text_rules_sha256: '722518b9ac8b39ab39ffc061657b32140de92b862fe04768908cdbb114c6e24a'}),
    'sha256:383eb60f32169402f128cb1e0187b8445ebb33931e75ab035e20d1e434b52ad4');
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: '464206b5055bab14262fd3af69a888df04ce5e67e85ba675185c1e398d5568eb',
    query_text_rules_sha256: '0069325d73a38ed716c361d1abd4409bf422a89100f5745166e2249b333ea380'}),
    'sha256:e14a88db3f98d88cb24edefca31ecd1c0d63f81e152a61d464756a83c5850329');
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: 'bc34b24a8a8ed39ecc61473e0d3aafc8b5b2541c70951d75b95707039fe5eb5a',
    query_text_rules_sha256: '474b4b442d4b486097278d9a0d91c0c670c943f302b7e3a882c332398cd49b1e'}),
    'sha256:bb311179f5afee3d6e03181b66113f045cbd6190ce4174b32d40ac9a67459a8d');
  // Retain the complete grouping-output-alias normative predecessor.
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: '6d6dcbc805bc916f9ed1ced0a0fc1d7c52d5d763b9ee51ba5a81e4c2c605b9a4',
    query_text_rules_sha256: '154069abe470214f5e51f0a9b960e09eefffb8932327eeb52774c658caaea18b'}),
    'sha256:4ac55d221c3878197277681acc425497bc6705a864745d4ae004bbcc17915444');
  // Retain the shorthand-ordering normative predecessor.
  assert.equal(cid({...preAbsBody, query_text_grammar_sha256: '6f25704123fd2d1fd4ee3a7fd57d4d7d2502b76994743edbc6322de0e54641ca', query_text_rules_sha256:
    '0c288ee063666d6e529fa354ded3539b32556d65e425a40ce05657b9740376e3'}),
    'sha256:fc3d401cf6db3bf3349114cc019111bbc32a112317d1e397b9573776d9ee7d6b');
  // Retain the scalar Pipe aggregate normative predecessor.
  assert.equal(cid({...preAbsBody, query_text_grammar_sha256: '6f25704123fd2d1fd4ee3a7fd57d4d7d2502b76994743edbc6322de0e54641ca', query_text_rules_sha256:
    'f5f1f5767586ab84b569d4d3126ada4c36e0ae244dbf33c41a46d800cab922fa'}),
    'sha256:2a433f295994301675ad42d4acc1859474b8e0e31b3583482f057602164c8951');
  // Keep the complete grammar closure before single-boundary ROWS frames.
  assert.equal(cid({...preAbsBody,
    query_text_grammar_sha256: '6f25704123fd2d1fd4ee3a7fd57d4d7d2502b76994743edbc6322de0e54641ca',
    query_text_rules_sha256: '13238f8dccbc99f4244427ac8362ee093307ceff6151f6116638b44b1fb0c885'}),
    'sha256:582ecd6f94df7584160874befda4fa5f2a7d028f347599fc11e9685c10ba36e8');
  // Each parent's full normative preimage retains its original identity.
  assert.equal(cid({...preAbsBody, query_text_grammar_sha256:
    'f503d7097c17b26ce592fe87357441f6ea86420478f2a3e66b4fa765aa051fd8',
    query_text_rules_sha256: '27fe4f563feb13443d7995f51f770399019e9645cbbc5a3105e0d0c48f870c73'}),
    'sha256:de630432fb2b6f3700294801070100e3340fc6ad295c2671fe9c0b3222f16169');
  assert.equal(cid({...preAbsBody, query_text_grammar_sha256:
    '6f25704123fd2d1fd4ee3a7fd57d4d7d2502b76994743edbc6322de0e54641ca',
    query_text_rules_sha256: '4c6e449ca893a50395143e5c1f54acb14251aacdde816f5df74f66ff4816bd60'}),
    'sha256:ba59c48eb915694484664a7daf7f839e492c36eae44137993f39130793c59672');
  assert.equal(preAbsCid, "sha256:440dfe0c1508b744e4ce22e6729dc362678785119932aa142aba313dc57b8680");
  // Preserve the submitted ABS parent's full normative grammar independently.
  const {grammar_manifest_cid: submittedCid, ...submittedBody} =
    read('scripts/fixtures/submitted-abs-values-identities.json').grammar;
  assert.equal(cid(submittedBody), submittedCid);
  assert.equal(submittedCid, 'sha256:0325886c76522de57048ef35ac3abb43e843e418d92c3b3d40e73a6d5c669222');
  const {grammar_manifest_cid: objectStarCid, ...objectStarBody} =
    read('scripts/fixtures/submitted-object-star-grammar.json').grammar;
  assert.equal(cid(objectStarBody), objectStarCid);
  assert.equal(objectStarCid, 'sha256:f403b42dd4a19e8a22629ba7f14f6bb6de754490194277e4f083ae0f08515bb5');
  assert.equal(cid({...objectStarBody,
    query_text_rules_sha256: '4833bf1144ceea372ce4b95c0ec78ea1aceb473a83dab930bcebb1cb42fe8d12'}),
    'sha256:4943caba75b011ab9aebfc07d4f30ea4a5aefa72c50bc2eab44724cc3e6aaff9');
  // Preserve both complete merge parents before composing their text rules.
  const {grammar_manifest_cid: computedCid, ...computedBody} =
    read('scripts/fixtures/submitted-computed-star-grammar.json').grammar;
  assert.equal(cid(computedBody), computedCid);
  assert.equal(computedCid, 'sha256:5e830a0888c0b5d8f3d1d65dbfb84825c50da8071bb697f97df667c27cadc979');
  const {grammar_manifest_cid: integratedCid, ...integratedBody} =
    read('scripts/fixtures/integrated-object-star-grammar.json').grammar;
  assert.equal(cid(integratedBody), integratedCid);
  assert.equal(integratedCid, 'sha256:aa72c07d6ede6683c451532f247b661fe5c440723625d79302c5c65cf4537216');
  assert.equal(cid({...integratedBody,
    query_text_rules_sha256: 'f04041e8cb9706ee535612f3f2e51f7b732e4fb5f9ac7f76836f82645262c749'}),
    'sha256:ad974dd510c1491960ebc6c86b0c426fecf6874895e4a0dc00ce07e714e145dc');
  // Preserve the pre-correction manifest: only the source grammar changes
  // when pivot.fill returns to its normative whole-value CellValue grammar.
  const beforePivotCellBody = {...integratedBody,
    query_text_grammar_sha256: '1f305f648cef0e06a22e42d2ad95a09b00596e84344f4c5899f4d72c71e068db',
    query_text_rules_sha256: '831de7808000326fdc2e0fe4d8b6224d7bc34495692455e6ff4f85aa026df10a'};
  assert.equal(cid(beforePivotCellBody),
    'sha256:a85a3517afd7a705e99e746f5a08332370b072ddc77868372db19b977ee87ecb');
  assert.equal(cid({...beforePivotCellBody, source_grammar_cid:
    'sha256:21bae76f36b9428995aba44017787ee327786a741db006ca952404253a409810'}),
    'sha256:30e6c2f83ccbeb15f883b544eb6930c305c04f8615a5ddc9c3bf72e48e60c59e');
  const {grammar_manifest_cid: beforeJoinCid, ...beforeJoinBody} =
    read('scripts/fixtures/pre-unnest-join-grammar.json').grammar;
  assert.equal(cid(beforeJoinBody), beforeJoinCid);
  assert.deepEqual(beforeJoinBody, beforePivotCellBody);
  const {grammar_manifest_cid: upstreamCid, ...upstreamBody} =
    read('scripts/fixtures/pre-b408-spec-repair-values-identities.json').upstream.grammar;
  assert.equal(cid(upstreamBody), upstreamCid);
  assert.equal(upstreamCid, 'sha256:62780078db668a0488bde0f683d6de3f2e15aa04875aa8593c64d60d7c187cf0');
  // Preserve the adopted manifest, then bind the actual b408 source bytes.
  // Its later query-text clarification changed the normative rules digest.
  assert.equal(upstreamBody.query_text_rules_sha256,
    'ede6d8449c25ed883ac9fe9eff46670655bb5212f548a3097e230d73394304ad');
  const {grammar_manifest_cid: beforeInnerCid, ...beforeInnerBody} =
    read('scripts/fixtures/pre-inner-unnest-grammar.json').grammar;
  assert.deepEqual(beforeInnerBody, {...upstreamBody, source_grammar_cid:
    'sha256:21bae76f36b9428995aba44017787ee327786a741db006ca952404253a409810',
    query_text_rules_sha256:
      'afe794150902368b6fc874ec462122400599ba4cda046899b991ab5c38f9477e'});
  assert.equal(beforeInnerCid, 'sha256:27ebfa9f22860ffcf7d16c15199c95cd41952579720e27b16b715fa5d5b0f18c');
  assert.equal(cid(beforeInnerBody), beforeInnerCid);
  const {grammar_manifest_cid: beforeExtendCid, ...beforeExtendBody} =
    read('scripts/fixtures/pre-pipe-extend-window-grammar.json').grammar;
  assert.equal(beforeExtendCid, 'sha256:6c736875bc97084060934856c845f467405e231cdd8971494e8d0934c043b18b');
  assert.equal(cid(beforeExtendBody), beforeExtendCid);
  assert.deepEqual(beforeExtendBody, {...beforeInnerBody,
    query_text_grammar_sha256: 'e0565d4c5c3d038b4f7ec38718e95725819772e4558de38144ed9206fbaccb04',
    query_text_rules_sha256: '48a784c862cdb3eac61e12a34ac9c19c79a3001a2b00a2bb0bc15591a89cfacb'});
  const {grammar_manifest_cid: beforePipeSelectCid, ...beforePipeSelectBody} =
    read('scripts/fixtures/pre-pipe-select-window-grammar.json').grammar;
  assert.equal(beforePipeSelectCid, 'sha256:2d24701e5ceee0f06400e197124eb7d9c05b74b88de7bd76500820b04fe692ed');
  assert.equal(cid(beforePipeSelectBody), beforePipeSelectCid);
  assert.deepEqual(beforePipeSelectBody, {...beforeExtendBody,
    query_text_grammar_sha256: 'eca5ea6807104e1c8fd74213c468e6e2b147c02f70e348b4ace778c788b10065',
    query_text_rules_sha256: 'd99c8079d21f7648cfa8e8fb1273b62cac28c05740b727769aa744ed8be052e2'});
  const {grammar_manifest_cid: beforeWhereCid, ...beforeWhereBody} =
    read('scripts/fixtures/pre-pipe-where-window-grammar.json').grammar;
  assert.equal(beforeWhereCid, 'sha256:621f06cc9ffc651a0d68da0b7994163bef2439b4b72a8608ccc480622e4c67d9');
  assert.equal(cid(beforeWhereBody), beforeWhereCid);
  assert.deepEqual(beforeWhereBody, {...beforePipeSelectBody,
    query_text_grammar_sha256: '2e71420d022a4de524c95545b1dd8525062a3d456e98efeb3fd9275777ac6b71',
    query_text_rules_sha256: '41dd912f04bb6fc837c70a023a2666733bda1d36eefad64f00439ca07c061126'});
  const {grammar_manifest_cid: beforeSetCid, ...beforeSetBody} =
    read('scripts/fixtures/pre-pipe-set-window-grammar.json').grammar;
  assert.equal(beforeSetCid, 'sha256:e0ad6a5fa648e290e490096887361d02e7a9b223c1d6a267646c6974a874d832');
  assert.equal(cid(beforeSetBody), beforeSetCid);
  assert.deepEqual(beforeSetBody, {...beforeWhereBody,
    query_text_grammar_sha256: '313d0a8950a653bd56a93f15877e70bef9137526cec0b0b0bd42e0dc8aa09d95',
    query_text_rules_sha256: '909f6396526d846fa687b8e4b456f10aa5c25d4b0ad5914c2d9a7f4992e9d3ad'});
  const beforeAs = read('scripts/fixtures/pre-value-table-as-grammar.json').grammar;
  const {grammar_manifest_cid: beforeAsCid, ...beforeAsBody} = beforeAs;
  assert.equal(cid(beforeAsBody), beforeAsCid);
  assert.equal(beforeAsCid, 'sha256:c4364e9947c8d6c7538d9245fca2da3fc0cd44bd70caceff58862ba9629c90d6');
  assert.deepEqual(beforeAsBody, {...beforeSetBody,
    query_text_grammar_sha256: 'd81bb2648d3c74bba4fcad4e5243e25572c63b392195cb152552f0dbff34e148',
    query_text_rules_sha256: 'e2db699ca728c632a34e1e4686a492a5570760c718e10e58b7e9d49bcb3648d9'});
  // Retain the former fixed body under its own historical closure.
  const oldFixed = read('scripts/fixtures/pre-zero-rows-boundary-values-identities.json').grammar;
  const {grammar_manifest_cid: oldFixedCid, ...oldFixedBody} = oldFixed;
  assert.equal(oldFixedCid, 'sha256:b88867a4416267a08d51e0e6e8b0b6f415ca9479d2be647ded3dd701e07e24c7');
  assert.equal(cid(oldFixedBody), oldFixedCid);
  const previousWith = read('scripts/fixtures/pre-with-graph-range-alias-values-identities.json').grammar;
  const {grammar_manifest_cid: previousWithCid, ...previousWithBody} = previousWith;
  assert.equal(cid(previousWithBody), previousWithCid);
  assert.equal(previousWithCid, 'sha256:c74b336ae4363e26b12e7af399b46791ce463755f66e47f12f557d1e7e72eab8');
  // Keep the submitted SGA closure under its original identity. Later window,
  // watermark and dedupe connections change the current normative preimage.
  const {grammar_manifest_cid: submittedSgaCid, ...submittedSgaBody} =
    read('scripts/fixtures/submitted-sga-signature-role-values-identities.json').grammar;
  assert.equal(cid(submittedSgaBody), submittedSgaCid);
  assert.equal(submittedSgaCid,
    'sha256:7c9347a89c7a097c608edbbd162631a438cd49e7e6822ac4d2a5dc800bf625eb');
  // Retain the pre-Lag body under its original identity. The adopted named
  // Lag surface changes only the two normative query-text digests.
  const {grammar_manifest_cid: beforeLagCid, ...beforeLagBody} =
    read('scripts/fixtures/pre-lag-values-identities.json').grammar;
  assert.equal(beforeLagCid,
    'sha256:255ae7c2de7279c3924f3f72fbdc7303ef0fc02af42064393f646068b2f8e992');
  assert.equal(cid(beforeLagBody), beforeLagCid);
  const {grammar_manifest_cid: submittedLagCid, ...submittedLagBody} =
    read('scripts/fixtures/submitted-lag-values-identities.json').grammar;
  const submittedLagExpected = 'sha256:3594d643035dbef8de5da40d88d007b9a88e1f438ade3575ffcf7c1db314a2f7';
  assert.equal(submittedLagCid, submittedLagExpected);
  assert.equal(cid(submittedLagBody), submittedLagExpected);
  assert.deepEqual(submittedLagBody, {...beforeLagBody,
    query_text_grammar_sha256: submittedLagBody.query_text_grammar_sha256,
    query_text_rules_sha256: submittedLagBody.query_text_rules_sha256});
  const nearest = read('scripts/fixtures/submitted-nearest-carrier-values-identities.json').grammar;
  const {grammar_manifest_cid: nearestCid, ...nearestBody} = nearest;
  assert.equal(cid(nearestBody), nearestCid);
  const {grammar_manifest_cid: continuationCid, ...continuationBody} = read('scripts/fixtures/submitted-nearest-continuation-values-identities.json').grammar;
  assert.equal(cid(continuationBody), continuationCid);
  assert.deepEqual(continuationBody, {...nearestBody,query_text_rules_sha256:continuationBody.query_text_rules_sha256});
  const {grammar_manifest_cid: joinCid, ...joinBody} = read('scripts/fixtures/submitted-nearest-join-values-identities.json').grammar;
  assert.equal(cid(joinBody), joinCid);
  assert.deepEqual(joinBody, {...continuationBody,query_text_rules_sha256:joinBody.query_text_rules_sha256});
  // Original Sequence grammar is immutable evidence; current merged input is separate.
  const {grammar_manifest_cid: sequenceCid, ...sequenceBody} = read('scripts/fixtures/submitted-sequence-values-identities.json').grammar;
  assert.equal(cid(sequenceBody), sequenceCid);
  assert.equal(sequenceBody.query_text_grammar_sha256, fileDigest('reviews/2026-10-12-frontend-sequence-predicate-ast/preimages/submitted-query-grammar.ebnf'));
  assert.equal(sequenceBody.query_text_rules_sha256, fileDigest('reviews/2026-10-12-frontend-sequence-predicate-ast/preimages/submitted-query-rules.md'));
  const {grammar_manifest_cid: retainedSequenceCid, ...retainedSequenceBody} =
    read('scripts/fixtures/pre-query-rules-repair-values-identities.json').grammar;
  assert.equal(cid(retainedSequenceBody), retainedSequenceCid);
  // This retained full preimage is independent of the current normative inputs.
  // Current rules remain checked against currentBody above.
  assert.equal(retainedSequenceCid, sequenceSnapshotCid);
  const {grammar_manifest_cid: seriesCid, ...seriesBody} = read('scripts/fixtures/submitted-time-series-primary-values-identities.json').grammar;
  assert.equal(cid(seriesBody), seriesCid);
  assert.deepEqual(seriesBody, {...joinBody,query_text_grammar_sha256:seriesBody.query_text_grammar_sha256,query_text_rules_sha256:seriesBody.query_text_rules_sha256});
  // The submitted time-series unit keeps its own authored grammar inputs.
  // Later Content/FILES contracts and the combined current grammar remain independent.
  assert.equal(seriesBody.query_text_grammar_sha256,
    fileDigest('reviews/2026-10-12-frontend-time-series-primary/preimages/submitted-query-grammar.ebnf'));
  assert.equal(seriesBody.query_text_rules_sha256,
    fileDigest('reviews/2026-10-12-frontend-time-series-primary/preimages/submitted-query-rules.md'));
  // The temporal unit also retains its complete authored normative inputs.
  const {grammar_manifest_cid: temporalCid, ...temporalBody} = read('scripts/fixtures/submitted-temporal-join-values-identities.json').grammar;
  assert.equal(cid(temporalBody), temporalCid);
  const {grammar_manifest_cid: preTemporalCid, ...preTemporalBody} = read('scripts/fixtures/pre-temporal-join-values-identities.json').grammar;
  assert.equal(cid(preTemporalBody), preTemporalCid);
  assert.deepEqual(temporalBody, {...preTemporalBody, query_text_grammar_sha256: temporalBody.query_text_grammar_sha256, query_text_rules_sha256: temporalBody.query_text_rules_sha256});
  assert.equal(temporalBody.query_text_grammar_sha256,
    fileDigest('reviews/2026-10-12-frontend-temporal-join-calls/preimages/submitted-query-grammar.ebnf'));
  assert.equal(temporalBody.query_text_rules_sha256,
    fileDigest('reviews/2026-10-12-frontend-temporal-join-calls/preimages/submitted-query-rules.md'));
  // Ranking syntax retains its own original complete contract closure.
  const {grammar_manifest_cid: rankingCid, ...rankingBody} = read('scripts/fixtures/submitted-ranking-fusion-values-identities.json').grammar;
  const {grammar_manifest_cid: preRankingCid, ...preRankingBody} = read('scripts/fixtures/pre-ranking-fusion-values-identities.json').grammar;
  assert.equal(cid(preRankingBody), preRankingCid);
  assert.equal(cid(rankingBody), rankingCid);
  assert.deepEqual(rankingBody, {...preRankingBody, query_text_grammar_sha256: rankingBody.query_text_grammar_sha256, query_text_rules_sha256: rankingBody.query_text_rules_sha256});
  assert.equal(rankingBody.query_text_grammar_sha256,
    fileDigest('reviews/2026-10-12-frontend-ranking-fusion-calls/preimages/submitted-query-grammar.ebnf'));
  assert.equal(rankingBody.query_text_rules_sha256,
    fileDigest('reviews/2026-10-12-frontend-ranking-fusion-calls/preimages/submitted-query-rules.md'));
  assert.deepEqual(nearestBody, {...submittedLagBody,
    query_text_grammar_sha256: nearestBody.query_text_grammar_sha256,
    query_text_rules_sha256: nearestBody.query_text_rules_sha256});
  assert.equal(frozenPreimage.query_text_rules_sha256, '60fc20eff142de49153b71ddd2ff0a68b405ee860e2336728fecf67f69fca42a');
  assert.equal(beforeInnerBody.query_text_grammar_sha256, '1f305f648cef0e06a22e42d2ad95a09b00596e84344f4c5899f4d72c71e068db');
  assert.equal(preAbsBody.query_text_rules_sha256, "f61c39b0d6160f2a16d70100ce389b698f1c415021a6dcb18ff36dff05d39e33");
  assert.equal(beforeInnerBody.query_text_rules_sha256, "afe794150902368b6fc874ec462122400599ba4cda046899b991ab5c38f9477e");
  assert.equal(cid(currentBody), currentCid);
  // Preserve the complete predecessor before adding a numeric type alias.
  const {grammar_manifest_cid: beforeDoubleCid, ...beforeDoubleBody} =
    read('scripts/fixtures/pre-double-type-alias-grammar.json').grammar;
  assert.equal(cid(beforeDoubleBody), beforeDoubleCid);
  assert.equal(beforeDoubleCid, 'sha256:f57132973b7e2bca2462607971e6ef8ab3529e3bf18b295f723a185120163e44');
  assert.deepEqual(beforeDoubleBody, {...beforeAsBody,
    query_text_rules_sha256: '8958d366842376934093b9eb2819fe8f95ffa6ac389f0d841973552a856c36f2'});
  const {grammar_manifest_cid: preScalarCid, ...preScalarBody} =
    read('scripts/fixtures/pre-scalar-batch-values-identities.json').grammar;
  assert.equal(cid(preScalarBody), preScalarCid);
  assert.equal(preScalarCid, 'sha256:b3688a442f39d99e7890d05e267c807914f2253c8a54b6de889885d7852af4b4');
  assert.deepEqual(preScalarBody, {...beforeDoubleBody,
    query_text_grammar_sha256: '54b6ff9dac5e92109448c5218906e70b99b90225799e01d75056db13914f0ba3',
    query_text_rules_sha256: 'a8fe03ffc3a8e6d640c531d0073a99500e85396ae7b6ed5d6899c39ad110590d'});
  const beforeMainIntegrationBody = {...preScalarBody,
    source_grammar_cid: 'sha256:5f67400cee99f7f718eb812bae8d39bb6058cd81038bd805f00e33e84a84c893',
    expression_contract_cid: 'sha256:f9a2ed26d8bf19e399fc94c64737ce2f1c76b890e173d51f8584b0fd9253b47a',
    expression_text_grammar_sha256: 'ff66d4a9096c8b34a0310b48d4f682db0efe4ce289e35161663b18252bcc9daf',
    expression_text_rules_sha256: '37c0ad8943173b2fce151a2420ba93079df4ba1a10b1151584c999ea34874c9f',
    query_text_rules_sha256: 'ab07a2c737f4739d3561fe1b4d235c2d04a98ab2c97b453930778fe6369f7b48'};
  assert.equal(cid(beforeMainIntegrationBody),
    'sha256:242daac87cc7b2c539f5f8bbe8e9b2bec841a09edf07739aa225c305f1d815c8');
  // Retain the pinned main Graph JOIN/MATCH DATA grammar and combined rules.
  const beforePivotIntegrationBody = {...beforeMainIntegrationBody,
    query_text_grammar_sha256: '8028584026fe4ac133f25ec5d75bfaea5c4733993c3eb988c0290a0383102288',
    query_text_rules_sha256: '3166801c63cf1143c1601ef30649247b9a87a3b0c33f340983481193e5a63e36'};
  assert.equal(cid(beforePivotIntegrationBody),
    'sha256:c3547f64ef37dc31982be2edb2067de0b6c76d6e25111fdaa801b789f16f2388');
  // Preserve the full adopted main grammar before STRPOS changes its
  // expression contract and containing source grammar identity.
  const {grammar_manifest_cid: beforeStrposCid, ...beforeStrposBody} =
    read('scripts/fixtures/pre-strpos-values-identities.json').grammar;
  assert.equal(cid(beforeStrposBody), beforeStrposCid);
  assert.equal(beforeStrposCid,
    'sha256:e70b946c81182b086c5ede1fb047eebe512699e7d71313986906d8d29acf8ab5');
  assert.deepEqual(beforeStrposBody, {...beforePivotIntegrationBody,
    query_text_grammar_sha256: 'dad903a0a27a05f7211fc4689ac89cf3a74b14b25b79621edf8f87e807a38f97',
    query_text_rules_sha256: '4635956e68e7d5862fd0553053bde9fc5a855e661c9cd4fd10339cdd1e61739a'});
  assert.deepEqual(oldFixedBody, {...beforeStrposBody,
    source_grammar_cid: 'sha256:aede5ef7057ac161894aac1b643719a6e361be31f349d5900cb9a75b6635426b',
    expression_contract_cid: 'sha256:beadee8142d8cad2614551bb79efb93d1306d8b00f9e945e28e962d8dfc384f4',
    expression_text_grammar_sha256: '3834e239750ed29dfc34a512655835a8dc9064651ef92d2a56cff5ef6b508a26',
    expression_text_rules_sha256: '5f9d21d7cf2afcc89fc7f39668c2703909048f7c35e8cd17b8b8c5f03d9fc561',
    query_text_grammar_sha256: 'c0251eb11b59d926ae886ef2e082e567856fda402b113c80499d8ba6f5c40463',
    query_text_rules_sha256: '40d9b9fdbc9180c7d4967c58951f262b1b0fbfa050896cac1dd295c45200be86'});
  const {grammar_manifest_cid, ...pinned} = read('spec/manifests/actql-grammar-0.1.json');
  assert.deepEqual(pinned, currentBody);
  assert.equal(grammar_manifest_cid, currentCid);
  for (const field of ['query_text_grammar_sha256', 'query_text_rules_sha256']) {
    assert.notEqual(cid({...currentBody, [field]: '0'.repeat(64)}), currentCid);
  }
});

test('combined PIVOT argument roles only change source grammar and lowering rules pins', () => {
  const before = read('scripts/fixtures/pre-pivot-argument-expression-values-identities.json').grammar;
  // Compare the accepted PIVOT boundary with its retained predecessor; later
  // expression extensions belong to the separate current-manifest checks.
  const after = read('scripts/fixtures/adopted-pivot-argument-main-grammar.json').grammar;
  const {grammar_manifest_cid: beforeCid, query_text_grammar_sha256: beforeSyntax,
    query_text_rules_sha256: beforeRules, ...beforeCommon} = before;
  const {grammar_manifest_cid: afterCid, query_text_grammar_sha256: afterSyntax,
    query_text_rules_sha256: afterRules, ...afterCommon} = after;
  assert.equal(cid({...beforeCommon, query_text_grammar_sha256: beforeSyntax,
    query_text_rules_sha256: beforeRules}), beforeCid);
  assert.deepEqual(afterCommon, beforeCommon);
  assert.notEqual(afterSyntax, beforeSyntax);
  assert.notEqual(afterRules, beforeRules);
  assert.notEqual(afterCid, beforeCid);
});

test('FROM PIVOT only changes source grammar and source-lowering rules',()=>{
 const before=read('scripts/fixtures/pre-from-pivot-values-identities.json').grammar;
 const after=read('scripts/fixtures/pre-derived-scope-stack-values-identities.json').grammar;
 const {grammar_manifest_cid:bc,query_text_grammar_sha256:bg,query_text_rules_sha256:br,...commonBefore}=before;
 const {grammar_manifest_cid:ac,query_text_grammar_sha256:ag,query_text_rules_sha256:ar,...commonAfter}=after;
 assert.deepEqual(commonAfter,commonBefore);
 assert.equal(cid({...commonBefore,query_text_grammar_sha256:bg,query_text_rules_sha256:br}),bc);
 assert.notEqual(ag,bg);assert.notEqual(ar,br);assert.notEqual(ac,bc);
});

test('optional table aliases change only source grammar/rules pins',()=>{
 const before=read('scripts/fixtures/pre-optional-derived-alias-values-identities.json').grammar;
 const after=read('scripts/fixtures/pre-derived-value-table-alias-values-identities.json').grammar;
 const {grammar_manifest_cid:bc,query_text_grammar_sha256:bg,query_text_rules_sha256:br,...commonBefore}=before;
 const {grammar_manifest_cid:ac,query_text_grammar_sha256:ag,query_text_rules_sha256:ar,...commonAfter}=after;
 assert.deepEqual(commonAfter,commonBefore);assert.notEqual(ag,bg);assert.notEqual(ar,br);assert.notEqual(ac,bc);
});


test('derived value-table alias changes source rules but keeps syntax/common contracts',()=>{
 const before=read('scripts/fixtures/pre-derived-value-table-alias-values-identities.json').grammar;
 const after=read('scripts/fixtures/pre-whole-row-range-values-identities.json').grammar;
 const {grammar_manifest_cid:bc,query_text_rules_sha256:br,...cb}=before;
 const {grammar_manifest_cid:ac,query_text_rules_sha256:ar,...ca}=after;
 assert.deepEqual(ca,cb);assert.notEqual(ar,br);assert.notEqual(ac,bc);
});



test('ordinary row expression changes only source rules, preserving syntax and common contracts',()=>{
 const before=read('scripts/fixtures/pre-whole-row-range-values-identities.json').grammar;
 const after=read('scripts/fixtures/pre-range-name-precedence-values-identities.json').grammar;
 const {grammar_manifest_cid:bc,query_text_rules_sha256:br,...cb}=before;
 const {grammar_manifest_cid:ac,query_text_rules_sha256:ar,...ca}=after;
 assert.deepEqual(ca,cb);assert.notEqual(ar,br);assert.notEqual(ac,bc);
});



test('range precedence changes only query rules, not common contracts or syntax',()=>{
 const before=read('scripts/fixtures/pre-range-name-precedence-values-identities.json').grammar;
 const after=read('scripts/fixtures/submitted-range-name-precedence-identities.json').grammar;
 const {grammar_manifest_cid:bc,query_text_rules_sha256:br,...cb}=before;
 const {grammar_manifest_cid:ac,query_text_rules_sha256:ar,...ca}=after;
 assert.deepEqual(ca,cb);assert.notEqual(ar,br);assert.notEqual(ac,bc);
});


test('joined row scope changes query rules without a new expression or JOIN contract',()=>{
 const before=read('scripts/fixtures/pre-joined-row-range-values-identities.json').grammar;
 const after=read('scripts/fixtures/submitted-joined-row-identities.json').grammar;
 const {grammar_manifest_cid:bc,query_text_rules_sha256:br,...commonBefore}=before;
 const {grammar_manifest_cid:ac,query_text_rules_sha256:ar,...commonAfter}=after;
 assert.deepEqual(commonAfter,commonBefore);
 assert.equal(cid({...commonBefore,query_text_rules_sha256:br}),bc);
 assert.equal(cid({...commonAfter,query_text_rules_sha256:ar}),ac);
 assert.notEqual(ar,br);assert.notEqual(ac,bc);
});


test('PIVOT scalar argument only changes its source grammar and lowering rules pins', () => {
  const before = read('scripts/fixtures/pre-pivot-argument-expression-values-identities.json').grammar;
  const after = read('scripts/fixtures/adopted-pivot-argument-main-grammar.json').grammar;
  const {grammar_manifest_cid: beforeCid, query_text_grammar_sha256: beforeSyntax,
    query_text_rules_sha256: beforeRules, ...beforeCommon} = before;
  const {grammar_manifest_cid: afterCid, query_text_grammar_sha256: afterSyntax,
    query_text_rules_sha256: afterRules, ...afterCommon} = after;
  assert.equal(cid({...beforeCommon, query_text_grammar_sha256: beforeSyntax,
    query_text_rules_sha256: beforeRules}), beforeCid);
  assert.deepEqual(afterCommon, beforeCommon);
  assert.notEqual(afterSyntax, beforeSyntax);
  assert.notEqual(afterRules, beforeRules);
  assert.notEqual(afterCid, beforeCid);
});


test('integrated derived scopes preserve common contracts and both historical parent closures', () => {
  const before = read('scripts/fixtures/pre-derived-scope-stack-values-identities.json').grammar;
  // Preserve the accepted derived-scope boundary; later scalar extensions
  // are checked by the separate current manifest and expression contracts.
  const retained = read('scripts/fixtures/adopted-derived-scope-stack-grammar.json');
  assert.equal(retained.source_revision, 'ec9b3966a2126eecf8880e1fe1608fce26a5f3bc');
  const after = retained.grammar;
  const {grammar_manifest_cid: bc, query_text_grammar_sha256: bg, query_text_rules_sha256: br, ...commonBefore} = before;
  const {grammar_manifest_cid: ac, query_text_grammar_sha256: ag, query_text_rules_sha256: ar, ...commonAfter} = after;
  assert.deepEqual(commonAfter, commonBefore);
  assert.equal(cid({...commonBefore, query_text_grammar_sha256: bg, query_text_rules_sha256: br}), bc);
  assert.equal(cid({...commonAfter, query_text_grammar_sha256: ag, query_text_rules_sha256: ar}), ac);
  assert.notEqual(ag, bg); assert.notEqual(ar, br); assert.notEqual(ac, bc);
});


test('WITH cutover changes query grammar/rules without changing machine contracts', () => {
  const before = read('scripts/fixtures/adopted-scalar-main-before-with-values-identities.json').grammar;
  const after = read('scripts/fixtures/submitted-with-carrier-cutover-values-identities.json').grammar;
  const {grammar_manifest_cid: bc, query_text_grammar_sha256: bg, query_text_rules_sha256: br, ...beforeCommon} = before;
  const {grammar_manifest_cid: ac, query_text_grammar_sha256: ag, query_text_rules_sha256: ar, ...afterCommon} = after;
  assert.deepEqual(afterCommon, beforeCommon);
  assert.equal(cid({...beforeCommon, query_text_grammar_sha256: bg, query_text_rules_sha256: br}), bc);
  assert.equal(cid({...afterCommon, query_text_grammar_sha256: ag, query_text_rules_sha256: ar}), ac);
  assert.notEqual(ag, bg); assert.notEqual(ar, br); assert.notEqual(ac, bc);
});


test('retained Sequence closure rejects current-rule and partial historical mixtures', () => {
  const {grammar_manifest_cid: retainedCid, ...historical} =
    read('scripts/fixtures/pre-query-rules-repair-values-identities.json').grammar;
  assert.equal(retainedCid, sequenceSnapshotCid);
  assert.equal(cid(historical), sequenceSnapshotCid);
  const current = normativeGrammarBody(path => readFileSync(path));
  assert.notEqual(cid(current), sequenceSnapshotCid);
  assert.notEqual(cid({...historical,
    query_text_rules_sha256: current.query_text_rules_sha256}), sequenceSnapshotCid);
  for (const field of ['source_grammar_cid', 'expression_contract_cid',
    'expression_text_grammar_sha256', 'expression_text_rules_sha256',
    'structural_text_grammar_sha256', 'structural_text_rules_sha256',
    'query_text_grammar_sha256', 'query_text_rules_sha256']) {
    assert.notEqual(cid({...historical, [field]: '0'.repeat(64)}), sequenceSnapshotCid);
    const partial = {...historical};
    delete partial[field];
    assert.notEqual(cid(partial), sequenceSnapshotCid);
  }
});
