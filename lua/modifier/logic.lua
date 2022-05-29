
local util = require "luci.util"
local log = require "applogic.util.log"

local logic = {}

function logic:skip(varname, rule)
	local debug = require "applogic.var.debug".init(rule)
	local setting = rule.setting
	local varlink = rule.setting[varname]
	varlink.input = varlink.input or ""
	varlink.output = varlink.ouput or ""
	local logic_body = ""
	local skip = false
	noerror = true
	debug(varname):input(varlink.input, noerror)
	debug(varname):output(varlink.output, noerror)


    if not varlink.modifier or #util.keys(varlink.modifier) == 0 then
        skip = false
    else
		for mdf_name, value in util.kspairs(varlink.modifier) do
			if(mdf_name:sub(3) == "skip") then
				logic_body = value

				for name, _ in pairs(rule.setting) do
					if name ~= varname then
						logic_body = logic_body:gsub('$'..name, tostring(setting[name].output))
					else
					--[[ If the Func has current variable name, substitute subtotal instead of output
						 because output value will be set after all modifiers have been applied. ]]
						chunk = logic_body:gsub('$'..logic_body, tostring(setting[name].subtotal))
					end
				end



				local finalcode = logic_body and loadstring(logic_body)
				if finalcode then
					noerror, skip = pcall(finalcode)
					if noerror == false then
						skip = true
					end
				else
					skip = true
					noerror = false
				end
			end
			debug(varname):modifier(mdf_name, logic_body, skip, noerror)
		end
	end
	return skip
end
return logic