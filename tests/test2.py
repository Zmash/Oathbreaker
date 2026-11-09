import os
from paths import ADDON, HERE, ZYGOR
import lupa.lua51 as L, sys, re
t=open(os.path.join(HERE,'test.py'),encoding='utf8').read()
mock=t[t.index("mock=r'''")+9:t.index("'''\nlua=L.LuaRuntime")]
def ok(c,m):
    print(('PASS ' if c else 'FAIL ')+m)
    if not c: sys.exit(1)
lua=L.LuaRuntime(unpack_returned_tuples=True); lua.execute(mock)
lua.execute(r"""
now=100; function GetTime() return now end
wipe=function(t) for k in pairs(t) do t[k]=nil end end
function UnitClass() return "Shaman","SHAMAN" end
function InCombatLockdown() return false end
function UnitOnTaxi() return false end
faction="Horde"; function UnitFactionGroup() return faction end
bit=bit or {band=function(a,b) local r,p=0,1 while a>0 and b>0 do if a%2==1 and b%2==1 then r=r+p end a=math.floor(a/2) b=math.floor(b/2) p=p*2 end return r end}
completed={}; inlog={}
C_QuestLog.IsQuestFlaggedCompleted=function(i) return completed[i] end
C_QuestLog.GetLogIndexForQuestID=function(i) return inlog[i] and 3 or nil end
wcRaw=[[
step
Reach Level 15 |ding 15
step
talk Arch Druid##5769
accept The Barrens Oasis##886 |goto Thunder Bluff 78.59,28.56
|only of not haveq(870)
step
talk Tonga##3448
turnin The Barrens Oasis##886 |goto The Barrens 52.26,31.93
accept The Forgotten Pools##870 |goto The Barrens 52.26,31.93
step
talk Warlock Trainer##9
accept Fel Task##871 |goto The Barrens 52.0,31.0
|only if Warlock
step
talk Shaman Trainer##10
accept Totem Task##872 |goto The Barrens 52.1,31.1
|only if Shaman
]]
status="SUGGESTED"
wc={title="DUNGEONS\\Wailing Caverns Quests",rawdata=wcRaw,GetStatus=function() return status end}
wc0={title="DUNGEONS\\Wailing Caverns (15-25)",rawdata="step\n"}
level={title="LEVELING\\Ashenvale",rawdata="accept X##7777 |goto A 1,1\n"}
ZGV={CurrentGuide=level,registeredguides={level,wc0,wc},db={char={keptItems={}}}}
function ZGV:GetGuideByTitle() end
tabsAdded={}
ZGV.Tabs={Pool={{guide=level}},GetTabFromPool=function(s) local tab={AssignGuide=function(self,title) tabsAdded[#tabsAdded+1]=title end}; return tab end}
ZGV.QuestDB={VALID_NOW=1,IsQuestPossible=function(s,i) return i==872 and 2 or 1 end}
ZGV.Parser={ParseMapXYDist=function(s) local x,y=s:match("([%d.]+),([%d.]+)"); local map=s:find("Thunder") and 1456 or 1413; return map,nil,x/100,y/100 end}
ZGV.HBD={GetWorldCoordinatesFromZone=function(s,x,y,m) return x*10000,y*10000,m==1456 and 1 or 1 end,
 GetPlayerWorldPosition=function() return px,py,1 end,
 GetWorldDistance=function(s,i,a,b,c,d) local dx,dy=c-a,d-b; return math.sqrt(dx*dx+dy*dy) end}
px,py=0,0
ZGV.Pointer={Icons={greendotbig=1},SetWaypoint=function(s,m,x,y,d) wp={m=m,x=x,y=y,d=d} end,ArrowFrame={}}
ZGV.Frame={Controls={}}
fp={name="Tarren Mill",faction="H",npc="Zarise",x=60.14,y=18.62,m=1424}
ZGV.LibTaxi={taxipoints={[0]={Hillsbrad={fp}}}}
""")
for f,arg in (('Oathbreaker.lua','M'),('Assistant.lua','A'),('SideQuests.lua','S'),('GuideCheck.lua','G')):
    lua.globals()['SRC']=open(os.path.join(ADDON,f),encoding='utf8').read()
    lua.execute("NS=NS or {}; assert(loadstring(SRC,'%s'))('Oathbreaker',NS)"%arg)
