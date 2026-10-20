// Explicit offline import. Normal server execution never opens a SQLite database.
import { DatabaseSync } from 'node:sqlite';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { openDatabase } from './database.js';

const path=process.argv[2];
if(!path || !existsSync(path)) throw new Error('Usage: npm run db:import-sqlite -- /path/to/existing.sqlite');
const source=new DatabaseSync(resolve(path),{readOnly:true});
const tables=['users','stops','subscriptions','device_tokens','alert_events','api_devices',
  'routes','route_stops','trips','stop_times','headway_windows','transfers','saved_journeys',
  'journey_options','journey_sessions','journey_alerts'];
let db;
try {
  source.exec('BEGIN'); // Consistent read snapshot across all source tables.
  const unknown=source.prepare("SELECT name FROM sqlite_master WHERE type='table'").all()
    .map(row=>row.name).filter(name=>!tables.includes(name)&&name!=='schema_migrations'&&!name.startsWith('sqlite_'));
  if(unknown.length) throw new Error('Unrecognized SQLite tables: '+unknown.join(', '));
  db=await openDatabase();
  await db.transaction(async()=>{
    // Maintenance operation: no app must write to either database during the import.
    await db.exec(`LOCK TABLE ${tables.map(t=>'"'+t+'"').join(',')} IN EXCLUSIVE MODE`);
    for(const table of tables) {
      const row=await db.prepare(`SELECT COUNT(*)::integer AS count FROM "${table}"`).get();
      if(row.count!==0) throw new Error('Target database must be empty: '+table);
    }
    for(const table of tables) {
      if(!source.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name=?").get(table)) continue;
      const columns=source.prepare(`PRAGMA table_info("${table}")`).all().map(c=>c.name);
      const allowed=(await db.prepare("SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name=$1").all(table)).map(c=>c.column_name);
      if(columns.some(c=>!allowed.includes(c))) throw new Error('Unknown SQLite column in '+table);
      const names=columns.map(c=>'"'+c+'"').join(',');
      const placeholders=columns.map((_,i)=>'$'+(i+1)).join(',');
      const insert=db.prepare(`INSERT INTO "${table}" (${names}) VALUES (${placeholders})`);
      let imported=0;
      for(const row of source.prepare(`SELECT * FROM "${table}"`).iterate()) {
        const values=columns.map(c=>{
          const value=row[c];
          // Preserve API string timestamps while normalizing SQLite's UTC defaults.
          if(value && (c.endsWith('_at')) && /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(value)) return value.replace(' ','T')+'.000Z';
          return value;
        });
        await insert.run(...values);imported++;
      }
      const count=(await db.prepare(`SELECT COUNT(*)::integer AS count FROM "${table}"`).get()).count;
      if(count!==imported) throw new Error('Row count mismatch: '+table);
      console.log(table+': '+imported+' rows');
    }
  });
  console.log('Import committed. Source SQLite file was opened read-only.');
} finally {
  try { source.exec('ROLLBACK'); } finally { source.close(); }
  if(db) await db.close();
}
