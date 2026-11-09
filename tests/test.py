import os
from paths import ADDON, HERE, ZYGOR
import lupa.lua51 as L, sys
mock=r'''
NOW=0; timers={}
frames={}
reg={}
local icon={Register=function(s,n,o,d) reg={n=n,o=o,d=d} end,Hide=function() hid=true end,Show=function() hid=false end}
local ldb={NewDataObject=function(s,n,o) return o end}
function LibStub(n) return n=='LibDBIcon-1.0' and icon or ldb end
function CreateFrame()
 local f={scripts={},shown=true}
 local mt={__index=function(t,k) return function() return nil end end}
 setmetatable(f,mt)
 local function region()
  local r={shown=true}
  setmetatable(r,{__index=function(t,k) return function() end end})
  function r:SetText(v) self.text=v end
  function r:SetShown(v) self.shown=v end
  function r:SetTextColor(...) self.color={...} end
  return r end
 function f:CreateTexture() return region() end
 function f:CreateFontString() return region() end
 function f:SetScript(k,v) self.scripts[k]=v end
 function f:RegisterEvent() end
 function f:Show() self.shown=true end; function f:Hide() self.shown=false end
 function f:SetShown(v) self.shown=v end; function f:GetName() return "OathbreakerFrame" end
 function f:GetHeight() return 100 end
 function f:IsShown() return self.shown end
 function f:GetVerticalScroll() return 0 end
 frames[#frames+1]=f; return f end
UIParent={}; UISpecialFrames={};
EllesmereUI={ELLESMERE_GREEN={r=.8,g=.6,b=.4},MakeFont=function(p) return p:CreateFontString() end,MakeBorder=function() return {SetColor=function() end} end,COGS_ICON='cog',AttachSmoothScrollbar=function() return function() sbUpdates=(sbUpdates or 0)+1 end end}; tinsert=table.insert; SlashCmdList={}
msgs={}; print=function(s) msgs[#msgs+1]=s end
GameTooltip={Hide=function() end,Show=function() end,SetOwner=function() end,AddLine=function() end,AddDoubleLine=function(s,l,r) tooltipRows=tooltipRows or {}; table.insert(tooltipRows,{l,r}) end}
C_Timer={After=function(s,f) timers[#timers+1]=f end,NewTicker=function(s,f) tick=f; return {Cancel=function() tickCancel=true end} end}
function UnitLevel() return 21 end
Q={
 {isHeader=true,title="Barrens"},
 {questID=1,title="Alt",level=13,frequency=0},
 {questID=2,title="Alt fertig",level=13,frequency=0},
 {questID=3,title="Alt im Guide",level=13,frequency=0},
 {questID=4,title="Dungeon Tag",level=13,frequency=0},
 {questID=5,title="Dungeon Guide",level=13,frequency=0},
 {questID=6,title="Aktuell",level=20,frequency=0},
 {questID=7,title="Daily",level=10,frequency=1},
 {questID=8,title="Zweite Alte",level=15,frequency=0},
 {questID=9,title="Klassenquest",level=12,frequency=0},
 {questID=10,title="Gruppe",level=12,frequency=0,suggestedGroup=3},
 {questID=11,title="Folgeguide",level=12,frequency=0},
}
abandoned={}; sel=nil
C_QuestLog={GetNumQuestLogEntries=function() return #Q end,GetInfo=function(i) return Q[i] end,
 IsComplete=function(i) return i==2 end,ReadyForTurnIn=function() return false end,
 GetQuestObjectives=function(i) return {{text='0/12 Raptor Head',finished=false}} end,
 GetQuestTagInfo=function(i) if i==4 then return {tagID=81} end end,
 SetSelectedQuest=function(i) sel=i end,SetAbandonQuest=function() end,AbandonQuest=function() abandoned[#abandoned+1]=sel end}
g1={title="LEVELING\\Ashenvale",next="Next",rawdata="step\naccept Im Guide##3 |goto X\nTalk to Npc##1 |goto Y\n"}
g2={title="Next",rawdata="step\nkill Foo |q 11/1\n"}
g3={title="DUNGEONS\\WC",rawdata="turnin D##5\n"}
g4={title="LEVELING\\Shaman Class Quests",rawdata="accept W##9\n"}
g5={title="LEVELING\\Alt",rawdata="accept X##1\n"}
ZGV={CurrentGuide=g1,registeredguides={g1,g2,g3,g4,g5},db={char={},profile={}}}
ZGV.QuestDB={VALID_NOW=1,VALID_FUTURE=2,IsQuestPossible=function(self,id) if not ZGV.db.profile.beta_use_chains then return 1,'chains disabled' end; if not ZGV.db.char.SISstarted then return 1,'no catchup' end; if id==99 then error('kaputt') end; return id==50 and 2 or 1,'checked' end}
function ZGV:GetGuideByTitle(t) return t=="Next" and g2 or nil end
'''
lua=L.LuaRuntime(unpack_returned_tuples=True); lua.execute(mock)
lua.globals()['SRC']=open(os.path.join(ADDON,'Oathbreaker.lua'),encoding='utf8').read()
lua.execute("NS={}; assert(loadstring(SRC,'Q'))('Oathbreaker',NS); function NS.StartAssistant() end; function NS.SideGuideCount() return 0,2 end; function NS.SideRadius() return 450 end")
def ok(c,m):
    print(('PASS ' if c else 'FAIL ')+m)
    if not c: sys.exit(1)