lua.execute("frames[1].scripts.OnEvent(nil,'ADDON_LOADED','Oathbreaker')")
parsed=lua.eval("NS.Assistant.ParseQuestGuide(wcRaw)")
names=[parsed[i].title for i in range(1,len(parsed)+1)]
ok(names==['The Barrens Oasis','The Forgotten Pools','Totem Task'],'Parser: Klassenfilter '+str(names))
ok(parsed[2].npc=='Tonga' and parsed[2].spot.startswith('The Barrens 52.26'),'Parser: NPC und Ort')
lua.execute("OathbreakerDB.sideQuests=false; OathbreakerDB.guideCheck=false")
scan=lua.eval("NS.Assistant.Scan")
# fern: Angebot, kein Hinweis
lua.execute("px,py=9000,9000"); scan()

def frame(name):
    return lua.eval("(function() for _,f in ipairs(frames) do local h=rawget(f,'heading'); if h and h.text and string.find(h.text,'%s',1,true) then return f end end end)()"%name)
d=frame('Wailing Caverns')
ok(d is not None and d.shown is True,'Angebot: erscheint')
ok(d.heading.text=='Wailing Caverns  (15-25)','Angebot Titel: '+d.heading.text)
ok(d.summary.text=='2 quests to pick up, 0 already in your log','Angebot Zahlen: '+d.summary.text)
d.collect.scripts.OnClick()
ok(lua.eval("tabsAdded[1]")=='DUNGEONS\\Wailing Caverns Quests','Mitsammeln: Tab angelegt')
ok(d.shown is False and lua.eval("OathbreakerDB.dungeons['Wailing Caverns']")=='yes','Mitsammeln: gemerkt')
for i in range(6): scan()
ok(lua.eval("#tabsAdded")==1 and d.shown is False,'Angebot: fragt nicht erneut')
# Quest in der Naehe
lua.execute("px,py=5226+50,3193")
scan()
t=frame('quest nearby')
ok(t is not None and t.shown is True,'Hinweis: Questgeber in Reichweite')
ok('The Forgotten Pools from Tonga, 50 yd' in t.detail.text,'Hinweis Text: '+t.detail.text)
t.scripts.OnClick(t); ok(lua.eval("wp.m")==1413 and lua.eval("wp.d.type")=='manual','Hinweis: Klick setzt Wegpunkt')
t.closeButton.scripts.OnClick(); ok(t.shown is False and lua.eval("OathbreakerDB.hinted['q:870']") is True,'Hinweis: X merkt sich Quest')
scan(); ok(t.shown is False or 'Forgotten' not in t.detail.text,'Hinweis: bleibt weg')
lua.execute("OathbreakerDB.hinted={}; ZGV.CurrentGuide={title='L2',rawdata='accept Y##870 |goto A 1,1\\n'}")
scan(); ok(t.shown is False,'Hinweis: Quest aus Leveling-Guide wird nicht gemeldet')
lua.execute("ZGV.CurrentGuide=level")

lua.execute("""
NSx=1
""")
# Flugpunkt
lua.execute("OathbreakerDB.hinted={}; px,py=6014+100,1862")
scan()
f=frame('New flight point')
ok(f is not None and f.shown is True and 'Tarren Mill' in f.heading.text,'Flug: Hinweis bei unbekanntem Punkt')
ok('Zarise, 100 yd' in f.detail.text,'Flug Text: '+f.detail.text)
lua.execute("fp.known=true"); scan(); ok(f.shown is False,'Flug: bekannter Punkt kein Hinweis')
lua.execute("fp.known=nil; px,py=6014+400,1862"); scan(); ok(f.shown is False,'Flug: ausser Reichweite')
lua.execute("ZGV.Pointer.DestinationWaypoint={m=1456,x=.9,y=.9}"); scan(); ok(f.shown is True,'Flug: langer Weg vergroessert Radius')
lua.execute("UnitOnTaxi=function() return true end"); scan(); ok(f.shown is False,'Hinweis: im Flug aus')

