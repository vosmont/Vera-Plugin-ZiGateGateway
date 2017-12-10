--[[
  This file is part of the plugin ZiGate Gateway.
  https://github.com/vosmont/Vera-Plugin-ZiGateGateway
  Copyright (c) 2017 Vincent OSMONT
  This code is released under the MIT License, see LICENSE.
--]]

module( "L_ZiGateGateway1", package.seeall )

-- Load libraries
local status, json = pcall( require, "dkjson" )
local bit = require( "bit" )

-- **************************************************
-- Plugin constants
-- **************************************************

_NAME = "ZiGateGateway"
_DESCRIPTION = "ZiGate gateway for the Vera"
_VERSION = "1.0"
_AUTHOR = "vosmont"

-- **************************************************
-- Plugin settings
-- **************************************************

local _SERIAL = {
	baudRate = "115200",
	dataBits = "8",
	parity = "none",
	stopBit = "1"
}

-- **************************************************
-- Generic utilities
-- **************************************************

function log( msg, methodName, lvl )
	local lvl = lvl or 50
	if ( methodName == nil ) then
		methodName = "UNKNOWN"
	else
		methodName = "(" .. _NAME .. "::" .. tostring( methodName ) .. ")"
	end
	luup.log( string_rpad( methodName, 45 ) .. " " .. tostring( msg ), lvl )
end

local debugMode = false
local function debug() end


local function warning( msg, methodName )
	log( msg, methodName, 2 )
end

local g_errors = {}
local function error( msg, methodName, notifyOnUI )
	table.insert( g_errors, { os.time(), methodName or "", tostring( msg ) } )
	if ( #g_errors > 100 ) then
		table.remove( g_errors, 1 )
	end
	log( msg, methodName, 1 )
	if ( notifyOnUI ~= false ) then
		UI.showError( "Error (see tab)" )
	end
end


-- **************************************************
-- Constants
-- **************************************************

-- This table defines all device variables that are used by the plugin
-- Each entry is a table of 4 elements:
-- 1) the service ID
-- 2) the variable name
-- 3) true if the variable is not updated when the value is unchanged
-- 4) variable that is used for the timestamp
local VARIABLE = {
	-- Sensors
	TEMPERATURE = { "urn:upnp-org:serviceId:TemperatureSensor1", "CurrentTemperature", true },
	HUMIDITY = { "urn:micasaverde-com:serviceId:HumiditySensor1", "CurrentLevel", true },
	LIGHT_LEVEL = { "urn:micasaverde-com:serviceId:LightSensor1", "CurrentLevel", true },
	PRESSURE = { "urn:upnp-org:serviceId:BarometerSensor1", "CurrentPressure", true },
	FORECAST = { "urn:upnp-org:serviceId:BarometerSensor1", "Forecast", true },
	WIND_DIRECTION = { "urn:micasaverde-com:serviceId:WindSensor1", "Direction", true },
	WIND_GUST_SPEED = { "urn:micasaverde-com:serviceId:WindSensor1", "GustSpeed", true },
	WIND_AVERAGE_SPEED = { "urn:micasaverde-com:serviceId:WindSensor1", "AvgSpeed", true },
	RAIN = { "urn:upnp-org:serviceId:RainSensor1", "CurrentTRain", true },
	RAIN_RATE = { "urn:upnp-org:serviceId:RainSensor1", "CurrentRain", true }, -- TODO ??
	UV = { "urn:micasaverde-com:serviceId:UvSensor1", "CurrentLevel", true },
	-- Switches
	SWITCH_POWER = { "urn:upnp-org:serviceId:SwitchPower1", "Status", true },
	DIMMER_LEVEL = { "urn:upnp-org:serviceId:Dimming1", "LoadLevelStatus", true },
	DIMMER_LEVEL_OLD = { "urn:upnp-org:serviceId:ZiGateDevice1", "LoadLevelStatus", true },
	DIMMER_DIRECTION = { "urn:upnp-org:serviceId:ZiGateDevice1", "LoadLevelDirection", true },
	DIMMER_STEP = { "urn:upnp-org:serviceId:ZiGateDevice1", "DimmingStep", true },
	--PULSE_MODE = { "urn:upnp-org:serviceId:ZiGateDevice1", "PulseMode", true },
	--TOGGLE_MODE = { "urn:upnp-org:serviceId:ZiGateDevice1", "ToggleMode", true },
	--IGNORE_BURST_TIME = { "urn:upnp-org:serviceId:ZiGateDevice1", "IgnoreBurstTime", true },
	-- Scene controller
	LAST_SCENE_ID = { "urn:micasaverde-com:serviceId:SceneController1", "LastSceneID", true, "LAST_SCENE_DATE" },
	LAST_SCENE_DATE = { "urn:micasaverde-com:serviceId:SceneController1", "LastSceneTime", false },
	-- Security
	ARMED = { "urn:micasaverde-com:serviceId:SecuritySensor1", "Armed", true },
	TRIPPED = { "urn:micasaverde-com:serviceId:SecuritySensor1", "Tripped", false, "LAST_TRIP" },
	ARMED_TRIPPED = { "urn:micasaverde-com:serviceId:SecuritySensor1", "ArmedTripped", false, "LAST_TRIP" },
	LAST_TRIP = { "urn:micasaverde-com:serviceId:SecuritySensor1", "LastTrip", true },
	TAMPER_ALARM = { "urn:micasaverde-com:serviceId:HaDevice1", "sl_TamperAlarm", false, "LAST_TAMPER" },
	LAST_TAMPER = { "urn:micasaverde-com:serviceId:SecuritySensor1", "LastTamper", true },
	-- Battery
	BATTERY_LEVEL = { "urn:micasaverde-com:serviceId:HaDevice1", "BatteryLevel", true, "BATTERY_DATE" },
	BATTERY_DATE = { "urn:micasaverde-com:serviceId:HaDevice1", "BatteryDate", true },
	-- Energy metering
	WATTS = { "urn:micasaverde-com:serviceId:EnergyMetering1", "Watts", true },
	KWH = { "urn:micasaverde-com:serviceId:EnergyMetering1", "KWH", true, "KWH_DATE" },
	KWH_DATE = { "urn:micasaverde-com:serviceId:EnergyMetering1", "KWHReading", true },
	-- HVAC
	HVAC_MODE_STATE = { "urn:micasaverde-com:serviceId:HVAC_OperatingState1", "ModeState", true },
	HVAC_MODE_STATUS = { "urn:upnp-org:serviceId:HVAC_UserOperatingMode1", "ModeStatus", true },
	HVAC_CURRENT_SETPOINT = { "urn:upnp-org:serviceId:TemperatureSetpoint1", "CurrentSetpoint", true },
	HVAC_CURRENT_SETPOINT_HEAT = { "urn:upnp-org:serviceId:TemperatureSetpoint1_Heat", "CurrentSetpoint", true },
	HVAC_CURRENT_SETPOINT_COOL = { "urn:upnp-org:serviceId:TemperatureSetpoint1_Cool", "CurrentSetpoint", true },
	-- IO connection
	IO_DEVICE = { "urn:micasaverde-com:serviceId:HaDevice1", "IODevice", true },
	IO_PORT_PATH = { "urn:micasaverde-com:serviceId:HaDevice1", "IOPortPath", true },
	BAUD = { "urn:micasaverde-org:serviceId:SerialPort1", "baud", true },
	STOP_BITS = { "urn:micasaverde-org:serviceId:SerialPort1", "stopbits", true },
	DATA_BITS = { "urn:micasaverde-org:serviceId:SerialPort1", "databits", true },
	PARITY = { "urn:micasaverde-org:serviceId:SerialPort1", "parity", true },
	-- Communication failure
	COMM_FAILURE = { "urn:micasaverde-com:serviceId:HaDevice1", "CommFailure", false, "COMM_FAILURE_TIME" },
	COMM_FAILURE_TIME = { "urn:micasaverde-com:serviceId:HaDevice1", "CommFailureTime", true },
	-- ZiGate gateway
	PLUGIN_VERSION = { "urn:upnp-org:serviceId:ZiGateGateway1", "PluginVersion", true },
	DEBUG_MODE = { "urn:upnp-org:serviceId:ZiGateGateway1", "DebugMode", true },
	LAST_DISCOVERED = { "urn:upnp-org:serviceId:ZiGateGateway1", "LastDiscovered", true },
	LAST_UPDATE = { "urn:upnp-org:serviceId:ZiGateGateway1", "LastUpdate", true },
	LAST_MESSAGE = { "urn:upnp-org:serviceId:ZiGateGateway1", "LastMessage", true },
	ZIBLUE_VERSION = { "urn:upnp-org:serviceId:ZiGateGateway1", "ZiGateVersion", true },
	ZIBLUE_MAC = { "urn:upnp-org:serviceId:ZiGateGateway1", "ZiGateMac", true },
	-- ZiGate device
	FEATURE = { "urn:upnp-org:serviceId:ZiGateDevice1", "Feature", true },
	ASSOCIATION = { "urn:upnp-org:serviceId:ZiGateDevice1", "Association", true },
	SETTING = { "urn:upnp-org:serviceId:ZiGateDevice1", "Setting", true }
}

