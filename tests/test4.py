import os
from paths import ADDON, HERE, ZYGOR
# Side quests
import re, sys
src=open(os.path.join(HERE,'test2.py'),encoding='utf8').read()
exec(src[:src.index('parsed=lua.eval("NS.Assistant.ParseQuestGuide')])
lua.execute(r'''
tinsert=table.insert
UnitLevel=function() return plevel end; plevel=20
ready={}
C_QuestLog.ReadyForTurnIn=function(i) return ready[i] end
C_QuestLog.IsComplete=function(i) return ready[i] end
OathbreakerDB.sideRadius=350; OathbreakerDB.guideCheck=false; OathbreakerDB.hintQuests=false; OathbreakerDB.hintFlights=false; OathbreakerDB.offerDungeons=false
local env={haveq=function(i) return inlog[i] and true or false end,completedq=function(i) return completed[i] and true or false end,Shaman=true,Warlock=false}
setmetatable(env,{__index=function() return false end})
ZGV.Parser.MakeCondition=function(c) local f=assert(loadstring("return ("..c..")")); setfenv(f,env); return f end
function ZGV:RaceClassMatch(list) for _,n in ipairs(list) do if n=="Shaman" or n=="Orc" then return true end end return false end
sideRaw=[[
step
Reach Level 15 |ding 15
step
talk Anne##1
accept Open Q##100 |goto The Barrens 50.0,50.0
step
talk Bob##2
turnin Ready##200 |goto The Barrens 50.5,50.0
accept Follow##201 |goto The Barrens 50.5,50.0
step
talk Cid##3
accept Instant##300 |goto The Barrens 50.0,50.0 |instant
step
talk Dan##4
accept Lock Task##400 |goto The Barrens 50.0,50.0
|only if Warlock
step
talk Eve##5
accept Blocked##500 |goto The Barrens 50.0,50.0
step
talk Fay##6
accept Totem##600 |goto The Barrens 50.0,50.0 |only Shaman
accept Mage Task##601 |goto The Barrens 50.0,50.0 |only Mage
step
Reach Level 30 |ding 30
step
talk Gus##7
accept Late##700 |goto The Barrens 50.0,50.0
step
kill Foo##9 |q 100/1 |goto The Barrens 50.0,50.0
]]
sideG={title="DUNGEONS\\Side Quests",rawdata=sideRaw,GetStatus=function() return "SUGGESTED" end}
mainG={title="LEVELING\\Main",rawdata="accept M##9\n",GetStatus=function() return "VALID" end}
ZGV.registeredguides={mainG,sideG}
ZGV.CurrentGuide=mainG
function ZGV:GetGuideByTitle(t) for _,g in ipairs(self.registeredguides) do if g.title==t then return g end end end
ZGV.QuestDB.IsQuestPossible=function(s,i) return i==500 and 2 or 1 end
ZGV.db.char={}
cleared=0; shown=0
ZGV.Pointer.ClearWaypoints=function(s,t) if t=="manual" then cleared=cleared+1 end end
function ZGV:ShowWaypoints() shown=shown+1 end
ZGV.Pointer.ArrowFrame={}
ZGV.Pointer.DestinationWaypoint=nil
px,py=5000,5000
''')
lua.execute("frames[1].scripts.OnEvent(nil,'PLAYER_LOGIN')")
scan=lua.eval("NS.Assistant.Scan")
def toast(): return lua.eval("(function() for _,f in ipairs(frames) do if rawget(f,'hint') then return f end end end)()")
def run(): lua.execute("NS.SideQuests.Reset()"); scan()
ok(lua.eval('OathbreakerDB.sideQuests') is True,'Standard an'); scan(); ok(toast() is None,'An, aber nichts markiert: kein Hinweis')
lua.execute(r'NS.ToggleSideGuide("DUNGEONS\\Side Quests")')
ok(lua.eval(r'OathbreakerDB.sideGuides["DUNGEONS\\Side Quests"]') is True,'Guide markiert')
scan(); t=toast(); ok(t is not None and t.shown is True,'Hinweis erscheint')
print(t.heading.text,'|',t.detail.text)
ok('side quests: Anne' in t.heading.text or 'Open Q' in t.heading.text,'Hinweis nennt Stopp')
lua.execute("toastF=(function() for _,f in ipairs(frames) do if rawget(f,'hint') then return f end end end)()"); keys=[lua.eval('toastF.hint["keys"][%d]'%i) for i in range(1,lua.eval('#toastF.hint["keys"]')+1)]
print(keys)
ok(sorted(keys)==['side:accept:100','side:accept:600'],'Nur machbare Annahmen am Ort: '+str(keys))
ok(lua.eval('#toastF.hint.rows')==2 and lua.eval('toastF.rows[1].shown') is True and lua.eval('toastF.rows[2].shown') is True,'Hinweis: eine Zeile pro Quest')
labels=lua.eval('toastF.rows[1].label.text')+' '+lua.eval('toastF.rows[2].label.text'); print(labels); ok('Open Q' in labels and 'Totem' in labels and 'Accept' in labels,'Zeilen nennen die Quests')
lua.execute("wp=nil; toastF.rows[2].scripts.OnClick(toastF.rows[2])"); ok(lua.eval("wp and wp.d.title")==lua.eval('toastF.rows[2].target.waypoint') and lua.eval("wp.d.title"). startswith('Accept'),'Klick auf Zeile setzt Pfeil dieser Quest')
lua.execute("inlog[100]=true"); scan(); t=toast(); ok(lua.eval('toastF.rows[1].shown') is False and 'Totem' in t.heading.text,'Eine angenommen: nur noch die andere, keine Zeilen')
lua.execute("inlog[100]=nil"); scan()
ok(lua.eval("NS.SideQuests.IsDoable(ZGV,{verb='accept',id=201,minLevel=0,step={conditions={}},after={200}})") is False,'Folgequest ohne Vorquest gesperrt')
lua.execute("completed[200]=true"); ok(lua.eval("NS.SideQuests.IsDoable(ZGV,{verb='accept',id=201,minLevel=0,step={conditions={}},after={200}})") is True,'Folgequest nach Abgabe frei'); lua.execute("completed[200]=nil")
# Abgabe nur wenn fertig und im Log
sq=lua.eval("(function() return {verb='turnin',id=200,minLevel=0,step={conditions={}},after={}} end)()")
d=lua.eval("NS.SideQuests.IsDoable")
ok(d(G:=lua.globals().ZGV,sq) is False,'Abgabe ohne Quest im Log: nein')
lua.execute("inlog[200]=true"); ok(d(G,sq) is False,'Abgabe unfertig: nein')
lua.execute("ready[200]=true"); ok(d(G,sq) is True,'Abgabe fertig: ja')
# bereits im aktuellen Schritt
lua.execute("ZGV.CurrentStep={goals={{questid=100},{questid=600}}}"); scan(); t=toast(); print(t.heading.text,'|',t.detail.text,t.shown); ok(t.hint.key=='side:turnin:200','Aktueller Zielschritt wird uebersprungen, Abgabe bleibt'); lua.execute("ZGV.CurrentStep=nil")
# Klick und Rueckkehr
lua.execute("ready[200]=nil; inlog[200]=nil"); scan(); t=toast()
lua.execute("wp=nil"); lua.execute("toastF=(function() for _,f in ipairs(frames) do if rawget(f,'hint') then return f end end end)(); toastF.scripts.OnClick(toastF)")
ok(lua.eval("wp and wp.d.type")=='manual','Klick setzt Pfeil')
lua.execute("inlog[100]=true"); scan(); ok(lua.eval("cleared")==0,'Noch ein Stopp offen: Pfeil bleibt')
lua.execute("inlog[600]=true"); scan(); ok(lua.eval("cleared")==1 and lua.eval("shown")==1,'Alles angenommen: Pfeil zurueck zum Guide')
lua.execute("inlog[100]=nil; inlog[600]=nil")
# Umweg
lua.execute(r'''function wayAt(x) ZGV.Pointer.DestinationWaypoint={m=1413,x=x,y=0.5} end''')
lua.execute("px,py=4800,5000; wayAt(0.55)"); scan(); t=toast(); ok(t.shown is True and 'on your way' in t.detail.text,'Auf dem Weg: '+t.detail.text)
lua.execute("px,py=4800,5000; wayAt(0.10)"); scan(); ok(toast().shown is False,'Grosser Umweg: kein Hinweis')
lua.execute("px,py=4800,5000; ZGV.Pointer.DestinationWaypoint=nil"); scan(); ok(toast().shown is False,'Ohne Ziel und 200 yd weg: kein Hinweis')
lua.execute("px,py=4950,5000"); scan(); ok(toast().shown is True and 'yd away' in toast().detail.text,'Ohne Ziel nah: Hinweis')
# Level
lua.execute("plevel=10"); scan(); ok(toast().shown is False,'Unter Guide-Level: kein Hinweis')
lua.execute("plevel=20"); scan()
# Wegklicken
lua.execute("toastF.closeButton.scripts.OnClick(toastF.closeButton)"); scan()
ok(lua.eval("OathbreakerDB.hinted['side:accept:100']") is True and lua.eval("OathbreakerDB.hinted['side:accept:600']") is True and toast().shown is False,'Schliessen merkt alle Stopps')
lua.execute("OathbreakerDB.hinted={}")
# Limit und Auswahl
lua.execute(r'''g6={title="LEVELING\\A",rawdata="accept A##1\n",GetStatus=function() return "VALID" end}; g7={title="LEVELING\\B",rawdata="accept B##2\n",GetStatus=function() return "VALID" end}; g8={title="LEVELING\\Hidden",rawdata="accept C##3\n",condition_visible=function() return false end,GetStatus=function() return "VALID" end}; g9={title="DUNGEONS\\WC (15-25)",rawdata="accept D##4\n",GetStatus=function() return "VALID" end}
ZGV.registeredguides={mainG,sideG,g6,g7,g8,g9}''')
lua.execute(r'NS.ToggleSideGuide("LEVELING\\A"); NS.ToggleSideGuide("LEVELING\\B")')
ok(lua.eval(r'OathbreakerDB.sideGuides["LEVELING\\B"]') is None and lua.eval('(NS.SideGuideCount())')==2,'Maximal zwei Guides')
pick=lua.eval('NS.SideQuests.Pickable(ZGV)'); titles=[pick[i].guide.title for i in range(1,len(pick)+1)]
print(titles); ok(titles[0]=='DUNGEONS\\Side Quests' and 'LEVELING\\Hidden' not in titles and 'DUNGEONS\\WC (15-25)' not in titles,'Auswahl: passende zuerst, Versteckte und Bossguides raus')
lua.execute('NS.ToggleSidePicker()'); pk=lua.eval("(function() for _,f in ipairs(frames) do if rawget(f,'rows') and rawget(f,'summary') then return f end end end)()"); ok(pk.shown is True and pk.summary.text.startswith('2 of 2'),'Auswahlfenster: '+pk.summary.text)
ok(lua.eval(r'NS.SideQuests.Reset()') is None,'Reset ok')
# Dungeon-Angebot bindet Side Guide an
lua.execute(r"""ZGV.registeredguides={mainG,sideG,g6,g7}; OathbreakerDB.sideGuides={}; OathbreakerDB.dungeons={}; OathbreakerDB.offerDungeons=true; NS.Assistant.Reset(); ZGV.Tabs.Pool={}; dialogF=nil
function offer() for i=1,5 do NS.Assistant.Scan() end; for _,f in ipairs(frames) do if rawget(f,'collect') then dialogF=f end end end
offer()""")
ok(lua.eval('dialogF.shown') is True and 'hint' in lua.eval('dialogF.question.text'),'Angebot erscheint mit Side-Text')
before=lua.eval('#tabsAdded')
lua.execute('dialogF.collect.scripts.OnClick()')
ok(lua.eval(r'OathbreakerDB.sideGuides["DUNGEONS\\Side Quests"]') is True and lua.eval('#tabsAdded')==before and lua.eval('dialogF.shown') is False and lua.eval('OathbreakerDB.dungeons.Side')=='yes','Collect: Side Guide statt Tab')
lua.execute(r"""OathbreakerDB.sideGuides={["LEVELING\\A"]=true,["LEVELING\\B"]=true}; OathbreakerDB.dungeons={}; offer(); dialogF.collect.scripts.OnClick()""")
pk=lua.eval("(function() for _,f in ipairs(frames) do if rawget(f,'rows') and rawget(f,'summary') then return f end end end)()")
ok(lua.eval('dialogF.shown') is True and pk.shown is True and lua.eval('OathbreakerDB.dungeons.Side') is None,'Collect voll: Auswahl offen, Angebot bleibt')
lua.execute(r"""dialogF:Hide(); dialogF.shown=false; OathbreakerDB.sideGuides={}; OathbreakerDB.dungeons={}; OathbreakerDB.sideQuests=false; offer(); dialogF.collect.scripts.OnClick()""")
ok(lua.eval('#tabsAdded')==before+1,'Modus aus: Collect oeffnet Tab wie bisher')
lua.execute(r"""OathbreakerDB.sideQuests=true; OathbreakerDB.offerDungeons=false""")
# echte Guides
raw=open(os.path.join(ZYGOR,'Guides-Forever/Dungeons/ZygorDungeonHordeCLASSIC.lua'),encoding='utf8',errors='replace').read()
m=re.search(r'Wailing Caverns Quests",\{.*?\},\[\[(.*?)\]\]',raw,re.S)
lua.globals().REAL=m.group(1)
stops=lua.eval('NS.SideQuests.ParseStops(ZGV,REAL)')
vals=[(stops[i].verb,stops[i].id,stops[i].title,stops[i].spot,stops[i].npc,stops[i].minLevel,len(stops[i].after)) for i in range(1,len(stops)+1)]
for v in vals[:12]: print(v)
print('ohne Ort',[v for v in vals if not v[3]])
ok(len(vals)>5 and sum(1 for v in vals if not v[3])<=3,'Echter Guide: Stopps haben Ort (%d)'%len(vals))
ok(all(v[5]>=15 for v in vals),'Echter Guide: Level aus ding')
lv=open(os.path.join(ZYGOR,'Guides-Forever/Leveling/ZygorLevelingHordeCLASSIC.lua'),encoding='utf8',errors='replace').read()
tot=0; missing=0
for mm in re.finditer(r'RegisterGuide\("Leveling Guides\\\\([^"]+)",\{.*?\},\[\[(.*?)\]\]',lv,re.S):
    lua.globals().REAL=mm.group(2)
    st=lua.eval('NS.SideQuests.ParseStops(ZGV,REAL)')
    tot+=len(st); missing+=sum(1 for i in range(1,len(st)+1) if not st[i].spot)
print('Leveling-Stopps',tot,'ohne Ort',missing)
ok(tot>1500 and missing/tot<0.08,'Echte Leveling-Guides: nur wandernde NPCs und Item-Quests ohne Ort')
