
local util = require "luci.util"
local log = require "openrules.util.log"


local all = {
	["func"] = require "openrules.modifier.func",
	["bash"] = require "openrules.modifier.bash",
}

function all:modify(varname, setting) --[[
	Apply modifiers to the target value
	---------------------------------]]

	local varlink = setting[varname] or {}

	-- Before the modifier applies, we put load the initial (input) value to intermediate (subtotal)
	varlink.subtotal = varlink.subtotal or string.format("%s", tostring(varlink.input))


	if not varlink.modifier then
		return
	end

	-- If modifiers are existed, then modify input and save to output
	for modifier_name, modifier_value in util.kspairs(varlink.modifier) do

		if "func" == modifier_name:sub(3) then
			local apply = all["func"]
			apply(varname, modifier_value, setting)
		end

		if "bash" == modifier_name:sub(3) then
			local apply = all["bash"]
			apply(varname, modifier_value, setting)
		end

		-- Place more modifiers here
	end

	-- After all modifiers was applied, we put result to "output"
	if(varlink.subtotal) then
		if(type(varlink.subtotal) == "table") then
			varlink.output = util.serialize_json(varlink.subtotal)
		elseif(type(varlink.subtotal) == "number") then
			varlink.output = tostring(varlink.subtotal)
		end
		varlink.output = string.format("%s", varlink.subtotal)
		varlink.subtotal = nil
	end

end

return all
