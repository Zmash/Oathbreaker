import os
from paths import ADDON, HERE, ZYGOR
# Guide check
import re, sys
src=open(os.path.join(HERE,'test2.py'),encoding='utf8').read()
exec(src[:src.index('parsed=lua.eval("NS.Assistant.ParseQuestGuide')])
lua.execute(r'''
tinsert=table.insert
UnitLevel=function() return plevel end; plevel=26
ready={}
C_QuestLog.ReadyForTurnIn=function(i) return ready[i] end
C_QuestLog.IsComplete=function(i) return ready[i] end
OathbreakerDB.hintQuests=false; OathbreakerDB.hintFlights=false; OathbreakerDB.offerDungeons=false; OathbreakerDB.sideQuests=false
local env=setmetatable({Shaman=true},{__index=function() return false end})
ZGV.Parser.MakeCondition=function(c) local f=assert(loadstring("return ("..c..")")); setfenv(f,env); return f end
function ZGV:RaceClassMatch(list) for _,n in ipairs(list) do if n=="Shaman" then return true end end return false end
function ZGV:GetGuideByTitle(t) for _,g in ipairs(self.registeredguides) do if g.title==t then return g end end end
local function G(t,n,r) return {title=t,next=n,rawdata=r,GetStatus=function() return "VALID" end} end
gA=G("LEVELING\\A (21-23)","LEVELING\\B (24-25)",[[
step
accept One##1 |goto X 1,1
step
turnin One##1 |goto X 1,1
accept Three##3 |goto X 1,1
step
accept Four##4 |goto X 1,1
step
accept Filler##5 |goto X 1,1
step
accept Mage##6 |goto X 1,1 |only Mage
step
accept Both##7 |goto X 1,1
]])
gB=G("LEVELING\\B (24-25)","LEVELING\\C (25-27)",[[
step
accept Ten##10 |goto Y 1,1
step
turnin Four##4 |goto Y 1,1
step
accept Eleven##11 |goto Y 1,1
step
accept Both##7 |goto Y 1,1
step
accept MageNeed##12 |goto Y 1,1
]])
gC=G("LEVELING\\C (25-27)",nil,"step\naccept Later##20 |goto Z 1,1\n")
gD=G("DUNGEONS\\X (20-30)",nil,"step\naccept D##30 |goto Z 1,1\n")
ZGV.registeredguides={gA,gB,gC,gD}
ZGV.CurrentGuide=gA
ZGV.Chains={[10]=3,[12]=6}
ZGV.Tabs.Pool={}
switched=nil
ZGV.Tabs.LoadGuideToTab=function(s,g) switched=g.title; ZGV.CurrentGuide=g end
function ZGV:FocusStep(n) focused=n end
''')
plan=lua.eval('function() local t,s,f=NS.GuideCheck.PlanRoute(ZGV,plevel); return t and t.title or "none",#s,#f end')
ok(plan()==('LEVELING\\B (24-25)',1,2),'Ziel: erster nicht ueberlevelter Guide')
lua.execute("plevel=27"); print(plan()); ok(plan()[0]=='LEVELING\\C (25-27)' and plan()[1]==2,'Level 27: B wird mit uebersprungen')
lua.execute("plevel=26")
lua.execute('function an() local t,s,f=NS.GuideCheck.PlanRoute(ZGV,plevel); todo,dropped=NS.GuideCheck.Analyze(ZGV,s,f) end')
def rows():
    lua.execute('an()'); n=lua.eval('#todo')
    return [(lua.eval('todo[%d].action'%i),lua.eval('todo[%d].title'%i),lua.eval('todo[%d].count'%i)) for i in range(1,n+1)]
print(rows())
ok(rows()==[('Do','One',1),('Do','Three',1),('Accept','Four',1)],'Kette mit Vorquest, Annahme fuer spaetere Abgabe, Klasse raus')
ok('Filler' not in str(rows()) and 'Both' not in str(rows()),'Unnoetiges und spaeter annehmbares raus')
lua.execute("completed[1]=true"); ok(rows()==[('Do','Three',1),('Accept','Four',1)],'Erledigte fallen raus'); lua.execute("completed[1]=nil")
lua.execute("inlog[3]=true"); ok(rows()[0][:2]==('Finish','Three'),'Im Log: fertig machen'); lua.execute("ready[3]=true"); ok(rows()[0][:2]==('Turn in','Three'),'Fertig: abgeben'); lua.execute("inlog[3]=nil; ready[3]=nil")
# Fertige Quests, deren Abgabe in einem uebersprungenen Guide liegt
def handin():
    lua.execute('an()'); n=lua.eval('#handIn')
    return [lua.eval('handIn[%d].title'%i) for i in range(1,n+1)]
