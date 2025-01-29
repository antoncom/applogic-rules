require "os"
require "ubus"
local sys  = require "luci.sys"
local uloop = require "uloop"
local util = require "luci.util"
local log = require "applogic.util.log"
local flist = require "applogic.util.filelist"
local uci = require "luci.model.uci".cursor()
local bit = require "bit"
local checkubus = require "applogic.util.checkubus"
local debug_mode = require "applogic.debug_mode"
local debug_cli = require "applogic.var.debug_cli"
local report = require "applogic.util.report"
local md5 = require "md5"

local profile = require "applogic.util.profile"

print(profile)


--[[ Restore UCI config of Applogic once the debug stopped by Ctrl-C ]]
local signal = require("posix.signal")
signal.signal(signal.SIGINT, function(signum)

	uci:set("applogic", "debug_mode", "enable", 0)
	uci:set("applogic", "debug_mode", "level", "ERROR")
	uci:delete("applogic", "debug_mode", "rule")
	uci:delete("applogic", "debug_mode", "showvar")
	uci:commit("applogic")

  io.write("\n")
  print("-----------------------")
  print("Applogic debug stopped.")
  print("UCI config restored.")
  print("-----------------------")
  io.write("\n")
  os.exit(128 + signum)
end)



--local F = require "posix.fcntl"
--local U = require "posix.unistd"


local rules = {}
rules.iteration = 1
rules.subscription = {
	queu = {},
	vars = {}
}
rules.ubus_object = {}
rules.conn = nil
rules.cache_ubus, rules.cache_uci, rules.cache_bash = {}, {}, {}
rules.state = 	{
					mode = "run",	-- "run", "stop" are only possible
				}					-- "stop" is needed when web-console of AT commands is activated
									-- "stop" stops ubus-requests from applogic to tsmodem.driver,
									-- as tsmodem.driver automation is in "stop" mode too.


local rules_setting = {
	title = "Группа правил CPE Agent",
	rules_list = {
		target = {},
	},
	tick_size_default = 200	-- use 1900 ms interval in debug mode
}

function rules:init()
	rules.cache_ubus, rules.cache_uci, rules.cache_bash = {}, {}, {}
end

function rules:clear_cache()
	--rules.cache_ubus, rules.cache_uci, rules.cache_bash = nil, nil, nil
	rules.cache_ubus, rules.cache_uci, rules.cache_bash = {}, {}, {}
	collectgarbage()

end

-- Пробежать по всем переменным всех правил

-- Создать подписки (функции обработчики), удовлетворяющие evname, event_matched.
-- Такая функйия подписи будет просто складывать подходящие события в очередь

