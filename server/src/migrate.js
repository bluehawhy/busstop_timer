import { openDatabase } from './database.js';
const db=openDatabase(process.env.DB_PATH??'./data/bustimer.sqlite');
console.log(db.prepare('SELECT * FROM schema_migrations ORDER BY name').all());
db.close();