lua.execute(r'''rawA,rawB=gA.rawdata,gB.rawdata; gA.rawdata=rawA..[[
step
turnin Done##60 |goto X 1,1
step
turnin Mid##61 |goto X 1,1
step
turnin Wait##62 |goto X 1,1
]]; gB.rawdata=rawB..[[
step
turnin Wait##62 |goto Y 1,1
]]; NS.SideQuests.Reset()''')
lua.execute('function an() local t,s,f=NS.GuideCheck.PlanRoute(ZGV,plevel); todo,dropped,handIn=NS.GuideCheck.Analyze(ZGV,s,f) end')
ok(handin()==[],'Abgabe: nichts fertig, nichts gelistet')
lua.execute("inlog[60]=true; ready[60]=true; inlog[62]=true; ready[62]=true"); ok(handin()==['Done'],'Abgabe: fertige Quest aus uebersprungenem Guide, spaetere Abgabe ausgeblendet')
lua.execute("inlog[61]=true"); ok(handin()==['Done'],'Abgabe: Quest im Log, aber nicht fertig, fehlt')
lua.execute("completed[60]=true"); ok(handin()==[],'Abgabe: schon abgegeben, fehlt'); lua.execute("completed[60]=nil")
lua.execute("ready[61]=true"); ok(handin()==['Done','Mid'],'Abgabe: Reihenfolge nach Guide-Schritt')
lua.execute("NS.ResetGuideCheck(); NS.CheckGuide(ZGV); for _,f in ipairs(frames) do if rawget(f,'stay') then gcw=f end end")
ok(lua.eval('gcw.shown') is True and 'Done' in lua.eval('gcw.rows[#todo+1].label.text') and 'Turn in' in lua.eval('gcw.rows[#todo+1].label.text'),'Abgabe: Zeile im Fenster nach den Pflichtquests')
lua.execute("focused=nil; gcw.rows[#todo+1].scripts.OnClick(gcw.rows[#todo+1])"); ok(lua.eval('gcw.shown') is True,'Abgabe: Klick laesst Fenster offen')
lua.execute("completed[60]=true; gcw.scripts.OnUpdate(gcw,1.1)"); ok('handed in' in lua.eval('gcw.rows[#todo+1].note.text'),'Abgabe: erledigte Zeile wird grau'); ok('handed in' not in lua.eval('gcw.rows[#todo+2].note.text'),'Abgabe: andere Zeile bleibt'); lua.execute("completed[60]=nil")
lua.execute("gcw.rows[1].scripts.OnClick(gcw.rows[1])"); ok(lua.eval('gcw.shown') is False,'Pflichtquest: Klick schliesst Fenster')
lua.execute("gcw:Hide(); gcw.shown=false; inlog[60]=nil; ready[60]=nil; inlog[61]=nil; ready[61]=nil; inlog[62]=nil; ready[62]=nil; NS.ResetGuideCheck()")
lua.execute('gA.rawdata,gB.rawdata=rawA,rawB; NS.SideQuests.Reset()')
# lange Kette
lua.execute(r'''gA.rawdata=gA.rawdata..[[
step
accept L1##41 |goto X 1,1
step
turnin L1##41 |goto X 1,1
accept L2##42 |goto X 1,1
step
turnin L2##42 |goto X 1,1
accept L3##43 |goto X 1,1
step
turnin L3##43 |goto X 1,1
accept L4##44 |goto X 1,1
]]; gB.rawdata=gB.rawdata.."step\naccept Long##50 |goto Y 1,1\n"; ZGV.Chains[50]=44; NS.SideQuests.Reset()''')
ok(lua.eval('(function() an(); return dropped end)()')==1 and 'L4' not in str(rows()),'Lange Kette fuer eine Quest lohnt nicht')
lua.execute('gB.rawdata=gB.rawdata.."step\\naccept Long2##51 |goto Y 1,1\\n"; ZGV.Chains[51]=44; NS.SideQuests.Reset()')
ok('L4' in str(rows()) and lua.eval('dropped')==0,'Gleiche Kette fuer zwei Quests lohnt')
lua.execute('ZGV.Chains[50]=nil; ZGV.Chains[51]=nil; gB.rawdata=gB.rawdata:gsub("accept Long2?##5%d |goto Y 1,1\\n",""); NS.SideQuests.Reset()')
# QuestieDB-Vorrang any/all
lua.execute(r'''LibQuestieDB={RequireContract=function() return true end,Quest={Exists=function(i) return i==11 end,Get=function(i,k) if i==11 and k=="preQuestSingle" then return {5,1} end if k=="preQuestGroup" then return {} end return {} end}}''')
r=rows(); print(r); ok('Filler' in str(r) and 'One' in str(r),'Questie any: erste Option wird genannt')
lua.execute("completed[1]=true"); r=rows(); print(r); ok('Filler' not in str(r),'Questie any: eine erledigt reicht'); lua.execute("completed[1]=nil; LibQuestieDB=nil")
# Zygors Mehrfach-Format
lua.execute('gB.rawdata=gB.rawdata.."step\\naccept Twelve##13 |goto Y 1,1\\n"; NS.SideQuests.Reset()')
lua.execute('ZGV.Chains[13]={"AND",5,1}'); r=rows(); ok('Filler' in str(r) and 'One' in str(r),'Zygor AND: beide noetig')
lua.execute("completed[1]=true"); r=rows(); ok('Filler' in str(r),'Zygor AND: eine reicht nicht'); lua.execute("completed[1]=nil")
lua.execute('ZGV.Chains[13]={"OR",5,1}'); lua.execute("completed[1]=true"); r=rows(); ok('Filler' not in str(r),'Zygor OR: eine reicht'); lua.execute("completed[1]=nil")
lua.execute('ZGV.ChainsBreadcrumbs={[5]=true}'); r=rows(); ok('Filler' not in str(r) and 'One' in str(r),'Zygor OR: Brotkrumen wird nicht empfohlen')
lua.execute('ZGV.Chains[13]={"AND",5}'); r=rows(); ok('Filler' not in str(r),'Zygor AND: Brotkrumen zaehlt nicht')
lua.execute('ZGV.Chains[13]=nil; ZGV.ChainsBreadcrumbs=nil')
# Fenster
lua.execute("NS.Assistant.Reset(); OathbreakerDB.guideCheck=true; NS.ResetGuideCheck()")
lua.execute("NS.CheckGuide(ZGV); for _,f in ipairs(frames) do if rawget(f,'stay') then gcw=f end end")
ok(lua.eval('gcw and gcw.shown') is True,'Fenster erscheint')
print(lua.eval('gcw.heading.text'),'|',lua.eval('gcw.summary.text'),'|',lua.eval('gcw.note.text'))
ok(lua.eval('gcw.rows[1].shown') is True and 'One' in lua.eval('gcw.rows[1].label.text'),'Zeile zeigt Quest')
lua.execute("gcw.later.scripts.OnClick(); NS.CheckGuide(ZGV)"); ok(lua.eval('gcw.shown') is False,'Later: bleibt zu')
lua.execute("plevel=27; NS.CheckGuide(ZGV)"); ok(lua.eval('gcw.shown') is True,'Levelup: kommt wieder')
lua.execute("gcw.stay.scripts.OnClick(); plevel=28; NS.CheckGuide(ZGV)"); ok(lua.eval('gcw.shown') is False and lua.eval(r'OathbreakerDB.guideCheckStay["LEVELING\\A (21-23)"]') is True,'Stay: nie wieder fuer den Guide')
lua.execute("NS.ResetGuideCheck(); plevel=26; NS.CheckGuide(ZGV)"); lua.execute("gcw.switch.scripts.OnClick()"); ok(lua.eval('switched')=='LEVELING\\B (24-25)','Switch laedt Ziel')
lua.execute("gcw:Hide(); gcw.shown=false; ZGV.CurrentGuide=gD; plevel=40; NS.ResetGuideCheck(); NS.CheckGuide(ZGV)"); ok(lua.eval('gcw.shown') is False,'Dungeon-Guide: kein Check')
lua.execute("ZGV.CurrentGuide=gA; plevel=24; NS.ResetGuideCheck(); NS.CheckGuide(ZGV)"); ok(lua.eval('gcw.shown') is False,'Unter Schwelle: kein Check')
lua.execute("plevel=25; NS.CheckGuide(ZGV)"); ok(lua.eval('gcw.shown') is True,'Genau 2 ueber Maximum: Check')
lua.execute("gcw:Hide(); gcw.shown=false")
# Knopf: Check unabhaengig von Level, Stay und Later
lua.execute("ZGV.CurrentGuide=gA; plevel=16; OathbreakerDB.guideCheckStay['LEVELING\\A (21-23)']=true; NS.CheckGuide(ZGV)"); ok(lua.eval('gcw.shown') is False,'Knopf: ohne Knopf kein Check bei niedrigem Level')
lua.execute("NS.CheckGuideNow(ZGV)"); ok(lua.eval('gcw.shown') is True and lua.eval('gcw.heading.text')=='Guide check','Knopf: Fenster trotz Level und Stay')
lua.execute("gcw:Hide(); gcw.shown=false; ZGV.CurrentGuide=gD; said=nil; NS.CheckGuideNow(ZGV)"); ok(lua.eval('gcw.shown') is False,'Knopf: Dungeon-Guide, kein Fenster')
lua.execute("ZGV.CurrentGuide=gA; NS.ToggleSettings(); NS.settingsFrame.check.scripts.OnClick()"); ok(lua.eval('gcw.shown') is True,'Knopf im Einstellungsfenster oeffnet den Check'); lua.execute("gcw:Hide(); gcw.shown=false; NS.settingsFrame:Hide()")
lua.execute("OathbreakerDB.guideCheckStay={}; ZGV.CurrentGuide=nil; NS.CheckGuideNow(nil)"); ok(lua.eval('gcw.shown') is False,'Knopf: ohne Guide kein Fehler')
# Zu viele Pflichtquests
lua.execute(r'''gA.rawdata="step\n"; gB.rawdata="step\n"; for i=1,6 do gA.rawdata=gA.rawdata.."accept A"..i.."##"..(100+i).." |goto X 1,1\nstep\n"; gB.rawdata=gB.rawdata.."turnin A"..i.."##"..(100+i).." |goto Y 1,1\nstep\n" end
NS.SideQuests.Reset(); NS.ResetGuideCheck(); said=nil; local oldsay=NS.say; plevel=26; NS.CheckGuide(ZGV)''')
ok(lua.eval('gcw.shown') is False,'Zu viele Pflichtquests: kein Fenster')
# echte Horde-Guides
raw=open(os.path.join(ZYGOR,'Guides-Forever/Leveling/ZygorLevelingHordeCLASSIC.lua'),encoding='utf8',errors='replace').read()
gs=[]
for p in re.split(r'ZygorGuidesViewer:RegisterGuide\("',raw)[1:]:
    title=p[:p.index('"')].replace('\\\\','\\').replace('Leveling Guides','LEVELING',1)
    m=re.search(r'\},\s*\[\[(.*?)\]\]\s*\)',p,re.S); 
    if not m: continue
    n=re.search(r'^next="([^"]+)"',p[:m.start()],re.M)
    gs.append((title,m.group(1),n.group(1).replace('\\\\','\\').replace('Leveling Guides','LEVELING',1) if n else None))
