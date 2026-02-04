
local a = {1,2,3,4,5,6,7,8}
for _, operator in ipairs(a) do
	if(operator == 3) then
		print("a= " .. tostring(operator))
		goto continue
	end
	print("after continue")
	::continue::
end