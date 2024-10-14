
local sys = require "luci.sys"
local util = require "luci.util"
local log = require "applogic.util.log"

function file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

function smssend(varname, mdf_name, modifier, rule)
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug" end
	local varlink = rule.setting[varname] or {}
	local params = util.clone(modifier) or {}
	local result = ""
	local noerror = true
	local allowed_params = {"phone", "text"}
	
	if(#util.keys(params) > 0) then
		for param, value in util.kspairs(params) do
			if(util.contains(allowed_params, param) == false) then
				noerror = false
				result = string.format("Smssend parameter [%s] is not allowed!", param)
				break
			end
		end
	else
		noerror = false
		result["stdout"] = string.format("No any parameters required for Smssend!")
	end

	if(noerror) then
		-- Substitute values from matched variables
		for par_name, par_value in util.vspairs(params) do
			params[par_name] = substitute(varname, rule, par_value, false)
		end
		util.dumptable(params)
		result = rule.conn:call("tsmodem.driver", "send_sms", {
			command = params["phone"],
			value = params["text"],
		})
	end

	--noerror = (not result.stderr)
	if rule.debug_mode.enabled then
		debug(varname, rule):modifier_bash(mdf_name, params["text"], result, noerror)
	end

	return result or ""
end

return smssend
