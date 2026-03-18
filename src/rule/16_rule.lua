local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Правило для управления роутером по СМС.",
	},

    max_text_size = {
        note = [[ Максимальный размер текста для отправки по смс, иначе отправка через email ]],
        default = 201, -- 3 смс кусочка по 67 символов
    },

    received_sms = {
		note = [[ Подписка на чтение новой смс ]],
		default = "",

		{
			["subscribe"] = {
				ubus = "tsmodem.sms",
				evname = "NEW-SMS-RECEIVED",
				match = { status = "ok"},
			}
		},
		{
			["func"] = function (nodes)
                local lua_table = luci.jsonc.parse(nodes.received_sms) or {}
				return lua_table or ""
			end,
		}
	},

    new_sms_phone = {
        note = [[ Получает номер телефона из смс ]],

        {
            ["skip"] = function (nodes)
                return #nodes.received_sms <= 2
            end
        },
        {
            ["func"] = function (nodes)
                local sms_data_table = luci.jsonc.parse(nodes.received_sms)
                return sms_data_table.sender
            end
        }
    },

    new_sms_message = {
        note = [[ Получает текст сообщения из смс ]],

        {
            ["skip"] = function (nodes)
                return #nodes.received_sms <= 2
            end
        },
        {
            ["func"] = function (nodes)
                local sms_data_table = luci.jsonc.parse(nodes.received_sms)
                return sms_data_table.message
            end
        }
    },

    trusted_phone = {
        note = [[ Получает разрешенный номер телефона для команд ]],

        {
            ["skip"] = function (nodes)
                return #nodes.received_sms <= 2 and (nodes.new_sms_phone == nil or #nodes.new_sms_phone == 0)
            end
        },
        {
            ["load-ubus"] = {
                object = "uci",
				method = "get",
				params = {
					config = "tsmsmscomm",
					type = "remote_control",
					option = "trusted_phone",
				},
            },
        },
        {
            ["func"] = function (nodes)
                local values = luci.jsonc.parse(nodes.trusted_phone)['values']

                for key, value in pairs(values) do
                    if nodes.new_sms_phone == value['trusted_phone'] then
                        return value['trusted_phone']
                    end
                end
            end
        },
        {
            ["func"] = function (nodes)
                return nodes.trusted_phone
            end
        }
    },

    allowed_command = {
        note = [[ Получает разрешенную команду для выполнения ]],

        {
            ["skip"] = function (nodes)
                return #nodes.received_sms <= 2 and (nodes.new_sms_message == nil or #nodes.new_sms_message == 0)
            end
        },
        {
            ["load-ubus"] = {
                object = "uci",
				method = "get",
				params = {
					config = "tsmsmscomm",
					type = "sms_command",
					option = "shell_command",
				},
            }
        },
        {
            ["func"] = function (nodes)
                local values = luci.jsonc.parse(nodes.allowed_command)['values']

                for key, value in pairs(values) do
                    if nodes.new_sms_message == value['sms_command'] then
                        return value['shell_command']
                    end
                end
            end
        },
        {
            ["func"] = function (nodes)
                return nodes.allowed_command
            end
        }
    },

    trusted_email = {
        note = [[ Получает email связанный с номером ]],

        {
            ["skip"] = function (nodes)
                return #nodes.received_sms <= 2 and (nodes.trusted_phone == nil or #nodes.trusted_phone == 0)
            end
        },
        {
            ["load-ubus"] = {
                object = "uci",
				method = "get",
				params = {
					config = "tsmsmscomm",
					type = "remote_control",
					option = "trusted_email",
				},
            },
        },
        {
            ["func"] = function (nodes)
                local values = luci.jsonc.parse(nodes.trusted_email)['values']
                for key, value in pairs(values) do
                    if nodes.new_sms_phone == value['trusted_phone'] then
                        return value['trusted_email']
                    end
                end
            end
        },
    },

    run_cmd = {
        note = [[ Запускает bash команду, если номер и команда разрешены ]],

        {
            ["skip"] = function (nodes)
                return (nodes.trusted_phone == nil or #nodes.trusted_phone == 0) or
                        (nodes.allowed_command == nil or #nodes.allowed_command == 0)
            end
        },
        {
            ["func"] = function (nodes)
                local handle = io.popen("df -k /tmp | awk 'NR==2 {print $2}'")
                local tmp_memory_half
                if handle ~= nil then
                    local kb_value = tonumber(handle:read("*a"))
                    local bytes = kb_value * 1024
                    tmp_memory_half = math.floor(bytes / 2)
                    handle:close()
                end

                local shell_cmd = nodes.allowed_command

                local tmp_file = '/tmp/sms_command_output.txt'
                local timeout_seconds = 10

                shell_cmd = string.format("%s | tail -c %d", shell_cmd, tmp_memory_half)
                local bash = string.format("timeout %d sh -c '%s' > %s 2>&1", timeout_seconds, shell_cmd, tmp_file)
                local status = os.execute(bash)
                local exit_code = math.floor(status / 256)

                if exit_code == 124 then
                    return ({
                        status = true,
                        result = "Произошел таймаут",
                    })
                end

                local file = io.open(tmp_file, "r")
                if file ~= nil then
                    local result = file:read("*a")
                    file:close()
                    return ({
                        status = true,
                        result = result,
                    })
                end

                return ({
                    status = false,
                    result = nil,
                })
            end
        },
    },

    send_result_via_sms = {
        title = [[ Отправляет результат по смс, если текст вмещается в max_text_size символ ]],

        {
            ["skip"] = function (nodes)
                if nodes.run_cmd == nil or #nodes.run_cmd == 0 then return true end

                local run_cmd = luci.jsonc.parse(nodes.run_cmd)
                if run_cmd.status == false then
                    return true
                end

                return (run_cmd.result == nil or #run_cmd.result == 0) or #run_cmd.result > tonumber(nodes.max_text_size)
            end
        },
        {
            ["func"] = function (nodes)
                local run_cmd = luci.jsonc.parse(nodes.run_cmd)
                return run_cmd.result
            end
        },
        {
            ["send-sms"] = {
                phone = "$trusted_phone",
                text = "$send_result_via_sms",
            },
        },
    },

    send_result_via_email = {
        title = [[ Отправляет результат по email, если текст более чем max_text_size символ ]],

        {
            ["skip"] = function (nodes)
                if nodes.run_cmd == nil or #nodes.run_cmd == 0 then return true end

                local run_cmd = luci.jsonc.parse(nodes.run_cmd)
                if run_cmd.status == false then
                    return true
                end

                return (run_cmd.result == nil or #run_cmd.result == 0) or #run_cmd.result <= tonumber(nodes.max_text_size)
            end
        },
        {
            ["func"] = function (nodes)
                local run_cmd = luci.jsonc.parse(nodes.run_cmd)
                return run_cmd.result
            end
        },
        {
            ["send-email"] = {
                to = "$trusted_email",
                subj = "Результат выполнения команды",
                body = "Результат выполнения команды",
                attach = "/tmp/sms_command_output.txt",
            }
        }
    },

    journal = {
		{
			["skip"] = function (nodes)
                if nodes.run_cmd == nil or #nodes.run_cmd == 0 then return true end
                local run_cmd = luci.jsonc.parse(nodes.run_cmd)
                return run_cmd.status == false
			end
		},
		{
			["func"] = function (nodes)
				local received_sms = luci.jsonc.parse(nodes.received_sms)
                local run_cmd = luci.jsonc.parse(nodes.run_cmd)
				return({
					datetime = received_sms.date,
					name = "Получена SMS-команда",
					source = received_sms.sender,
					command = received_sms.message,
					response = run_cmd.result,
				})
			end
		},
		{
			["store-db"] = {
				param_list = { "journal" }
			},
		}
	},
}

function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	local overview = {}

    self:follow("max_text_size"):debug()
    self:follow("received_sms"):debug()
    self:follow("new_sms_phone"):debug()
    self:follow("new_sms_message"):debug()

    self:follow("trusted_phone"):debug()
    self:follow("allowed_command"):debug()
    self:follow("trusted_email"):debug()

    self:follow("run_cmd"):debug()

    self:follow("send_result_via_sms"):debug()
    self:follow("send_result_via_email"):debug()

    self:follow("journal"):debug()
end

local metatable = {
    __call = function(table, parent)
        local rule_init_table = rule_init(table, rule_setting, parent)
        rule_init_table:make()
        return rule_init_table
    end
}
setmetatable(rule, metatable)
return rule