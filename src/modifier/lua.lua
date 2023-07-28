
local substitute = require "applogic.util.substitute"
local pcallchunk = require "applogic.util.pcallchunk"
local util = require "luci.util"

function func(varname, mdf_name, rule) --[[
	Apply modifiers to the target value
	---------------------------------]]
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug" end
	local varlink = rule.setting[varname]
	local result = ""
	local noerror = true
	local body = rule.setting[varname].modifier[mdf_name]

	local from_input = (not varlink.source) and mdf_name:sub(1,1) == "1"

	local luacode = substitute(varname, rule, body, from_input, true)
	local noerror, res = pcallchunk(luacode)
	result = res or ""


	if rule.debug_mode.enabled then
		luacode = luacode:gsub("^%s+", ""):gsub("%s$", "") or ""
		--if(type(result) == "table") then result = util.serialize_json(result) end
		debug(varname, rule):modifier(mdf_name, luacode, result, noerror)
	end

	-- if (type(result) == "number") then result = tostring(result) end
	-- if (type(result) == "table") then result = util.serialize_json(result) end
	-- if (type(result) == "function") then result = tostring(result) end
	-- if (type(result) == "userdata") then result = tostring(result) end
	return result
end

return func
