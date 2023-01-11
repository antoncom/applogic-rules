## Что это?

Applogic - это библиотека для OpenWrt, позволяющая реализовать логику выполнения программы путём написания пользовательских правил на языке Lua.

## Область применения

Автоматизация процессов телекоммуникационного оборудования под управлением встраиваемых систем на базе Linux / OpenWrt.

## Варианты использования

* Опрос и управление датчиками
* Опрос и управление модемами сотовой связи
* Приём-передача данных по различным сетевым протоколам
* Преобразование данных
* Поставка данных в системы мониторинга наблюдаемых величин
* Журналирование и информирование пользователя
* Выполнение управляющих команд

## Преимущества

Попробуйте собрать и обработать 50-100 величин из различных источников в режиме реального времени. Проанализировать их значения, и на основе этого принять решение о поведении системы.
Для этого потребовалось бы написать отдельную программу, отладить её и сопровождать код если источники данных изменятся.

Applogic предлагает не программировать сценарии автоматизации, а описывать их в виде правил. Applogic разбирает эти правила, и в соответствии с ними назначет необходимые функции, задействует механизмы хранения и обработки поступающих данных.

При этом пользователю не требуются глубокие знания программирования на языке скриптов, а достаточно иметь базовые знания языка Lua, который считается одним из самых простых.

## Что есть Правило

Правило это набор переменных, обрабатываемых последовательно. Каждая переменная имеет по существу два параметра, таких как:
1. Источник данных (откуда получать исходные данные)
2. Список модификаторов (что делать с полученным значением)

Пример описания переменной

```
	sim_id = {
		note = [[ Идентификатор активной Сим-карты: 0/1. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "sim",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]]
            ["2_ui-update"] = {
                param_list = { "sim_id" }
            }
		}
	},
```
В данном примере пользователь определил переменную _**sim_id**_ , источником данных для которой является шина UBUS. После получения данных в формате JSON к ним применяются два модификатора: _**bash**_ и _**ui-update**_. Первый выделяет из JSON-структуры определённое значение, а второй передат его в систему мониторинга, на экран пользователя.

Источником данных в настоящей версии, применительно к OpenWrt, служат: шина UBUS, конфиги UCI, любые SHELL-команды.

Модификаторы - это расширяемый список пользовательских функций. В настоящей версии предусмотрены следующие Модификаторы:

**[bash]** - позволяет указать произвольную shell-команду для обработки данных;

**[func]** - позволяет вставить Lua-код для обработки переменных правила;

[**skip]** - позволяет пропустить обработку переменной по заданному условию;

**[frozen]** - позволяет зафиксировать значение переменной на заданный промежуток времени;

**[ui_update]** - для передачи значения переменной в интерфейс мониторинга.

## Проверка правила

Отслеживание значений переменных правила превратилось бы в муку дебаггинга, если бы не специальный режим работы Applogic, при котором пользователю выводится в консоль таблица полученных значений переменных после каждой обработки правила. Пример:

```
root@OpenWrt:~# applogic debug
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ [01_rule] Правило переключения Сми-карты при отсутствии регистрации в сети                                  ┃
┣━━━━━━━━━━━━━━━━━━━━━━┯━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┯━━━━━━━━━━━━━┯━━━━━━━━━━━━━━━━━━━━━━━━━━┯━━━━┫
┃ VARIABLE             │ NOTES                                  │ PASS LOGIC  │ RESULTS ON THE ITERATION │ #5 ┃
┣━━━━━━━━━━━━━━━━━━━━━━┿━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┿━━━━━━━━━━━━━┿━━━━━━━━━━━━━━━━━━━━━━━━━━┿━━━━┫
┃ sim_id               │ Идентификатор активной Сим-карты: 0/1. │             │ 0                        │ ✔  ┃
┠──────────────────────┼────────────────────────────────────────┼─────────────┼──────────────────────────┼────┨
┃ uci_section          │ Идентификатор секции вида "sim_0" или  │             │ sim_0                    │ ✔  ┃
┃                      │ "sim_1". Источник: /etc/config/tsmodem │             │                          │    ┃
┠──────────────────────┼────────────────────────────────────────┼─────────────┼──────────────────────────┼────┨
┃ uci_timeout_reg      │ Таймаут отсутствия регистрации в       │             │ 550                      │ ✔  ┃
┃                      │ сети. Источник: /etc/config/tsmodem    │             │                          │    ┃
┠──────────────────────┼────────────────────────────────────────┼─────────────┼──────────────────────────┼────┨
┃ network_registration │ Статус регистрации Сим-карты в сети    │ [ui-update] │ 1                        │ ✔  ┃
┃                      │ 0..7.                                  │             │                          │    ┃
┠──────────────────────┼────────────────────────────────────────┼─────────────┼──────────────────────────┼────┨
┃ changed_reg_time     │ Время последней успешной регистрации   │             │ 1673461557               │ ✔  ┃
┃                      │ в сети или "", если неизвестно.        │             │                          │    ┃
┠──────────────────────┼────────────────────────────────────────┼─────────────┼──────────────────────────┼────┨
┃ lastreg_timer        │ Отсчёт секунд при потере регистрации   │ [skip]      │ 0                        │ ✔  ┃
┃                      │ Сим-карты в сети.                      │             │                          │    ┃
┠──────────────────────┼────────────────────────────────────────┼─────────────┼──────────────────────────┼────┨
┃ switching            │ Статус переключения Sim: true / false. │ [ui-update] │ false                    │ ✔  ┃
┠──────────────────────┼────────────────────────────────────────┼─────────────┼──────────────────────────┼────┨
┃ do_switch            │ Активирует и возвращает трезультат     │ [skip]      │ empty                    │ ✔  ┃
┃                      │ переключения Сим-карты                 │             │                          │    ┃
┗━━━━━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━┷━━━━┛

```
(пример проверки правила целиком)


Для более детальной проверки можно вывести в консоль состояние отдельной переменной:

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┯━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┯━━━━┓
┃ [ 01_RULE ][ SIM_ID ] VARIABLE ATTRIBUTES VALUE                                              │ RESULTS ON THE ITERATION     │ #1 ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┿━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┿━━━━┫
┃ input                                                                                        │ empty                        │ ✔  ┃
┠──────────┬──────────┬────────────────────────────────────────────────────────────────────────┼──────────────────────────────┼────┨
┃ source   │ ubus     │   source = {                                                           │ {                            │ ✔  ┃
┃          │          │     type = "ubus",                                                     │   "command": "~0:SIM.SEL=?", │    ┃
┃          │          │     object = "tsmodem.driver",                                         │   "unread": "false",         │    ┃
┃          │          │     method = "sim",                                                    │   "time": "1673363038",      │    ┃
┃          │          │     params = "[]",                                                     │   "value": "0"               │    ┃
┃          │          │    }                                                                   │ }                            │    ┃
┃          │          │                                                                        │                              │    ┃
┠──────────┼──────────┼────────────────────────────────────────────────────────────────────────┼──────────────────────────────┼────┨
┃ modifier │ [1_bash] │ echo                                                                   │ 0                            │ ✔  ┃
┃          │          │ '{"command":"~0:SIM.SEL=?","unread":"false","time":"1673363038","value │                              │    ┃
┃          │          │ ":"0"}' | jsonfilter -e $.value                                        │                              │    ┃
┠──────────┴──────────┴────────────────────────────────────────────────────────────────────────┼──────────────────────────────┼────┨
┃ output                                                                                       │ 0                            │ ✔  ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┷━━━━┛

```
(пример обработки отдельной переменной)