-- Device types (with commands/actions)
local DEVICE = {
	SERIAL_PORT = {
		type = "urn:micasaverde-org:device:SerialPort:1", file = "D_SerialPort1.xml"
	},
	DOOR_SENSOR = {
		name = "zigate_device_type_door_sensor",
		type = "urn:schemas-micasaverde-com:device:DoorSensor:1", file = "D_DoorSensor1.xml",
		parameters = { { "ARMED", "0" }, { "TRIPPED", "0" }, { "TAMPER_ALARM", "0" } },
		commands = {
			[ "on" ] = function( ziGateDevice, feature )
				DeviceHelper.setTripped( ziGateDevice, feature, "1" )
			end,
			[ "off" ] = function( ziGateDevice, feature )
				DeviceHelper.setTripped( ziGateDevice, feature, "0" )
			end,
			[ "alarm" ] = function( ziGateDevice, feature )
				DeviceHelper.setTripped( ziGateDevice, feature, "1" )
			end,
			[ "tamper" ] = function( ziGateDevice, feature )
				DeviceHelper.setTamperAlarm( ziGateDevice, feature, "1" )
			end
		}
	},
	MOTION_SENSOR = {
		name = "zigate_device_type_motion_sensor",
		type = "urn:schemas-micasaverde-com:device:MotionSensor:1", file = "D_MotionSensor1.xml",
		--jsonFile = "D_MotionSensorWithTamper1.json",
		parameters = { { "ARMED", "0" }, { "TRIPPED", "0" }, { "TAMPER_ALARM", "0" } },
		commands = {
			[ "on" ] = function( ziGateDevice, feature )
				DeviceHelper.setTripped( ziGateDevice, feature, "1" )
			end,
			[ "off" ] = function( ziGateDevice, feature )
				DeviceHelper.setTripped( ziGateDevice, feature, "0" )
			end,
			[ "alarm" ] = function( ziGateDevice, feature )
				DeviceHelper.setTripped( ziGateDevice, feature, "1" )
			end,
			[ "tamper" ] = function( ziGateDevice, feature )
				DeviceHelper.setTamperAlarm( ziGateDevice, feature, "1" )
			end
		}
	},
	BAROMETER_SENSOR = {
		name = "zigate_device_type_barometer_sensor",
		type = "urn:schemas-micasaverde-com:device:BarometerSensor:1", file = "D_BarometerSensor1.xml",
		parameters = { { "PRESSURE", "0" }, { "FORECAST", "" } },
		commands = {
			[ "pressure" ] = function( ziGateDevice, feature, data )
				DeviceHelper.setPressure( ziGateDevice, feature, data )
			end
		}
	},
	BINARY_LIGHT = {
		name = "zigate_device_type_binary_light",
		type = "urn:schemas-upnp-org:device:BinaryLight:1", file = "D_BinaryLight1.xml",
		parameters = { { "SWITCH_POWER", "0" } },
		commands = {
			[ "on" ] = function( ziGateDevice, feature )
				DeviceHelper.setStatus( ziGateDevice, feature, "1", nil, true )
			end,
			[ "off" ] = function( ziGateDevice, feature )
				DeviceHelper.setStatus( ziGateDevice, feature, "0", nil, true )
			end
		}
	},
	DIMMABLE_LIGHT = {
		name = "zigate_device_type_dimmable_light",
		type = "urn:schemas-upnp-org:device:DimmableLight:1", file = "D_DimmableLight1.xml",
		parameters = { { "SWITCH_POWER", "0" }, { "DIMMER_LEVEL", "0" } },
		commands = {
			[ "on" ] = function( ziGateDevice, feature )
				DeviceHelper.setStatus( ziGateDevice, feature, "1", nil, true )
			end,
			[ "off" ] = function( ziGateDevice, feature )
				DeviceHelper.setStatus( ziGateDevice, feature, "0", nil, true )
			end,
			[ "dim" ] = function( ziGateDevice, feature, loadLevel )
				DeviceHelper.setLoadLevel( ziGateDevice, feature, loadLevel, nil, nil, true )
			end
		}
	},
	TEMPERATURE_SENSOR = {
		name = "zigate_device_type_temperature_sensor",
		type = "urn:schemas-micasaverde-com:device:TemperatureSensor:1", file = "D_TemperatureSensor1.xml",
		parameters = { { "TEMPERATURE", "0" } },
		commands = {
			[ "temperature" ] = function( ziGateDevice, feature, data )
				DeviceHelper.setTemperature( ziGateDevice, feature, data )
			end
		}
	},
	HUMIDITY_SENSOR = {
		name = "zigate_device_type_humidity_sensor",
		type = "urn:schemas-micasaverde-com:device:HumiditySensor:1", file = "D_HumiditySensor1.xml",
		parameters = { { "HUMIDITY", "0" } },
		commands = {
			[ "humidity" ] = function( ziGateDevice, feature, data )
				DeviceHelper.setHumidity( ziGateDevice, feature, data )
			end
		}
	},
	LIGHT_SENSOR = {
		name = "zigate_device_type_light_sensor",
		type = "urn:schemas-micasaverde-com:device:LightSensor:1", file = "D_LightSensor1.xml",
		parameters = { { "LIGHT_LEVEL", "0" } },
		commands = {
			[ "illuminance" ] = function( ziGateDevice, feature, data )
				DeviceHelper.setLightLevel( ziGateDevice, feature, data )
			end
		}
	},
	SCENE_CONTROLLER = {
		name = "zigate_device_type_scene_controller",
		type = "urn:schemas-micasaverde-com:device:SceneController:1", file = "D_SceneController1.xml",
		parameters = { { "LAST_SCENE_ID", "" } },
		commands = {
			[ "scene" ] = function( ziGateDevice, feature, data )
				DeviceHelper.setSceneId( ziGateDevice, feature, data )
			end
		}
	}
}

local _indexDeviceTypeInfos = {}
for deviceTypeName, deviceTypeInfos in pairs( DEVICE ) do
	_indexDeviceTypeInfos[ deviceTypeInfos.type ] = deviceTypeInfos
end

local function _getDeviceTypeInfos( deviceType )
	local deviceType = deviceType or ""
	local deviceTypeInfos = DEVICE[ deviceType ] or _indexDeviceTypeInfos[ deviceType ]
	if ( deviceTypeInfos == nil ) then
		warning( "Can not get infos for device type " .. tostring( deviceType ), "getDeviceTypeInfos" )
	end
	return deviceTypeInfos
end

local function _getEncodedParameters( deviceTypeInfos )
	local parameters = ""
	if ( deviceTypeInfos and deviceTypeInfos.parameters ) then
		for _, param in ipairs( deviceTypeInfos.parameters ) do
			local variable = VARIABLE[ param[1] ]
			parameters = parameters .. variable[1] .. "," .. variable[2] .. "=" .. ( param[2] or "" ) .. "\n"
		end
	end
	return parameters
end

local JOB_STATUS = {
	NONE = -1,
	WAITING_TO_START = 0,
	IN_PROGRESS = 1,
	ERROR = 2,
	ABORTED = 3,
	DONE = 4,
	WAITING_FOR_CALLBACK = 5
}

-- **************************************************
-- ZigBee
-- **************************************************

local ZIGATE_INFOS = {
	[ "0000" ] = {
		name = "Basic",
		category = "General",
		attributes = {
			[ "FF01" ] = {
				feature = "battery", unit = "%",
				command = function( value )
					debug( string_formatToHex(value), "ZIGATE_INFOS" )
					local batteryLevel = ( bit.lshift( value:byte( 4 ), 8 ) + value:byte( 3 ) ) / 1000
					debug( tostring(batteryLevel), "batteryLevel" )
					--  3.3V is 100%, 2.6V is 0%
					-- CR2032 (3V) :
					-- 2.95V : the battery should be replaced; 2.8V : the battery is almost dead
					debug( tostring(batteryLevel), "batteryLevel" )
					if ( batteryLevel > 2.95 ) then
						batteryLevel = 100
					elseif ( batteryLevel > 2.8 ) then
						batteryLevel = 30
					else
						batteryLevel = 10
					end
					return "battery", batteryLevel
				end
			}
		}
	},
	[ "0006" ] = {
		name = "On/Off",
		category = "General",
		attributes = {
			[ "0000" ] = {
				feature = "state", deviceTypes = { "BINARY_LIGHT", "DIMMABLE_LIGHT", "DOOR_SENSOR" }, settings = "",
				command = function( value )
					return ( value and "on" or "off" )
				end
			},
			[ "8000" ] = {
				feature = "scene", deviceTypes = { "SCENE_CONTROLLER" },
				command = function( value )
					return "scene", value, "Number of click: " .. tostring(value)
				end
			}
		}
	},
	[ "000C" ] = {
		name = "Magic cube",
		category = "General",
		attributes = {
			[ "FF05" ] = {
				feature = "scene", deviceTypes = { "BINARY_LIGHT" }, settings = "button,pulse",
				command = function( value )
					if ( value == 0x01F4 ) then
						return "scene", 0, "shake"
					elseif ( value == 0x0103 ) then
						return "scene", 1, "slide"
					end
				end
			}
		}
	},
	[ "0012" ] = {
		name = "Magic cube",
		category = "General",
		attributes = {
			[ "0055" ] = {
				feature = "scene", deviceTypes = { "SCENE_CONTROLLER" }, settings = "button,pulse",
				command = function( value )
					if ( value == 0x0000 ) then
						return "scene", 0, "shake"
					elseif ( value == 0x0103 ) then
						return "scene", 1, "slide"
					elseif ( value == 0x0204 ) then
						return "scene", 2, "tap"
					end
				end
			}
		}
	},
	[ "0400" ] = {
		name = "Illuminance",
		category = "Measurement",
		attributes = {
			[ "0000" ] = {
				feature = "illuminance", deviceTypes = { "LIGHT_SENSOR" }, unit = "lux",
				command = function( value )
					return "illuminance", value
				end
			}
		}
	},
	[ "0402" ] = {
		name = "Temperature",
		category = "Measurement",
		attributes = {
			[ "0000" ] = {
				feature = "temperature", deviceTypes = { "TEMPERATURE_SENSOR" }, unit = "°C",
				command = function( value )
					return "temperature", value / 100
				end
			}
		}
	},
	[ "0403" ] = {
		name = "Atmospheric pressure",
		category = "Measurement",
		attributes = {
			[ "0000" ] = {
				feature = "pressure", deviceTypes = { "BAROMETER_SENSOR" }, unit = "hPa",
				command = function( value )
					return "pressure", value
				end
			}
		}
	},
	[ "0405" ] = {
		name = "Humidity",
		category = "Measurement",
		attributes = {
			[ "0000" ] = {
				feature = "humidity", deviceTypes = { "HUMIDITY_SENSOR" }, unit = "%",
				command = function( value )
					return "humidity", tonumber(value) / 100
				end
			}
		}
	},
	[ "0406" ] = {
		name = "Occupancy Sensing",
		category = "Measurement",
		attributes = {
			[ "0000" ] = {
				feature = "occupancy" , deviceTypes = { "MOTION_SENSOR" }, settings = "timeout=30",
				command = function( value )
					return ( value and "on" or "off" )
				end
			}
		}
	}
}


-- **************************************************
-- Globals
-- **************************************************

local DEVICE_ID      -- The device # of the parent device

local g_maxId = 0           -- A number that increments with every device learned.
local g_baseId = ""

-- **************************************************
-- Number functions
-- **************************************************

-- Formats a number as hex.
function number_toHex( n )
	if ( type( n ) == "number" ) then
		return string.format( "%02X", n )
	end
	return tostring( n )
end

-- **************************************************
-- Table functions
-- **************************************************

