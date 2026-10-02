#!/usr/bin/env bun
import { mkdirSync, writeFileSync, existsSync, unlinkSync } from 'node:fs'
import { join, resolve, dirname } from 'node:path'
import { homedir } from 'node:os'
import { spawnSync } from 'node:child_process'
const root=resolve(import.meta.dir,'..'), directory=join(root,'.borsa-server')
const label='dev.prototype.borsa.server', target=`gui/${process.getuid()}/${label}`
const agents=join(homedir(),'Library/LaunchAgents'), plist=join(agents,label+'.plist')
const run=args=>spawnSync('/bin/launchctl',args,{encoding:'utf8'})
const xml=value=>String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;')
switch(process.argv[2]) {
  case 'install': {
    if(!existsSync(join(directory,'cert.pem')))throw new Error('Önce bun run server:setup çalıştır.')
    mkdirSync(agents,{recursive:true});mkdirSync(join(directory,'logs'),{recursive:true,mode:0o700})
    const content=`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>${label}</string>
<key>ProgramArguments</key><array><string>${xml(process.execPath)}</string><string>${xml(join(root,'server/main.mjs'))}</string></array>
<key>WorkingDirectory</key><string>${xml(root)}</string>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>${xml(dirname(process.execPath))}:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
<key>RunAtLoad</key><true/><key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
<key>ThrottleInterval</key><integer>30</integer>
<key>StandardOutPath</key><string>${xml(join(directory,'logs/output.log'))}</string>
<key>StandardErrorPath</key><string>${xml(join(directory,'logs/error.log'))}</string>
</dict></plist>\n`
    writeFileSync(plist,content,{mode:0o600})
    run(['bootout',target])
    const result=run(['bootstrap',`gui/${process.getuid()}`,plist])
    if(result.status!==0)throw new Error('Servis başlatılamadı: '+result.stderr.trim())
    console.log('Borsa servisi oturum açıldığında başlatılacak. Durum: bun run server:service:status')
    break
  }
  case 'status': {
    const r=run(['print',target]);console.log(r.status===0?r.stdout.split('\n').filter(x=>/state =|pid =|last exit code =/.test(x)).join('\n'):'Servis yüklü değil.');break
  }
  case 'restart': {const r=run(['kickstart','-k',target]);if(r.status!==0)throw new Error('Servis yeniden başlatılamadı. Önce service:install çalıştır.');console.log('Servis yeniden başlatıldı.');break}
  case 'uninstall': {run(['bootout',target]);if(existsSync(plist))unlinkSync(plist);console.log('Otomatik başlangıç kaldırıldı. Hesap ve ayarlar korundu.');break}
  default: throw new Error('Kullanım: bun scripts/service.mjs install|status|restart|uninstall')
}
