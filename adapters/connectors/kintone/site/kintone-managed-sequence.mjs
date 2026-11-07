// Kintone DATA protocol on the same generic reader's bound response borrow.
// No credential, physical transport, RowRun, charge or cleanup ACK is created here.
import {types} from 'node:util';
import {checked} from '../../../host-common/runtime-result.mjs';
import {KINTONE_FORM_READ_OPERATION, KINTONE_RECORD_READ_OPERATION} from './kintone-record-read.mjs';
const fail=code=>{throw Object.assign(new Error(code),{code});};
function method(value,name){
  if(value===null||typeof value!=='object'||types.isProxy(value))fail('InvalidKintoneManagedSequence');
  const field=Object.getOwnPropertyDescriptor(value,name);
  if(!field||!Object.hasOwn(field,'value')||typeof field.value!=='function')fail('KintoneManagedMethodUnavailable');
  return field.value;
}

// The installing Source supplies exact native typed limits and complete quote
// callbacks. This constructor is not selected by any profile spelling.
export function createKintoneManagedSequence({moon,original,bounds,limits,guestSpaceId,
  authorizeForm,capacityForResponse,baseCapacity}) {
  if(typeof authorizeForm!=='function'||typeof capacityForResponse!=='function'||baseCapacity==null||
      !Number.isSafeInteger(limits?.maxPages)||limits.maxPages<1||
      !Number.isSafeInteger(limits?.perPage)||limits.perPage<1||
      !Number.isSafeInteger(limits?.maxRequestBytes)||limits.maxRequestBytes<1||
      !Number.isSafeInteger(limits?.maxContractPairs)||limits.maxContractPairs<1||
      guestSpaceId!==undefined&&!/^[1-9][0-9]*$/u.test(guestSpaceId))fail('InvalidKintoneManagedSequence');
  const names=['clientProgramKintoneAdoptManagedBorrow','clientProgramKintoneManagedColumns',
    'clientProgramKintoneManagedFormRequest','clientProgramKintoneManagedPageRequest',
    'clientProgramKintoneManagedRecheckForm','clientProgramKintoneManagedProjectPage',
    'clientProgramKintoneManagedComplete','clientProgramKintoneManagedRetire'];
  const methods=Object.freeze(Object.fromEntries(names.map(name=>[name,method(moon,name)])));
  const call=(name,args)=>Reflect.apply(methods[name],moon,args);
  const prefix=guestSpaceId===undefined?'/k/v1/':`/k/guest/${guestSpaceId}/v1/`;
  const maxPages=limits.maxPages,perPage=limits.perPage,maxRequestBytes=limits.maxRequestBytes,
    maxContractPairs=limits.maxContractPairs;
  const page=bounds.page,values=bounds.values,form=bounds.form;
  return function prepare(input){
    if(input?.responseBorrow===undefined||input.originalAuthorization===undefined)fail('KintoneManagedBorrowUnavailable');
    let read=checked(call(names[0],[original,input.responseBorrow,page,values,maxContractPairs,perPage]));
    let columns=call(names[1],[read]),capacity=baseCapacity,kind,retired=false,started=false;
    let sequence;
    const current=()=>{if(retired)fail('KintoneManagedSequenceClosed');};
    const request=(body,path)=>Object.freeze({method:'POST',path:prefix+path,body,
      headers:Object.freeze([Object.freeze(['x-http-method-override','GET'])]),responseHeaders:Object.freeze([])});
    sequence=Object.freeze({
      responseCapacity(bytes){
        if(this!==sequence)fail('ForeignKintoneManagedSequence');current();
        if(kind!=='form'&&kind!=='page')fail('KintoneManagedResponseUnavailable');
        // The generic owner has retained and charged the original body before
        // this typed same-base/cumulative quote is asked for. No body is decoded here.
        capacity=Reflect.apply(capacityForResponse,undefined,[read,kind,bytes,capacity]);
        if(capacity==null)fail('KintoneManagedCapacityUnavailable');
        return capacity;
      },
      async read(context){
        if(this!==sequence||started)fail('ForeignKintoneManagedSequence');current();started=true;
        const observeForm=async()=>{
          context.signal.throwIfAborted();current();
          const supplied=await Reflect.apply(authorizeForm,undefined,[input,context.signal]);
          current();context.signal.throwIfAborted();kind='form';
          await context.readChild({operation:KINTONE_FORM_READ_OPERATION,prepare(){
            current();return Object.freeze({original:Object.freeze({}),
              originalAuthorization:supplied.originalAuthorization,authorization:supplied.authorization,
              verifyCurrent:supplied.verifyCurrent,
              request:request(checked(call(names[2],[read,maxRequestBytes])),'app/form/fields.json'),
              project(response){current();if(response.statusCode!==200)fail('KintoneReadHttpRejected');
                checked(call(names[4],[read,response.body,form]));},
            });
          }});
          await context.consumeObservation();current();
        };
        await observeForm();
        for(let index=0;index<maxPages;index++){
          current();context.signal.throwIfAborted();kind='page';
          const rows=await context.readChild({operation:KINTONE_RECORD_READ_OPERATION,prepare(){
            return Object.freeze({original:Object.freeze({}),
              request:request(checked(call(names[3],[read,maxRequestBytes])),'records.json'),
              project(response){current();if(response.statusCode!==200)fail('KintoneReadHttpRejected');
                return checked(call(names[5],[read,response.body]));},
            });
          }});
          await context.consumeValues(columns,rows);current();
          await observeForm();
          if(call(names[6],[read])===true)return;
        }
        fail('KintoneReadPageLimit');
      },
      retire(){
        if(this!==sequence)fail('ForeignKintoneManagedSequence');
        if(retired)return true;
        call(names[7],[read]);retired=true;read=columns=capacity=kind=undefined;
        return true;
      },
    });
    return sequence;
  };
}
