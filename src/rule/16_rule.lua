local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Правило для дистанционного управления по СМС.",
	},
	
	trusted_phones = {
		note = [[ Доверенные номера телефонов ]],
		source = {
			type = "ubus",
			object = "uci",
			method = "get",
			params = {
				config = "tsmsmscomm",
				type = "remote_control",
				option = "trusted_phone",
			}
		},
        modifier = {
            ["1_bash"] = [[ jsonfilter -e $.values.*.trusted_phone | tr '\n' ' ' ]],
        }
	},

	allowed_commands = {
		note = [[ Разрешеный список команд оболочки ]],
		source = {
			type = "ubus",
			object = "uci",
			method = "get",
			params = {
				config = "tsmsmscomm",
				type = "sms_command",
				option = "sms_command",
			}
		},
        modifier = {
            ["1_bash"] = [[ jsonfilter -e $.values.*.sms_command | tr '\n' '|' ]],

        }
	},
	
	sms_phone_number_recive = {
		note = [[ Номер телефона, отправившего смс ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "remote_control",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			["2_func"] = [[
				local tr_phones = $trusted_phones
				if(string.find(tr_phones, $sms_phone_number_recive)) then
					return $sms_phone_number_recive
				elseif($sms_phone_number_recive == "") then
					return ""
				else
					return "DISALLOWED"
				end
			]]
		}
	},

	trusted_email = {
		note = [[ Доверенный имэйл, соответствующий доверенному телефону ]],
		source = {
			type = "ubus",
			object = "uci",
			method = "get",
			params = {
				config = "tsmsmscomm",
				type = "remote_control",
				option = "trusted_email",
				match = {
					trusted_phone = "$sms_phone_number_recive"
				}
			}
		},
        modifier = {
            ["1_bash"] = [[ jsonfilter -e $.values.*.trusted_email ]],
        }
	},
	
	sms_is_read = {
		note = [[ Новое смс ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "remote_control",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.unread ]]
		}	
	},

	sms_command = {
		note = [[ Команда, принятая по смс ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "remote_control",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.command ]],
			["2_func"] = [[
				function escape_pattern(text)
				    return text:gsub("([^%w])", "%%%1")
				end
				local is_command_allowed = string.find($allowed_commands, escape_pattern($sms_command))
				if is_command_allowed then
					return $sms_command
				end
			]],
		}
	},

	shell_command = {
		note = [[ Реальная shell-команда ]],
		source = {
			type = "ubus",
			object = "uci",
			method = "get",
			params = {
				config = "tsmsmscomm",
				type = "sms_command",
				option = "shell_command",
				match = {
					sms_command = "$sms_command"
				}
			}
		},
        modifier = {
            ["1_bash"] = [[ jsonfilter -e $.values.*.shell_command ]],
        }
	},

	sms_response_file = {
		modifier = {
			["1_skip"] = [[
				if ($sms_is_read == "true") then 
					return false 
				else
					return true
				end
			]],
			["2_func"] = [[
				local filename = string.format("/tmp/sms_command_response_%s.txt", tostring(os.date("%Y%m%d_%H:%M:%S")))
				return filename
			]],
		}
	},

	execute_sms = {
		modifier = {
			["1_skip"] = [[
				if ($sms_is_read == "true" and $sms_phone_number_recive ~= "DISALLOWED") then 
					return false 
				else
					return true
				end
			]],
			["2_func"] = [[
				--local response = io.popen($sms_command):read("*a")
				local timeout = "timeout 3"
				local comm = $sms_command
				local file = $sms_response_file
				--os.execute(timeout .. " " .. comm .. " > " .. file .. " &")
				local succ = os.execute("timeout 3 pwd > /tmp/sms_command_response_20240923_18:04:21.txt &")
				local fileId = io.open(file, "rb" ) 
				-- local fileSize = fileId:seek("end")
				-- local res
				return(succ)
				
				-- if fileSize < 70 and fileSize > 1 then
				-- 	fileId:seek("set")
				-- 	res = fileId:read("*a")
				-- 	fileId:close()
				-- 	return res
				-- elseif fileSize >= 70 then
				-- 	fileId:close()
				--     return 'sent_by_email'
				-- end
			]]
		}
	},

	sms_send = {
		modifier = {
			["1_skip"] = [[
				local sms_comm_execute = tostring($execute_sms)
				return (sms_comm_execute == "" or sms_comm_execute == "sent_by_email" or sms_comm_execute == "error_write_file")
			]],
			--["2_sms"] = {
				-- phone = "$sms_phone_number_recive",
				-- text = "$read_from_file"
			--	phone = "+79030507175",
			--	text = "sms from 16_rule"
			--}
		}
	},

	email_send = {
		modifier = {
			["1_skip"] = [[
				local sms_comm = tostring($sms_command)
				if (($sms_is_read == "true") and ($execute_sms == "sent_by_email")) then 
					return false 
				else
					return true
				end
			]],
			["2_mail"] = {
				server = "mail.tskver.com",
				login = "rkv@rosze.ru",
				password = "T6-Xjh%W2#",
				from = "rkv@rosze.ru",
				to = "$trusted_email",
				subject = "Bitcord RTR-2",
				body = "SMS response for the command [$sms_command] received - see attachment.",
				attach = "$sms_response_file"
			}
		}
	},
	event_datetime = {
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "remote_control",
			params = {}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.time ]],
			["2_func"] = 'return(os.date("%Y-%m-%d %H:%M:%S", tonumber($event_datetime)))'
		}
	},

    event_is_new = {
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "remote_control",
			params = {}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.unread ]],
		}
	},
    journal = {
		modifier = {
			["1_skip"] = [[ if ($event_is_new == "true") then return false else return true end ]],
			["2_func"] = [[return({
					datetime = $event_datetime,
					name = "Received SMS command",
					source = "Modem  (16-rule)",
					command = "*",
					response = $sms_command
				})]],
                
			["3_store-db"] = {
				param_list = { "journal" }
			},
			["4_frozen"] = [[ return 5 ]],
		}
	},
}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug level
-- Use :debug(ONLY) - to debug single variable in the rule
function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level
	
	local overview = {
	}

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end

	-- Пропускаем выполнения правила, если СИМ-карты нет в слоте
	local all_rules = rule.parent.setting.rules_list.target
	local r01_wait_timer = tonumber(all_rules["01_rule"].setting.wait_timer.output)
	if (r01_wait_timer and r01_wait_timer > 0) then 
		--if rule.debug_mode.enabled then print("------ 15_rule SKIPPED as r01_wait_timer > 0 -----") end
		return 
	end

	
	self:load("title"):modify():debug()
	self:load("trusted_phones"):modify():debug()
	self:load("allowed_commands"):modify():debug()
	
	self:load("sms_phone_number_recive"):modify():debug()
	self:load("trusted_email"):modify():debug()
	self:load("sms_is_read"):modify():debug()

	self:load("sms_command"):modify():debug()
	self:load("shell_command"):modify():debug()
	--self:load("sms_response_file"):modify():debug()
	--self:load("execute_sms"):modify():debug()
	--self:load("sms_send"):modify():debug()
	--self:load("email_send"):modify():debug()

	
	-- self:load("allowed_commands"):modify():debug()
	-- self:load("sms_command"):modify():debug()
	-- self:load("sms_response_file"):modify():debug()
	-- self:load("execute_sms"):modify():debug()
	-- self:load("email_send"):modify():debug()
	
end

---[[ Initializing. Don't edit the code below ]]---
local metatable = {
	__call = function(table, parent)
		local t = rule_init(table, rule_setting, parent)
		if not t.is_busy then
			t.is_busy = true
			t:make()
			t.is_busy = false
		end
		return t
	end
}
setmetatable(rule, metatable)
return rule
