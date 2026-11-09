import os
from paths import ADDON, HERE, ZYGOR
# Guide finder against Zygor's real Horde guides
import re, sys
src=open(os.path.join(HERE,'test2.py'),encoding='utf8').read()
cut=src.index('parsed=lua.eval("NS.Assistant.ParseQuestGuide')
exec(src[:cut])
raw=open(os.path.join(ZYGOR,'Guides-Forever/Leveling/ZygorLevelingHordeCLASSIC.lua'),encoding='utf8',errors='replace').read()
parts=re.split(r'ZygorGuidesViewer:RegisterGuide\("',raw)[1:]
guides=[]
for p in parts:
    title=p[:p.index('"')].replace('\\\\','\\').replace('Leveling Guides','LEVELING',1)
    m=re.search(r'\},\s*\[\[(.*?)\]\]\s*\)',p,re.S)
    n=re.search(r'^next="([^"]+)"',p[:(m.start() if m else 0)],re.M)
    if m: guides.append((title,m.group(1),n.group(1).replace('\\\\','\\').replace('Leveling Guides','LEVELING',1) if n else None))
print(len(guides),'guides')
G=lua.globals(); make=lua.eval('function(t,r,n) return {title=t,rawdata=r,next=n,GetStatus=function() return "VALID" end} end')
reg=lua.table_from([make(t,r,n) for t,r,n in guides])
G.ZGV.registeredguides=reg
lua.execute(r"""ZGV.Quest_Cache={};ZGV.Quest_Cache_Accept={};ZGV.Tabs.Pool={}; obj={}; C_QuestLog.GetQuestObjectives=function(i) return obj[i] or {} end
function ZGV:GetGuideByTitle(t) for _,g in ipairs(self.registeredguides) do if g.title==t then return g end end end
function setCur(t) ZGV.CurrentGuide=ZGV:GetGuideByTitle(t) end""")
ask=lua.eval('NS.Assistant.QuestRoute')
def route(i):
    r=ask(G.ZGV,i); return [(r[k].stage,r[k].guide.title.split('\\',1)[1],r[k].ahead) for k in range(1,len(r)+1)]
def setobj(i,fin): lua.execute('obj[%d]={%s}'%(i,','.join('{finished=%s}'%str(f).lower() for f in fin)))
lua.execute(r"setCur('LEVELING\\The Barrens (24-25)')")
setobj(868,[False]); print(route(868)); ok(route(868)==[('now','The Barrens (24-25)',0)],'Egg Hunt offen: hier, Abgabe im selben Guide')
setobj(1534,[False]); print(route(1534)); ok(route(1534)==[('now','Ashenvale (26-28)',2),('now','Shaman Class Quests',None),('turnin','Thousand Needles (28-30)',3)],'Call of Water offen: jetzt plus spaetere Abgabe')
lua.execute(r"setCur('LEVELING\\Ashenvale (26-28)')"); ok(route(1534)[0][2]==0 and route(1534)[2]==('turnin','Thousand Needles (28-30)',1),'Abstand folgt aktuellem Guide')
setobj(1534,[True]); print(route(1534)); ok([x[0] for x in route(1534)]==['turnin','turnin'] and route(1534)[0][1]=='Thousand Needles (28-30)','Ziele fertig: nur Abgabe, naechster zuerst')
lua.execute(r"""tinsert=table.insert; QuestMapFrame={QuestsFrame={DetailsFrame=setmetatable({IsVisible=function() return true end,GetFrameLevel=function() return 5 end},{})}}; OathbreakerDB.guideFinder=true
tooltipRows={}""")
lua.eval('NS.Assistant.ShowFinder')(1534)
lua.execute("fb=(function() for _,f in ipairs(frames) do if rawget(f,'targets') then return f end end end)(); badgeText=nil; fb.badge.SetText=function(s,t) badgeText=t end")
lua.eval('NS.Assistant.ShowFinder')(1534); ok(lua.eval('badgeText')=='+1','Lupe zeigt +1 fuer naechsten Guide')
lua.execute("fb.scripts.OnEnter(fb)"); rows=lua.eval('#tooltipRows'); print(lua.eval('tooltipRows[1][1]'),lua.eval('tooltipRows[1][2]')); ok(rows==2 and lua.eval('tooltipRows[1][2]')=='next guide','Tooltip nennt Abstand')
lua.execute("tooltipRows={}; setobj=nil; obj[1534]={{finished=false}}"); lua.eval('NS.Assistant.ShowFinder')(1534); lua.execute("fb.scripts.OnEnter(fb)"); ok(lua.eval('tooltipRows[1][1]')=='Ashenvale (26-28)' and 'Turn in' in lua.eval('tooltipRows[3][1]'),'Tooltip: nur Abgabe beschriftet')
setobj(9001,[False]); ok(route(9001)==[],'Unbekannte Quest: leer')
# Sprung zum passenden Schritt
lua.execute(r'''gx={steps={{goals={{questid=7,action="accept"}}},{goals={{questid=7,action="collect"}}},{goals={{questid=7,action="kill",objnum=2}}},{goals={{questid=7,action="turnin"}}}}}''')
step=lua.eval('NS.Assistant.QuestStep')
lua.execute('obj[7]={{finished=true},{finished=false}}'); ok(step(G.gx,7)==3,'Sprung: offenes Ziel')
lua.execute('obj[7]={{finished=false}}'); ok(step(G.gx,7)==2,'Sprung: ohne Zielschritt Hilfsschritt')
lua.execute('obj[7]={}'); ok(step(G.gx,7)==4,'Sprung: fertig zur Abgabe')
lua.execute('obj[7]={{finished=false}}'); ok(step(G.gx,7,'turnin')==4,'Sprung: Abgabe-Zeile trotz offener Ziele')
