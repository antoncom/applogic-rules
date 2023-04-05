local util = require "luci.util"
local log = require "applogic.util.log"
local last_mdfr_name = require "applogic.util.last_mdfr_name"


require "applogic.modifier.skip"
require "applogic.modifier.lua"
require "applogic.modifier.bash"
require "applogic.modifier.frozen"
require "applogic.modifier.trigger"
require "applogic.modifier.save"
require "applogic.modifier.shell"
require "applogic.modifier.ui_update"


local main = {}
function main:modify(varname, rule) --[[
	Apply modifiers to the target value
	---------------------------------]]

	--profiler.start()
	-- Code block and/or called functions to profile --



	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug" end
	local varlink = rule.setting[varname]

    -- Before the modifier applies, we put load the initial (input) value to intermediate (subtotal)
	--varlink.subtotal = varlink.subtotal or string.format("%s", tostring(varlink.input))

	if(varlink["saved"]) then
		varlink.input = varlink["saved"]
		print("SAVED:", varlink["saved"])
	end

	varlink.subtotal = varlink.subtotal or string.format("%s", tostring(varlink.input))

	if varlink.modifier then --and #util.keys(varlink.modifier) > 0 then
        for mdf_name, mdf_body in util.kspairs(varlink.modifier) do
			if not varlink.frozen  then
	            if "skip" == mdf_name:sub(3) then
	                local is_skip = skip(varname, rule)
	                if is_skip then
						-- Если указать у переменной input = "some value"
						-- то перед отменой обработки присвоить переменно йзначение из input
						-- иначе в переменной останется хранится последнее расчётное значение (из output)
						 varlink.subtotal = varlink.input or varlink.output or ""
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
	                varlink.subtotal = func(varname, mdf_name, rule)
	            end

	            if "bash" == mdf_name:sub(3) then
	                varlink.subtotal = bash(varname, mdf_name, mdf_body, rule)
	            end

				if "save" == mdf_name:sub(3) then
	                varlink.subtotal = save(varname, mdf_name, rule)
	            end

				if "shell" == mdf_name:sub(3) then
					shell(varname, mdf_name, mdf_body, rule)
				end

				if "ui-update" == mdf_name:sub(3) then
					ui_update(varname, mdf_name, mdf_body, rule)
				end
			end

            if "frozen" == mdf_name:sub(3) then
                frozen(varname, rule, mdf_name)
            end
            --- Place more modifiers here ---

        end
    end
	-- Afterall, put subtotal to output
	-- Remove trailing \n if only one string returned
	if(type(varlink.subtotal) == "table") then
		varlink.output = util.serialize_json(varlink.subtotal)
	else
		varlink.output = string.format("%s", varlink.subtotal)
		local _, n = varlink.output:gsub("\n", "\n")
		if n == 1 then varlink.output = varlink.output:gsub("%s+$", "") end
	end


	if rule.debug_mode.enabled then debug(varname, rule):output(varlink.output) end
	--varlink.subtotal = nil
	--varlink.bash_join = nil

	-- profiler.stop()
	-- profiler.report("profiler.log")
end


return main
