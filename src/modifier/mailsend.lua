
local sys = require "luci.sys"
local util = require "luci.util"
local log = require "applogic.util.log"

function file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

function mailsend(varname, mdf_name, modifier, rule)
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug" end
	local varlink = rule.setting[varname] or {}
	local params = util.clone(modifier) or {}
	local result = {}
	local noerror = false
	local allowed_params = {"server", "login", "password", "from", "to", "subject", "body", "attach"}
	local mailsend_comm = [[mailsend -smtp %s -user %s -pass "%s" -ssl -port 465 -auth-plain -from %s -to %s -sub "%s" -cs "us-ascii" -enc-type "7bit" -M "%s"]]
	local attachment = [[-attach "%s"]]
	
	if(#util.keys(params) > 0) then
		for param, value in util.kspairs(params) do
			if(util.contains(allowed_params, param) == false) then
				noerror = false
				result = string.format("Mailsend parameter [%s] is not allowed!", param)
				break
			end
		end
		noerror = true
	else
		noerror = false
		result["stdout"] = string.format("No any parameters required for Mailsend!")
	end

	if(noerror) then
		-- Substitute values from matched variables
		for par_name, par_value in util.vspairs(params) do
			params[par_name] = substitute(varname, rule, par_value, false)
		end

		mailsend_comm = string.format(mailsend_comm, 
			params["server"], 
			params["login"], 
			params["password"],
			params["from"],
			params["to"],
			params["subject"],
			params["body"]
		)


		if(params["attach"] and #params["attach"] > 0) then
			if(file_exists(params["attach"])) then
				attachment = string.format(attachment, params["attach"])
				mailsend_comm = string.format("%s %s",mailsend_comm, attachment)
			else
				noerror = false
				result["stdout"] = string.format("Attachment file doesn't exist or unknown: %s", params["attach"])
			end
		end

		local nowait = true
		result = sys.process.exec({"/bin/sh", "-c", mailsend_comm }, true, true, nowait)
		-- TODO
		-- Invent an approach to set timeout for long process

		if result.stdout then
			result.stdout = result.stdout:gsub("%c", "")
		end

		if (result.code == -1) then
			noerror = false
		end

	end

	--noerror = (not result.stderr)
	if rule.debug_mode.enabled then
		debug(varname, rule):modifier_bash(mdf_name, mailsend_comm, result, noerror)
	end

	return result.stdout or mailsend_comm
end

return mailsend
