
local util = require "luci.util"
local log = require "applogic.util.log"
local last_mdfr_name = require "applogic.util.last_mdfr_name"


require "applogic.modifier.skip"
require "applogic.modifier.func"
require "applogic.modifier.bash"
require "applogic.modifier.frozen"
require "applogic.modifier.trigger"

local main = {}
function main:modify(varname, rule) --[[
	Apply modifiers to the target value
	---------------------------------]]
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug".init(rule) end
	local varlink = rule.setting[varname]

    -- Before the modifier applies, we put load the initial (input) value to intermediate (subtotal)
	varlink.subtotal = varlink.subtotal or string.format("%s", tostring(varlink.input))

	if varlink.modifier and #util.keys(varlink.modifier) > 0 then
        for mdf_name, mdf_body in util.kspairs(varlink.modifier) do
			if not varlink.frozen  then
	            if "skip" == mdf_name:sub(3) then
	                local is_skip = skip(varname, rule)
	                if is_skip then
	                    break
	                end
	            end
				if "trigger" == mdf_name:sub(3) then
	                local must_trigger = trigger(varname, rule)
					if not must_trigger then
	                    break
	                end
	            end
	            if "func" == mdf_name:sub(3) then
	                varlink.subtotal = tostring(func(varname, mdf_name, rule))
	            end

	            if "bash" == mdf_name:sub(3) then
	                varlink.subtotal = tostring(bash(varname, mdf_name, mdf_body, rule))
	            end
			end

            if "frozen" == mdf_name:sub(3) then
                varlink.subtotal = tostring(frozen(varname, rule, mdf_name))
            end
            --- Place more modifiers here ---

        end
    end
	-- Afterall, put subtotal to output
	-- Remove trailing \n if only one string returned
	varlink.output = string.format("%s", varlink.subtotal)
	local _, n = varlink.output:gsub("\n", "\n")
	if n == 1 then varlink.output = varlink.output:gsub("%s+$", "") end

	if rule.debug_mode.enabled then debug(varname):output(varlink.output) end
	varlink.subtotal = nil
	varlink.bash_join = nil
end

return main
