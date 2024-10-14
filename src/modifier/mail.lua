
local sys = require "luci.sys"
local log = require "applogic.util.log"

function file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

function mailsend(varname, mdf_name, modifier, rule)
	Apply modifiers to the target value
	---------------------------------]]
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug" end
	local varlink = rule.setting[varname] or {}
	local params = modifier or {}
	local result = {}
	local noerror = false
	local allowed_params = {"server", "login", "password", "from", "to", "subject", "body", "attach"}
	local mailsend_comm = [[mailsend -smtp %s -user %s -pass "%s" -ssl -port 465 -auth-plain -from %s -to %s -sub "%s" -body "%s"]]
	local attachment = [[-attach "%s"]]
	]]
	
	if(#params > 0) then
		for param, value in params do
			if(util.contains(allowed_params, param) == false) then
				noerror = false
				result = string.format("Mailsend parameter [%s] is not allowed!", param)
				break
			end
		end
		noerror = true
	else
		noerror = false
		result = string.format("No any parameters required for Mailsend!")
	end

	if(noerror) then
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
				result = string.format("Attachment file doesn't exist or unknown: %s", params["attach"])
			end
		end

		result = sys.process.exec({"/bin/sh", "-c", mailsend_comm }, true, true, true)

		if result.stdout then
			result.stdout = result.stdout:gsub("%c", "")
		end

	end

	noerror = (not result.stderr)
	if rule.debug_mode.enabled then
		debug(varname, rule):modifier_bash(mdf_name, mailsend_comm, result, noerror)
	end

	return result.stdout or ""
end

return mailsend
