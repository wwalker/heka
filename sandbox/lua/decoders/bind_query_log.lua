-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[

Parses DNS query logs from the BIND DNS server.

**Note**: You must have the `print-time`, `print-severity` and `print-category` options all set to **yes** in the logging configuration section of your `named.conf` file:

.. code-block:: bash

    channel query_log {
      file "/var/log/named/named_query.log" versions 3 size 5m;
      severity info;
      print-time yes;
      print-severity yes;
      print-category yes;
    };

Config:

- type (string, optional, default nil):
    Sets the message 'Type' header to the specified value

*Example Heka Configuration*

.. code-block:: ini

    [BindQueryLogInput]
    type = "LogstreamerInput"
    decoder = "BindQueryLogDecoder"
    file_match = 'named_query.log'
    log_directory = "/var/log/named"

    [BindQueryLogDecoder]
    type = "SandboxDecoder"
    filename = "lua_decoders/bind_query_log.lua"
      [BindQueryLogDecoder.config]
      type = "bind.query"

*Example Heka Message*

2016/04/25 17:31:37 
:Timestamp: 2016-04-26 00:31:37 +0000 UTC
:Type: bind_query
:Hostname: ns1.company.com
:Pid: 0
:Uuid: 09a83ad2-89c0-4a7d-adfc-0e225e1c1ad6
:Logger: bind_query_log_input
:Payload: 27-May-2015 21:06:49.246 queries: info: client 10.0.1.70#41242 (webserver.company.com): query: webserver.company.com IN A +E (10.0.1.71)
:EnvVersion: 
:Severity: 7
:Fields:
    | name:"QueryFlags" type:string value:["recursion requested","EDNS used"]
    | name:"ClientIP" type:string value:"10.0.1.70" representation:"ipv4"
    | name:"ServerRespondingIP" type:string value:"10.0.1.71" representation:"ipv4"
    | name:"RecordType" type:string value:"A"
    | name:"QueryName" type:string value:"webserver"
    | name:"RecordClass" type:string value:"IN"
    | name:"Timestamp" type:double value:1.432760809e+18
    | name:"QueryDomain" type:string value:"company.com"
    | name:"FullQuery" type:string value:"webserver.company.com"

--]]

local l = require 'lpeg'
local math = require 'math'
local string = require 'string'
local date_time = require 'date_time'
local ip = require 'ip_address'
local table = require 'table'
local syslog   = require "syslog"
local bind = require "bind"

l.locale(l)

local formats  = read_config("formats")
--The config for the SandboxDecoder plugin should have the type set to 'bindquerylog'
local msg_type = read_config("type")

local msg = {
  --This value is read in from the 'msg_type' config option in the TOML:
  Type        = msg_type,
  Payload     = nil,
  Severity    = 'info',
  Fields      = {},
}

--Load the query log grammar from the bind module:
local grammar = l.Ct(bind.query_log_grammar)

function process_message ()

  --Create a local variable for the log line from the Payload of the incoming Heka message.
  --The LogstreamerInput that generates the messages automatically puts the 
  local query_log_line = read_message("Payload")

  --Create a fields table and use the :match method on the grammar object to fill it with the Lua table
  --of values generated by parsing the query_log_line:
  fields = grammar:match(query_log_line)

  --If fields is empty, exit immediately:
  if not fields then return -1 end
  --Set the time in the message we're generating and set it to nil in the original log line:
  msg.Timestamp = fields.time
  fields.time = nil

  --Set the Fields part of the generated message to the fields Lua table that was generated by the grammar:match function:
  msg.Fields = fields
  --Include the original, unparsed log line as the Payload of the message:
  msg.Payload = read_message("Payload")
  inject_message(msg)

  return 0

end