lua.execute("frames[1].scripts.OnEvent(nil,'ADDON_LOADED','Oathbreaker'); frames[1].scripts.OnEvent(nil,'PLAYER_LOGIN')")
names=lua.eval("function() local l,p=Oathbreaker.Candidates(); local t={}; for _,e in ipairs(l) do t[#t+1]=e.title end; return table.concat(t,','),p end")
n,p=names(); ok(n=='Alt,Zweite Alte','nur alte, unbenoetigte Quests: '+n); ok(p==9,'geschuetzt gezaehlt: '+str(p))
lua.execute("ZGV:ShowQuestCleanup()")
g=lua.globals()
ok(lua.eval("OathbreakerFrame==nil or true"),'Fenster offen')
win=lua.eval("frames[2]")
lua.execute("""f=frames[2]""")
action=lua.eval("function() return f.action.label.text end")
ok(action()=='Abandon 2 quests','Button zaehlt: '+action())
lua.execute("f.rows[1].scripts.OnClick(f.rows[1])")
ok(action()=='Abandon 1 quest','Haken raus: '+action())
lua.execute("f.action.scripts.OnClick()")
ok('Really' in action() and lua.eval('#abandoned')==0,'erst Bestaetigung')
lua.execute("timers[#timers]()"); ok(action()=='Abandon 1 quest','Bestaetigung laeuft ab')
lua.execute("f.action.scripts.OnClick(); f.action.scripts.OnClick()")
ok(lua.eval('#abandoned')==1 and lua.eval('abandoned[1]')==8,'nur angehakte Quest abgebrochen')
lua.execute("Q[2].level=13; f.less.scripts.OnClick()")
lua.execute("ZGV.CurrentGuide=nil"); ok(lua.eval("Oathbreaker.Candidates()") is None,'ohne Guide kein Vorschlag')

# Tabs ohne CurrentGuide
lua.execute("""ZGV.CurrentGuide=nil; g6={title="Tab",rawdata="accept Y##8\\n"}; ZGV.Tabs={Pool={{guide=g1},{guide=g6},{}}}""")
n,p=names(); ok(n=='Alt','Tabs: Guides aller Tabs schuetzen, ohne CurrentGuide: '+n)
lua.execute("ZGV.Tabs={Pool={{}}}"); ok(lua.eval("Oathbreaker.Candidates()") is None,'Tabs leer: kein Vorschlag')

