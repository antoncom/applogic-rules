
local util = require "luci.util"
local log = require "applogic.util.log"
local md5 = require "md5" -- https://github.com/keplerproject/md5/blob/master/tests/test.lua
local sys = require "luci.sys"
local substitute = require "applogic.util.substitute"

local loadvar_bash = {}

function loadvar_bash:load(varname, rule)
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug" end

	local setting = rule.setting
	local varlink = rule.setting[varname]
	local cache_key = ""
	local result = {}
	local noerror = true

	--[[ LOAD FROM BASH ]]
	local command = varlink.source.command or ""
	command = substitute(varname, rule, command, false)

	varlink.bash_join = command


	cache_key = md5.sumhexa(varname.."bash"..command)
	if not rule.cache_bash[cache_key] then
		result = sys.process.exec({"/bin/sh", "-c", command}, true, true, false)
		noerror = not result.stderr
		if noerror then
			rule.cache_bash[cache_key] = result.stdout and string.format("%s", result.stdout) or ""
		end
	end
	if rule.debug_mode.enabled then debug(varname, rule):source_bash(command, rule.cache_bash[cache_key] or "", noerror) end

	return rule.cache_bash[cache_key]
end

return loadvar_bash