lua.execute("UnitOnTaxi=function() return false end"); scan(); ok(f.shown is True,'Flug: wieder sichtbar')
# Fraktion: Horde sieht keine Allianz-Flugpunkte und umgekehrt
lua.execute("OathbreakerDB.hintFlights=true; px,py=6014+100,1862; ZGV.Pointer.DestinationWaypoint=nil; fp.faction='A'")
scan(); ok(f.shown is False,'Fraktion: Horde, Allianz-Flugpunkt kein Hinweis')
lua.execute("faction='Alliance'"); scan(); ok(f.shown is True,'Fraktion: Allianz, Allianz-Flugpunkt Hinweis')
lua.execute("fp.faction='H'"); scan(); ok(f.shown is False,'Fraktion: Allianz, Horde-Flugpunkt kein Hinweis')
lua.execute("fp.faction='B'"); scan(); ok(f.shown is True,'Fraktion: beidseitiger Flugpunkt Hinweis')
lua.execute("faction='Neutral'; fp.faction='A'"); scan(); ok(f.shown is True,'Fraktion: Neutral sieht beide')
lua.execute("faction='Horde'; fp.faction='H'")
# Fraktion bei Quests (Questie requiredRaces, Horde=Maske 2, Allianz=Maske 1)
lua.execute("""LibQuestieDB={RequireContract=function() return true end,Enum={factionRaceMasks={Alliance=1,Horde=2}},
Quest={Exists=function(i) return i<100 end,Get=function(i,k) if k=='requiredRaces' then return ({[1]=1,[2]=2,[3]=3,[4]=0})[i] end end}}""")
ok(lua.eval("NS.isOtherFactionQuest(1)") is True,'Quest: Allianzquest fuer Horde gesperrt')
ok(lua.eval("NS.isOtherFactionQuest(2)") is False,'Quest: Hordequest fuer Horde offen')
ok(lua.eval("NS.isOtherFactionQuest(3)") is False and lua.eval("NS.isOtherFactionQuest(4)") is False,'Quest: beide Seiten und ohne Angabe offen')
ok(lua.eval("NS.isOtherFactionQuest(500)") is False,'Quest: unbekannte Quest offen')
ok(lua.eval("NS.isQuestAvailable(ZGV,1)") is False,'Quest: isQuestAvailable sperrt Allianzquest')
lua.execute("faction='Neutral'"); ok(lua.eval("NS.isOtherFactionQuest(1)") is False,'Quest: Neutral nicht gesperrt')
lua.execute("faction='Horde'; LibQuestieDB=nil")
ok(lua.eval("NS.isOtherFactionQuest(1)") is False,'Quest: ohne Questie nichts gesperrt')

lua.execute("OathbreakerDB.hintFlights=false"); scan(); ok(f.shown is False,'Einstellung: Flug-Hinweise aus')