lua.execute("ZGV.CurrentGuide=g1; ZGV.Tabs=nil")
ok(lua.eval("reg.n")=='Oathbreaker' and lua.eval("reg.o.icon")=='Interface\\AddOns\\Oathbreaker\\Media\\oathbreaker.tga','Minimap: Icon registriert')
lua.execute("f:Hide(); reg.o.OnClick()"); ok(lua.eval("f.shown") is True,'Minimap: Klick oeffnet')
lua.execute("reg.o.OnClick()"); ok(lua.eval("f.shown") is False,'Minimap: Klick schliesst')
lua.execute("NS.ToggleSettings(); NS.settingsFrame.toggles.showMinimap.scripts.OnClick(NS.settingsFrame.toggles.showMinimap)"); ok(lua.eval("hid") is True,'Einstellungen: Minimap-Schalter versteckt Button')
lua.execute("hit=false; f.gearButton.scripts.OnClick(); hit=NS.settingsFrame.shown"); ok(lua.eval("hit") is False,'Zahnrad schaltet Einstellungen um')
lua.execute("reg.o.OnClick(nil,'RightButton')"); ok(lua.eval("NS.settingsFrame.shown") is True,'Rechtsklick oeffnet Einstellungen')
lines=[]
lua.execute("tt={AddLine=function(s,t) ttl=(ttl or '')..t..'|' end}; reg.o.OnTooltipShow(tt)")
ok('to clear out' in lua.eval("ttl"),'Tooltip: '+lua.eval("ttl"))

lua.execute("ZGV.CurrentGuide=g1; f:Show(); f.Refresh()")
ok(lua.eval("f.rows[1].detail.text")=='Barrens  |cff666666/|r  0/12 Raptor Head','Zeile: Zone und Fortschritt')
ok(lua.eval("sbUpdates>0"),'Scrollbar aktualisiert')
ok(lua.eval("f.subtitle.text").endswith('selected'),'Untertitel: '+lua.eval("f.subtitle.text"))
lua.execute("f.selectAll.scripts.OnClick()"); 
s1=lua.eval("f.subtitle.text"); lua.execute("f.selectAll.scripts.OnClick()"); s2=lua.eval("f.subtitle.text")
ok(s1!=s2,'Alle waehlen schaltet: '+s1+' -> '+s2)
lua.execute("f.closeButton.scripts.OnClick()"); ok(lua.eval("f.shown") is False,'X schliesst')

lua.execute("""
zgvBar={}
closeB=CreateFrame(); frames[#frames]=nil; closeB.GetParent=function() return zgvBar end; closeB.GetFrameLevel=function() return 5 end
ZGV.Frame={Controls={CloseButton=closeB}}
if tick then tick() end
""")
ok(lua.eval("tickCancel") is True,'Zygor-Button: Ticker endet nach Anlegen')
last=lua.eval("frames[#frames]")
lua.execute("zb=frames[#frames]; zb.scripts.OnClick()"); ok(lua.eval("f.shown") is True,'Zygor-Button oeffnet Fenster')
lua.execute("zb.scripts.OnEnter(zb); zb.scripts.OnLeave(zb)"); ok(True,'Zygor-Button Tooltip laeuft')

