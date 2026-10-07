// Local diagnostic compilation only. Retain the referenced helper declarations
// verbatim; this projection neither deletes repository tests nor authorizes reuse.
import assert from 'node:assert/strict';
import {hash} from '../../inventory.mjs';

function tokens(source) {
  const result = [];
  let i = 0;
  const comment = () => {
    if (source.startsWith('//', i)) {
      const end = source.indexOf('\n', i); i = end < 0 ? source.length : end; return true;
    }
    if (!source.startsWith('/*', i)) return false;
    i += 2; let depth = 1;
    while (i < source.length && depth) {
      if (source.startsWith('/*', i)) { depth++; i += 2; }
      else if (source.startsWith('*/', i)) { depth--; i += 2; }
      else i++;
    }
    assert.equal(depth, 0, 'Unterminated compilation-input comment'); return true;
  };
  const rawLine = () => {
    assert(!source.startsWith('$|', i), 'Unsupported interpolated raw line');
    if (!source.startsWith('#|', i)) return false;
    assert.match(source.slice(source.lastIndexOf('\n', i - 1) + 1, i), /^\s*$/, 'Ambiguous raw line');
    const end = source.indexOf('\n', i); i = end < 0 ? source.length : end; return true;
  };
  const quoted = quote => {
    assert.equal(source[i++], quote);
    while (i < source.length) {
      if (source[i] === quote) { i++; return; }
      assert(source[i] !== '\n' && source[i] !== '\r', 'Unterminated compilation-input literal');
      if (source[i++] === '\\') {
        assert(i < source.length, 'Unterminated compilation-input escape');
        if (quote === '"' && source[i] === '{') interpolation();
        else i++;
      }
    }
    assert.fail('Unterminated compilation-input literal');
  };
  const interpolation = () => {
    assert.equal(source[i++], '{'); let depth = 1;
    while (i < source.length && depth) {
      if (comment() || rawLine()) continue;
      if (source[i] === '"' || source[i] === "'") { quoted(source[i]); continue; }
      if (source[i] === '{') depth++;
      else if (source[i] === '}') depth--;
      i++;
    }
    assert.equal(depth, 0, 'Unterminated compilation-input interpolation');
  };
  while (i < source.length) {
    if (/\s/.test(source[i]) || comment() || rawLine()) { if (/\s/.test(source[i] ?? '')) i++; continue; }
    const begin = i;
    if (source[i] === '"' || source[i] === "'") {
      quoted(source[i]); result.push({value: 'literal', begin, end: i}); continue;
    }
    if (/[A-Za-z_]/.test(source[i])) {
      while (i < source.length && /[A-Za-z0-9_]/.test(source[i])) i++;
    } else i++;
    result.push({value: source.slice(begin, i), begin, end: i});
  }
  return result;
}

export function omitUnselectedTests(source) {
  const ts = tokens(source), omitted = [];
  let depth = 0;
  for (let i = 0; i < ts.length; i++) {
    const t = ts[i];
    assert(!(depth === 0 && t.value === '#' && ts[i+1]?.value === '['), 'Unsupported declaration attribute');
    if (t.value === 'test' && depth === 0) {
      assert.match(source.slice(source.lastIndexOf('\n', t.begin - 1) + 1, t.begin), /^\s*$/, 'Ambiguous test declaration');
      let open = i + 1;
      if (ts[open]?.value === 'literal') open++;
      assert.equal(ts[open]?.value, '{', 'Unsupported test declaration');
      let d = 1, close = open + 1;
      for (; close < ts.length && d; close++) {
        if (ts[close].value === '{') d++;
        else if (ts[close].value === '}') d--;
      }
      assert.equal(d, 0, 'Unterminated test declaration');
      const end = ts[close - 1].end;
      omitted.push({begin: t.begin, end, digest: hash(source.slice(t.begin, end))});
      i = close - 1;
    } else {
      if (t.value === '{') depth++;
      else if (t.value === '}') depth--;
      assert(depth >= 0, 'Unbalanced compilation input');
    }
  }
  assert.equal(depth, 0, 'Unbalanced compilation input');
  // Preserve offsets, newlines and every byte outside an omitted test range.
  let text = '', end = 0;
  for (const range of omitted) {
    text += source.slice(end, range.begin) + source.slice(range.begin, range.end).replace(/[^\r\n]/g, ' ');
    end = range.end;
  }
  text += source.slice(end);
  return {text, omitted, originalDigest: hash(source), projectedDigest: hash(text)};
}

