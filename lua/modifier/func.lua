

function func(varname, formula, setting) --[[
	Apply modifiers to the target value
	---------------------------------]]
	local varlink = setting[varname] or {}

	-- Replace all variables in the Func text with actual values
	local luacode = (function(chunk)
		for name, _ in pairs(setting) do
			if name ~= varname then
				if(type(setting[name].output) == "string") then
					chunk = chunk:gsub('$'..name, setting[name].output)
				end
			else
			--[[ If the Func has current variable name, substitute subtotal instead of output
				 because output value will be set after all modifiers have been applied. ]]
				if(type(setting[name].subtotal) == "string") then
                    chunk = chunk:gsub('$'..name, setting[name].subtotal)
				end
			end
		end
		return chunk
	end)(formula)

	local finalcode = luacode and loadstring(luacode)

	if finalcode then
		status, result = pcall(finalcode)
		if status == false then
			print("openrules: Error in pcall(finalcode) for [" .. varname .. "]: " .. result)
			log(varname, luacode)
		else
			varlink.subtotal = finalcode() or ""
		end
	else
		print("openrules: Error in loadstring(luacode) for [" .. varname .. "]: " .. result)
	end

end

return func
