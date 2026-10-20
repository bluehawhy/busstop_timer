import { openDatabase } from './database.js';
const db = await openDatabase();
try { console.log(await db.prepare('SELECT * FROM schema_migrations ORDER BY name').all()); }
finally { await db.close(); }
