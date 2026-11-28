dofile('config.lua');dofile('model.lua');dofile('professional.lua')
local M,C=FrontierMedicalModel,FrontierMedicalConfig
local s=M.new()
for i=1,4 do assert(M.injure(s,'left_leg','penetrating',7,0)) end
local w=s.wounds.left_leg
assert(w.fracture and w.bone==100 and w.projectile==2)
assert(M.treat(s,'splint','left_leg',0) and not M.canHeal(w))
assert(M.applyProcedure(s,'left_leg','realign','success',0) and w.aligned)
s=M.new();M.injure(s,'chest','penetrating',10,0)
w=s.wounds.chest;assert(w.internal>0 and w.organ>0 and w.projectile==1)
M.treat(s,'bandage','chest',0);assert(M.bleed(s)==0 and M.internalBleed(s)>0)
local blood=s.blood;M.tick(s,5,true);assert(s.blood<blood)
assert(not M.procedureEligible(s,'chest','suture',5))
assert(M.applyProcedure(s,'chest','haemostasis','success',5))
assert(M.applyProcedure(s,'chest','repair','success',5))
assert(M.applyProcedure(s,'chest','extract','success',5))
assert(M.applyProcedure(s,'chest','disinfect','success',5))
assert(M.applyProcedure(s,'chest','suture','success',5) and M.canHeal(w))
s=M.new();assert(M.testInjury(s,'right_arm','splinter',30,0));w=s.wounds.right_arm
local bleed=w.bleed
assert(not M.applyProcedure(s,'right_arm','extract','failed',0) and w.fragment==1)
assert(M.applyProcedure(s,'right_arm','extract','complication',0) and w.fragment==1 and w.bleed>bleed)
assert(M.applyProcedure(s,'right_arm','extract','success',0) and w.fragment==0)
assert(M.scoreStage(1500,1500,400)=='success')
assert(M.scoreStage(2200,1500,400)=='failed')
assert(M.scoreStage(3000,1500,400)=='complication')
assert(M.scoreStage(5000,1500,400)=='failed')
assert(not M.testInjury(s,'head','fracture',30,0))
assert(not M.testInjury(s,'left_leg','organ',30,0))
s=M.new();s.shock=500
assert(M.applyProcedure(s,'chest','saline','success',0) and s.blood==1000 and s.shock==300)
assert(not M.procedureEligible(s,'invalid','saline',0))
print('Professional injury and procedure model tests passed')
