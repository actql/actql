import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {resolve} from 'node:path';

const maxOutputBytes=32*1024*1024;
const timeoutMs=30000;
function inspectionFailure(tool,result,worker) {
  const details=worker??{code:result.error?.code??null,status:result.status,signal:result.signal??null,
    stdoutBytes:Buffer.byteLength(result.stdout??''),stderrBytes:Buffer.byteLength(result.stderr??'')};
  const error=new Error(`Code inspection failed: ${JSON.stringify({tool,...details})}`);
  error.code='ERR_NATIVE_CODE_INSPECTION';error.details=details;return error;
}
export function runCodeInspection(tool,args,{timeout=timeoutMs}={}) {
  assert(Number.isSafeInteger(timeout)&&timeout>0&&timeout<=timeoutMs,'Invalid code inspection deadline');
  const result=spawnSync(tool,args,{encoding:'utf8',timeout,maxBuffer:maxOutputBytes});
  if(result.error||result.status!==0)throw inspectionFailure(tool,result);
  return result.stdout;
}
function refusal(code) {const error=new Error(code);error.code=code;throw error;}
function symbolProjection(selection,emit) {
  const names=new Set(selection.names??[]),suffixes=selection.suffixes??[];
  let prior,pending,selected=0;
  return {
    line(line) {
      const match=line.match(/^([0-9a-f]+)\s+[tT]\s+(\S+)$/);
      if(!match) {
        // Keep normal undefined/data symbols and one-file headings outside the
        // code selection. Unknown output is not silently treated as code.
        if(line.trim()==='' || /^(?:[0-9a-f]+|[ ]+)\s+[A-Za-z?]\s+\S+(?: \(indirect for \S+\))?$/.test(line) ||
          line===selection.heading || line===selection.architectureHeading)return;
        refusal('ERR_NATIVE_SYMBOL_MALFORMED');
      }
      const name=match[2],real=!name.startsWith('.')&&!name.includes('$bb');
      const address=real?BigInt(`0x${match[1]}`):undefined;
      if(real){if(prior!==undefined&&address<prior)refusal('ERR_NATIVE_SYMBOL_ORDER');prior=address;}
      const wanted=name.includes('connectors5local')||names.has(name)||suffixes.some(suffix=>name.endsWith(suffix));
      const successor=real&&pending!==undefined&&address>pending;
      if(successor)pending=undefined;
      if(wanted||successor)emit(line+'\n');
      if(wanted){selected++;if(real)pending=address;}
    },
    finish(){if(selected===0)refusal('ERR_NATIVE_SYMBOL_MISSING');},
  };
}
// Whole nm output scales with unrelated debug labels. Consume that stream to
// a successful EOF, retaining the SAME relevant identities and the next real
// function above each relevant address. Validate the order of every real
// function, including discarded ones. The old 32MiB retained-output bound and
// 30s command deadline remain; one input line and stderr have the same bound.
export function readNativeSymbols(tool,args,selection={}, {timeout=timeoutMs}={}) {
  assert(Number.isSafeInteger(timeout)&&timeout>0&&timeout<=timeoutMs,'Invalid code inspection deadline');
  assert(typeof tool==='string'&&Array.isArray(args)&&args.every(value=>typeof value==='string'),
    'Invalid Native symbol command');
  assert(Array.isArray(selection.names??[])&&Array.isArray(selection.suffixes??[])&&
    [...selection.names??[],...selection.suffixes??[]].every(value=>typeof value==='string'&&value.length>0),
    'Invalid Native symbol selection');
  const configuration={tool,args,names:selection.names??[],suffixes:selection.suffixes??[],timeout};
  const result=spawnSync(process.execPath,[fileURLToPath(import.meta.url),'--symbol-stream',JSON.stringify(configuration)],
    {encoding:'utf8',timeout:timeout+1000,maxBuffer:maxOutputBytes});
  if(result.error||result.status!==0) {
    let worker;
    // Only our closed metadata packet can be included in a failure. Never
    // forward arbitrary tool stderr, symbol names or partially inspected code.
    try {
      const value=JSON.parse(result.stderr??'');
      if(Object.keys(value).sort().join(',')==='code,signal,status,stderrBytes,stdoutBytes'&&
        typeof value.code==='string'&&/^[A-Z_0-9]+$/.test(value.code)&&
        (value.status===null||Number.isInteger(value.status))&&
        (value.signal===null||/^SIG[A-Z0-9]+$/.test(value.signal))&&
        [value.stdoutBytes,value.stderrBytes].every(n=>Number.isSafeInteger(n)&&n>=0))worker=value;
    } catch {}
    throw inspectionFailure(tool,result,worker);
  }
  return result.stdout;
}
async function streamSymbols({tool,args,names,suffixes,timeout}) {
  let child,code,stdoutBytes=0,stderrBytes=0,retained=0,chunks=[],lineBytes=0,ended=false;
  const stop=reason=>{
    code??=reason;
    chunks=[];lineBytes=0;
    child.kill('SIGKILL');child.stdout.resume();child.stderr.resume();
  };
  const heading=args.at(-1)+':';
  const projection=symbolProjection({names,suffixes,heading,
    architectureHeading:args.at(-1)+' (for architecture arm64):'},line=>{
    const bytes=Buffer.byteLength(line);
    if(retained+bytes>maxOutputBytes)refusal('ERR_NATIVE_SYMBOL_OUTPUT_LIMIT');
    retained+=bytes;
    if(!process.stdout.write(line))child.stdout.pause();
  });
  child=spawn(tool,args,{stdio:['ignore','pipe','pipe']});
  const timer=setTimeout(()=>stop('ERR_NATIVE_INSPECTION_TIMEOUT'),timeout);
  const interrupted=()=>stop('ERR_NATIVE_INSPECTION_INTERRUPTED');
  process.once('SIGTERM',interrupted);process.once('SIGINT',interrupted);
  process.stdout.on('drain',()=>child.stdout.resume());
  process.stdout.on('error',()=>stop('ERR_NATIVE_INSPECTION_OUTPUT'));
  child.on('error',error=>{code??=/^[A-Z_0-9]+$/.test(error.code??'')?error.code:'ERR_NATIVE_INSPECTION_SPAWN';});
  child.stdout.on('error',()=>stop('ERR_NATIVE_SYMBOL_INPUT'));
  child.stderr.on('error',()=>stop('ERR_NATIVE_INSPECTION_STDERR'));
  child.stderr.on('data',chunk=>{
    stderrBytes+=chunk.length;
    if(!Number.isSafeInteger(stderrBytes)||stderrBytes>maxOutputBytes)stop('ERR_NATIVE_INSPECTION_STDERR_LIMIT');
  });
  const decoder=new TextDecoder('utf-8',{fatal:true,ignoreBOM:true});
  child.stdout.on('data',chunk=>{
    stdoutBytes+=chunk.length;
    if(code)return;
    try {
      if(!Number.isSafeInteger(stdoutBytes))refusal('ERR_NATIVE_SYMBOL_INPUT_LIMIT');
      let start=0;
      for(let end=chunk.indexOf(10,start);end>=0;end=chunk.indexOf(10,start)) {
        const part=chunk.subarray(start,end);
        if(lineBytes+part.length>maxOutputBytes)refusal('ERR_NATIVE_SYMBOL_LINE_LIMIT');
        const line=chunks.length?Buffer.concat([...chunks,part],lineBytes+part.length):part;
        let text;try{text=decoder.decode(line);}catch{refusal('ERR_NATIVE_SYMBOL_ENCODING');}
        projection.line(text);chunks=[];lineBytes=0;start=end+1;
      }
      if(start<chunk.length) {
        const part=chunk.subarray(start);
        lineBytes+=part.length;
        if(lineBytes>maxOutputBytes)refusal('ERR_NATIVE_SYMBOL_LINE_LIMIT');
        chunks.push(part);
      }
    }catch(error){stop(error.code??'ERR_NATIVE_SYMBOL_MALFORMED');}
  });
  child.stdout.on('end',()=>{ended=true;});
  await new Promise(done=>child.on('close',(status,signal)=>{
    clearTimeout(timer);process.removeListener('SIGTERM',interrupted);process.removeListener('SIGINT',interrupted);
    if(!code&&status===0) {
      try {
        if(!ended||lineBytes!==0)refusal('ERR_NATIVE_SYMBOL_TRUNCATED');
        projection.finish();
      }catch(error){code=error.code??'ERR_NATIVE_SYMBOL_MALFORMED';}
    }
    if(code||status!==0) {
      process.stderr.write(JSON.stringify({code:code??'ERR_NATIVE_INSPECTION_EXIT',status,signal,stdoutBytes,stderrBytes}));
      process.exitCode=1;
    }
    done();
  }));
}
if(process.argv[1]&&pathToFileURL(resolve(process.argv[1])).href===import.meta.url&&process.argv[2]==='--symbol-stream') {
  try {await streamSymbols(JSON.parse(process.argv[3]));}
  catch {process.stderr.write(JSON.stringify({code:'ERR_NATIVE_INSPECTION_WORKER',status:null,signal:null,stdoutBytes:0,stderrBytes:0}));process.exitCode=1;}
}
