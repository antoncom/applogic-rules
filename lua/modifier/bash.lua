

function bash(varname, command, setting) --[[
	Apply modifiers to the target value
	---------------------------------]]
	local varlink = setting[varname] or {}

	-- Replace all variables in the Command text with actual values
    for name, _ in pairs(setting) do
        if(type(setting[name].output) == "string") then
            if name ~= varname then
                command = command:gsub('$'..name, setting[name].output)
            else
                -- If the Command has current variable name, then substitute subtotal instead of output
                -- because output value will be set after all modifiers have been applied.
                command = command:gsub('$'..name, setting[name].subtotal)
            end
        else
            log(string.format("openrules: Unable to substitute variable value to bash command from %s.output] as it's not a string value.", name))
            break
        end
    end

    return luci.sys.exec(command) or ""
end

return bash
