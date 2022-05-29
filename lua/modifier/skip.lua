local util = require "luci.util"
local substitute = require "applogic.util.substitute"
local pcallchunk = require "applogic.util.pcallchunk"

function skip(varname, rule)
	local debug
	if rule.debug then debug = require "applogic.var.debug".init(rule) end
	local result = false
	local noerror = true

	local mdf_body = rule.setting[varname].modifier["1_skip"]
	mdf_body = mdf_body:gsub("^%s+", ""):gsub("%s$", "") or ""
	local luacode = substitute(varname, rule, mdf_body)


	local noerror, res = pcallchunk(luacode)
	if res == nil then noerror = false end
	result = res or false

	if rule.debug then debug(varname):modifier("1_skip", luacode, result, noerror) end

	return result
end

return skip
