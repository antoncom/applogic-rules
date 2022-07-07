
local sys = require "luci.sys"
local util = require "luci.util"
local uloop = require "uloop"
local log = require "applogic.util.log"

function shell(varname, mdf_name, shell, rule) --[[
	Apply modifiers to the target value
	---------------------------------]]
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug" end
	local varlink = rule.setting[varname] or {}
	local result
	local noerror = true

	local shell_split = util.split(shell, " ")
	local command = shell_split[1]
	table.remove(shell_split, 1)
	local args = shell_split

	local from_input = (not varlink.source) and mdf_name:sub(1,1) == "1"
	local result_shell_command = ""
	for _,arg in pairs(args) do
		arg = substitute(varname, rule, arg, from_input, true)
		result_shell_command = result_shell_command .. " " .. arg
	end

	log("-- SUBSTITUTED ARGS --", args)

	function call_back(r)
		log("SHELL R", r)
		result = "SHELL DONE"
		varlink.output = result

		if rule.debug_mode.enabled then
			debug(varname, rule):modifier(mdf_name, result_shell_command, result, noerror)
		end
	end

	--uloop.process("/usr/lib/lua/luci/model/tsmodem/util/ping.sh", {"--host", host_spc_sim }, {"PROCESS=1"}, call_back)
	uloop.process(command, args, {"PROCESS=1"}, call_back)

end

return shell