function declarations(source) {
  const ts = tokens(source), starts = [];
  let depth = 0, parens = 0, brackets = 0;
  for (let i=0;i<ts.length;i++) {
    const t=ts[i], prefix=source.slice(source.lastIndexOf('\n',t.begin-1)+1,t.begin);
    if (depth===0 && parens===0 && brackets===0 && /^\s*$/.test(prefix)) {
      const keyword=t.value==='priv'?ts[i+1]?.value:t.value;
      assert(['fn','struct','enum','suberror'].includes(keyword), 'Unsupported helper declaration '+t.value);
      starts.push({index:i,begin:t.begin});
    }
    if(t.value==='{')depth++; else if(t.value==='}')depth--;
    if(t.value==='(')parens++; else if(t.value===')')parens--;
    if(t.value==='[')brackets++; else if(t.value===']')brackets--;
    assert(depth>=0&&parens>=0&&brackets>=0,'Unbalanced helper declaration');
  }
  assert.equal(depth+parens+brackets,0);
  return starts.map((s,i)=>{
    const last=ts[(starts[i+1]?.index ?? ts.length)-1];
    const text=source.slice(s.begin,last.end);
    const name=/^(?:priv\s+)?(?:fn(?:\[[^\]]+\])?|struct|enum|suberror)\s+([A-Za-z_]\w*)/.exec(text)?.[1];
    assert(name,'Unsupported helper header');
    // Count every textual identifier, including literals/comments. This can
    // over-include declarations but cannot hide a reference in interpolation.
    const names=new Set([name]);
    if(/^(?:priv\s+)?enum\b/.test(text)) {
      for(const m of text.matchAll(/^\s+([A-Z][A-Za-z0-9_]*)\b/gm))names.add(m[1]);
    }
    return {begin:s.begin,end:last.end,text,name,names,identifiers:new Set(text.match(/[A-Za-z_]\w*/g)??[])};
  });
}

export function helperCompilation(sources,selected) {
  const units=Object.entries(sources).map(([path,source])=>({path,source,...omitUnselectedTests(source)}));
  const all=units.flatMap(u=>declarations(u.text).map(d=>({...d,path:u.path})));
  const byName=new Map();
  for(const d of all)for(const name of d.names) {
    assert(!byName.has(name),'Ambiguous helper identity '+name); byName.set(name,d);
  }
  const wanted=new Set(),pending=[...selected.matchAll(/[A-Za-z_]\w*/g)].map(m=>m[0]);
  for(let i=0;i<pending.length;i++) {
    const d=byName.get(pending[i]); if(!d||wanted.has(d))continue;
    wanted.add(d); pending.push(...d.identifiers);
  }
  assert([...wanted].some(d=>d.name==='run_current_host_graph_relation_path'),'Missing selected Host helper');
  const overlay={},inputs={};
  for(const unit of units) {
    const kept=all.filter(d=>d.path===unit.path&&wanted.has(d));
    const omitted=all.filter(d=>d.path===unit.path&&!wanted.has(d));
    let text=unit.text;
    for(const d of omitted) text=text.slice(0,d.begin)+text.slice(d.begin,d.end).replace(/[^\r\n]/g,' ')+text.slice(d.end);
    for(const d of kept) assert.equal(text.slice(d.begin,d.end),d.text,'Selected helper changed');
    overlay[unit.path]=text;
    inputs[unit.path]={offsetUnit:'utf16-code-unit',observedDigest:hash(unit.source),projectedDigest:hash(text),
      omittedTests:unit.omitted,
      keptDeclarations:kept.map(d=>({name:d.name,begin:d.begin,end:d.end,digest:hash(d.text)})),
      omittedDeclarations:omitted.map(d=>({name:d.name,begin:d.begin,end:d.end,digest:hash(d.text)}))};
  }
  return {overlay,inputs,referencedText:[selected,...[...wanted].map(d=>d.text)].join('\n')};
}

export function helperImports(pkg,referencedText) {
  const aliasNames=new Set([...referencedText.matchAll(/@([A-Za-z_]\w*)/g)].map(m=>m[1]));
  const blocks=[...pkg.matchAll(/import \{([\s\S]*?)\} for "wbtest"/g)];
  assert.equal(blocks.length,1,'Changed whitebox import layout');
  const kept=[],omitted=[];
  const lines=blocks[0][1].split('\n').filter(l=>l.trim());
  for(const line of lines) {
    const m=/^\s*"([^"]+)"(?:\s+@([A-Za-z_]\w*))?,\s*$/.exec(line);
    assert(m,'Unsupported whitebox import');
    const alias=m[2]??m[1].split('/').at(-1);
    (aliasNames.has(alias)?kept:omitted).push({path:m[1],alias,line});
  }
  return {text:pkg.replace(blocks[0][0],'import {\n'+kept.map(i=>i.line).join('\n')+'\n} for "wbtest"'),
    kept:kept.map(({path,alias})=>({path,alias})),omitted:omitted.map(({path,alias})=>({path,alias}))};
}

export function retirementCompilation(read, source, overlay) {
  assert(source.sources, 'Compilation requires the original directory inventory');
  const paths = Object.keys(source.sources).filter(p => /^src\/query_integration\/[^/]+_wbtest\.mbt$/.test(p)).sort();
  assert(paths.length > 0, 'Missing existing Host whitebox input inventory');
  const observedSources = {};
  for (const path of paths) {
    const original = read(path).toString();
    assert.equal(hash(original), source.sources[path], 'Changed compilation source '+path);
    observedSources[path] = overlay[path] ?? original;
  }
  const fixture='src/query_integration/driver_retirement_native_wbtest.mbt',pkg='src/query_integration/moon.pkg';
  const {overlay:projected,inputs,referencedText}=helperCompilation(observedSources,overlay[fixture]);
  const imports=helperImports(overlay[pkg],referencedText);
  Object.assign(overlay,projected);overlay[pkg]=imports.text;
  for(const path of paths)inputs[path].sourceDigest=source.sources[path];
  return {scope: 'one selected Native Host fixture; conservative identifier closure, retained declarations verbatim',
    inputs,imports:{kept:imports.kept,omitted:imports.omitted},
    omittedTests: Object.values(inputs).reduce((n, input) => n + input.omittedTests.length, 0),
    repositoryTestsRemoved: false, reuseAuthorized: false};
}
