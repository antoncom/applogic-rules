
local substitute = require "applogic.util.substitute"
local pcallchunk = require "applogic.util.pcallchunk"

function func(varname, mdf_name, rule) --[[
	Apply modifiers to the target value
	---------------------------------]]
	local debug
	if rule.debug then debug = require "applogic.var.debug".init(rule) end
	local varlink = rule.setting[varname]
	local result = ""
	local noerror = true
	local body = rule.setting[varname].modifier[mdf_name]
	body = body:gsub("^%s+", ""):gsub("%s$", "") or ""

	local from_output = (not varlink.source) and mdf_name:sub(1,1) == "1"
	local luacode = substitute(varname, rule, body, from_output)

	local noerror, res = pcallchunk(luacode)
	result = res or ""

	if rule.debug then debug(varname):modifier(mdf_name, luacode, result, noerror) end

	return result
end

return func
