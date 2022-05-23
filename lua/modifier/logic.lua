
local util = require "luci.util"
local log = require "openrules.util.log"

local logic = {}

function logic:updateif(varname, setting) --[[
	Updateif modifier realization.
	Substitute values instead variables
	and check logic expression
	]]

	local varlink = setting[varname] or {}
	local logic_body, result, status = '', true, true

    if not varlink.modifier then
        return true
    end

	for name, value in util.kspairs(varlink.modifier) do
		if(name:sub(3) == "updateif") then
			logic_body = value

			for name, _ in pairs(setting) do
				if(type(setting[name].output) == "string") then
					logic_body = logic_body:gsub('$'..name, setting[name].output)
				end
			end

			local finalcode = logic_body and loadstring(logic_body)
			if finalcode then
				status, result = pcall(finalcode)
				if status == false then
					print("openrules: Error in [" .. varname .. "] updateif modifier pcall(finalcode): " .. result)
					--log(varname, logic_body)
					return false
				end
			else
				print("openrules: Error in [" .. varname .. "] updateif modifier finalcode: " .. logic_body)
				--log(varname, logic_body)
				return false
			end

			if not (result == true or result == false) then
				print("openrules: Error in [" .. varname .. "] updateif modifier returns NIL (but true/falce required): " .. logic_body)
				--log(varname, logic_body)
				result = false

			end

		end
	end
	return result
end

return logic
