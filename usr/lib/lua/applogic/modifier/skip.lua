local util = require "luci.util"
local substitute = require "applogic.util.substitute"
local pcallchunk = require "applogic.util.pcallchunk"

function skip(varname, rule)
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug" end
	local result = false
	local noerror = true

	local mdf_body = rule.setting[varname].modifier and rule.setting[varname].modifier["1_skip"] or 'Mistype: always use ["1_skip"] as skip modifier name.'

	local luacode = substitute(varname, rule, mdf_body, true, true)

	local noerror, res = pcallchunk(luacode)
	if res == nil then
		noerror = false
		result = true -- Skip anyway if error in lua chank
	else
		result = res
	end

	if rule.debug_mode.enabled then
		mdfluacode_body = luacode:gsub("^%s+", ""):gsub("%s$", "") or ""
		debug(varname, rule):modifier("1_skip", luacode, result, noerror)
	end

	return result
end

return skip
