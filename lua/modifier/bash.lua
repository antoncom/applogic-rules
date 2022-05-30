
local sys = require "luci.sys"
local log = require "applogic.util.log"

function bash(varname, mdf_name, mdf_body, rule) --[[
	Apply modifiers to the target value
	---------------------------------]]
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug".init(rule) end
	local varlink = rule.setting[varname] or {}
	local command = mdf_body and mdf_body:gsub("^%s+", ""):gsub("%s$", "") or ""
	local command_extra = ""

	local result = {}
	local noerror = true

	local from_output = (not varlink.source) and mdf_name:sub(1,1) == "1"
	command = substitute(varname, rule, command, from_output)

	-- Because we already probably have initial value (or from previous modifier)
	-- we need to prepend "echo ... | " before new bash command

	local command_extra = ""
	if varlink.subtotal:len() > 0 then
		command_extra = string.format("echo '%s' | %s", rule.setting[varname].subtotal, command)
	else
		command_extra = string.format("%s", command)
	end

	command_extra = command_extra:gsub("%c", "")
	result = sys.process.exec({"/bin/sh", "-c", command_extra }, true, true, false)

	if result.stdout then
		result.stdout = result.stdout:gsub("%c", "")
	end

	noerror = (not result.stderr)
	if rule.debug_mode.enabled then debug(varname):modifier_bash(mdf_name, command, result, noerror) end

	return result.stdout or ""
end

return bash
