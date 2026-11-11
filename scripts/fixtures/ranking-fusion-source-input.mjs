// Independent binary64 RRF arithmetic in the declared input occurrence order.
const number={type:'number',nullable:false};
const left=[{id:1,position:1},{id:2,position:2}];
const right=[{id:2,position:1},{id:3,position:2}];
const leftText='SELECT 1 AS id, 1 AS position UNION ALL SELECT 2, 2';
const rightText='SELECT 2 AS id, 1 AS position UNION ALL SELECT 3, 2';
const columns=['id','score','rank'].map(name=>({name,contract:number}));
const variants=[
 {name:'repeated-peers',peers:['r','r'],weights:[1,2,3],window:2,rows:[{id:2,score:1/3+2/2+3/2,rank:1},{id:3,score:0+2/3+3/3,rank:2},{id:1,score:1/2+0+0,rank:3}]},
 {name:'single-peer',peers:'r',weights:[1,2],window:2,rows:[{id:2,score:1/3+2/2,rank:1},{id:3,score:0+2/3,rank:2},{id:1,score:1/2+0,rank:3}]},
 {name:'rank-window',peers:['r','r'],weights:[1,2,3],window:1,rows:[{id:2,score:0+2/2+3/2,rank:1},{id:1,score:1/2+0+0,rank:2}]},
 {name:'same-current',peers:['l','l'],weights:[1,2,3],window:2,rows:[{id:1,score:1/2+2/2+3/2,rank:1},{id:2,score:1/3+2/3+3/3,rank:2}]},
];
function program(v) {
 return {version:'actql/0.1',id:'fixture.ranking_'+v.name,stages:[{id:'main',inputs:{},steps:[
  {values:{schema:{id:number,position:number},rows:left},as:'l'},
  {values:{schema:{id:number,position:number},rows:right},as:'r'},
  {from:'l',merge_rankings:{with:v.peers,by:[],candidate:'id',rank:'position',k:3,score_policy:{rrf:{rank_constant:1,weights:v.weights,rank_window:v.window}}},as:'fused'},
  {from:'fused',sort:[{field:'rank',dir:'asc',nulls:'first'}]},
  {select:['id','score','rank'],as:'out'}],results:{rows:{from:'out',fields:['id','score','rank']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}};
}
function call(v) {
 const peers=Array.isArray(v.peers)?'['+v.peers.join(', ')+']':v.peers;
 return `merge_rankings(with: ${peers}, by: [], candidate: current.id, rank: current.position, k: 3, score_policy: {rrf: {rank_constant: 1, weights: [${v.weights.join(', ')}], rank_window: ${v.window}}})`;
}
function source(c, alias = 'current') {
 return `WITH l AS (${leftText}), r AS (${rightText}), fused AS (FROM l AS ${alias} |> ${c}) SELECT id, score, rank FROM fused ORDER BY rank`;
}
export const rankingFusionSourceSuccesses=variants.flatMap(v=>{
 const results={answer:{rows:v.rows,columns}};
 return [{name:'ranking-fusion-json-'+v.name,format:'json',text:JSON.stringify(program(v)),results,sourceReadCount:0},
 ...['sql','aql-text'].map(format=>({name:'ranking-fusion-'+format+'-'+v.name,format,text:source(call(v), '`current`'),results:{main:results.answer},sourceReadCount:0}))];
});
const valid=call(variants[0]);
export const rankingFusionSourceRefusals=[
 ['string-peer',valid.replace('[r, r]',"['r', 'r']")],
 ['weights-length',valid.replace('[1, 2, 3]','[1, 2]')],
 ['empty-peer-list',valid.replace('[r, r]','[]')],
 ['zero-rank-window',valid.replace('rank_window: 2','rank_window: 0')],
 ['zero-k',valid.replace('k: 3','k: 0')],
 ['rrf-score-field',valid.replace('rank: current.position','rank: current.position, score: current.position')],
 ['rrf-tie-break',valid.replace('rank: current.position','rank: current.position, tie_break: [current.id]')],
 ['missing-rank',valid.replace(', rank: current.position','')],
].map(([name,c])=>({name:'ranking-fusion-'+name,format:'aql-text',text:source(c),expectedCode:'ClientProgramInvalidInput'}));
// Retain the true common evidence gap; these are refusals, never scored-fusion success.
for(const [name,policy] of [['max',"'max'"],['weighted-sum',"{weighted_sum: {left: 0.5, right: 0.5}}"]]) {
 rankingFusionSourceRefusals.push({name:'ranking-fusion-undeclared-'+name,format:'aql-text',text:`WITH l AS (SELECT 1 AS id, 0.5 AS s), r AS (SELECT 2 AS id, 0.5 AS s) FROM l |> merge_rankings(with: r, by: [], candidate: id, score: s, k: 3, score_policy: ${policy}, score_contract: {domain: 'Relevance', range: [0, 1], normalization: 'Identity'})`,expectedCode:'ClientProgramInvalidInput'});
}