G=lua.globals(); make=lua.eval('function(t,r,n) return {title=t,rawdata=r,next=n,GetStatus=function() return "VALID" end} end')
G.ZGV.registeredguides=lua.table_from([make(t,r,n) for t,r,n in gs])
lua.execute("ZGV.Chains={}; NS.SideQuests.Reset(); completed={}; inlog={}; ready={}")
idx=[t for t,_,_ in gs].index('LEVELING\\Ashenvale (21-22)')
ids=set()
chain=['LEVELING\\Orc & Troll Starter (1-13)','LEVELING\\Silverpine Forest (13-15)','LEVELING\\The Barrens & Stonetalon Mountain (15-21)']
for t,r,n in gs:
    if t in chain: ids|=set(int(x) for x in re.findall(r'(?:accept|turnin) .*?##(\d+)',r))
lua.execute('completed={'+','.join('[%d]=true'%i for i in ids)+'}')
for lvl,cur in ((26,'LEVELING\\Ashenvale (21-22)'),(24,'LEVELING\\Ashenvale (21-22)'),(30,'LEVELING\\Hillsbrad Foothills (22-24)')):
    lua.execute('plevel=%d; ZGV.CurrentGuide=ZGV:GetGuideByTitle(%r)'%(lvl,cur).replace("'",'"').replace('\\','\\\\') if False else 'plevel=%d; ZGV.CurrentGuide=ZGV:GetGuideByTitle([[%s]])'%(lvl,cur))
    lua.execute('tg=NS.GuideCheck.PlanRoute(ZGV,plevel)')
    print(lvl,cur,'->',lua.eval('tg and tg.title'))
    r=rows(); print(len(r),r[:9],'dropped',lua.eval('dropped'))
ok(len(r)>=0,'Echte Guides: laeuft durch')
