local util = require "luci.util"
local substitute = require "applogic.util.substitute"
local pcallchunk = require "applogic.util.pcallchunk"

function trigger(varname, rule)
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug" end
	local result = false
	local noerror = true

	local mdf_body = rule.setting[varname].modifier["1_trigger"]
	local luacode = substitute(varname, rule, mdf_body, true)


	local noerror, res = pcallchunk(luacode)
	if res == nil then
		noerror = false
		result = false -- Trigger the var anyway if error in lua chank
	else
		result = res
	end

	if rule.debug_mode.enabled then
		luacode = luacode:gsub("^%s+", ""):gsub("%s$", "") or ""
		debug(varname, rule):modifier("1_trigger", luacode, result, noerror)
	end

	return result
end

return trigger
