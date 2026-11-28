dofile('rules.lua')
local R=JobsRules
assert(R.text('Help harvest',80) and not R.text('  ',80) and not R.text('bad\ntext',80))
assert(R.integer(1,1,10) and not R.integer(-1,1,10) and not R.integer(1.2,1,10))
assert(R.near({x=0,y=0,z=0,bucket=0},{x=3,y=0,z=0},4))
assert(not R.near({x=0,y=0,z=0,bucket=1},{x=0,y=0,z=0},4))
local j={state='open',poster='owner',expires=100}
assert(R.canAccept(j,'worker',99) and not R.canAccept(j,'owner',99) and not R.canAccept(j,'worker',100))
j.state='active';j.worker='worker';assert(R.canSubmit(j,'worker',99) and not R.canSubmit(j,'other',99))
j.state='submitted';assert(R.canApprove(j,'owner') and not R.canApprove(j,'worker') and not R.canAbandon(j,'worker'))
print('Frontier jobs rule checks passed')
