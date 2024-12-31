
local sys = require "luci.sys"
local log = require "applogic.util.log"

function bash(varname, mdf_name, mdf_body, rule) --[[
	Apply modifiers to the target value
	---------------------------------]]
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug" end
	local varlink = rule.setting[varname] or {}
	local command = mdf_body and mdf_body:gsub("^%s+", ""):gsub("%s$", "") or ""
	local command_extra

	local result = {}
	local noerror = true

	local from_output = (not varlink.source) and mdf_name:sub(1,1) == "1"
	command = substitute(varname, rule, command, from_output, true)

	-- Because we already probably have initial value (or from previous modifier)
	-- we need to prepend "echo ... | " before new bash command

	local command_extra = ""
	if (varlink.subtotal:len() > 0 and varlink.subtotal ~= "\"\"" and varlink.subtotal ~= "''") then
		-- Remove "'" from bash command to prevent errors
		rule.setting[varname].subtotal = rule.setting[varname].subtotal:gsub("'", "")
		command_extra = string.format("echo '%s' | %s", rule.setting[varname].subtotal, command)

		command_extra = command_extra:gsub("%c", "")
		--if varname == "ussd_command" then print("COMMAND_EXTRA=", command_extra) end
		result = sys.process.exec({"/bin/sh", "-c", command_extra }, true, true, true)

		if result.stdout then
			result.stdout = result.stdout:gsub("%c", "")
		end
	end

	noerror = (not result.stderr)
	if rule.debug_mode.enabled then
		debug(varname, rule):modifier_bash(mdf_name, command_extra, result, noerror)
	end

	return result.stdout or ""
end

return bash
