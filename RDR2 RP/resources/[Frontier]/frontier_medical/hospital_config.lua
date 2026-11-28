-- All money is integer cents. Gameplay prices are configurable, not historical claims.
FrontierHospitalConfig={
 hourlyFunding=5000,initialFunding=10000,fundingInterval=3600,invoiceDueSeconds=86400,
 reach=4.0,spawnDistance=65.0,policeAce='frontier.medical.police',maxIssuePerHour=3,
 stations={
  valentine={name='Valentine Hospital',x=-288.82,y=808.44,z=119.43,heading=90,model='U_M_M_VALDOCTOR_01'},
  strawberry={name='Strawberry Hospital',x=-1807.87,y=-430.77,z=158.83,heading=90,model='U_M_M_VALDOCTOR_01'},
  saint_denis={name='Saint Denis Hospital',x=2721.29,y=-1233.11,z=50.37,heading=90,model='U_M_M_NBXDOCTOR_01'}
 },
 supplies={
  bandage={label='Bandage',price=25,max=10},splint={label='Basic splint',price=50,max=4},tonic={label='Pain tonic',price=75,max=4},
  stethoscope={label='Stethoscope',price=250,max=1},thermometer={label='Thermometer',price=125,max=1},surgical_kit={label='Surgical instruments',price=500,max=1},
  surgical_supplies={label='Surgical supplies',price=100,max=10},suture_kit={label='Suture kit',price=75,max=6},antiseptic={label='Antiseptic',price=50,max=6},
  medical_splint={label='Medical splint',price=100,max=4},morphine={label='Morphine',price=150,max=6},saline_solution={label='Saline',price=125,max=6}
 },
 kits={
  standard={label='Standard medical kit',items={bandage=5,splint=2,tonic=2,stethoscope=1,thermometer=1}},
  surgical={label='Surgical kit',items={surgical_kit=1,surgical_supplies=5,suture_kit=3,antiseptic=3,medical_splint=2}},
  medication={label='Medication kit',items={morphine=3,saline_solution=3}}
 },
 fees={
  bandage={label='Bandage applied',price=75},splint={label='Basic fracture stabilisation',price=100},tonic={label='Pain tonic administered',price=125},
  disinfect={label='Wound cleaning',price=100},extract={label='Foreign object removal',price=500},haemostasis={label='Internal bleeding control',price=400},
  repair={label='Organ injury treatment',price=600},suture={label='Deep wound closure',price=200},realign={label='Fracture realignment',price=300},
  morphine={label='Morphine administered',price=250},saline={label='Circulatory support',price=225}
 }
}
