
local sys = require "luci.sys"
local log = require "applogic.util.log"

function bash(varname, mdf_name, mdf_body, setting, rule) --[[
	Apply modifiers to the target value
	---------------------------------]]
	local debug = require "applogic.var.debug".init(rule)
	local varlink = setting[varname] or {}
	local command = mdf_body or ""
	local result = {}
	local noerror = true

	-- Replace all variables in the Command text with actual values
    for name, _ in pairs(setting) do
        if name ~= varname then
            command = command:gsub('$'..name, (setting[name].output or ""))
        else
            -- If the Command has current variable name, then substitute subtotal instead of output
            -- because output value will be set after all modifiers have been applied.
            command = command:gsub('$'..name, (setting[name].subtotal or ""))
        end
    end

	-- Because we already have initial value (or from previous modifier)
	-- we need to prepend "echo ... | " before new bash command
	local command_extra = string.format([[echo '%s' | %s]], setting[varname].subtotal, command)
	command_extra = command_extra:gsub("%c", "")

	result = sys.process.exec({"/bin/sh", "-c", command_extra }, true, true, false)

	noerror = (not result.stderr) and (result.code == 0)
	debug(varname):modifier(mdf_name, command, result.stdout or "", noerror)

	return result.stdout or ""
end

return bash