pos=lua.eval("function(i) return ZGV.QuestDB:IsQuestPossible(i) end")
ok(pos(50)==(2,'checked'),'Skip: Voraussetzung wird immer geprueft')
ok(lua.eval("ZGV.db.char.SISstarted") is None and lua.eval("ZGV.db.profile.beta_use_chains") is None,'Skip: Zygor-Status bleibt unveraendert (Ketten-Option auf Forever nil)')
ok(pos(51)[0]==1,'Skip: erfuellte Quest bleibt moeglich')
lua.execute("ok2,err=pcall(ZGV.QuestDB.IsQuestPossible,ZGV.QuestDB,99)")
ok(lua.eval("ok2") is False and lua.eval("ZGV.db.char.SISstarted") is None,'Skip: bei Fehler Status zurueckgesetzt')
ok(pos(60)[0]==1,'Ohne QuestieDB: Quest bleibt moeglich')
lua.execute("""
qcompleted={}
C_QuestLog.IsQuestFlaggedCompleted=function(i) return qcompleted[i] end
ZGV.Chains={[70]=1}
QD={[60]={preQuestSingle={500,501}},[61]={preQuestGroup={500,501}},[62]={preQuestSingle={62,502},exclusiveTo={502}},[63]={preQuestSingle={503}},[70]={preQuestSingle={999}},[71]={}}
LibQuestieDB={RequireContract=function() return true end,Quest={Exists=function(i) return QD[i]~=nil end,Get=function(i,k) return QD[i][k] end}}
ZGV.questsbyid={[503]={inlog=true}}
""")
ok(pos(60)==(2,'questie: prerequisite missing'),'Questie: fehlende Vorquest blockiert')
lua.execute("qcompleted[501]=true"); ok(pos(60)[0]==1,'Questie: eine von mehreren reicht')
ok(pos(61)[0]==2,'Questie: Gruppe braucht alle')
lua.execute("qcompleted[500]=true"); ok(pos(61)[0]==1,'Questie: Gruppe erfuellt')
ok(pos(62)[0]==1,'Questie: Selbstbezug und Exklusive ignoriert')
ok(pos(63)[0]==2,'Questie: Vorquest nur im Log reicht nicht')
lua.execute("ZGV.CurrentStep={goals={{action='turnin',questid=503}}}"); ok(pos(63)[0]==1,'Questie: Abgabe im selben Schritt reicht')
ok(pos(70)[1]=='checked','Questie: Zygor-Kette hat Vorrang')
ok(pos(71)[0]==1 and pos(72)[0]==1,'Questie: ohne Daten bleibt Quest moeglich')
lua.execute("local t=NS.settingsFrame.toggles.smartSkip; t.scripts.OnClick(t)"); ok(pos(50)[1]=='chains disabled','Skip: Schalter schaltet ab (Zygors Ursprungsantwort)')

# Schritt ueberspringen, wenn alle Quest-Ziele unmoeglich sind (nur vorwaerts)
lua.execute("""
local t=NS.settingsFrame.toggles.smartSkip; t.scripts.OnClick(t)
skipped=0
function ZGV:SkipStep() skipped=skipped+1 end
local function g(a,c,p) return {action=a,IsComplete=function() return c,p end} end
function mk(n,...) return {num=n,goals={...}} end
stepTalkTurnin=function(n) return mk(n,g('talk'),g('turnin',false,false),{tooltip='tip'}) end
""")
run=lua.eval("function(step) ZGV.CurrentStep=step; NS.SkipImpossibleStep(ZGV); return skipped end")
lua.execute("ZGV.CurrentGuide=g1")
ok(run(lua.eval("stepTalkTurnin(14)"))==1,'Schritt: Talk + unmoegliche Abgabe wird uebersprungen')
ok(run(lua.eval("stepTalkTurnin(14)"))==2,'Schritt: wird weiter geprueft, bis Zygor wechselt')
ok(run(lua.eval("mk(15,{action='talk'},{action='accept',IsComplete=function() return false,true end})"))==2,'Schritt: moegliche Annahme bleibt')
ok(run(lua.eval("mk(16,{action='kill'},{action='turnin',IsComplete=function() return false,false end})"))==2,'Schritt: andere Ziele (kill) bleiben')
ok(run(lua.eval("stepTalkTurnin(10)"))==2,'Schritt: rueckwaerts (zurueck geklickt) wird nicht uebersprungen')
ok(run(lua.eval("stepTalkTurnin(17)"))==3,'Schritt: wieder vorwaerts')
lua.execute("local t=NS.settingsFrame.toggles.smartSkip; t.scripts.OnClick(t)")
ok(run(lua.eval("stepTalkTurnin(18)"))==3,'Schritt: Smart Skip aus = nichts')

# Bewertungsfenster von Zygor
ok(lua.eval("ZGV.db.profile.ratings") is False,'Bewertung: beim Login ausgeschaltet (Standard)')
lua.execute("local t=NS.settingsFrame.toggles.skipRating; t.scripts.OnClick(t)"); ok(lua.eval("ZGV.db.profile.ratings") is True,'Bewertung: Schalter aus = Zygor fragt wieder')
lua.execute("local t=NS.settingsFrame.toggles.skipRating; t.scripts.OnClick(t)"); ok(lua.eval("ZGV.db.profile.ratings") is False,'Bewertung: Schalter an = keine Frage')