-- Создать пустую очередь для вновь поступающих событий
-- Создать функцию-диспетчер, который будет загружать события в переменные
-- при возникновении события.
-- Структура очереди:
--	rules.subscription.queu = {
--		["network.interface"] = {
--			[evmatch_1] = {
--				evname = "interface.up",						-- Имя события
--				subscribed_vars = {varlink1, varlink2},			-- Данный список клонируется в vars_to_load
--				subscribed_varnames = {"[21_rule]: upvar", [21_rule]: downvar"},			-- Данный список клонируется в vars_to_load
--				events = {										-- при поступлении события в очередь
--					[1] = {
--						msg = {},
--						name = "",
--						md5 = {"f4556ff3f17bb744ec8819b42bc1291c"}		-- Содержит контрольную сумму добавленного в очередь события
--						vars_to_load = { varlink1 }				-- Когда все переменые прогрузятся
--					}											-- данное событие удаляется из очереди
--				}
--			},
--			[evmatch_2] = {
--				evname = "interface.down",						-- Имя события
--				subscribed_vars = {varlink1, varlink2},
--				events = {
--					[1] = {
--						msg = {},
--						name = "",
--						md5 = {"f4556ff3f17bb744ec8819b42bc1291c"}		-- Содержит контрольную сумму добавленного в очередь события
--						vars_to_load = { varlink1 }				-- Когда все переменые прогрузятся
--					}											-- данное событие удаляется из очереди
--				}
--			},
--		},
--	}
--  rules.subscription.vars = {									-- Здесь храним список всех переменных, загружаемых по подписке
--		varlink1, varlink2, varlink3							-- При возикновении события из них берутся matched
--	}															-- чтобы не все события помещать в очередь, а только соответствующие условию matched


function rules:matched_evmsg(ev, pattern)
	local msg_matched = false
	local evmsg = ev
	if not evmsg then return end

	for attr,value in util.kspairs(pattern) do
		if (evmsg[attr] and evmsg[attr] == value) then
			msg_matched = true
			break
		end
	end
	return msg_matched

end

function evuuid(name, match)
	return md5.sumhexa(tostring(name)..tostring(util.serialize_json(match)))
end

--	--[[ Диспетчер раскладывает поступающие события по очередям ]]
rules.subscription.dispatcher = function(ubusobj, evname, evmsg) 
	-- Проверяем события на дубли. Если повторно возникает - не добавляем в очередь
	function chekDuplucates(md5, events)
		local res = false
		for _, ev in ipairs(events) do
			if ev["md5"] == md5 then
				res = true
				break
			end
		end
		return res
	end
	-- пробегаем по списку переменных rules.subscription.vars
	for _,v in ipairs(rules.subscription.vars) do
		-- если событие соответствует условию matched в какой-либо переменной
		if(rules:matched_evmsg(evmsg, v.source.match) == true) then
			local evmatch_md5 = evuuid(evname, v.source.match)
			if (rules.subscription.queu[ubusobj] and rules.subscription.queu[ubusobj][evmatch_md5]) then
				-- Отсекаем события дубли, имеющие местj при подписке, например, на объект network.interface
				local name_message_md5 = evuuid(evname,evmsg)
				local events = rules.subscription.queu[ubusobj][evmatch_md5].events
				if (chekDuplucates(name_message_md5, events) == false) then
					local qu_item = {
						msg = evmsg,
						name = evname,
						md5 = name_message_md5,
						vars_to_load = util.clone(rules.subscription.queu[ubusobj][evmatch_md5].subscribed_vars, false)
					}
					-- добавляем в очередь
					table.insert(rules.subscription.queu[ubusobj][evmatch_md5].events, qu_item)
				end
			end
		end
	end
end

rules.subscription.removeEvent = function(ubusobj, evmatch_md5, varlink)
	local evmatch = rules.subscription.queu[ubusobj] and rules.subscription.queu[ubusobj][evmatch_md5] or false
	if (evmatch) then
		local event = evmatch.events[1] or false
		if (event) then
			local subscribed_vars = evmatch.subscribed_vars
			local vars_to_load = event.vars_to_load
			-- Если для данного события есть подписанные переменные
			if util.contains(subscribed_vars, varlink) then
				-- Если в списке переменных к загрузке есть данная переменная
				if (util.contains(vars_to_load, varlink)) then
					local i = false
					-- Удаляем переменную из списка загруженных
					for j,vlink in ipairs(vars_to_load) do
						if vlink == varlink then
							i = j
							break
						end
					end
					if (i) then 
						table.remove(vars_to_load, i) 
					end
				elseif (#vars_to_load == 0) then
					-- если список загруженных переменных пуст - удаляем данное событие из очереди
					table.remove(evmatch.events, 1)
				end
			end
		end
	--util.dumptable(rules.subscription.queu)
	end
end

function rules:make_subscription(rule)
	for varname, varlink in pairs(rule.setting) do
		if (varlink["source"] and varlink["source"]["type"] == "subscribe") then
			-- Записываем переменную в список всех, имеющих подписки
			table.insert(rules.subscription.vars, rule.setting[varname])

			-- Формируем каркас пустой очереди
			local ubus_objname = varlink["source"]["ubus"]
			local evname = varlink["source"]["evname"]
			local event_match = varlink["source"]["match"]
			local evmatch_md5 = evuuid(evname, event_match)
			rules.subscription.queu[ubus_objname] = rules.subscription.queu[ubus_objname] or {}
			rules.subscription.queu[ubus_objname][evmatch_md5] = rules.subscription.queu[ubus_objname][evmatch_md5] or {
				["evname"] = evname,
				subscribed_vars = {},
				subscribed_varnames = {}, -- for debug needs only
				events = {}
			}
			if (not util.contains(rules.subscription.queu[ubus_objname][evmatch_md5].subscribed_vars, varlink)) then
				table.insert(rules.subscription.queu[ubus_objname][evmatch_md5].subscribed_vars, varlink)
				if (debug_cli.rule and debug_cli.rule == "queu") then
					local vr_name = "[" .. rule.ruleid .. " | " .. varname .. "]"
					table.insert(rules.subscription.queu[ubus_objname][evmatch_md5].subscribed_varnames, vr_name)
				end
			end

			-- Подписываемся на UBUS
			for ubusname,_ in util.kspairs(rules.subscription.queu) do
				local sub = {
			        notify = function(msg, name)
			            rules.subscription.dispatcher(ubusname, name, msg)
			        end
			    }
			    rules.conn:subscribe(ubusname, sub)
			end


			--print("======= QUEU =========")
			--util.dumptable(rules.subscription.queu)

		end
	end
end


function rules:make_ubus()
	self.conn = ubus.connect()
	if not self.conn then
		error("rules:make_ubus() - Failed to connect to ubus")
	end

	--[[ Get name of Ubus object from /etc/config/applogic ]]
	local ubus_name = uci:get("applogic", "ubus", "object") or "applogic"

	local ubus_object = {
		[ubus_name] = {
			list = {
				function(req, msg)
					local rlist = {}
					for rule_file, rule_obj in util.kspairs(self.setting.rules_list.target) do
						rlist[rule_file] = rule_obj.setting.title.output
					end
					self.conn:reply(req, rlist)
				end, {id = ubus.INT32, msg = ubus.STRING }
			},

			vars = {
				function(req, msg)
					local vlist = {}
					local rules = self.setting.rules_list.target
					local rule_name = msg["rule"]
					if not rule_name then
						self.conn:reply(req, { ["error"] = "Rule name was not found. Try 'list' to see all names."})
						return
					end

					if rules[rule_name] and rules[rule_name].setting then
						for varname, varparams in pairs(rules[rule_name].setting) do
							if varname ~= "title" then -- Hide title variable in UBUS response
								vlist[varname] = (type(varparams["output"]) == "table") and util.serialize_json(varparams["output"]) or varparams["output"]
							end
						end
					else
						self.conn:reply(req, { ["error"] = string.format("Rule '%s' was not found.", tostring(rule_name)) })
					end

					self.conn:reply(req, vlist)

				end, {id = ubus.INT32, msg = ubus.STRING }
			},

			state = {
	            function(req, msg)
	                if msg["mode"] and msg["mode"] == "run" then
						rules.state = { mode = "run" }
						resp = rules.state
	                elseif msg["mode"] and msg["mode"] == "stop" then
	                    rules.state = {
							mode = "stop",
							run_after = 30,
							comment = [[
								After 30 sec. Applogic will check if http session is active.
								If the http session is expired or user logged off from UI,
								then Applogic go back to 'run' mode automatically.
							]]
						}
						rules.state.comment = rules.state.comment:gsub("\t", "")
						rules.state.comment = rules.state.comment:gsub("\n", " ")
						resp = rules.state
					else
						resp = rules.state
	                end

	                self.conn:reply(req, resp);
	            end, {id = ubus.INT32, msg = ubus.STRING }
	        },
		},
	}
	self.conn:add( ubus_object )
	self.ubus_object = ubus_object

end


function rules:make()
	local rules_path = "/usr/lib/lua/applogic/rule"
	local id, ruleshome = '', self.setting.rules_list.target

	local files = flist({path = rules_path, grep = ".lua"})
	for i=1, #files do
		id = util.split(files[i], '.lua')[1]
		ruleshome[id] = require("applogic.rule." .. id)
	end
end


function rules:check_driver_automation()
	local driver_mode = ""
	local automation = { mode = "" }
	if checkubus(rules.conn, "tsmodem.driver", "automation") then
		automation = util.ubus("tsmodem.driver", "automation", {})
		driver_mode = automation and automation["mode"] or ""

		rules.state.mode = driver_mode
	end
	--return driver_mode
end

function rules:run_all()
--profile.start()

	local user_session_alive = rules:check_driver_automation()
	--if (rules:check_driver_automation() == "run") then
		local rules_list = self.setting.rules_list.target
		local state = ''

		for name, rule in util.kspairs(rules_list) do
			-- rule.debug = (rules.debug_type and (rules.debug_type == "VAR" or rules.debug_type == "RULE") or false
			-- rule.debug_var = (rules.debug_type and rules.debug_type == "VAR") or false
			-- rule.debug_rule = (rules.debug_type and rules.debug_type == "RULE") or false
			-- rule.iteration = self.iteration
			-- Initiate rule with link to the present (parent) module
			-- Then the rule can send notification on the ubus object of parent module

			state = rule(self)

			-- DEBUG: Print all vars table
			if rule.debug_mode.enabled then
				local rule_has_error = rule.debug_mode.level == "ERROR" and (rule.debug and rule.debug.noerror and rule.debug.noerror == false)
				local report_anyway_mode = rule.debug_mode.level == "INFO"
				if rule.debug then
					if rule_has_error or report_anyway_mode then
						rule.debug.report(rule):print_rule(rule.debug_mode.level, rule.iteration)
						rule.debug.report(rule):clear()
					end
					rule.debug.noerror = true
				end
			end
		end

		if (debug_cli.rule and debug_cli.rule == "overview") then
			rules:overview(rules_list,rules.iteration)
		end

		if (debug_cli.rule and debug_cli.rule == "queu") then
			report:queu(rules, iteration)
		end

		rules:clear_cache()
		--rules:push_next_subscribed()
		rules.iteration = rules.iteration + 1

	--end
-- execute code that will be profiled
--profile.stop()
-- report for the top 10 functions, sorted by execution time
--print(profile.report(10))
end

function rules:overview(rules_list, iteration)
	--log("self.setting.rules_list.target", self.setting.rules_list.target["01_rule"].debug)
	--print("COUNT", #util.keys(rules_list), iteration)
	report:overview(rules_list, iteration)
end


local metatable = {
	__call = function(table)
		table.setting = rules_setting
		local tick = table.setting.tick_size_default

		table:init()

		table:make_ubus()
		table:make()

		-- looping
		uloop.init()

		local timer
		function t()
			table:run_all()
			timer:set(tick)
		end
		timer = uloop.timer(t)
		timer:set(tick)

		uloop.run()

		table.conn:close()
		return table
	end
}
setmetatable(rules, metatable)
rules()
