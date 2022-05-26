
local util = require "luci.util"
local log = require "applogic.util.log"
local uci = require "luci.model.uci".cursor()
local md5 = require "md5" -- https://github.com/keplerproject/md5/blob/master/tests/test.lua
local sys = require "luci.sys"
local nixio = require "nixio"

local loadvar_bash = {}

function loadvar_bash:load(varname, rule)
	local debug = require "applogic.var.debug".init(rule)
	local setting = rule.setting
	local varlink = rule.setting[varname]
	local cache_key = ""
	local result = {}
	local noerror = true


	local command = varlink.source.command or ""

	-- Substitute variable value if bash command contains the variable name
	for name, _ in pairs(setting) do
		command = command:gsub("$"..name, setting[name].output or "")
	end

	cache_key = md5.sumhexa(varname.."bash"..command)
	if not rule.cache_bash[cache_key] then
		result = sys.process.exec({"/bin/sh", "-c", command}, true, true, false)
		noerror = not result.stderr
		if noerror then
			rule.cache_bash[cache_key] = result.stdout or ""
		end
	end

	debug(varname):source_bash(command, rule.cache_bash[cache_key] or "", noerror)
	varlink.subtotal = rule.cache_bash[cache_key]


end

return loadvar_bash