do -- extend table
	-- Merges (deeply) the contents of one table (t2) into another (t1)
	function table_extend( t1, t2, excludedKeys )
		if ( ( t1 == nil ) or ( t2 == nil ) ) then
			return
		end
		local exclKeys
		if ( type( excludedKeys ) == "table" ) then
			exclKeys = {}
			for _, key in ipairs( excludedKeys ) do
				exclKeys[ key ] = true
			end
		end
		for key, value in pairs( t2 ) do
			if ( not exclKeys or not exclKeys[ key ] ) then
				if ( type( value ) == "table" ) then
					if ( type( t1[key] ) == "table" ) then
						t1[key] = table_extend( t1[key], value, excludedKeys )
					else
						t1[key] = table_extend( {}, value, excludedKeys )
					end
				elseif ( value ~= nil ) then
					if ( type( t1[key] ) == type( value ) ) then
						t1[key] = value
					else
						-- Try to keep the former type
						if ( type( t1[key] ) == "number" ) then
							luup.log( "table_extend : convert '" .. key .. "' to number " , 2 )
							t1[key] = tonumber( value )
						elseif ( type( t1[key] ) == "boolean" ) then
							luup.log( "table_extend : convert '" .. key .. "' to boolean" , 2 )
							t1[key] = ( value == true )
						elseif ( type( t1[key] ) == "string" ) then
							luup.log( "table_extend : convert '" .. key .. "' to string" , 2 )
							t1[key] = tostring( value )
						else
							t1[key] = value
						end
					end
				end
			elseif ( value ~= nil ) then
				t1[key] = value
			end
		end
		return t1
	end

	-- Checks if a table contains the given item.
	-- Returns true and the key / index of the item if found, or false if not found.
	function table_contains( t, item )
		if ( t == nil ) then
			return
		end
		for k, v in pairs( t ) do
			if ( v == item ) then
				return true, k
			end
		end
		return false
	end

	-- Checks if table contains all the given items (table).
	function table_containsAll( t1, items )
		if ( ( type( t1 ) ~= "table" ) or ( type( t2 ) ~= "table" ) ) then
			return false
		end
		for _, v in pairs( items ) do
			if not table_contains( t1, v ) then
				return false
			end
		end
		return true
	end

	-- Appends the contents of the second table at the end of the first table
	function table_append( t1, t2, noDuplicate )
		if ( ( t1 == nil ) or ( t2 == nil ) ) then
			return
		end
		local table_insert = table.insert
		if ( type( t2 ) == "table" ) then
			table.foreach(
				t2,
				function ( _, v )
					if ( noDuplicate and table_contains( t1, v ) ) then
						return
					end
					table_insert( t1, v )
				end
			)
		else
			if ( noDuplicate and table_contains( t1, t2 ) ) then
				return
			end
			table_insert( t1, t2 )
		end
		return t1
	end

	-- Extracts a subtable from the given table
	function table_extract( t, start, length )
		if ( start < 0 ) then
			start = #t + start + 1
		end
		length = length or ( #t - start + 1 )

		local t1 = {}
		for i = start, start + length - 1 do
			t1[#t1 + 1] = t[i]
		end
		return t1
	end

	--[[
	function table_concatChar( t )
		local res = ""
		for i = 1, #t do
			res = res .. string.char( t[i] )
		end
		return res
	end
	--]]

	-- Concatenates a table of numbers into a string with Hex separated by the given separator.
	function table_concatHex( t, sep, start, length )
		sep = sep or "-"
		start = start or 1
		if ( start < 0 ) then
			start = #t + start + 1
		end
		length = length or ( #t - start + 1 )
		local s = number_toHex( t[start] )
		if ( length > 1 ) then
			for i = start + 1, start + length - 1 do
				s = s .. sep .. number_toHex( t[i] )
			end
		end
		return s
	end

	function table_filter( t, filter )
		local out = {}
		for k, v in pairs( t ) do
			if filter( k, v ) then
				if ( type(k) == "number" ) then
					table.insert( out, v )
				else
					out[ k ] = v
				end
			end
		end
		return out
	end

	function table_getKeys( t )
		local keys = {}
		for key, value in pairs( t ) do
			table.insert( keys, key )
		end
		return keys
	end
end


-- **************************************************
-- String functions
-- **************************************************

do -- extend string
	-- Pads string to given length with given char from left.
	function string_lpad( s, length, c )
		s = tostring( s )
		length = length or 2
		c = c or " "
		return c:rep( length - #s ) .. s
	end

	-- Pads string to given length with given char from right.
	function string_rpad( s, length, c )
		s = tostring( s )
		length = length or 2
		c = char or " "
		return s .. c:rep( length - #s )
	end

	-- Returns if a string is empty (nil or "")
	function string_isEmpty( s )
		return ( ( s == nil ) or ( s == "" ) ) 
	end

	function string_trim( s )
		return s:match( "^%s*(.-)%s*$" )
	end

	-- Splits a string based on the given separator. Returns a table.
	function string_split( s, sep, convert, convertParam )
		if ( type( convert ) ~= "function" ) then
			convert = nil
		end
		if ( type( s ) ~= "string" ) then
			return {}
		end
		sep = sep or " "
		local t = {}
		--for token in s:gmatch( "[^" .. sep .. "]+" ) do
		for token in ( s .. sep ):gmatch( "([^" .. sep .. "]*)" .. sep ) do
			if ( convert ~= nil ) then
				token = convert( token, convertParam )
			end
			table.insert( t, token )
		end
		return t
	end

	function string_fromHex( s )
		return ( s:gsub( '..', function( cc )
			return string.char( tonumber(cc, 16) )
		end ))
	end

	function string_toHex( s )
		return ( s:gsub( '.', function( c )
			return string.format( '%02X', string.byte(c) )
		end ))
	end

	-- Formats a string into hex.
	function string_formatToHex( s, sep )
		sep = sep or "-"
		local result = ""
		if ( s ~= nil ) then
			for i = 1, string.len( s ) do
				if ( i > 1 ) then
					result = result .. sep
				end
				result = result .. string.format( "%02X", string.byte( s, i ) )
			end
		end
		return result
	end

	function string_decodeURI( s )
		local hex={}
		for i = 0, 255 do
			hex[ string.format("%0x",i) ] = string.char(i)
			hex[ string.format("%0X",i) ] = string.char(i)
		end
		return ( s:gsub( '%%(%x%x)', hex ) )
	end
end


-- **************************************************
-- Variable management
-- **************************************************

Variable = {
	-- Check if variable (service) is supported
	isSupported = function( deviceId, variable )
		if not luup.device_supports_service( variable[1], deviceId ) then
			warning( "Device #" .. tostring( deviceId ) .. " does not support service " .. variable[1], "Variable.isSupported" )
			return false
		end
		return true
	end,

	-- Get variable timestamp
	getTimestamp = function( deviceId, variable )
		if ( ( type( variable ) == "table" ) and ( type( variable[4] ) == "string" ) ) then
			local variableTimestamp = VARIABLE[ variable[4] ]
			if ( variableTimestamp ~= nil ) then
				return tonumber( ( luup.variable_get( variableTimestamp[1], variableTimestamp[2], deviceId ) ) )
			end
		end
		return nil
	end,

	-- Set variable timestamp
	setTimestamp = function( deviceId, variable, timestamp )
		if ( variable[4] ~= nil ) then
			local variableTimestamp = VARIABLE[ variable[4] ]
			if ( variableTimestamp ~= nil ) then
				luup.variable_set( variableTimestamp[1], variableTimestamp[2], ( timestamp or os.time() ), deviceId )
			end
		end
	end,

	-- Get variable value (can deal with unknown variable)
	get = function( deviceId, variable )
		deviceId = tonumber( deviceId )
		if ( deviceId == nil ) then
			error( "deviceId is nil", "Variable.get" )
			return
		elseif ( variable == nil ) then
			error( "variable is nil", "Variable.get" )
			return
		end
		local value, timestamp = luup.variable_get( variable[1], variable[2], deviceId )
		if ( value ~= "0" ) then
			local storedTimestamp = Variable.getTimestamp( deviceId, variable )
			if ( storedTimestamp ~= nil ) then
				timestamp = storedTimestamp
			end
		end
		return value, timestamp
	end,

	getUnknown = function( deviceId, serviceId, variableName )
		local variable = indexVariable[ tostring( serviceId ) .. ";" .. tostring( variableName ) ]
		if ( variable ~= nil ) then
			return Variable.get( deviceId, variable )
		else
			return luup.variable_get( serviceId, variableName, deviceId )
		end
	end,

	-- Set variable value
	set = function( deviceId, variable, value )
		deviceId = tonumber( deviceId )
		if ( deviceId == nil ) then
			error( "deviceId is nil", "Variable.set" )
			return
		elseif ( variable == nil ) then
			error( "variable is nil", "Variable.set" )
			return
		elseif ( value == nil ) then
			error( "value is nil", "Variable.set" )
			return
		end
		if ( type( value ) == "number" ) then
			value = tostring( value )
		end
		local doChange = true
		local currentValue = luup.variable_get( variable[1], variable[2], deviceId )
		local deviceType = luup.devices[deviceId].device_type
		--[[
		if (
			(variable == VARIABLE.TRIPPED)
			and (currentValue == value)
			and (
				(deviceType == DEVICE.MOTION_SENSOR.type)
				or (deviceType == DEVICE.DOOR_SENSOR.type)
				or (deviceType == DEVICE.SMOKE_SENSOR.type)
			)
			and (luup.variable_get(VARIABLE.REPEAT_EVENT[1], VARIABLE.REPEAT_EVENT[2], deviceId) == "0")
		) then
			doChange = false
		elseif (
				(luup.devices[deviceId].device_type == tableDeviceTypes.LIGHT[1])
			and (variable == VARIABLE.LIGHT)
			and (currentValue == value)
			and (luup.variable_get(VARIABLE.VAR_REPEAT_EVENT[1], VARIABLE.VAR_REPEAT_EVENT[2], deviceId) == "1")
		) then
			luup.variable_set(variable[1], variable[2], "-1", deviceId)
		else--]]
		if ( ( currentValue == value ) and ( ( variable[3] == true ) or ( value == "0" ) ) ) then
			-- Variable is not updated when the value is unchanged
			doChange = false
		end

		if doChange then
			luup.variable_set( variable[1], variable[2], value, deviceId )
		end

		-- Updates linked variable for timestamp (just for active value)
		if ( value ~= "0" ) then
			Variable.setTimestamp( deviceId, variable, os.time() )
		end
	end,

	-- Get variable value and init if value is nil or empty
	getOrInit = function( deviceId, variable, defaultValue )
		local value, timestamp = Variable.get( deviceId, variable )
		if ( ( value == nil ) or (  value == "" ) ) then
			value = defaultValue
			Variable.set( deviceId, variable, value )
			timestamp = os.time()
			Variable.setTimestamp( deviceId, variable, timestamp )
		end
		return value, timestamp
	end,

	watch = function( deviceId, variable, callback )
		luup.variable_watch( callback, variable[1], variable[2], lul_device )
	end
}


-- **************************************************
-- UI messages
-- **************************************************

UI = {
	show = function( message )
		debug( "Display message: " .. tostring( message ), "UI.show" )
		Variable.set( DEVICE_ID, VARIABLE.LAST_MESSAGE, message )
	end,

	showError = function( message )
		debug( "Display message: " .. tostring( message ), "UI.showError" )
		--message = '<div style="color:red">' .. tostring( message ) .. '</div>'
		message = '<font color="red">' .. tostring( message ) .. '</font>'
		Variable.set( DEVICE_ID, VARIABLE.LAST_MESSAGE, message )
	end,

	clearMessage = function()
		Variable.set( DEVICE_ID, VARIABLE.LAST_MESSAGE, "" )
	end
}


-- **************************************************
-- Device functions
-- **************************************************

local function _getZiGateId( ziGateDevice, feature )
	return ziGateDevice.address .. ";" .. ziGateDevice.endPoint .. ";" .. tostring( feature.name ) .. ";" .. tostring( feature.deviceId )
end


-- **************************************************
-- Device helper
-- **************************************************

DeviceHelper = {
	isDimmable = function( ziGateDevice, feature, checkProtocol )
		if checkProtocol then
			if ( ziGateDevice.protocol == "RTS" ) then
				return false
			end
		end
		return luup.device_supports_service( VARIABLE.DIMMER_LEVEL[1], feature.deviceId )
	end,

	-- Switch OFF/ON/TOGGLE
	setStatus = function( ziGateDevice, feature, status, isLongPress, noAction )
		if status then
			status = tostring( status )
		end
		local deviceId = feature.deviceId
		local formerStatus = Variable.get( deviceId, VARIABLE.SWITCH_POWER ) or "0"
		local msg = "ZiGate device '" .. _getZiGateId( ziGateDevice, feature ) .. "'"
		if ( feature.settings.receiver ) then
			msg = msg .. " (receiver)"
		end

		-- Pulse
		local isPulse = ( feature.settings.pulse == true )
		-- Toggle
		local isToggle = ( feature.settings.toggle == true )
		if ( isToggle or ( status == nil ) or ( status == "" ) ) then
			if isPulse then
				-- Always ON in pulse and toggle mode
				msg = msg .. " - Switch"
				status = "1"
			else
				msg = msg .. " - Toggle"
				if ( formerStatus == "1" ) then
					status = "0"
				else
					status = "1"
				end
			end
		else
			msg = msg .. " - Switch"
		end

		-- Has status changed ?
		if ( status == formerStatus ) then
			debug( msg .. " - Status has not changed", "DeviceHelper.setStatus" )
			return
		end

		-- Update status variable
		local loadLevel
		if ( status == "1" ) then
			msg = msg .. " ON device #" .. tostring( deviceId )
			if DeviceHelper.isDimmable( ziGateDevice, feature, false ) then
				loadLevel = Variable.get( deviceId, VARIABLE.DIMMER_LEVEL_OLD ) or "100"
				if ( loadLevel == "0" ) then
					loadLevel = "100"
				end
				msg = msg .. " at " .. loadLevel .. "%"
			end
		else
			msg = msg .. " OFF device #" .. tostring( deviceId )
			status = "0"
			if DeviceHelper.isDimmable( ziGateDevice, feature, false ) then
				msg = msg .. " at 0%"
				loadLevel = 0
			end
		end
		if isLongPress then
			msg = msg .. " (long press)"
		end
		debug( msg, "DeviceHelper.setStatus" )
		Variable.set( deviceId, VARIABLE.SWITCH_POWER, status )
		if loadLevel then
			if ( loadLevel == 0 ) then
				Variable.set( deviceId, VARIABLE.DIMMER_LEVEL_OLD, Variable.get( deviceId, VARIABLE.DIMMER_LEVEL ) )
			end
			Variable.set( deviceId, VARIABLE.DIMMER_LEVEL, loadLevel )
		end

		-- Send command if needed
		if ( feature.settings.receiver and not ( noAction == true ) ) then
			local cmd
			if ( status == "1" ) then
				cmd = "01"
			else
				cmd = "00"
			end
			local qualifier = feature.settings.qualifier and ( " QUALIFIER " .. ( ( feature.settings.qualifier == "1" ) and "1" or "0" ) ) or ""
			local burst = feature.settings.burst and ( " BURST " .. feature.settings.burst ) or ""
			if ( loadLevel and DeviceHelper.isDimmable( ziGateDevice, feature, true ) ) then 
				-- TODO
				--Network.send( "ZIA++DIM " .. ziGateDevice.protocol .. " ID " .. ziGateDevice.protocolDeviceId .. " %" .. tostring(loadLevel) .. qualifier .. burst )
			else
				Network.send( "0092", "02" .. ziGateDevice.address .. "01" .. ziGateDevice.endPoint .. cmd )
			end
		end

		-- Pulse
		if ( isPulse and ( status == "1" ) ) then
			-- TODO : OFF après 200ms : voir multiswitch
			msg = "ZiGate device '" .. _getZiGateId( ziGateDevice, feature ) .. "' - Pulse OFF device #" .. tostring( deviceId )
			if DeviceHelper.isDimmable( ziGateDevice, feature, false ) then
				debug( msg .. " at 0%", "DeviceHelper.setStatus" )
				Variable.set( deviceId, VARIABLE.SWITCH_POWER, "0" )
				Variable.set( deviceId, VARIABLE.DIMMER_LEVEL_OLD, Variable.get( deviceId, VARIABLE.DIMMER_LEVEL ) )
				Variable.set( deviceId, VARIABLE.DIMMER_LEVEL, 0 )
			else
				debug( msg, "DeviceHelper.setStatus" )
				Variable.set( deviceId, VARIABLE.SWITCH_POWER, "0" )
			end
		end

		-- Association
		Association.propagate( feature.association, status, loadLevel, isLongPress )
		if ( isPulse and ( status == "1" ) ) then
			Association.propagate( feature.association, "0", nil, isLongPress )
		end

		return status
	end,

	-- Dim OFF/ON/TOGGLE
	setLoadLevel = function( ziGateDevice, feature, loadLevel, direction, isLongPress, noAction )
		loadLevel = tonumber( loadLevel )
		local deviceId = feature.deviceId
		local formerLoadLevel, lastLoadLevelChangeTime = Variable.get( deviceId, VARIABLE.DIMMER_LEVEL )
		formerLoadLevel = tonumber( formerLoadLevel ) or 0
		local msg = "Dim"

		if ( isLongPress and not DeviceHelper.isDimmable( ziGateDevice, feature, true ) ) then
			-- Long press handled by a switch
			return DeviceHelper.setStatus( ziGateDevice, feature, nil, isLongPress, noAction )

		elseif ( loadLevel == nil ) then
			-- Toggle dim
			loadLevel = formerLoadLevel
			if ( direction == nil ) then
				direction = Variable.getOrInit( deviceId, VARIABLE.DIMMER_DIRECTION, "up" )
				if ( os.difftime( os.time(), lastLoadLevelChangeTime ) > 2 ) then
					-- Toggle direction after 2 seconds of inactivity
					msg = "Toggle dim"
					if ( direction == "down" ) then
						direction = "up"
						Variable.set( deviceId, VARIABLE.DIMMER_DIRECTION, "up" )
					else
						direction = "down"
						Variable.set( deviceId, VARIABLE.DIMMER_DIRECTION, "down" )
					end
				end
			end
			if ( direction == "down" ) then
				loadLevel = loadLevel - 3
				msg = msg .. "-"
			else
				loadLevel = loadLevel + 3
				msg = msg .. "+"
			end
		end

		-- Update load level variable
		if ( loadLevel < 3 ) then
			loadLevel = 0
		elseif ( loadLevel > 100 ) then
			loadLevel = 100
		end

		-- Has load level changed ?
		if ( loadLevel == formerLoadLevel ) then
			debug( msg .. " - Load level has not changed", "DeviceHelper.setLoadLevel" )
			return
		end

		debug( msg .. " device #" .. tostring( deviceId ) .. " at " .. tostring( loadLevel ) .. "%", "DeviceHelper.setLoadLevel" )
		Variable.set( deviceId, VARIABLE.DIMMER_LEVEL, loadLevel )
		if ( loadLevel > 0 ) then
			Variable.set( deviceId, VARIABLE.SWITCH_POWER, "1" )
		else
			Variable.set( deviceId, VARIABLE.SWITCH_POWER, "0" )
		end

		-- Send command if needed
		if ( feature.settings.receiver and not ( noAction == true ) ) then
			local qualifier = feature.settings.qualifier and ( " QUALIFIER " .. ( ( feature.settings.qualifier == "1" ) and "1" or "0" ) ) or ""
			local burst = feature.settings.burst and ( " BURST " .. feature.settings.burst ) or ""
			if ( loadLevel > 0 ) then
				if not DeviceHelper.isDimmable( ziGateDevice, feature, true ) then
					if ( loadLevel == 100 ) then
						Network.send( "ZIA++ON " .. ziGateDevice.protocol .. " ID " .. ziGateDevice.protocolDeviceId .. qualifier .. burst )
					else
						debug( "This protocol does not support DIM", "DeviceHelper.setLoadLevel" )
					end
				else
					Network.send( "ZIA++DIM " .. ziGateDevice.protocol .. " ID " .. ziGateDevice.protocolDeviceId .. " %" .. tostring(loadLevel) .. qualifier .. burst )
				end
			else
				Network.send( "ZIA++OFF " .. ziGateDevice.protocol .. " ID " .. ziGateDevice.protocolDeviceId .. qualifier .. burst )
			end
		end

		-- Association
		Association.propagate( feature.association, nil, loadLevel, isLongPress )

		return loadLevel
	end,

	-- Set armed
	setArmed = function( ziGateDevice, feature, armed )
		local deviceId = feature.deviceId
		if not Variable.isSupported( deviceId, VARIABLE.ARMED ) then
			return
		end
		armed = tostring( armed or "0" )
		if ( armed == "1" ) then
			debug( "Arm device #" .. tostring( deviceId ), "DeviceHelper.setArmed" )
		else
			debug( "Disarm device #" .. tostring( deviceId ), "DeviceHelper.setArmed" )
		end
		Variable.set( deviceId, VARIABLE.ARMED, armed )
		if ( armed == "0" ) then
			Variable.set( deviceId, VARIABLE.ARMED_TRIPPED, "0" )
		end
	end,

	-- Set tripped
	setTripped = function( ziGateDevice, feature, tripped )
		local deviceId = feature.deviceId
		if not Variable.isSupported( deviceId, VARIABLE.TRIPPED ) then
			return
		end
		tripped = tostring( tripped or "0" )
		if ( tripped == "1" ) then
			debug( "Device #" .. tostring( deviceId ) .. " is tripped", "DeviceHelper.setTripped" )
			local timeout = feature.settings.timeout or 0
			if ( timeout > 0 ) then
				debug( "Device #" .. tostring( deviceId ) .. " will be untripped in " .. tostring(timeout) .. "s", "DeviceHelper.setTripped" )
				luup.call_delay( "ZiGateGateway.Child.untripAuto", timeout, deviceId )
			end
		else
			debug( "Device #" .. tostring( deviceId ) .. " is untripped", "DeviceHelper.setTripped" )
		end
		Variable.set( deviceId, VARIABLE.TRIPPED, tripped )
		if ( ( tripped == "1" ) and ( Variable.get( deviceId, VARIABLE.ARMED) == "1" ) ) then
			Variable.set( deviceId, VARIABLE.ARMED_TRIPPED, "1" )
		else
			Variable.set( deviceId, VARIABLE.ARMED_TRIPPED, "0" )
		end

		-- Association
		Association.propagate( feature.association, tripped )
	end,

	-- Set tamper alarm
	setTamperAlarm  = function( ziGateDevice, feature, alarm )
		local deviceId = feature.deviceId
		if not Variable.isSupported( deviceId, VARIABLE.TAMPER_ALARM ) then
			return
		end
		debug( "Set device #" .. tostring(deviceId) .. " tamper alarm to '" .. tostring( alarm ) .. "'", "DeviceHelper.setTamperAlarm" )
		Variable.set( deviceId, VARIABLE.TAMPER_ALARM, alarm )
	end,

	-- Set temperature
	setTemperature = function( ziGateDevice, feature, data )
		local deviceId = feature.deviceId
		if not Variable.isSupported( deviceId, VARIABLE.TEMPERATURE ) then
			return
		end
		local temperature = tonumber( data ) or 0 -- degree celcius
		-- TODO : manage Fahrenheit
		debug( "Set device #" .. tostring(deviceId) .. " temperature to " .. tostring( temperature ) .. "°C", "DeviceHelper.setTemperature" )
		Variable.set( deviceId, VARIABLE.TEMPERATURE, temperature )
	end,

	-- Set humidity
	setHumidity = function( ziGateDevice, feature, humidity )
		local deviceId = feature.deviceId
		if not Variable.isSupported( deviceId, VARIABLE.HUMIDITY ) then
			return
		end
		local humidity = tonumber( humidity )
		if ( humidity and humidity ~= 0 ) then
			debug( "Set device #" .. tostring(deviceId) .. " humidity to " .. tostring( humidity ) .. "%", "DeviceHelper.setHumidity" )
			Variable.set( deviceId, VARIABLE.HUMIDITY, humidity )
		end
	end,

	-- Set light level
	setLightLevel = function( ziGateDevice, feature, lightLevel )
		local deviceId = feature.deviceId
		if not Variable.isSupported( deviceId, VARIABLE.LIGHT_LEVEL ) then
			return
		end
		debug( "Set device #" .. tostring(deviceId) .. " light level to " .. tostring( lightLevel ) .. "lux", "DeviceHelper.setLightLevel" )
		Variable.set( deviceId, VARIABLE.LIGHT_LEVEL, lightLevel )
	end,

	-- Set atmospheric pressure
	setPressure = function( ziGateDevice, feature, pressure )
		local deviceId = feature.deviceId
		--[[if not Variable.isSupported( deviceId, VARIABLE.PRESSURE ) then
			return
		end--]]
		local pressure = tonumber( pressure )
		local forecast = "TODO" -- TODO
		--[[
		"sunny"
		"partly cloudy"
		"cloudy"
		"rain"
		--]]
		debug( "Set device #" .. tostring(deviceId) .. " pressure to " .. tostring( pressure ) .. "hPa and forecast to " .. forecast, "DeviceHelper.setPressure" )
		Variable.set( deviceId, VARIABLE.PRESSURE, pressure )
		Variable.set( deviceId, VARIABLE.FORECAST, forecast )
	end,

	-- Set scene id
	setSceneId = function( ziGateDevice, feature, sceneId )
		local deviceId = feature.deviceId
		if not Variable.isSupported( deviceId, VARIABLE.LAST_SCENE_ID ) then
			return
		end
		debug( "Set device #" .. tostring(deviceId) .. " last scene to '" .. tostring( sceneId ) .. "'", "DeviceHelper.setSceneId" )
		Variable.set( deviceId, VARIABLE.LAST_SCENE_ID, sceneId )
	end,

	-- Set battery level
	setBatteryLevel = function( ziGateDevice, feature, batteryLevel )
		local deviceId = ziGateDevice.mainDeviceId
		local batteryLevel = tonumber(batteryLevel) or 0
		if (batteryLevel < 0) then
			batteryLevel = 0
		elseif (batteryLevel > 100) then
			batteryLevel = 100
		end
		debug( "Set device #" .. tostring(deviceId) .. " battery level to " .. tostring(batteryLevel) .. "%", "DeviceHelper.setBatteryLevel" )
		Variable.set( deviceId, VARIABLE.BATTERY_LEVEL, batteryLevel )
	end

}

-- **************************************************
-- ZigBee Message types
-- **************************************************

function _getAttrValue( attrType, attrData )
	if ( attrType == 0x10 ) then
		-- boolean
		return ( attrData:byte() == 0x01 )

	elseif ( attrType == 0x20 ) then
		-- uint8
		return attrData:byte( 1 )

	elseif ( attrType == 0x21 ) then
		-- uint16
		return bit.lshift( attrData:byte( 1 ), 8 ) + attrData:byte( 2 )

	elseif ( attrType == 0x28 ) then
		-- int8
		return attrData:byte( 1 )

	elseif ( attrType == 0x29 ) then
		-- int16
		return bit.lshift( attrData:byte( 1 ), 8 ) + attrData:byte( 2 )

	elseif ( attrType == 0x42 ) then
		-- string
		return attrData

	else
		return "unknown data type"
	end
end


ZIGATE_MESSAGE_TYPES = {

-- Status
	["8000"] = function( payload, quality )
		
	end,

	-- Version
	["8010"] = function( payload, quality )
		
	end,

	-- Attribute Report
	["8102"] = function( payload, quality )
		local sqn = payload:byte( 1 )
		local srcAddress = string_toHex( payload:sub( 2, 3 ) )
		local endPoint = string_toHex( payload:sub( 4, 4 ) )
		local msg = "(address:0x:".. srcAddress .. "), (endPoint:0x" .. endPoint .. ")"
		local clusterId = string_toHex( payload:sub( 5, 6 ) )
		local attrId = string_toHex( payload:sub( 7, 8 ) )
		local attrStatus = payload:byte( 9 )
		local attrType = payload:byte( 10 )
		local attrSize = bit.lshift( payload:byte( 11 ), 8 ) + payload:byte( 12 )
		local attrData = payload:sub( 13, 12 + attrSize )
		--debug( string_formatToHex(attrData), "attrData" )
		--debug( tostring(attrSize), "attrSize" )
		local attrValue = _getAttrValue( attrType, attrData )
		local clusterInfos = ZIGATE_INFOS[ clusterId ]
		if clusterInfos then
			local attrInfos = clusterInfos.attributes[ attrId ]
			if attrInfos then
				local commandName, data = attrInfos.command( attrValue )
				if commandName then
					debug( msg .. ", (" .. clusterInfos.category .. ":" .. clusterInfos.name .. "), (attrId:0x" .. attrId .. "), (feature:" .. attrInfos.feature .. "), (command:" .. commandName .. "), (data: " .. tostring(data) .. ")", "Network.receive" )
					Command.process( srcAddress, endPoint, attrInfos, commandName, data, quality )
				else
					error( msg .. ", (" .. clusterInfos.category .. ":" .. clusterInfos.name .. "), attrId 0x" .. attrId .. " has no command", "Network.receive" )
				end
			else
				warning( msg .. ", (" .. clusterInfos.category .. ":" .. clusterInfos.name .. "), attrId 0x" .. attrId .. " is not handled", "Network.receive" )
			end
		else
			warning( msg .. ", cluster 0x" .. clusterId .. " is not handled", "Network.receive" )
		end
	end
}

-- **************************************************
-- Commands
-- **************************************************

local _commandsToProcess = {}
local _isProcessingCommand = false
local _lastCommandsByZiGateId = {}

Command = {

	process = function( srcAddress, endPoint, attrInfos, commandName, data, quality )
		local msg = "ZiGate device (0x" .. srcAddress .. ", 0x" .. endPoint .. ")"
		local ziGateDevice, feature

		if ( attrInfos.feature == "battery" ) then
			ziGateDevice = ZiGateDevices.get( srcAddress, endPoint )
			if ziGateDevice then
				table.insert( _commandsToProcess, { ziGateDevice, feature, DeviceHelper.setBatteryLevel, data } )
			end
		else
			ziGateDevice, feature = ZiGateDevices.getFromFeatureName( srcAddress, endPoint, attrInfos.feature )

			if ( ziGateDevice and feature ) then
				-- ZiGate device is known for this feature
				feature.data = ""
				if ( attrInfos.feature ~= commandName ) then
					feature.data = commandName
				end
				if ( data ~= nil ) then
					feature.data = feature.data .. " " .. tostring(data)
					if attrInfos.unit then
						feature.data = feature.data .. attrInfos.unit
					end
				end
				ziGateDevice.lastUpdate = os.time()
				local deviceTypeInfos = _getDeviceTypeInfos( feature.deviceType )
				if ( deviceTypeInfos == nil ) then
					error( msg .. " - Device type " .. feature.deviceType .. " is unknown", "Command.process" )
				elseif ( deviceTypeInfos.commands[ commandName ] ~= nil ) then
					debug( msg .. " - Feature command " .. commandName, "Command.process" )
					table.insert( _commandsToProcess, { ziGateDevice, feature, deviceTypeInfos.commands[ commandName ], data } )
					if ( ( commandName == "on" ) and ziGateDevice.sceneControllerFeature ) then
						ziGateDevice.sceneControllerFeature.data = "1"
						table.insert( _commandsToProcess, { ziGateDevice, ziGateDevice.sceneControllerFeature, _getDeviceTypeInfos( "SCENE_CONTROLLER" ).commands[ "scene" ], "1" } )
					end
				else
					warning( msg .. " - Feature command " .. commandName .. " not yet implemented for this device type " .. feature.deviceType, "Command.process" )
				end
			else
				-- Add this device to the discovered ZiGate devices
				if DiscoveredDevices.add( srcAddress, endPoint, attrInfos, commandName, data, quality ) then
					debug( "This message is from an unknown " .. msg .. " for feature '" .. attrInfos.feature .. "'", "Command.process" )
				else
					debug( "This message is from an " .. msg .. " already discovered", "Command.process" )
				end
			end
		end

		if ziGateDevice then
			ziGateDevice.quality = quality
		end

		if ( #_commandsToProcess > 0 ) then
			luup.call_delay( "ZiGateGateway.Command.deferredProcess", 0 )
		end
	end,

	deferredProcess = function()
		if _isProcessingCommand then
			debug( "Processing is already in progress", "Command.deferredProcess" )
			return
		end
		_isProcessingCommand = true
		local status, err = pcall( Command.protectedProcess )
		if err then
			error( "Error: " .. tostring( err ), "Command.deferredProcess" )
		end
		_isProcessingCommand = false
	end,

	protectedProcess = function()
		while _commandsToProcess[1] do
			local ziGateDevice, feature, commandFunction, data = unpack( _commandsToProcess[1] )
			if commandFunction( ziGateDevice, feature, data ) then
				--channel.lastCommand = message.CMD
				--channel.lastCommandReceiveTime = os.clock()
			end
			table.remove( _commandsToProcess, 1 )
		end
	end
}

-- **************************************************
-- Network
-- **************************************************

local _buffer = "" -- The received data buffer
local _messageToSendQueue = {}   -- The outbound message queue
local _isSendingMessage = false
local _transcodage = false

local function _getChecksum( s )
	local checksum = 0
	s:gsub( '.', function( c )
		checksum = bit.bxor( checksum, string.byte( c ) )
	end )
	return checksum
end

local function _transcode( s )
	return ( s:gsub( '.', function( c )
		local b = string.byte( c )
		if ( b > 10 ) then
			return c
		else
			return string.char( 2, bit.bxor( b, 0x10 ) )
		end
	end ))
end

Network = {

	receive = function( rxData )
		local rxByte = string.byte( rxData )

		if ( rxByte == 1 ) then
			_buffer = ""
		elseif ( rxByte == 3 ) then

			local msgType = string_toHex( _buffer:sub( 1,2 ) )
			local msgLen = bit.lshift( _buffer:byte( 3 ), 8 ) + _buffer:byte( 4 )
			local chkSum = _buffer:byte( 5 )
			local payload = _buffer:sub( 6, 4 + msgLen )
			local quality = _buffer:byte( 5 + msgLen )
			if ( chkSum ~= _getChecksum( _buffer:sub( 1,4 ) .. _buffer:sub( 6 ) ) ) then
				error( "Incoming message is corrupted (checksum) : " .. string_formatToHex(_buffer), "Network.receive" )
			elseif ( string.len(payload) + 1 ~= msgLen ) then
				error( "Incoming message is corrupted (expected length: " .. tostring(msgLen - 1) .. ", received: " .. tostring(string.len(payload)) .. ") : " .. string_formatToHex(_buffer), "Network.receive" )
			elseif ZIGATE_MESSAGE_TYPES[msgType] then
				debug( string_formatToHex(_buffer), "Network.receive" )
				ZIGATE_MESSAGE_TYPES[msgType]( payload, quality )
			else
				warning( "Unknown message type 0x" .. msgType, "Network.receive" )
			end

		elseif ( rxByte == 2 ) then
			_transcodage = true
		else
			if _transcodage then
				rxByte = bit.bxor( rxByte, 0x10 )
				_buffer = _buffer .. string.char( rxByte )
				_transcodage = false
			else
				_buffer = _buffer .. rxData
			end
		end
	end,

	-- Send a message (add to send queue)
	send = function( cmd, data )
		if ( luup.attr_get( "disabled", DEVICE_ID ) == "1" ) then
			warning( "Can not send message: ZiGate Gateway is disabled", "Network.send" )
			return
		end

		local command = string_fromHex( cmd )
		local payload = string_fromHex( data or "" )
		local length = string_fromHex( string.format( "%04X", string.len( payload ) ) )
		--debug("chk: ".. tostring(_getChecksum( command .. length .. payload )), "Network.send")
		local packet = string.char(1) .. _transcode( command .. length .. string.char( _getChecksum( command .. length .. payload ) ) .. payload ) .. string.char(3)

		table.insert( _messageToSendQueue, packet )
		if not _isSendingMessage then
			Network.flush()
		end
	end,

	-- Send the packets in the queue to ZiGate dongle
	flush = function ()
		if ( luup.attr_get( "disabled", DEVICE_ID ) == "1" ) then
			debug( "Can not send message: ZiGate Gateway is disabled", "Network.flush" )
			return
		end
		-- If we don't have any message to send, return.
		if ( #_messageToSendQueue == 0 ) then
			_isSendingMessage = false
			return
		end

		_isSendingMessage = true
		while _messageToSendQueue[1] do
			debug( "Send message: ".. string_formatToHex(_messageToSendQueue[1]), "Network.flush" )
			--debug( "Send message: " .. _messageToSendQueue[1], "Network.flush" )
			if not luup.io.write( _messageToSendQueue[1] ) then
				error( "Failed to send packet", "Network.flush" )
				return
			end
			table.remove( _messageToSendQueue, 1 )
		end

		_isSendingMessage = false
	end
}


-- **************************************************
-- Poll engine (Not used)
-- **************************************************

PollEngine = {
	poll = function ()
		log( "Start poll", "PollEngine.start" )
	end
}


-- **************************************************
-- Tools
-- **************************************************

Tools = {
	-- Get PID (array representation of the Product ID)
	getPID = function (productId)
		if (productId == nil) then
			return nil
		end
		local PID = {}
		for i, strHex in ipairs(string_split(productId, "-")) do
			PID[i] = tonumber(strHex, 16)
		end
		return PID
	end,

	extractInfos = function( infos )
		local result = {}
		for _, info in ipairs( infos ) do
			if not string_isEmpty( info.n ) then
				result[ info.n ] = info.v
			end
			for key, value in pairs( info ) do
				if ( string.len( key ) > 1 ) then
				result[ key ] = value
				end
			end
		end
		return result
	end,

	updateSystemStatus = function( infos )
		local status = Tools.extractInfos( infos )
		Variable.set( DEVICE_ID, VARIABLE.ZIBLUE_VERSION, status.Version )
		Variable.set( DEVICE_ID, VARIABLE.ZIBLUE_MAC,     status.Mac )
	end

}


-- **************************************************
-- Associations
-- **************************************************

Association = {
	-- Get associations from string
	get = function( strAssociation )
		local association = {}
		for _, encodedAssociation in pairs( string_split( strAssociation or "", "," ) ) do
			local linkedId, level, isScene, isZiGate = nil, 1, false, false
			while ( encodedAssociation ) do
				local firstCar = string.sub( encodedAssociation, 1 , 1 )
				if ( firstCar == "*" ) then
					isScene = true
					encodedAssociation = string.sub( encodedAssociation, 2 )
				elseif ( firstCar == "%" ) then
					isZiGate = true
					encodedAssociation = string.sub( encodedAssociation, 2 )
				elseif ( firstCar == "+" ) then
					level = level + 1
					if ( level > 2 ) then
						break
					end
					encodedAssociation = string.sub( encodedAssociation, 2 )
				else
					linkedId = tonumber( encodedAssociation )
					encodedAssociation = nil
				end
			end
			if linkedId then
				if isScene then
					if ( luup.scenes[ linkedId ] ) then
						if ( association.scenes == nil ) then
							association.scenes = { {}, {} }
						end
						table.insert( association.scenes[ level ], linkedId )
					else
						error( "Associated scene #" .. tostring( linkedId ) .. " is unknown", "Associations.get" )
					end
				elseif isZiGate then
					if ( luup.devices[ linkedId ] ) then
						if ( association.ziGateDevices == nil ) then
							association.ziGateDevices = { {}, {} }
						end
						table.insert( association.ziGateDevices[ level ], linkedId )
					else
						error( "Associated ZiGate device #" .. tostring( linkedId ) .. " is unknown", "Associations.get" )
					end
				else
					if ( luup.devices[ linkedId ] ) then
						if ( association.devices == nil ) then
							association.devices = { {}, {} }
						end
						table.insert( association.devices[ level ], linkedId )
					else
						error( "Associated device #" .. tostring( linkedId ) .. " is unknown", "Associations.get" )
					end
				end
			end
		end
		return association
	end,

	getEncoded = function( association )
		local function _getEncodedAssociations( associations, prefix )
			local encodedAssociations = {}
			for level = 1, 2 do
				for _, linkedId in pairs( associations[ level ] ) do
					table.insert( encodedAssociations, string.rep( "+", level - 1 ) .. prefix .. tostring( linkedId ) )
				end
			end
			return encodedAssociations
		end
		local result = {}
		if association.devices then
			table_append( result, _getEncodedAssociations( association.devices, "" ) )
		end
		if association.scenes then
			table_append( result, _getEncodedAssociations( association.scenes, "*" ) )
		end
		if association.ziGateDevices then
			table_append( result, _getEncodedAssociations( association.ziGateDevices, "%" ) )
		end
		return table.concat( result, "," )
	end,

	propagate = function( association, status, loadLevel, isLongPress )
		if ( association == nil ) then
			return
		end

		local status = status or ""
		local loadLevel = tonumber( loadLevel ) or -1
		local level = 1
		if isLongPress then
			level = 2
		end

		-- Associated devices
		if association.devices then
			for _, linkedDeviceId in ipairs( association.devices[ level ] ) do
				--debug( "Linked device #" .. tostring( linkedDeviceId ), "Association.propagate")
				if ( ( loadLevel > 0 ) and luup.device_supports_service( VARIABLE.DIMMER_LEVEL[1], linkedDeviceId ) ) then
					debug( "Dim associated device #" .. tostring( linkedDeviceId ) .. " to " .. tostring( loadLevel ) .. "%", "Association.propagate" )
					luup.call_action( VARIABLE.DIMMER_LEVEL[1], "SetLoadLevelTarget", { newLoadlevelTarget = loadLevel }, linkedDeviceId )
				elseif luup.device_supports_service( VARIABLE.SWITCH_POWER[1], linkedDeviceId ) then
					if ( ( status == "1" ) or ( loadLevel > 0 ) ) then
						debug( "Switch ON associated device #" .. tostring( linkedDeviceId ), "Association.propagate" )
						luup.call_action( VARIABLE.SWITCH_POWER[1], "SetTarget", { newTargetValue = "1" }, linkedDeviceId )
					else
						debug( "Switch OFF associated device #" .. tostring( linkedDeviceId ), "Association.propagate" )
						luup.call_action( VARIABLE.SWITCH_POWER[1], "SetTarget", { newTargetValue = "0" }, linkedDeviceId )
					end
				else
					error( "Associated device #" .. tostring( linkedDeviceId ) .. " does not support services Dimming or SwitchPower", "Association.propagate" )
				end
			end
		end

		-- Associated scenes (just if status is ON)
		if ( association.scenes and ( ( status == "1" ) or ( loadLevel > 0 ) ) ) then
			for _, linkedSceneId in ipairs( association.scenes[ level ] ) do
				debug( "Call associated scene #" .. tostring(linkedSceneId), "Association.propagate" )
				luup.call_action( "urn:micasaverde-com:serviceId:HomeAutomationGateway1", "RunScene", { SceneNum = linkedSceneId }, 0 )
			end
		end
	end
}


-- **************************************************
-- Discovered ZiGate devices
-- **************************************************

local _discoveredDevices = {}
local _indexDiscoveredDevicesById = {}

DiscoveredDevices = {

	add = function( address, endPoint, attrInfos, commandName, data, quality )
		local hasBeenAdded = false
		local id = address .. ";" .. endPoint
		local discoveredDevice = _indexDiscoveredDevicesById[ id ]
		if ( discoveredDevice == nil ) then
			discoveredDevice = {
				address = address,
				endPoint = endPoint,
				features = {}
			}
			table.insert( _discoveredDevices, discoveredDevice )
			_indexDiscoveredDevicesById[ id ] = discoveredDevice
			hasBeenAdded = true
			debug( "Discovered ZiGate device '" .. id .. "'", "DiscoveredDevices.add" )
		end
		discoveredDevice.quality = tonumber( quality )

		-- Feature
		if attrInfos.feature then
			local feature = discoveredDevice.features[ attrInfos.feature ]
			if ( feature == nil ) then
				feature = {
					deviceTypes = attrInfos.deviceTypes,
					settings = attrInfos.settings
				}
				discoveredDevice.features[ attrInfos.feature ] = feature
				hasBeenAdded = true
				debug( "Discovered ZiGate device '" .. id .. "' and new feature '" .. attrInfos.feature .. "'", "DiscoveredDevices.add" )
			end
			feature.data = ""
			if ( attrInfos.feature ~= commandName ) then
				feature.data = commandName
			end
			if ( data ~= nil ) then
				feature.data = feature.data .. " " .. tostring(data)
				if attrInfos.unit then
					feature.data = feature.data .. attrInfos.unit
				end
			end
		end

		discoveredDevice.lastUpdate = os.time()
		if hasBeenAdded then
			Variable.set( DEVICE_ID, VARIABLE.LAST_DISCOVERED, os.time() )
			UI.show( "New device discovered" )
		end
		return hasBeenAdded
	end,

	get = function( address, endPoint )
		if ( ( address ~= nil ) and ( endPoint ~= nil ) ) then
			local id = address .. ";" .. endPoint
			return _indexDiscoveredDevicesById[ id ]
		else
			return _discoveredDevices
		end
	end,

	remove = function( address, endPoint )
		if ( ( address ~= nil ) and ( endPoint ~= nil ) ) then
			local id = address .. ";" .. endPoint
			local discoveredDevice = _indexDiscoveredDevicesById[ id ]
			for i, device in ipairs( _discoveredDevices ) do
				if ( device == discoveredDevice ) then
					table.remove( _discoveredDevices, i )
					_indexDiscoveredDevicesById[ id ] = nil
					break
				end
			end
		end
	end
}


-- **************************************************
-- ZiGate Devices
-- **************************************************

local _ziGateDevices = {}   -- The list of all our child devices
local _indexZiGateDevicesById = {}
local _indexZiGateDevicesByDeviceId = {}
local _indexClustersByZiGateId = {}
local _indexFeaturesById = {}
local _deviceIdsById = {} -- TODO : ça sert où ?

ZiGateDevices = {

	-- Get a list with all our child devices.
	retrieve = function()
		local formerZiGateDevices = _ziGateDevices
		_ziGateDevices = {}
		_indexZiGateDevicesById = {}
		_indexZiGateDevicesByDeviceId = {}
		_indexFeaturesById = {}
		_deviceIdsById = {}
		for deviceId, device in pairs( luup.devices ) do
			if ( device.device_num_parent == DEVICE_ID ) then
				local address, endPoint, deviceNum = unpack( string_split( device.id or "", ";" ) )
				deviceNum = tonumber(deviceNum) or 1
				if ( ( address == nil ) or ( endPoint == nil ) ) then
					debug( "Found child device #".. tostring( deviceId ) .."(".. device.description .."), but id '" .. tostring( device.id ) .. "' does not match pattern '[0-9]+;[0-9]+;[0-9]+'", "ZiGateDevices.retrieve" )
				else
					local id = address .. ";" .. endPoint
					local ziGateDevice = _indexZiGateDevicesById[ id ]
					if ( ziGateDevice == nil ) then
						ziGateDevice = {
							address = address,
							endPoint = endPoint,
							quality = -1,
							features = {},
							maxDeviceNum = 0
						}
						table.insert( _ziGateDevices, ziGateDevice )
						_indexZiGateDevicesById[ id ] = ziGateDevice
						_indexFeaturesById[ id ] = {}
						_deviceIdsById[ id ] = {}
					end
					--
					if ( deviceNum > ziGateDevice.maxDeviceNum ) then
						ziGateDevice.maxDeviceNum = deviceNum
					end
					if ( ( deviceNum == 1 ) or not ziGateDevice.mainDeviceId ) then
						-- Main device
						ziGateDevice.mainDeviceId = deviceId
						ziGateDevice.mainRoomId = device.room_num
					end
					_deviceIdsById[ id ][ deviceNum ] = deviceId
					-- Settings
					local settings = {}
					for _, encodedSetting in ipairs( string_split( Variable.get( deviceId, VARIABLE.SETTING ) or "", "," ) ) do
						local settingName, value = string.match( encodedSetting, "([^=]*)=?(.*)" )
						if not string_isEmpty( settingName ) then
							if not string_isEmpty( value ) then
								settings[ settingName ] = tonumber(value) or value
							else
								settings[ settingName ] = true
							end
						end
					end
					-- Features
					local featureNames = string_split( Variable.get( deviceId, VARIABLE.FEATURE ) or "default", "," )
					for _, featureName in ipairs( featureNames ) do
						local feature = _indexFeaturesById[ id ][ featureName ]
						if ( feature ~= nil ) then
							-- TODO
							--[[
							warning(
								"Found device #".. tostring( deviceId ) .."(".. device.description ..")," ..
								" productId=" .. productId .. ", channelId=" .. channelId ..
								" but this channel is already defined for device #" .. tostring( ziGateDevice.channels[ channelId ].deviceId ) .. "(" .. luup.devices[ ziGateDevice.channels[ channelId ].deviceId ].description .. ")",
								"ZiGateDevices.retrieve"
							)
							--]]
						else
							local deviceTypeInfos = _getDeviceTypeInfos( device.device_type )
							feature = {
								name = featureName,
								deviceId = deviceId,
								deviceName = device.description,
								deviceType = device.device_type,
								deviceTypeName = deviceTypeInfos and deviceTypeInfos.name or "UNKOWN",
								roomId = device.room_num,
								settings = settings,
								association = Association.get( Variable.get( deviceId, VARIABLE.ASSOCIATION ) )
							}
							table.insert( ziGateDevice.features, feature )
							_indexFeaturesById[ id ][ featureName ] = feature
							-- Add to index
							if ( _indexZiGateDevicesByDeviceId[ tostring( deviceId ) ] == nil ) then
								_indexZiGateDevicesByDeviceId[ tostring( deviceId ) ] = { ziGateDevice, { feature } }
							else
								table.insert( _indexZiGateDevicesByDeviceId[ tostring( deviceId ) ][2], feature )
							end
							if ( featureName == "scene" ) then
								ziGateDevice.sceneControllerFeature = feature
							end
						end
						debug( "Found device #" .. tostring(deviceId) .. "(" .. feature.deviceName .. "), address 0x" .. address .. ", endPoint 0x" .. endPoint .. ", feature " .. featureName, "ZiGateDevices.retrieve" )
					end
				end
			end
		end
		-- Retrieve former states
		for _, formerZiGateDevice in ipairs( formerZiGateDevices ) do
			local id = formerZiGateDevice.address .. ";" .. formerZiGateDevice.endPoint
			local ziGateDevice = _indexZiGateDevicesById[ id ]
			if ( ziGateDevice ) then
				for _, formerFeature in ipairs( formerZiGateDevice.features ) do
					local feature = _indexFeaturesById[ id ][ formerFeature.name ]
					if ( feature ) then
						feature.state = formerFeature.state -- TODO : value ?
					end
				end
			elseif ( formerZiGateDevice.isNew ) then
				-- Add newly created ZiGate device (not present in luup.devices until a reload of the luup engine)
				table.insert( _ziGateDevices, formerZiGateDevice )
				_indexZiGateDevicesById[ id ] = formerZiGateDevice
				_indexFeaturesById[ id ] = {}
				_deviceIdsById[ id ] = {}
				for _, feature in ipairs( formerZiGateDevice.features ) do
					_indexFeaturesById[ id ][ feature.name ] = feature 
				end
			end
		end
		formerZiGateDevices = nil
		--debug( json.encode(_ziGateDevices), "ZiGateDevices.retrieve" )
	end,

	-- Add a new device (should really be added after a reload)
	add = function( address, endPoint, deviceTypeInfos, featureNames, deviceId, deviceName )
		local id = tostring(address) .. ";" .. tostring(endPoint)
		debug( "Add ZiGate device '" .. id .. "', features " .. json.encode( featureNames or "" ) .. ", deviceId #" .. tostring(deviceId) .."(".. tostring(deviceName) ..")", "ZiGateDevices.add" )
		local newZiGateDevice = _indexZiGateDevicesById[ id ]
		if ( newZiGateDevice == nil ) then
			newZiGateDevice = {
				isNew = true,
				address = address,
				endPoint = endPoint,
				quality = -1,
				features = {}
			}
			table.insert( _ziGateDevices, newZiGateDevice )
			_indexZiGateDevicesById[ id ] = newZiGateDevice
			_indexFeaturesById[ id ] = {}
		end
		for _, featureName in ipairs( featureNames ) do
			local feature = {
				name = featureName,
				deviceId = deviceId,
				deviceName = deviceName,
				deviceType = deviceTypeInfos.type,
				deviceTypeName = deviceTypeInfos.name or "UNKOWN",
				association = Association.get( "" )
			}
			table.insert( newZiGateDevice.features, feature )
			_indexFeaturesById[ id ][ featureName ] = feature
		end
	end,

	getFromClusterId = function( id, clusterId )
		if ( id ~= nil ) then
			local ziGateDevice = _indexZiGateDevicesById[ id ]
			if ( ziGateDevice ~= nil ) then
				if ( clusterId ~= nil ) then
					local feature = _indexClustersByZiGateId[ id ][ clusterId ]
					if ( feature ~= nil ) then
						return ziGateDevice, feature
					end
				end
				return ziGateDevice, nil
			end
			return nil
		else
			return _ziGateDevices
		end
	end,

	getFromFeatureName = function( address, endPoint, featureName )
		if ( ( address ~= nil ) and ( endPoint ~= nil ) ) then
			local id = tostring(address) .. ";" .. tostring(endPoint)
			local ziGateDevice = _indexZiGateDevicesById[ id ]
			if ( ziGateDevice ~= nil ) then
				if ( featureName ~= nil ) then
					local feature = _indexFeaturesById[ id ][ featureName ]
					if ( feature ~= nil ) then
						return ziGateDevice, feature
					end
				end
				return ziGateDevice, nil
			end
			return nil
		else
			return _ziGateDevices
		end
	end,

	get = function( address, endPoint, clusterId )
		if ( ( address ~= nil ) and ( endPoint ~= nil ) ) then
			local id = tostring(address) .. ";" .. tostring(endPoint)
			return ZiGateDevices.getFromClusterId( id, clusterId )
		else
			return _ziGateDevices
		end
	end,

	getFromDeviceId = function( deviceId )
		local index = _indexZiGateDevicesByDeviceId[ tostring( deviceId ) ]
		if index then
			return index[1], index[2][1]
		else
			warning( "ZiGate device with deviceId #" .. tostring( deviceId ) .. "' is unknown", "ZiGateDevices.getFromDeviceId" )
		end
		return nil
	end,

	log = function()
		local nbZiGateDevices = 0
		local nbDevicesByFeature = {}
		for _, ziGateDevice in pairs( _ziGateDevices ) do
			nbZiGateDevices = nbZiGateDevices + 1
			for _, feature in ipairs( ziGateDevice.features ) do
				if (nbDevicesByFeature[feature.name] == nil) then
					nbDevicesByFeature[feature.name] = 1
				else
					nbDevicesByFeature[feature.name] = nbDevicesByFeature[feature.name] + 1
				end
			end
		end
		log("* ZiGate devices: " .. tostring(nbZiGateDevices), "ZiGateDevices.log")
		for featureName, nbDevices in pairs(nbDevicesByFeature) do
			log("*" .. string_lpad(featureName, 20) .. ": " .. tostring(nbDevices), "ZiGateDevices.log")
		end
	end
}


-- **************************************************
-- Serial connection
-- **************************************************

SerialConnection = {
	-- Check IO connection
	check = function()
		if not luup.io.is_connected( DEVICE_ID ) then
			-- Try to connect by ip (openLuup)
			local ip = luup.attr_get( "ip", DEVICE_ID )
			if ( ( ip ~= nil ) and ( ip ~= "" ) ) then
				local ipaddr, port = string.match( ip, "(.-):(.*)" )
				if ( port == nil ) then
					ipaddr = ip
					port = 80
				end
				log( "Open connection on ip " .. ipaddr .. " and port " .. port, "SerialConnection.check" )
				luup.io.open( DEVICE_ID, ipaddr, tonumber( port ) )
			end
		end
		if not luup.io.is_connected( DEVICE_ID ) then
			error( "Serial port not connected. First choose the serial port and restart the lua engine.", "SerialConnection.check", false )
			UI.showError( "Choose the Serial Port" )
			return false
		else
			local ioDevice = tonumber(( Variable.get( DEVICE_ID, VARIABLE.IO_DEVICE ) ))
			if ioDevice then
				-- Check serial settings
				local baudRate = Variable.get( ioDevice, VARIABLE.BAUD ) or "115200"
				if ( baudRate ~= _SERIAL.baudRate ) then
					error( "Incorrect setup of the serial port. Select " .. _SERIAL.baudRate .. " bauds.", "SerialConnection.check", false )
					UI.showError( "Select " .. _SERIAL.baudRate .. " bauds for the Serial Port" )
					return false
				end
				log( "Baud rate is " .. _SERIAL.baudRate, "SerialConnection.check" )

				-- TODO : Check Parity none / Data bits 8 / Stop bit 1
			end
		end
		log( "Serial port is connected", "SerialConnection.check" )
		return true
	end
}


-- **************************************************
-- HTTP request handler
-- **************************************************

local _handlerCommands = {
	["default"] = function( params, outputFormat )
		return "Unknown command '" .. tostring( params["command"] ) .. "'", "text/plain"
	end,

	["getDevicesInfos"] = function( params, outputFormat )
		log( "Get device list", "handleCommand.getDevicesInfos" )
		result = { devices = ZiGateDevices.get(), discoveredDevices = DiscoveredDevices.get() }
		return tostring( json.encode( result ) ), "application/json"
	end,

	["getDeviceParams"] = function( params, outputFormat )
		log( "Get device params", "handleCommand.getDeviceParams" )
		result = {}
		return tostring( json.encode( result ) ), "application/json"
	end,

	["getErrors"] = function( params, outputFormat )
		return tostring( json.encode( g_errors ) ), "application/json"
	end
}
setmetatable(_handlerCommands,{
	__index = function(t, command, outputFormat)
		log( "No handler for command '" ..  tostring(command) .. "'", "handlerZiGateGateway" )
		return _handlerCommands["default"]
	end
})

local function _handleCommand( lul_request, lul_parameters, lul_outputformat )
	local command = lul_parameters["command"] or "default"
	log( "Get handler for command '" .. tostring(command) .."'", "handleCommand" )
	return _handlerCommands[command]( lul_parameters, lul_outputformat )
end


-- **************************************************
-- Action implementations for childs
-- **************************************************

Child = {

	setTarget = function( childDeviceId, newTargetValue )
		local ziGateDevice, feature = ZiGateDevices.getFromDeviceId( childDeviceId )
		if (ziGateDevice == nil) then
			error( "Device #" .. tostring( childDeviceId ) .. " is not an ZiGate device", "Child.setTarget" )
			return JOB_STATUS.ERROR
		end
		DeviceHelper.setStatus( ziGateDevice, feature, newTargetValue )
		return JOB_STATUS.DONE
	end,

	setLoadLevelTarget = function( childDeviceId, newLoadlevelTarget )
		local ziGateDevice, feature = ZiGateDevices.getFromDeviceId( childDeviceId )
		if ( ziGateDevice == nil ) then
			error( "Device #" .. tostring( childDeviceId ) .. " is not an ZiGate device", "Child.setLoadLevelTarget" )
			return JOB_STATUS.ERROR
		end
		DeviceHelper.setLoadLevel( ziGateDevice, feature, newLoadlevelTarget )
		return JOB_STATUS.DONE
	end,

	setArmed = function( childDeviceId, newArmedValue )
		local ziGateDevice, feature = ZiGateDevices.getFromDeviceId( childDeviceId )
		if ( ziGateDevice == nil ) then
			error( "Device #" .. tostring( childDeviceId ) .. " is not an ZiGate device", "Child.setArmed" )
			return JOB_STATUS.ERROR
		end
		DeviceHelper.setArmed( ziGateDevice, feature, newArmedValue or "0" )
		return JOB_STATUS.DONE
	end,

	moveShutter = function( childDeviceId, direction )
		local ziGateDevice, feature = ZiGateDevices.getFromDeviceId( childDeviceId )
		if ( ziGateDevice == nil ) then
			error( "Device #" .. tostring( childDeviceId ) .. " is not an ZiGate device", "Child.moveShutter" )
			return JOB_STATUS.ERROR
		end
		DeviceHelper.moveShutter( ziGateDevice, feature, direction )
		return JOB_STATUS.DONE
	end,

	setModeStatus = function( childDeviceId, newModeStatus, option )
		debug( "test", "Child.setModeStatus" )
		local ziGateDevice, feature = ZiGateDevices.getFromDeviceId( childDeviceId )
		if (ziGateDevice == nil) then
			error( "Device #" .. tostring( childDeviceId ) .. " is not an ZiGate device", "Child.setModeStatus" )
			return JOB_STATUS.ERROR
		end
		DeviceHelper.setModeStatus( ziGateDevice, feature, newModeStatus, option )
		return JOB_STATUS.DONE
	end,

	setSetPoint = function( childDeviceId, newSetpoint, option )
		local ziGateDevice, feature = ZiGateDevices.getFromDeviceId( childDeviceId )
		if (ziGateDevice == nil) then
			error( "Device #" .. tostring( childDeviceId ) .. " is not an ZiGate device", "Child.setCurrentSetPoint" )
			return JOB_STATUS.ERROR
		end
		DeviceHelper.setSetPoint( ziGateDevice, feature, newSetpoint, option )
		return JOB_STATUS.DONE
	end,

	untripAuto = function( childDeviceId )
		local ziGateDevice, feature = ZiGateDevices.getFromDeviceId( childDeviceId )
		local timeout = feature.settings.timeout or 0
		if ( ( timeout > 0 ) and ( Variable.get( childDeviceId, VARIABLE.TRIPPED ) == "1" ) ) then 
			local elapsedTime = os.difftime( os.time(), Variable.getTimestamp( childDeviceId, VARIABLE.TRIPPED ) or 0 )
			if ( elapsedTime >= timeout ) then
				DeviceHelper.setTripped( ziGateDevice, feature, "0" )
			end
		end
	end

}


-- **************************************************
-- Main action implementations
-- **************************************************

function refresh()
	debug( "Refresh ZiGate devices", "refresh" )
	ZiGateDevices.retrieve()
	ZiGateDevices.log()
	return JOB_STATUS.DONE
end

local function _createDevice( address, endPoint, deviceNum, deviceName, deviceTypeInfos, roomId, parameters, featureNames )
	local id = address .. ";" .. endPoint
	local internalId = id .. ";" .. tostring(deviceNum)
	if ( not deviceTypeInfos or not deviceTypeInfos.file ) then
		error( "Device infos are missing for ZiGate device '" .. id .. "'", "createDevice" )
		return
	end
	debug( "Add ZiGate productId '" .. internalId .. "', deviceFile '" .. deviceTypeInfos.file .. "'", "createDevice" )
	local newDeviceId = luup.create_device(
		'', -- device_type
		internalId,
		deviceName,
		deviceTypeInfos.file,
		'', -- upnp_impl
		'', -- ip
		'', -- mac
		false, -- hidden
		false, -- invisible
		DEVICE_ID, -- parent
		roomId,
		0, -- pluginnum
		parameters,
		0, -- pnpid
		'', -- nochildsync
		'', -- aeskey
		false, -- reload
		false -- nodupid
	)

	ZiGateDevices.add( address, endPoint, deviceTypeInfos, featureNames, newDeviceId, deviceName )

	return newDeviceId
end

function createDevices( encodedItems )
	local hasBeenCreated = false
	local roomId = luup.devices[ DEVICE_ID ].room_num or 0

	local items = json.decode( string_decodeURI( encodedItems ) )
	debug( "Create devices " .. json.encode(items), "createDevices" )
	for _, item in ipairs( items ) do
		local id = item.address .. ";" .. item.endPoint
		local msg = "ZiGate device '" .. id .. "'"
		for i, feature in ipairs( item.features ) do
			-- TODO : manage several feature names
			local ziGateDevice, formerFeature = ZiGateDevices.getFromFeatureName( item.address, item.endPoint, feature.names[1] )
			if ( ziGateDevice and formerFeature ) then
				-- The ZiGate device is already known for this feature
				warning( msg .. ", feature " .. feature.names[1] .. " already exists", "createDevices" )
			else
				local deviceTypeInfos = _getDeviceTypeInfos( feature.deviceType )
				if deviceTypeInfos then
					local parameters = _getEncodedParameters( deviceTypeInfos )
					parameters = parameters .. VARIABLE.FEATURE[1] .. "," .. VARIABLE.FEATURE[2] .. "=" .. table.concat( feature.names, "," ) .. "\n"
					parameters = parameters .. VARIABLE.ASSOCIATION[1] .. "," .. VARIABLE.ASSOCIATION[2] .. "=\n"
					parameters = parameters .. VARIABLE.SETTING[1] .. "," .. VARIABLE.SETTING[2] .. "=" .. ( feature.settings or "" ) .. "\n"

					deviceName = item.address .. " " .. item.endPoint .. " " .. feature.names[1]
					local newDeviceId = _createDevice( item.address, item.endPoint, i, deviceName, deviceTypeInfos, roomId, parameters, feature.names )

					debug( msg .. ", device #" .. tostring(newDeviceId) .. "(" .. deviceName .. ") has been created", "createDevices" )
					hasBeenCreated = true
				else
					error( msg .. ", feature " .. featureName .. ", device type " .. tostring(feature.deviceType) .. " is unknown", "createDevices" )
				end
			
			end
		end

		DiscoveredDevices.remove( item.address, item.endPoint )
	end

	if hasBeenCreated then
		ZiGateDevices.retrieve()
		ZiGateDevices.log()
		Variable.set( DEVICE_ID, VARIABLE.LAST_UPDATE, os.time() )
	end

	return JOB_STATUS.DONE
end

-- Associate a feature to devices on the Vera
function associate( address, endPoint, featureName, strAssociation )
	local ziGateDevice, feature = ZiGateDevices.getFromFeatureName( address, endPoint, featureName )
	if ( ( ziGateDevice == nil ) or ( feature == nil ) ) then
		return JOB_STATUS.ERROR
	end
	debug("Associate ZiGate device '" .. tostring( ziGateDevice.id ) .. "' and feature #" .. feature.name .. " with " .. tostring( strAssociation ), "associate" )
	feature.association = Association.get( strAssociation )
	Variable.set( feature.deviceId, VARIABLE.ASSOCIATION, Association.getEncoded( feature.association ) )
	return JOB_STATUS.DONE
end

-- Start inclusion (permit joining) during 30 secondes
function startInclusion()
	debug("Permit joining during 30 secondes", "startInclusion")
	Network.send( "0049", "FFFC1E"); -- FFFC = mask, 1E = 30 secondes
	return JOB_STATUS.DONE
end

-- DEBUG METHOD
function sendMessage( msgType, data )
	debug( "Send message - type:" .. tostring(msgType) .. ", data:" .. tostring(data), "sendMessage" )
	Network.send( msgType, data )
	return JOB_STATUS.DONE
end


-- **************************************************
-- Startup
-- **************************************************

-- Init plugin instance
local function _initPluginInstance()
	log( "Init", "initPluginInstance" )

	-- Update the Debug Mode
	debugMode = ( Variable.getOrInit( DEVICE_ID, VARIABLE.DEBUG_MODE, "0" ) == "1" ) and true or false
	if debugMode then
		log( "DebugMode is enabled", "init" )
		debug = log
	else
		log( "DebugMode is disabled", "init" )
		debug = function() end
	end

	Variable.set( DEVICE_ID, VARIABLE.PLUGIN_VERSION, _VERSION )
	Variable.set( DEVICE_ID, VARIABLE.LAST_UPDATE, os.time() )
	Variable.set( DEVICE_ID, VARIABLE.LAST_MESSAGE, "" )
	Variable.getOrInit( DEVICE_ID, VARIABLE.LAST_DISCOVERED, "" )
end

-- Register with ALTUI once it is ready
local function _registerWithALTUI()
	for deviceId, device in pairs( luup.devices ) do
		if ( device.device_type == "urn:schemas-upnp-org:device:altui:1" ) then
			if luup.is_ready( deviceId ) then
				log( "Register with ALTUI main device #" .. tostring( deviceId ), "registerWithALTUI" )
				luup.call_action(
					"urn:upnp-org:serviceId:altui1",
					"RegisterPlugin",
					{
						newDeviceType = "urn:schemas-upnp-org:device:ZiGateGateway:1",
						newScriptFile = "J_ZiGateGateway1.js",
						newDeviceDrawFunc = "ZiGateGateway.ALTUI_drawDevice"
					},
					deviceId
				)
			else
				log( "ALTUI main device #" .. tostring( deviceId ) .. " is not yet ready, retry to register in 10 seconds...", "registerWithALTUI" )
				luup.call_delay( "ZiGateGateway.registerWithALTUI", 10 )
			end
			break
		end
	end
end

function init( lul_device )
	log( "Start plugin '" .. _NAME .. "' (v" .. _VERSION .. ")", "startup" )

	-- Get the master device
	DEVICE_ID = lul_device

	-- Init
	_initPluginInstance()

	if ( type( json ) == "string" ) then
		UI.showError( "No JSON decoder" )
	elseif SerialConnection.check() then
		-- Get the list of the child devices
		ZiGateDevices.retrieve()
		ZiGateDevices.log()

		-- Get ZiGate version
		Network.send( "0010", "" )
		-- Start network
		Network.send( "0024", "" )
	end

	-- Watch setting changes
	Variable.watch( DEVICE_ID, VARIABLE.DEBUG_MODE, "ZiGateGateway.initPluginInstance" )

	-- HTTP Handlers
	log( "Register handler ZiGateGateway", "init" )
	luup.register_handler( "ZiGateGateway.handleCommand", "ZiGateGateway" )

	-- Register with ALTUI
	luup.call_delay( "ZiGateGateway.registerWithALTUI", 10 )

	if ( luup.version_major >= 7 ) then
		luup.set_failure( 0, DEVICE_ID )
	end

	log( "Startup successful", "init" )
	return true, "Startup successful", _NAME
end


-- Promote the functions used by Vera's luup.xxx functions to the global name space
_G["ZiGateGateway.handleCommand"] = _handleCommand
_G["ZiGateGateway.Command.deferredProcess"] = Command.deferredProcess
_G["ZiGateGateway.Child.untripAuto"] = Child.untripAuto
_G["ZiGateGateway.Network.send"] = Network.send

_G["ZiGateGateway.initPluginInstance"] = _initPluginInstance
_G["ZiGateGateway.registerWithALTUI"] = _registerWithALTUI
