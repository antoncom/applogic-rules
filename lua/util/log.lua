local util = require "luci.util"

function log(title, obj)
	if(obj ~= nil) then
		if(type(obj) == "table") then
			util.perror(title)
			util.perror("====== START ========")
			util.dumptable(obj)
			util.perror("====== END ========")
		elseif(type(obj) == "string") then
			util.perror(title .. " = " .. obj)
		else
			util.perror(title .. " = " .. tostring(obj))
		end
	else
		util.perror(title)
	end
	return true
end

return log
