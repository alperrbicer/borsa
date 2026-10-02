import { test, expect } from 'bun:test'
import { Repository } from '../../server/storage.mjs'
import { PushDelivery, PushError } from '../../server/notifications.mjs'
const configured={APNS_KEY_PATH:'test-only',APNS_KEY_ID:'test',APNS_TEAM_ID:'test'}
const fixture=(count=1)=>{
  const r=new Repository(':memory:')
  r.update(s=>{s.decisions=Array.from({length:count},(_,i)=>({id:'review-'+i,symbol:'AAPL',state:'review',expiresAt:Date.now()+60000}))})
  r.db.query('INSERT INTO devices VALUES (?,?)').run('a'.repeat(64),Date.now());return r
}
test('configured push is only ready until Apple accepts a delivery',async()=>{
  const repo=fixture(0),push=new PushDelivery(configured)
  try{await push.flush(repo);expect(repo.read().health[0].status).toBe('ready');expect(repo.read().health[0].lastSuccessAt).toBeNull()}finally{repo.close()}
})
test('failed pushes are visible, retried and recorded only after acceptance',async()=>{
  const repo=fixture(),push=new PushDelivery(configured);let attempts=0
  push.send=async()=>{if(++attempts===1)throw new PushError(503,'ServiceUnavailable');return true}
  try{
    await push.flush(repo);expect(repo.read().health[0].status).toBe('error')
    expect(repo.db.query('SELECT COUNT(*) AS n FROM delivery').get().n).toBe(0)
    await push.flush(repo);await push.flush(repo)
    expect(attempts).toBe(2);expect(repo.read().health[0].status).toBe('connected')
    expect(repo.read().health[0].message).toContain('Apple bildirim isteğini kabul etti')
  }finally{repo.close()}
})
test('already delivered recent reviews do not starve older pending ones',async()=>{
  const repo=fixture(24),push=new PushDelivery(configured),sent=[]
  push.send=async(_,d)=>{sent.push(d.id);return true}
  try{await push.flush(repo);await push.flush(repo);await push.flush(repo);expect(sent).toHaveLength(24);expect(new Set(sent).size).toBe(24)}finally{repo.close()}
})
test('one failed device does not block other devices; retired tokens are removed',async()=>{
  const repo=fixture(),push=new PushDelivery(configured)
  repo.db.query('INSERT INTO devices VALUES (?,?)').run('b'.repeat(64),Date.now())
  push.send=async(token)=>{if(token.startsWith('a'))throw new PushError(410,'Unregistered');return true}
  try{await push.flush(repo);expect(repo.db.query('SELECT COUNT(*) AS n FROM devices').get().n).toBe(1);expect(repo.db.query('SELECT COUNT(*) AS n FROM delivery').get().n).toBe(1);expect(repo.read().health[0].status).toBe('error')}finally{repo.close()}
})
