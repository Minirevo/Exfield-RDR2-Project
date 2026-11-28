ShopRules={}
local R=ShopRules
function R.int(n,min,max) return type(n)=='number' and n==n and n%1==0 and n>=min and n<=max end
function R.near(p,s,r) return p and s and p.bucket==0 and (p.x-s.x)^2+(p.y-s.y)^2+(p.z-s.z)^2<=r*r or false end
function R.basket(catalog,mode,lines,limits)
 if mode~='buy' and mode~='sell' then return nil,'Invalid transaction.' end
 if type(lines)~='table' or #lines<1 or #lines>limits.maxLines then return nil,'Select items first.' end
 local out,total,seen={},0,{}
 for _,l in ipairs(lines) do
  if type(l)~='table' or type(l.id)~='string' or seen[l.id] or not R.int(l.quantity,1,limits.maxQuantity) then return nil,'Invalid quantity or duplicate item.' end
  local d=catalog[l.id];local price=d and d[mode]
  if not R.int(price,1,limits.maxTotal) then return nil,'Item not available at this counter.' end
  if d.maxStack==1 and l.quantity>1 then return nil,'Purchase individual equipment one at a time.' end
  seen[l.id]=true;total=total+price*l.quantity
  if total>limits.maxTotal then return nil,'Basket exceeds transaction limit.' end
  out[#out+1]={id=l.id,quantity=l.quantity}
 end
 table.sort(out,function(a,b)return a.id<b.id end)
 return out,total
end
