import { Database } from 'bun:sqlite'
import { mkdirSync, chmodSync } from 'node:fs'
import { dirname } from 'node:path'
import { initialState, validateState, hash } from './domain.mjs'
export class Repository {
  constructor(path, now=Date.now()) {
    if (path!==':memory:') mkdirSync(dirname(path),{recursive:true,mode:0o700})
    this.db=new Database(path,{create:true,strict:true})
    this.db.exec('PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=5000; CREATE TABLE IF NOT EXISTS account (id INTEGER PRIMARY KEY CHECK(id=1), value TEXT NOT NULL); CREATE TABLE IF NOT EXISTS credentials (digest TEXT PRIMARY KEY, created INTEGER NOT NULL); CREATE TABLE IF NOT EXISTS devices (token TEXT PRIMARY KEY, updated INTEGER NOT NULL); CREATE TABLE IF NOT EXISTS delivery (id TEXT PRIMARY KEY, delivered INTEGER NOT NULL);')
    if (!this.db.query('SELECT id FROM account WHERE id=1').get()) this.db.query('INSERT INTO account VALUES (1,?)').run(JSON.stringify(initialState(now)))
    validateState(this.read())
    if (path!==':memory:') chmodSync(path,0o600)
  }
  read() { return JSON.parse(this.db.query('SELECT value FROM account WHERE id=1').get().value) }
  update(change) {
    return this.db.transaction(()=>{
      const state=this.read(), result=change(state)
      validateState(state); state.revision++
      this.db.query('UPDATE account SET value=? WHERE id=1').run(JSON.stringify(state))
      return result
    })()
  }
  addToken(token) { this.db.query('INSERT INTO credentials VALUES (?,?)').run(hash(token),Date.now()) }
  authorize(token) { return typeof token==='string' && token.length>=32 && !!this.db.query('SELECT digest FROM credentials WHERE digest=?').get(hash(token)) }
  close() { this.db.close() }
}
