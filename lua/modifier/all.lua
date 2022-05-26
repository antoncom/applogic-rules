
local util = require "luci.util"
local log = require "applogic.util.log"


local all = {
	["func"] = require "applogic.modifier.func",
	["bash"] = require "applogic.modifier.bash",
}

function all:modify(varname, setting, rule) --[[
	Apply modifiers to the target value
	---------------------------------]]
	local debug = require "applogic.var.debug".init(rule)
	local varlink = setting[varname] or {}

	-- Before the modifier applies, we put load the initial (input) value to intermediate (subtotal)
	varlink.subtotal = varlink.subtotal or string.format("%s", tostring(varlink.input))

	if not varlink.modifier then
		varlink.output = string.format("%s", varlink.subtotal)
		debug(varname):output(varlink.output:gsub("\t", " "))
		return
	else
		-- If modifiers are existed, then modify input and save to output
		for mdf_name, mdf_body in util.kspairs(varlink.modifier) do
			if "func" == mdf_name:sub(3) then
				local apply = all["func"]
				varlink.subtotal = apply(varname, mdf_name, mdf_body, rule, setting)
			end

			if "bash" == mdf_name:sub(3) then
				local apply = all["bash"]
				varlink.subtotal = apply(varname, mdf_name, mdf_body, setting, rule)
			end

			--- Place more modifiers here ---

		end
		-- After all modifiers was applied, we put result to "output"
		if(varlink.subtotal) then
			if(type(varlink.subtotal) == "table") then
				varlink.output = util.serialize_json(varlink.subtotal)
			else
				varlink.output = string.format("%s", tostring(varlink.subtotal))
			end

			debug(varname):output(varlink.output or "")

			varlink.subtotal = nil
		end
	end

end

return all
