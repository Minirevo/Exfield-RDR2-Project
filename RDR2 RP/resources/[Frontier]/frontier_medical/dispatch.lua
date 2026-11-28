-- In-memory emergency dispatch; coordinates and identities are supplied by the server.
FrontierMedicalDispatch={}
local D=FrontierMedicalDispatch
function D.new() return {calls={},duty={},serial=0} end
function D.same(call,id,life,bucket)
 return call and call.patient==id and call.life==life and call.bucket==bucket
end
function D.open(board,src,id,life,bucket,pos)
 local existing=board.calls[src]
 if D.same(existing,id,life,bucket) then return existing,false end
 board.serial=board.serial+1
 local call={number=board.serial,source=src,patient=id,life=life,bucket=bucket,pos=pos}
 board.calls[src]=call;return call,true
end
function D.claim(board,call,src,id,bucket)
 if not call or board.calls[call.source]~=call or board.duty[src]~=id or src==call.source or call.bucket~=bucket then return false,'unavailable' end
 if call.responder then
  if call.responder==src and call.responderId==id then return true end
  return false,'assigned'
 end
 for _,other in pairs(board.calls) do if other.responder==src then return false,'busy' end end
 call.responder=src;call.responderId=id;return true
end
function D.release(call)
 local src,id=call.responder,call.responderId
 call.responder=nil;call.responderId=nil
 return src,id
end
function D.close(board,call)
 if board.calls[call.source]~=call then return false end
 board.calls[call.source]=nil;return true
end
function D.find(board,number)
 for _,call in pairs(board.calls) do if call.number==number then return call end end
end
