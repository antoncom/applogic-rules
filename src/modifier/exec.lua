
local sys = require "luci.sys"
local log = require "applogic.util.log"

function exec(varname, mdf_name, mdf_body, rule) --[[
	Apply modifiers to the target value
	---------------------------------]]
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug" end
	local varlink = rule.setting[varname] or {}
	local command = mdf_body and mdf_body:gsub("^%s+", ""):gsub("%s$", "") or ""

	local result = {}
	local noerror = true

	local from_output = (not varlink.source) and mdf_name:sub(1,1) == "1"
	command = substitute(varname, rule, command, from_output, true)

	command = command:gsub("%c", "")
	result = sys.process.exec({"/bin/sh", "-c", command }, true, true, true)

	if result.stdout then
		result.stdout = result.stdout:gsub("%c", "")
	end

	noerror = (not result.stderr)
	if rule.debug_mode.enabled then
		debug(varname, rule):modifier_bash(mdf_name, command, result, noerror)
	end

	return result.stdout or ""
end

return exec