# Guide-Finder
lua.execute(r'''
loaded={}
map={QuestsFrame={DetailsFrame=setmetatable({IsVisible=function() return true end,GetFrameLevel=function() return 5 end},{})}}
QuestMapFrame=map
g2={title="LEVELING\\Barrens",rawdata="accept Q##5000 |goto A 1,1\ncollect 3 X##1 |q 5000/1\n",GetStatus=function() return "VALID" end}
g3={title="DUNGEONS\\WC2 Quests",rawdata="collect 3 X##1 |q 5000/1\n",GetStatus=function() return "VALID" end}
g4={title="LEVELING\\Bad",rawdata="collect 3 X##1 |q 5000/1\n",GetStatus=function() return "INVALID" end}
g5={title="Dailies\\Dq",rawdata="",GetStatus=function() return "VALID" end}
ZGV.registeredguides={level,wc0,wc,g2,g3,g4,g5}
ZGV.Quest_Cache={["Dailies\\Dq"]={{ids="6000,6001"}}}
ZGV.Tabs.Pool={{guide=level}}
ZGV.Tabs.LoadGuideToTab=function(s,g,st) loaded[#loaded+1]=g.title; ZGV.CurrentGuide=g end
ZGV.QuestDB.FocusNextStepForQuest=function() focused=true end
tinsert=table.insert
ZGV.FocusStep=function(s,n) focused=n end
g2.steps={{goals={{questid=5000,action="accept"}}},{goals={{questid=5000,action="collect",objnum=1}}}}
C_QuestLog.GetQuestObjectives=function(i) if i==5000 then return {{finished=false}} end return {} end
ZGV.Quest_Cache[g5.title]={{ids="6000,6001"}}
''')
show=lua.eval("NS.Assistant.ShowFinder")
lua.execute('hit=OathbreakerDB')
show(5000)
fb=lua.eval("(function() for _,f in ipairs(frames) do if rawget(f,'targets') then return f end end end)()")
ok(fb is not None and fb.shown is True,'Finder: Icon erscheint')
ok(len(fb.targets)==2 and fb.targets[1].guide.title=='LEVELING\\Barrens','Finder: Leveling zuerst, ungueltig raus')
lua.execute("fb=(function() for _,f in ipairs(frames) do if rawget(f,'targets') then return f end end end)(); fb.scripts.OnClick(fb)")
menu=lua.eval("(function() for _,f in ipairs(frames) do if rawget(f,'rows') and rawget(f,'rows')[1] and rawget(rawget(f,'rows')[1],'hover') and rawget(rawget(f,'rows')[1],'label') then return f end end end)()")
ok(menu is not None and menu.shown is True,'Finder: mehrere Guides zeigen Auswahl')
menu.rows[1].scripts.OnClick()
ok(lua.eval("loaded[1]")=='LEVELING\\Barrens' and lua.eval("focused")==2,'Finder: Auswahl laedt Guide und springt zur Quest')
show(6000); ok(fb.shown is True and len(fb.targets)==1,'Finder: Cache-Guide gefunden')
lua.execute("fb.scripts.OnClick(fb)"); ok(lua.eval("loaded[2]")=='Dailies\\Dq','Finder: ein Guide laedt direkt')
show(7777777); ok(fb.shown is True and len(fb.targets)==0 and lua.eval('fb.scripts.OnClick(fb)') is None,'Finder: ohne Guide graues Icon')
lua.execute("OathbreakerDB.guideFinder=false"); show(5000); ok(fb.shown is False,'Einstellung: Finder aus')

lua.execute("OathbreakerDB.guideFinder=true; C_QuestLog.GetSelectedQuest=function() return sel end; sel=5000")
sync=lua.eval("NS.Assistant.SyncFinder"); sync(); ok(fb.shown is True and fb.questID==5000,'Abfrage: ausgewaehlte Quest erkannt')
lua.execute("g3.turnin=nil; g2.rawdata=nil; OBJ=false"); before=len(fb.targets)
lua.execute("C_QuestLog.GetQuestObjectives=function(i) if i==5000 then return {{finished=OBJ}} end return {} end; OBJ=true"); sync(); ok(len(fb.targets)==0 and before==2,'Abfrage: fertiges Ziel aktualisiert die Lupe')
lua.execute("OBJ=false"); sync(); ok(len(fb.targets)==2,'Abfrage: wieder offenes Ziel')
lua.execute("g2.condition_visible=function() return false end"); show(5000); ok(len(fb.targets)==1,'Finder: fremde Rasse-Guides raus'); lua.execute("g2.condition_visible=nil")
lua.execute("sel=6000"); sync(); ok(fb.questID==6000,'Abfrage: Questwechsel erkannt')
lua.execute("map.QuestsFrame.DetailsFrame.IsVisible=function() return false end"); sync(); ok(fb.shown is False,'Abfrage: Details zu, Icon weg')
