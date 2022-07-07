local util = require "luci.util"
local substitute = require "applogic.util.substitute"
local pcallchunk = require "applogic.util.pcallchunk"

function save(varname, mdf_name, rule)
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug" end
	local varlink = rule.setting[varname]
	local result = false
	local noerror = true
	local body = rule.setting[varname].modifier[mdf_name]

	local from_input = (not varlink.source) and mdf_name:sub(1,1) == "1"
	local luacode = substitute(varname, rule, body, from_input, true)

	local noerror, res = pcallchunk(luacode)
	result = res or ""

	if (noerror) then
		varlink["saved"] = result
	end

	if rule.debug_mode.enabled then
		mdfluacode_body = luacode:gsub("^%s+", ""):gsub("%s$", "") or ""
		debug(varname, rule):modifier("1_save", luacode, result, noerror)
	end

	return result
end

return save
