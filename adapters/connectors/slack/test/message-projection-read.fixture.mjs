// Actual Common/Credential/Account/SQLite/TLS. Tickets and consumers are explicit
// sequencing fixtures, not a normal Resource supplier or installed Source.
import assert from 'node:assert/strict';
import * as provider from '../../../../_build/js/release/build/connectors/slack/host_node/host_node.js';
import {messageHistoryFixture,messagePage} from './message-history-read.fixture.mjs';
import {createSlackMessageRepliesReader,coalesceSlackMessageReaders,
  SLACK_MESSAGE_REPLIES_OPERATION} from '../site/message-history-read.mjs';

export const messageProjectionLimits=Object.freeze({maxRows:20,maxOccurrences:64,maxWork:100000,
  maxComparisonNodes:200,maxComparisonDepth:16,maxComparisonTextBytes:8192,
  maxRowsWireBytes:8192,maxRowsWireNodes:200,maxRowsWireDepth:8});

export async function messageProjectionFixture(t,{moon=provider,before={},after={},
  historyRecords,replyRecords,readReplies=true}={}) {
  const f=await messageHistoryFixture(t,{accounted:false});
  const historyRecordsDefault=[{type:'message',ts:'1.000001',text:'parent',reply_count:1,...before}];
  f.state.pages=[messagePage(historyRecords??historyRecordsDefault,null)];
  f.state.replyPages=[messagePage(replyRecords??[
    {type:'message',ts:'1.000001',thread_ts:'1.000001',text:'parent',reply_count:1,...after},
    {type:'message',ts:'2.000001',thread_ts:'1.000001',text:'child'}],null)];
  const tokens=[],historyRows=[],replyRows=[],mode={current:undefined};
  let pending;
  const chargeResponse=body=>{
    assert.equal(pending,undefined);pending=Object.freeze({body});return pending;
  };
  const consume=(target,rows,{charge})=>{
    assert.equal(charge,pending);target.push(...rows);pending=undefined;
  };
  const current=async operation=>{await f.current(operation);await mode.current?.(operation);};
  const history=f.create({moon,current,chargeResponse,
    consumeObservation:charge=>{assert.equal(charge,pending);pending=undefined;},
    consumePage:(rows,metadata)=>{tokens.push(metadata.originalPage);consume(historyRows,rows,metadata);}});
  await history.read();
  const scope=Object.freeze({...f.scope,operation:SLACK_MESSAGE_REPLIES_OPERATION});
  const grant=f.control.prepare(scope);f.journal.acceptGrant(f.sign(grant),f.control);
  const replyOptions={historyReader:history,originalPage:tokens[0],index:0,
    names:provider.slackMessageColumnNames(),initialAuthorization:{grant,scope,useId:'initial-reply'},
    credential:f.options.credential,current,authorizationFor:({operation,index})=>{
      assert.equal(operation,SLACK_MESSAGE_REPLIES_OPERATION);return {grant,scope,useId:`replies-${index}`};
    },limits:{...f.options.limits,maxComparisonNodes:200,maxComparisonDepth:16,
      maxComparisonTextBytes:8192,maxWork:100000},chargeResponse,
    consumePage:(rows,metadata)=>consume(replyRows,rows,metadata)};
  const replies=createSlackMessageRepliesReader(replyOptions);
  if(readReplies)await replies.read();
  return {...f,history,replies,historyRows,replyRows,tokens,mode,
    project:overrides=>coalesceSlackMessageReaders({historyReader:history,replyReaders:[replies],
      names:provider.slackMessageColumnNames(),limits:messageProjectionLimits,...overrides}),
    assertNoPending:()=>assert.equal(pending,undefined)};
}
