import os
from paths import ADDON, HERE
# Update notice, side quest radius, toast icon
src=open(os.path.join(HERE,'test2.py'),encoding='utf8').read()
exec(src[:src.index('parsed=lua.eval("NS.Assistant.ParseQuestGuide')])
lua.execute(r'''
sent={}; timers={}
C_Timer={After=function(s,f) timers[#timers+1]=f end}
function runTimers() local t=timers; timers={}; for _,f in ipairs(t) do f() end end
C_ChatInfo={RegisterAddonMessagePrefix=function() end,SendAddonMessage=function(p,t,c,tg) sent[#sent+1]={p,t,c,tg} end}
ingroup=false; inguild=true
function IsInGuild() return inguild end
function IsInRaid() return false end
instance=false
function IsInGroup(cat) if cat then return instance end return ingroup end
LE_PARTY_CATEGORY_INSTANCE=2
chanid=0; function GetChannelName() return chanid end
joined=nil; function JoinTemporaryChannel(n) joined=n end
function UnitName() return "Me" end
function Ambiguate(n) return (n:gsub("%-.*","")) end
ChatFontNormal={}
C_AddOns={GetAddOnMetadata=function() return "2.10.3" end}
''')
lua.globals()['SRC']=open(os.path.join(ADDON,'Update.lua'),encoding='utf8').read()
lua.execute("assert(loadstring(SRC,'U'))('Oathbreaker',NS)")
ev=lua.eval("(function() return frames[#frames] end)()")
lua.execute("OathbreakerDB.updateNotice=true; uf=frames[#frames]; uf.scripts.OnEvent(uf,'PLAYER_LOGIN')")
U=lua.eval('NS.Update')
ok(U.IsNewer('2.10.3','2.10.2') is True and U.IsNewer('2.10.3','2.9.9') is True and U.IsNewer('2.10.3','2.10.3') is False and U.IsNewer('2.9.0','2.10.0') is False,'Version: Vergleich numerisch')
ok(U.IsNewer('abc','2.0.0') is False and U.IsNewer('3','2.0.0') is False,'Version: Unsinn ist nie neuer')
lua.execute("runTimers(); runTimers()")
ok(lua.eval('joined')=='OathbreakerSync','Kanal wird betreten')
ok(lua.eval('#sent')==1 and lua.eval('sent[1][2]')=='V:2.10.3' and lua.eval('sent[1][3]')=='GUILD','Login: Version an die Gilde')
lua.execute("sent={}; chanid=7; ingroup=true; lastTest=1")
U.Broadcast(True); chans=[lua.eval('sent[%d][3]'%i) for i in range(1,lua.eval('#sent')+1)]
ok(chans==['GUILD','PARTY','CHANNEL'],'Senden: Gilde, Gruppe, Kanal '+str(chans))
lua.execute("sent={}; lastSent=0; instance=true"); U.Broadcast(True); ok(lua.eval('sent[2][3]')=='INSTANCE_CHAT','Senden: Instanzgruppe per INSTANCE_CHAT'); lua.execute("instance=false")
lua.execute("sent={}"); U.Broadcast(False); ok(lua.eval('#sent')==0,'Senden: nicht oefter als alle 60 s')
def win(): return lua.eval("(function() for _,f in ipairs(frames) do if rawget(f,'skip') and rawget(f,'link') then return f end end end)()")
lua.execute("sent={}")
U.OnMessage('Oathbreaker','V:2.10.3','PARTY','Friend-Realm'); ok(win() is None and lua.eval('#sent')==0,'Gleiche Version: nichts')
U.OnMessage('Other','V:9.0.0','PARTY','Friend'); ok(win() is None,'Fremdes Praefix ignoriert')
U.OnMessage('Oathbreaker','hallo','PARTY','Friend'); ok(win() is None,'Unsinn ignoriert')
U.OnMessage('Oathbreaker','V:9.0.0','PARTY','Me-Realm'); ok(win() is None,'Eigene Nachricht ignoriert')
U.OnMessage('Oathbreaker','V:2.10.4','GUILD','Friend-Realm')
w=win(); ok(w is not None and w.shown is True and '2.10.4' in w.summary.text and U.Url=='https://github.com/Zmash/Oathbreaker/releases/latest','Neuere Version: Fenster mit Link')
lua.execute("OathbreakerDB.updateNotice=true"); w.shown=False; w.later.scripts.OnClick()
U.OnMessage('Oathbreaker','V:2.10.4','GUILD','Friend2'); ok(w.shown is False,'Pro Version nur einmal pro Sitzung')
U.OnMessage('Oathbreaker','V:2.11.0','GUILD','Friend2'); ok(w.shown is True,'Noch neuere Version: wieder')
w.skip.scripts.OnClick(); ok(lua.eval('OathbreakerDB.updateIgnored')=='2.11.0' and w.shown is False,'Ueberspringen merkt die Version')
# Kampf: erst danach
lua.execute("OathbreakerDB.updateIgnored=nil; InCombatLockdown=function() return true end")
U.OnMessage('Oathbreaker','V:3.0.0','GUILD','Friend3'); ok(w.shown is False,'Im Kampf kein Fenster')
lua.execute("InCombatLockdown=function() return false end; uf.scripts.OnEvent(uf,'PLAYER_REGEN_ENABLED')"); ok(w.shown is True and '3.0.0' in w.summary.text,'Nach dem Kampf kommt es')
# Aeltere Version: Antwort per Fluestern, einmal je Spieler
w.shown=False; lua.execute("sent={}")
U.OnMessage('Oathbreaker','V:2.9.0','GUILD','Old-Realm'); ok(lua.eval('#sent')==1 and lua.eval('sent[1][3]')=='WHISPER' and lua.eval('sent[1][4]')=='Old-Realm' and lua.eval('sent[1][2]')=='V:2.10.3','Aeltere Version: Antwort per Fluestern')
U.OnMessage('Oathbreaker','V:2.9.0','GUILD','Old-Realm'); ok(lua.eval('#sent')==1,'Antwort nur einmal je Spieler')
# Schalter aus: nichts
lua.execute("OathbreakerDB.updateNotice=false; shownFor=nil; sent={}")
U.OnMessage('Oathbreaker','V:9.9.9','GUILD','Friend4'); ok(w.shown is False,'Schalter aus: kein Fenster')
U.Broadcast(True); ok(lua.eval('#sent')==0,'Schalter aus: nichts senden')
# Radius
lua.execute("OathbreakerDB.sideRadius=nil"); ok(lua.eval('NS.SideRadius()')==450,'Radius: Standard 450')
ok(lua.eval('NS.ChangeSideRadius(1)')==500 and lua.eval('NS.ChangeSideRadius(-1)')==450,'Radius: Schritte 50')
lua.execute("OathbreakerDB.sideRadius=1000"); ok(lua.eval('NS.ChangeSideRadius(1)')==1000,'Radius: oben begrenzt')
lua.execute("OathbreakerDB.sideRadius=150"); ok(lua.eval('NS.ChangeSideRadius(-1)')==150,'Radius: unten begrenzt')
lua.execute("OathbreakerDB.sideRadius=99999"); ok(lua.eval('NS.SideRadius()')==1000,'Radius: kaputter Wert wird begrenzt')
# Low-Level-Markierung
lua.execute(r'''
plevel=26; UnitLevel=function() return plevel end
LibQuestieDB={RequireContract=function() return true end,Quest={Exists=function(i) return i<1000 end,Get=function(i,k) if k=='questLevel' then return ({[1]=10,[2]=26,[3]=18,[4]=0})[i] end end}}
OathbreakerDB.markLowLevel=true
calls=0
ZGV.GoalProto={GetText=function(self,a,b,c,nocolor) calls=calls+1; return "Accept 'Q'", 7, 8 end}
NS.InstallLowLevelMarker(ZGV); NS.InstallLowLevelMarker(ZGV)
mt={__index=ZGV.GoalProto}
function goal(action,id) return setmetatable({action=action,questid=id},mt) end
''')
ok(lua.eval('NS.isLowLevelQuest(1)') is True,'Low-Level: Stufe 10 bei 26 ist grau')
ok(lua.eval('NS.isLowLevelQuest(2)') is False and lua.eval('NS.isLowLevelQuest(3)') is False,'Low-Level: gleiche Stufe und knapp darunter nicht')
ok(lua.eval('NS.isLowLevelQuest(4)') is False and lua.eval('NS.isLowLevelQuest(5000)') is False,'Low-Level: unbekannt oder ohne Stufe nicht')
lua.execute("t,a,b=goal('accept',1):GetText()")
ok('low level' in lua.eval('t') and lua.eval('a')==7 and lua.eval('b')==8 and lua.eval('calls')==1,'Zygor-Zeile: Hinweis angehaengt, Rueckgaben bleiben, nur einmal gehookt')
lua.execute("t=goal('accept',2):GetText()"); ok('low level' not in lua.eval('t'),'Zygor-Zeile: normale Quest ohne Hinweis')
lua.execute("t=goal('kill',1):GetText()"); ok('low level' not in lua.eval('t'),'Zygor-Zeile: nur Annahme und Abgabe')
lua.execute("t=goal('turnin',1):GetText()"); ok('low level' in lua.eval('t'),'Zygor-Zeile: Abgabe auch')
lua.execute("t=goal('accept',1):GetText(false,false,true,true)"); ok('low level' not in lua.eval('t'),'Zygor-Zeile: nicht beim Teilen (ohne Farben)')
lua.execute("OathbreakerDB.markLowLevel=false; t=goal('accept',1):GetText()"); ok('low level' not in lua.eval('t'),'Schalter aus: kein Hinweis')
lua.execute("OathbreakerDB.markLowLevel=true; plevel=12"); ok(lua.eval('NS.isLowLevelQuest(1)') is False,'Low-Level: Stufe aendert sich, Cache folgt')
lua.execute("LibQuestieDB=nil; plevel=26"); ok(lua.eval('NS.isLowLevelQuest(1)') is False,'ohne Questie nichts markiert, kein Fehler')
