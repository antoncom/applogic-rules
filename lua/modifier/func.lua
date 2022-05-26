

function func(varname, mdf_name, mdf_body, rule, setting) --[[
	Apply modifiers to the target value
	---------------------------------]]
	local debug = require "applogic.var.debug".init(rule)
	local varlink = setting[varname] or {}
	varlink.input = varlink.input or ""
	varlink.output = varlink.ouput or ""
	local result = ""
	local noerror = true

	-- Replace all variables in the Func text with actual values
	local luacode = (function(chunk)
		for name, _ in pairs(setting) do
			if name ~= varname then
				chunk = chunk:gsub('$'..name, tostring(setting[name].output))
			else
			--[[ If the Func has current variable name, substitute subtotal instead of output
				 because output value will be set after all modifiers have been applied. ]]
                chunk = chunk:gsub('$'..name, tostring(setting[name].subtotal))
			end
		end
		return chunk
	end)(mdf_body)

	local finalcode = luacode and loadstring(luacode)
	--if varname == "timer" then log(luacode) end

	if finalcode then
		status, result = pcall(finalcode)
		if status == false then
			--print(string.format("applogic: Error in pcall(finalcode) for [%s]: %s", varname, tostring(result)))
			--log(varname, luacode)
			noerror = false
			result = ""
		end
	else
		--print(string.format("applogic: Error in loadstring(luacode) for [%s]: %s", varname, tostring(result)))
		noerror = false
	end

	--result = varlink.subtotal
	--rule:debug(varname, "modifier", "func", luacode, result, noerror)
	debug(varname):modifier(mdf_name, luacode, result, noerror)
	varlink.subtotal = result


	return result

end

return func
