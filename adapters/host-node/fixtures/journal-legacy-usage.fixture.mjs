import assert from 'node:assert/strict';

// Controlled test seed for the exact previous private Journal format.
// Only derived counter DDL changes here; original histories and rows survive.
export function stageLegacySubmissionUsageCounters(db){
 const names=['client_submitted_intent_usage','client_submission_restart_usage'];
 const rows=names.map(name=>({...db.prepare(`SELECT * FROM ${name}`).get()}));
 const triggers=db.prepare("SELECT name,sql FROM sqlite_schema WHERE type='trigger'").all().filter(row=>names.some(name=>row.name.startsWith(name+'_')));
 assert.equal(triggers.length,6);db.exec('BEGIN IMMEDIATE');
 try{
  for(const {name}of triggers)db.exec(`DROP TRIGGER ${name}`);
  for(let i=0;i<names.length;i++){
   const name=names[i];db.exec(`DROP TABLE ${name}`);
   // Independently pinned exact v2 counter DDL, not the new product's output.
   db.exec(`CREATE TABLE ${name} (
    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
    retained_count INTEGER NOT NULL CHECK (retained_count >= 0 AND retained_count <= 9007199254740991),
    retained_bytes INTEGER NOT NULL CHECK (retained_bytes >= 0 AND retained_bytes <= 67108864),
    revision INTEGER NOT NULL CHECK (revision >= 0 AND revision <= 9007199254740991)
  ) STRICT`);
   const row=rows[i];db.prepare(`INSERT INTO ${name} VALUES(?,?,?,?)`).run(row.singleton,row.retained_count,row.retained_bytes,row.revision);
  }
  for(const {sql}of triggers)db.exec(sql);db.exec('PRAGMA user_version=2');db.exec('COMMIT');
 }catch(error){db.exec('ROLLBACK');throw error;}
}
