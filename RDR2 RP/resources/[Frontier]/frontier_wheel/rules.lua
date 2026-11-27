FrontierWheelRules={}
function FrontierWheelRules.segment(x,y,count)
 if x*x+y*y<0.09 then return 0 end
 local a=math.atan(x,-y)
 return math.floor((a+math.pi/count)/(2*math.pi/count))%count+1
end
function FrontierWheelRules.limit(x,y)
 local length=math.sqrt(x*x+y*y)
 if length>1 then return x/length,y/length end
 return x,y
end
