--[[
  This file is part of the plugin ZiGate Gateway.
  https://github.com/vosmont/Vera-Plugin-ZiGateGateway
  Copyright (c) 2018 Vincent OSMONT
  This code is released under the MIT License, see LICENSE.

  Device : device on the Vera / openLuup
  Equipment : device handled by the ZiGate dongle
--]]

module( "L_ZiGateGateway1", package.seeall )

-- https://community.smartthings.com/t/release-xiaomi-mi-cube-magic-controller/70669/73

-- Load libraries
local hasJson, json = pcall( require, "dkjson" )
local hasBit, bit = pcall( require , "bit" )

-- **************************************************
-- Plugin constants
-- **************************************************

_NAME = "ZiGateGateway"
_DESCRIPTION = "ZiGate gateway for the Vera"
_VERSION = "1.2"
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

local _errors = {}
local function error( msg, methodName, notifyOnUI )
	table.insert( _errors, { os.time(), methodName or "", tostring( msg ) } )
	if ( #_errors > 100 ) then
		table.remove( _errors, 1 )
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
-- 4) variable that is used for the timestamp, for active value
-- 5) variable that is used for the timestamp, for inactive value
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
	RAIN_TOTAL = { "urn:upnp-org:serviceId:RainSensor1", "CurrentTRain", true },
	RAIN = { "urn:upnp-org:serviceId:RainSensor1", "CurrentRain", true },
	UV_LEVEL = { "urn:micasaverde-com:serviceId:UvSensor1", "CurrentLevel", true },
	-- Switches
	SWITCH_POWER = { "urn:upnp-org:serviceId:SwitchPower1", "Status", true },
	DIMMER_LEVEL = { "urn:upnp-org:serviceId:Dimming1", "LoadLevelStatus", true },
	DIMMER_LEVEL_TARGET = { "urn:upnp-org:serviceId:Dimming1", "LoadLevelTarget", true },
	DIMMER_LEVEL_OLD = { "urn:upnp-org:serviceId:ZiGateDevice1", "LoadLevelStatus", true },
	DIMMER_DIRECTION = { "urn:upnp-org:serviceId:ZiGateDevice1", "LoadLevelDirection", true },
	DIMMER_STEP = { "urn:upnp-org:serviceId:ZiGateDevice1", "DimmingStep", true },
	-- Scene controller
	LAST_SCENE_ID = { "urn:micasaverde-com:serviceId:SceneController1", "LastSceneID", true, "LAST_SCENE_DATE" },
	LAST_SCENE_DATE = { "urn:micasaverde-com:serviceId:SceneController1", "LastSceneTime", true },
	-- Security
	ARMED = { "urn:micasaverde-com:serviceId:SecuritySensor1", "Armed", true },
	TRIPPED = { "urn:micasaverde-com:serviceId:SecuritySensor1", "Tripped", true, "LAST_TRIP", "LAST_UNTRIP" },
	ARMED_TRIPPED = { "urn:micasaverde-com:serviceId:SecuritySensor1", "ArmedTripped", true, "LAST_TRIP" },
	LAST_TRIP = { "urn:micasaverde-com:serviceId:SecuritySensor1", "LastTrip", true },
	LAST_UNTRIP = { "urn:micasaverde-com:serviceId:SecuritySensor1", "LastTrip", true },
	TAMPER_ALARM = { "urn:micasaverde-com:serviceId:HaDevice1", "sl_TamperAlarm", false, "LAST_TAMPER" },
	LAST_TAMPER = { "urn:micasaverde-com:serviceId:SecuritySensor1", "LastTamper", true },
	-- HA Device
	DEVICE_CONFIGURED = { "urn:micasaverde-com:serviceId:HaDevice1", "Configured", true },
	DEVICE_LAST_UPDATE = { "urn:micasaverde-com:serviceId:HaDevice1", "LastUpdate", true },
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
	-- Equipment
	ADDRESS = { "urn:upnp-org:serviceId:ZiGateDevice1", "Address", true },
	ENDPOINT = { "urn:upnp-org:serviceId:ZiGateDevice1", "Endpoint", true },
	FEATURE = { "urn:upnp-org:serviceId:ZiGateDevice1", "Feature", true },
	ASSOCIATION = { "urn:upnp-org:serviceId:ZiGateDevice1", "Association", true },
	SETTING = { "urn:upnp-org:serviceId:ZiGateDevice1", "Setting", true },
	FACE = { "urn:upnp-org:serviceId:ZiGateDevice1", "Face", true },
	CAPABILITIES = { "urn:upnp-org:serviceId:ZiGateDevice1", "Capabilities", true },
	LAST_INFO = { "urn:upnp-org:serviceId:ZiGateDevice1", "LastInfo", true },
	NEXT_SCHEDULE = { "urn:upnp-org:serviceId:ZiGateDevice1", "NextSchedule", true }
}

-- Device types
local DEVICE = {
	SERIAL_PORT = {
		type = "urn:micasaverde-org:device:SerialPort:1", file = "D_SerialPort1.xml"
	},
	SECURITY_SENSOR = {
		type = "urn:schemas-micasaverde-com:device:SecuritySensor:1"
	},
	DOOR_SENSOR = {
		type = "urn:schemas-micasaverde-com:device:DoorSensor:1", file = "D_DoorSensor1.xml",
		category = 4, subCategory = 1,
		parameters = { { "ARMED", "0" }, { "TRIPPED", "0" }, { "TAMPER_ALARM", "0" } }
	},
	MOTION_SENSOR = {
		type = "urn:schemas-micasaverde-com:device:MotionSensor:1", file = "D_MotionSensor1.xml",
		category = 4, subCategory = 3,
		--jsonFile = "D_MotionSensorWithTamper1.json",
		parameters = { { "ARMED", "0" }, { "TRIPPED", "0" }, { "TAMPER_ALARM", "0" } }
	},
	SMOKE_SENSOR = {
		type = "urn:schemas-micasaverde-com:device:SmokeSensor:1", file = "D_SmokeSensor1.xml",
		category = 4, subCategory = 4,
		parameters = { { "ARMED", "0" }, { "TRIPPED", "0" }, { "TAMPER_ALARM", "0" } }
	},
	WIND_SENSOR = {
		type = "urn:schemas-micasaverde-com:device:WindSensor:1", file = "D_WindSensor1.xml",
		parameters = { { "WIND_DIRECTION", "0" }, { "WIND_GUST_SPEED", "0" }, { "WIND_AVERAGE_SPEED", "0" } }
	},
	BAROMETER_SENSOR = {
		type = "urn:schemas-micasaverde-com:device:BarometerSensor:1", file = "D_BarometerSensor1.xml",
		parameters = { { "PRESSURE", "0" }, { "FORECAST", "" } }
	},
	UV_SENSOR = {
		type = "urn:schemas-micasaverde-com:device:UvSensor:1", file = "D_UvSensor.xml",
		parameters = { { "UV_LEVEL", "0" } }
	},
	RAIN_METER = {
		type = "urn:schemas-micasaverde-com:device:RainSensor:1", file = "D_RainSensor1.xml",
		parameters = { { "RAIN", "0" }, { "RAIN_TOTAL", "0" } }
	},
	BINARY_LIGHT = {
		type = "urn:schemas-upnp-org:device:BinaryLight:1", file = "D_BinaryLight1.xml",
		parameters = { { "SWITCH_POWER", "0" } }
	},
	DIMMABLE_LIGHT = {
		type = "urn:schemas-upnp-org:device:DimmableLight:1", file = "D_DimmableLight1.xml",
		parameters = { { "SWITCH_POWER", "0" }, { "DIMMER_LEVEL", "0" } }
	},
	RGB_LIGHT = { -- TODO
		type = "urn:schemas-upnp-org:device:DimmableLight:1", file = "D_DimmableLight1.xml",
		parameters = { { "SWITCH_POWER", "0" }, { "DIMMER_LEVEL", "0" } }
	},
	TEMPERATURE_SENSOR = {
		type = "urn:schemas-micasaverde-com:device:TemperatureSensor:1", file = "D_TemperatureSensor1.xml",
		parameters = { { "TEMPERATURE", "0" } }
	},
	HUMIDITY_SENSOR = {
		type = "urn:schemas-micasaverde-com:device:HumiditySensor:1", file = "D_HumiditySensor1.xml",
		parameters = { { "HUMIDITY", "0" } }
	},
	LIGHT_SENSOR = {
		type = "urn:schemas-micasaverde-com:device:LightSensor:1", file = "D_LightSensor1.xml",
		parameters = { { "LIGHT_LEVEL", "0" } }
	},
	SCENE_CONTROLLER = {
		type = "urn:schemas-micasaverde-com:device:SceneController:1", file = "D_SceneController1.xml",
		parameters = { { "LAST_SCENE_ID", "" } }
	}
}

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
-- ZigBee equipments
-- **************************************************

-- Capabilities by cluster and attribute
local CAPABILITIES = {
	[ "0000" ] = {
		name = "Basic",
		category = "General",
		attributes = {
			[ "0001" ] = {
				name = "Application version",
				getCommands = function( value )
					debug( "(application version:" .. tostring(value) .. ")", "Network.receive" )
				end
			},
			[ "0005" ] = { -- Model info Xiaomi
				name = "Model info",
				getCommands = function( value )
					return { { name = "modelinfo", data = value } }
				end
			},
			[ "FF01" ] = {
				name = "Battery", -- Only Xiaomi ?
				getCommands = function( value )
				-- little endian
					local batteryLevel = ( bit.lshift( value:byte( 4 ), 8 ) + value:byte( 3 ) ) / 1000
					--  3.3V is 100%, 2.6V is 0%
					-- CR2032 (3V) :
					-- 2.95V : the battery should be replaced; 2.8V : the battery is almost dead
					--debug( tostring(batteryLevel), "batteryLevel" )
					if ( batteryLevel > 2.95 ) then
						batteryLevel = 100
					elseif ( batteryLevel > 2.8 ) then
						batteryLevel = 30
					else
						batteryLevel = 10
					end
					return { { name = "battery", data = batteryLevel, unit = "%" } }
				end
			}
		}
	},
	[ "0001" ] = {
		name = "Basic",
		category = "General",
		attributes = {
			[ "0020" ] = {
				name = "Battery",
				getCommands = function( value )
					local batteryLevel = ( bit.lshift( value:byte( 4 ), 8 ) + value:byte( 3 ) ) / 1000
					--  3.3V is 100%, 2.6V is 0%
					-- CR2032 (3V) :
					-- 2.95V : the battery should be replaced; 2.8V : the battery is almost dead
					--debug( tostring(batteryLevel), "batteryLevel" )
					if ( batteryLevel > 2.95 ) then
						batteryLevel = 100
					elseif ( batteryLevel > 2.8 ) then
						batteryLevel = 30
					else
						batteryLevel = 10
					end
					return { { name = "battery", data = batteryLevel, unit = "%" } }
				end
			}
		}
	},
	[ "0006" ] = {
		name = "On/Off",
		category = "General",
		attributes = {
			[ "0000" ] = {
				modelings = {
					{
						mappings = {
							{ features = { "state" }, deviceTypes = { "BINARY_LIGHT", "DIMMABLE_LIGHT", "DOOR_SENSOR" }, settings = { "transmitter" } }
						}
					}
				},
				getCommands = function( value )
					local cmds = {}
					if ( value ) then
						table.insert( cmds, { name = "state", data = "on" } )
						table.insert( cmds, { name = "scene", data = 1, info = "number of click: 1", broadcast = true } )
					else
						table.insert( cmds, { name = "state", data = "off" } )
					end
					return cmds
				end
			},
			[ "8000" ] = {
				name = "Scene controller",
				modelings = {
					{
						mappings = {
							{ features = { "scene" }, deviceTypes = { "SCENE_CONTROLLER" }, settings = { "transmitter" } }
						}
					}
				},
				getCommands = function( value )
					return { { name = "scene", data = value, info = "number of click: " .. tostring(value) } }
				end
			}
		}
	},
	[ "000C" ] = {
		name = "Magic cube",
		category = "General",
		attributes = {
			[ "0055" ] = {
				name = "Dimmer",
				modelings = {
					{
						mappings = {
							{ features = { "dim", "face" }, deviceTypes = { "DIMMABLE_LIGHT" }, settings = { "transmitter", "dimmingStep=10" } }
						}
					}
				},
				getCommands = function( value )
					local cmds = {}
	debug(tostring(value), "test" )
					if ( tonumber( value ) >= 0 ) then
						table.insert( cmds, { name = "dim", data = "+" } )
						table.insert( cmds, { name = "scene", data = 6, info = "rotate_right", broadcast = true } )
					else
						table.insert( cmds, { name = "dim", data = "-" } )
						table.insert( cmds, { name = "scene", data = 7, info = "rotate_left", broadcast = true } )
					end
					return cmds
				end
			},
			[ "FF05" ] = {
				name = "Scene controller",
				modelings = {
					{
						mappings = {
							{ features = { "scene" }, deviceTypes = { "SCENE_CONTROLLER" }, settings = { "transmitter" } }
						}
					}
				},
				getCommands = function( value )
					if ( value == 0x01F4 ) then
						return { { name = "not_implemented" } }
					end
					return {}
				end
			}
		}
	},
	[ "0012" ] = {
		name = "Magic cube",
		category = "General",
		attributes = {
			[ "03-0055" ] = {
				name = "Dimmer",
				modelings = {
					{
						mappings = {
							{ features = { "dim" }, deviceTypes = { "DIMMABLE_LIGHT" }, settings = { "transmitter", "dimmingStep=10" } }
						}
					}
				},
				getCommands = function( value )
					return {
						{ name = "dim", data = value },
						{ name = "scene", data = 6, info = "rotate_left" } -- TODO
					}
				end
			},
			[ "0055" ] = {
				name = "Scene controller",
				modelings = {
					{
						mappings = {
							--{ features = { "scene", "face" }, deviceTypes = { "SCENE_CONTROLLER" }, settings = { "transmitter" } }
							{ features = { "scene" }, deviceTypes = { "SCENE_CONTROLLER" }, settings = { "transmitter" } }
						}
					}
				},
				getCommands = function( value )
					-- https://github.com/ClassicGOD/SmartThingsPublic/tree/master/devicetypes/classicgod/xiaomi-magic-cube-controller.src
					-- Motion
					debug( "value: " .. tostring(value), "Motion" )
					local motionType = bit.rshift( bit.band( value, 0xC0 ), 6 ) -- 11000000
					debug( "motionType: " .. tostring(motionType), "Motion" )
					local sourceFace = bit.rshift( bit.band( value, 0x38 ), 3 ) -- 00111000
					debug( "sourceFace : " .. tostring(sourceFace), "Motion" )
					local targetFace = bit.band( value, 0x07 ) -- 00000111
					debug( "targetFace : " .. tostring(targetFace), "Motion" )
					local cmds = {}
					table.insert( cmds, { name = "face", data = targetFace, broadcast = true } )
					if ( motionType == 0 ) then
						local value = bit.rshift( bit.band( value, 0x30 ), 4 ) -- 00110000
						debug( "value : " .. tostring(value), "Motion" )
					elseif ( motionType == 1 ) then
						-- Flip 90
						table.insert( cmds, { name = "scene", data = 2, info = "flip_90" } )
					elseif ( motionType == 2 ) then
						-- Flip 180
						table.insert( cmds, { name = "scene", data = 3, info = "flip_180" } )
					end
					
					if ( value == 0x0000 ) then
						table.insert( cmds, { name = "scene", data = 1, info = "shake" } )
					elseif ( value == 0x0103 ) then
						table.insert( cmds, { name = "scene", data = 4, info = "slide" } )
					elseif ( value == 0x0201 ) then
						table.insert( cmds, { name = "scene", data = 2, info = "tap_twice" } )
					elseif ( value == 0x0204 ) then
						table.insert( cmds, { name = "scene", data = 3, info = "tap" } )
					end
					return cmds
				end
			}
		}
	},
	[ "0400" ] = {
		name = "Illuminance",
		category = "Measurement",
		attributes = {
			[ "0000" ] = {
				modelings = {
					{
						mappings = {
							{ features = { "illuminance" }, deviceTypes = { "LIGHT_SENSOR" }, settings = { "transmitter" } }
						}
					}
				},
				getCommands = function( value )
					return { { name = "illuminance", data = value, unit = "lux" } }
				end
			}
		}
	},
	[ "0402" ] = {
		name = "Temperature",
		category = "Measurement",
		attributes = {
			[ "0000" ] = {
				modelings = {
					{
						mappings = {
							{ features = { "temperature" }, deviceTypes = { "TEMPERATURE_SENSOR" }, settings = { "transmitter" } }
						}
					}
				},
				getCommands = function( value )
					return { { name = "temperature", data = ( value / 100 ), unit = "°C" } }
				end
			}
		}
	},
	[ "0403" ] = {
		name = "Atmospheric pressure",
		category = "Measurement",
		attributes = {
			[ "0000" ] = {
				modelings = {
					{
						mappings = {
							{ features = { "pressure" }, deviceTypes = { "BAROMETER_SENSOR" }, settings = { "transmitter" } }
						}
					}
				},
				getCommands = function( value )
					return { { name = "pressure", data = value, unit = "hPa" } }
				end
			}
		}
	},
	[ "0405" ] = {
		name = "Humidity",
		category = "Measurement",
		attributes = {
			[ "0000" ] = {
				modelings = {
					{
						mappings = {
							{ features = { "humidity" }, deviceTypes = { "HUMIDITY_SENSOR" }, settings = { "transmitter" } }
						}
					}
				},
				getCommands = function( value )
					return { { name = "humidity", data = ( tonumber(value) / 100 ), unit = "%" } }
				end
			}
		}
	},
	[ "0406" ] = {
		name = "Occupancy Sensing",
		category = "Measurement",
		attributes = {
			[ "0000" ] = {
				modelings = {
					{
						mappings = {
							{ features = { "state" }, deviceTypes = { "MOTION_SENSOR" }, settings = { "transmitter", "pulse", "timeout=30" } }
						}
					}
				},
				getCommands = function( value )
					return { { name = "state", data = ( value and "on" or "off" ) } }
				end
			}
		}
	}
}

-- Compute feature structure
for _, clusterInfos in pairs( CAPABILITIES ) do
	for _, attributeInfos in pairs( clusterInfos.attributes ) do
		if attributeInfos.name then
			attributeInfos.name = clusterInfos.category .. "/" .. clusterInfos.name .. "/" .. attributeInfos.name
		else
			attributeInfos.name = clusterInfos.category .. "/" .. clusterInfos.name
		end
		if attributeInfos.modelings then
			for _, modeling in ipairs( attributeInfos.modelings ) do
				modeling.isUsed = false
				for _, mapping in ipairs( modeling.mappings ) do
					local features = {}
					for _, featureName in ipairs( mapping.features ) do
						features[ featureName ] = {}
					end
					mapping.features = features
				end
			end
		end
	end
end

do --  Equipments commands/actions translation to Vera devices
	DEVICE.SECURITY_SENSOR.commands = {
		[ "state" ] = function( deviceId, state )
			state = string.lower(state or "")
			if ( ( state == "on" ) or ( state == "alarm" ) ) then
				Device.setTripped( deviceId, "1" )
			elseif ( state == "off" ) then
				Device.setTripped( deviceId, "0" )
			elseif ( state == "tamper" ) then
				Device.setVariable( deviceId, "TAMPER_ALARM", "1" )
			end
		end
	}
	DEVICE.DOOR_SENSOR.commands = DEVICE.SECURITY_SENSOR.commands
	DEVICE.MOTION_SENSOR.commands = DEVICE.SECURITY_SENSOR.commands
	DEVICE.SMOKE_SENSOR.commands = DEVICE.SECURITY_SENSOR.commands
	DEVICE.BAROMETER_SENSOR.commands = {
		[ "pressure" ] = function( deviceId, pressure )
			Device.setPressure( deviceId, pressure )
		end
	}
	DEVICE.BINARY_LIGHT.commands = {
		[ "state" ] = function( deviceId, state, params )
			state = string.lower(state or "")
			if ( state == "on" ) then
				Device.setStatus( deviceId, "1", table_extend( { noAction = true }, params ) )
			elseif ( state == "off" ) then
				Device.setStatus( deviceId, "0", table_extend( { noAction = true }, params ) )
			end
		end
	}
	DEVICE.DIMMABLE_LIGHT.commands = {
		[ "state" ] = DEVICE.BINARY_LIGHT.commands["state"],
		[ "dim" ] = function( deviceId, loadLevel, params )
			if ( loadLevel == "+" ) then
				Device.setLoadLevel( deviceId, nil, table_extend( { direction = "up", noAction = true }, params ) )
			elseif ( loadLevel == "-" ) then
				Device.setLoadLevel( deviceId, nil, table_extend( { direction = "down", noAction = true }, params ) )
			else
				Device.setLoadLevel( deviceId, loadLevel, table_extend( { noAction = true }, params ) )
			end
		end,
		[ "face" ] = function( deviceId, face )
			Variable.set( tonumber(deviceId), "FACE", face )
		end
	}
	DEVICE.RGB_LIGHT.commands = {
		[ "state" ] = DEVICE.DIMMABLE_LIGHT.commands["state"],
		[ "dim" ] = DEVICE.DIMMABLE_LIGHT.commands["dim"],
		[ "rgb" ] = function( deviceId, loadLevel )
			-- TODO
		end
	}
	DEVICE.TEMPERATURE_SENSOR.commands = {
		[ "temperature" ] = function( deviceId, temperature )
			Device.setVariable( deviceId, "TEMPERATURE", temperature, "°C" )
		end
	}
	DEVICE.HUMIDITY_SENSOR.commands = {
		[ "humidity" ] = function( deviceId, humidity )
			Device.setVariable( deviceId, "HUMIDITY", humidity, "%" )
		end
	}
	DEVICE.LIGHT_SENSOR.commands = {
		[ "illuminance" ] = function( deviceId, lightLevel )
			Device.setVariable( deviceId, "LIGHT_LEVEL", lightLevel, "lux" )
		end
	}
	DEVICE.SCENE_CONTROLLER.commands = {
		[ "scene" ] = function( deviceId, sceneId )
			Device.setVariable( deviceId, "LAST_SCENE_ID", sceneId )
		end
	}
end


-- **************************************************
-- Globals
-- **************************************************

local DEVICE_ID      -- The device # of the parent device

local SETTINGS = {
	plugin = {
		pollInterval = 30
	},
	system = {}
}

-- **************************************************
-- Number functions
-- **************************************************

do
	-- Formats a number as hex.
	function number_toHex( n )
		if ( type( n ) == "number" ) then
			return string.format( "%02X", n )
		end
		return tostring( n )
	end

	function number_toBytes( num, endian, signed )
		if ( ( num < 0 ) and not signed ) then
			num = -num
		end
		local res = {}
		local n = math.ceil( select( 2, math.frexp(num) ) / 8 ) -- number of bytes to be used.
		if ( signed and num < 0 ) then
			num = num + 2^n
		end
		for k = n, 1, -1 do -- 256 = 2^8 bits per char.
			local mul = 2^(8*(k-1))
			res[k] = math.floor( num / mul )
			num = num - res[k] * mul
		end
		assert( num == 0 )
		if endian == "big" then
			local t={}
			for k = 1, n do
				t[k] = res[n-k+1]
			end
			res = t
		end
		return string.char(unpack(res))
	end

end

-- **************************************************
-- Table functions
-- **************************************************

do
	-- Merges (deeply) the contents of one table (t2) into another (t1)
	function table_extend( t1, t2, excludedKeys )
		if ( ( type(t1) == "table" ) and ( type(t2) == "table" ) ) then
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

do
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
		if string_isEmpty( s ) then
			return ""
		end
		local hex={}
		for i = 0, 255 do
			hex[ string.format("%0X",i) ] = string.char(i)
		end
		return ( s:gsub( '%%(%x%x)', hex ) )
	end
end


-- **************************************************
-- UI messages
-- **************************************************

UI = {
	show = function( message )
		debug( "Display message: " .. tostring( message ), "UI.show" )
		Variable.set( DEVICE_ID, "LAST_MESSAGE", message )
	end,

	showError = function( message )
		debug( "Display message: " .. tostring( message ), "UI.showError" )
		--message = '<div style="color:red">' .. tostring( message ) .. '</div>'
		message = '<font color="red">' .. tostring( message ) .. '</font>'
		Variable.set( DEVICE_ID, "LAST_MESSAGE", message )
	end,

	clearMessage = function()
		Variable.set( DEVICE_ID, "LAST_MESSAGE", "" )
	end
}


-- **************************************************
-- Variable management
-- **************************************************

local _getVariable = function( name )
	return ( ( type( name ) == "string" ) and VARIABLE[name] or name )
end

Variable = {
	-- Check if variable (service) is supported
	isSupported = function( deviceId, variable )
		deviceId = tonumber(deviceId)
		variable = _getVariable( variable )
		if ( deviceId and variable ) then
			if not luup.device_supports_service( variable[1], deviceId ) then
				warning( "Device #" .. tostring( deviceId ) .. " does not support service " .. variable[1], "Variable.isSupported" )
			else
				return true
			end
		end
		return false
	end,

	-- Get variable timestamp
	getTimestamp = function( deviceId, variable, isActive )
		variable = _getVariable( variable )
		local pos = isActive and 4 or 5
		if ( ( type( variable ) == "table" ) and ( type( variable[pos] ) == "string" ) ) then
			local variableTimestamp = VARIABLE[ variable[pos] ]
			if ( variableTimestamp ~= nil ) then
				return tonumber( ( luup.variable_get( variableTimestamp[1], variableTimestamp[2], deviceId ) ) )
			end
		end
		return nil
	end,

	-- Set variable timestamp
	setTimestamp = function( deviceId, variable, timestamp, isActive )
		variable = _getVariable( variable )
		local pos = isActive and 4 or 5
		if ( variable[pos] ~= nil ) then
			local variableTimestamp = VARIABLE[ variable[pos] ]
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
		end
		variable = _getVariable( variable )
		if ( variable == nil ) then
			error( "Variable is nil", "Variable.get" )
			return
		end
		local value, timestamp = luup.variable_get( variable[1], variable[2], deviceId )
		timestamp = Variable.getTimestamp( deviceId, variable, ( value ~= "0" ) ) or timestamp
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
		end
		variable = _getVariable( variable )
		if ( variable == nil ) then
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
		if ( ( currentValue == value ) and ( ( variable[3] == true ) or ( value == "0" ) ) ) then
			-- Variable is not updated when the value is unchanged
			doChange = false
		end

		if doChange then
			luup.variable_set( variable[1], variable[2], value, deviceId )
		end

		-- Updates linked variable for timestamp
		Variable.setTimestamp( deviceId, variable, os.time(), ( value ~= "0" ) )
	end,

	-- Get variable value and init if value is nil or empty
	getOrInit = function( deviceId, variable, defaultValue )
		local value, timestamp = Variable.get( deviceId, variable )
		if ( ( value == nil ) or (  value == "" ) ) then
			value = defaultValue
			Variable.set( deviceId, variable, value )
			timestamp = os.time()
			Variable.setTimestamp( deviceId, variable, timestamp, true )
		end
		return value, timestamp
	end,

	watch = function( deviceId, variable, callback )
		luup.variable_watch( callback, variable[1], variable[2], lul_device )
	end,

	getEncodedValue = function( variable, value )
		variable = _getVariable( variable )
		local encodedParameter = ""
		if variable then
			encodedParameter = variable[1] .. "," .. variable[2] .. "=" .. tostring( value or "" )
		end
		return encodedParameter
	end
}


-- **************************************************
-- Device management
-- **************************************************

local _indexDeviceInfos = {}
for deviceTypeName, deviceInfos in pairs( DEVICE ) do
	deviceInfos.name = deviceTypeName
	_indexDeviceInfos[ deviceInfos.type ] = deviceInfos
end
setmetatable(_indexDeviceInfos, {
	__index = function( t, deviceType )
		warning( "Can not get infos for device type '" .. tostring( deviceType ) .. "'", "Device.getInfos" )
		return {
			type = deviceType
		}
	end
})

Device = {
	-- Get device type infos, by device id, type name or UPnP device id (e.g. "BINARY_LIGHT" or "urn:schemas-upnp-org:device:BinaryLight:1")
	getInfos = function( deviceType )
		if ( type(deviceType) == "number" ) then
			-- Get the device type from the id
			local luDevice = luup.devices[deviceType]
			if luDevice then
				deviceType = luDevice.device_type
			end
		elseif ( deviceType == nil ) then
			deviceType = ""
		end
		-- Get the device infos
		local deviceInfos = DEVICE[ deviceType ]
		if ( deviceInfos == nil ) then
			-- Not known by name, try with UPnP device id
			deviceInfos = _indexDeviceInfos[ deviceType ]
		end
		return deviceInfos
	end,

	getEncodedParameters = function( deviceInfos )
		local encodedParameters = ""
		if ( deviceInfos and deviceInfos.parameters ) then
			for _, param in ipairs( deviceInfos.parameters ) do
				encodedParameters = encodedParameters .. Variable.getEncodedValue( param[1], param[2] ) .. "\n"
			end
		end
		return encodedParameters
	end,

	fileExists = function( deviceInfos )
		local name = deviceInfos.file or ""
		return (
				Tools.fileExists( "/etc/cmh-lu/" .. name .. ".lzo" ) or Tools.fileExists( "/etc/cmh-lu/" .. name )
			or	Tools.fileExists( "/etc/cmh-ludl/" .. name .. ".lzo" ) or Tools.fileExists( "/etc/cmh-ludl/" .. name )
			or	Tools.fileExists( name ) or Tools.fileExists( "../cmh-lu/" .. name )
		)
	end,

	isDimmable = function( deviceId )
		return luup.device_supports_service( VARIABLE.DIMMER_LEVEL[1], deviceId )
	end,

	-- Switch OFF/ON/TOGGLE
	setStatus = function( deviceId, status, params )
		if status then
			status = tostring( status )
		end
		local params = params or {}
		local formerStatus = Variable.get( deviceId, "SWITCH_POWER" ) or "0"
		local equipment, mapping = Equipments.getFromDeviceId( deviceId )
		local msg = "Equipment '" .. Tools.getEquipmentSummary( equipment, mapping ) .. "'"
		if ( mapping.device.settings.receiver ) then
			msg = msg .. " (receiver)"
		elseif ( mapping.device.settings.transmitter ) then
			msg = msg .. " (transmitter)"
		end

		-- Momentary
		local isMomentary = ( mapping.device.settings.momentary == true )
		if ( isMomentary and ( status == "0" ) and not params.isAfterTimeout ) then
			debug( msg .. " - Begin of momentary state", "Device.setStatus" )
			return
		end

		-- Toggle
		local isToggle = ( mapping.device.settings.toggle == true )
		if ( isToggle or ( status == nil ) or ( status == "" ) ) then
			if ( status == "0" ) then
				debug( msg .. " - Toggle : ignore OFF state", "Device.setStatus" )
				return
			elseif isMomentary then
				-- Always ON in momentary and toggle mode
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

		-- Long press (works at least for Xiaomi button)
		local isLongPress = false
		local timeForLongPress = tonumber(mapping.device.settings.timeForLongPress) or 0
		if ( isMomentary and ( timeForLongPress > 0 ) and ( status == "1" ) and ( params.lastData == "off" ) and ( params.elapsedTime >= timeForLongPress ) ) then
			isLongPress = true
		end

		-- Has status changed ?
		if ( not isMomentary and ( status == formerStatus ) ) then
			debug( msg .. " - Status has not changed", "Device.setStatus" )
			return
		end

		-- Update status variable
		local loadLevel
		if ( status == "1" ) then
			msg = msg .. " ON device #" .. tostring( deviceId )
			if Device.isDimmable( deviceId ) then
				loadLevel = Variable.get( deviceId, "DIMMER_LEVEL_OLD" ) or "100"
				if ( loadLevel == "0" ) then
					loadLevel = "100"
				end
				msg = msg .. " at " .. loadLevel .. "%"
			end
		else
			msg = msg .. " OFF device #" .. tostring( deviceId )
			status = "0"
			if Device.isDimmable( deviceId ) then
				msg = msg .. " at 0%"
				loadLevel = 0
			end
		end
		if isLongPress then
			msg = msg .. " (long press)"
		end
		debug( msg, "Device.setStatus" )
		Variable.set( deviceId, "SWITCH_POWER", status )
		if loadLevel then
			if ( loadLevel == 0 ) then
				-- Store the current load level
				Variable.set( deviceId, "DIMMER_LEVEL_OLD", Variable.get( deviceId, "DIMMER_LEVEL" ) )
			end
			Variable.set( deviceId, "DIMMER_LEVEL", loadLevel )
		end

		-- Send command to the linked equipment if needed
		if ( mapping.device.settings.receiver and not params.noAction ) then
			if ( loadLevel and Device.isDimmable( deviceId ) ) then 
				Equipment.setLoadLevel( equipment, loadLevel, mapping )
			else
				Equipment.setStatus( equipment, status, mapping )
			end
		end

		-- Propagate to associated devices
		if not params.noPropagation then
			Association.propagate( mapping.device.association, status, loadLevel, isLongPress )
		end

		-- Momentary
		if ( isMomentary and ( status == "1" ) ) then
			local timeout = mapping.device.settings.timeout or 0
			if ( timeout > 0 ) then
				debug( "Device #" .. tostring( deviceId ) .. " will be switch OFF in " .. tostring(timeout) .. "s", "Device.setStatus" )
				luup.call_delay( _NAME .. ".Device.setStatusAfterTimeout", timeout, deviceId )
			else
				status = "0"
				Device.setStatus( deviceId, status, { noAction = true, noPropagation = true, isAfterTimeout = true } )
			end
		end

		return status
	end,

	setStatusAfterTimeout = function( deviceId )
		deviceId = tonumber( deviceId )
		local equipment, mapping = Equipments.getFromDeviceId( deviceId )
		local timeout = tonumber(mapping.device.settings.timeout) or 0
		if ( ( timeout > 0 ) and ( Variable.get( deviceId, VARIABLE.SWITCH_POWER ) == "1" ) ) then 
			local elapsedTime = os.difftime( os.time(), Variable.getTimestamp( deviceId, VARIABLE.SWITCH_POWER ) or 0 )
			if ( elapsedTime >= timeout ) then
				Device.setStatus( deviceId, "0", { isAfterTimeout = true } )
			end
		end
	end,

	-- Dim OFF/ON/TOGGLE
	setLoadLevel = function( deviceId, loadLevel, params )
		local params = params or {}
		loadLevel = tonumber( loadLevel )
		local formerLoadLevel, lastLoadLevelChangeTime = Variable.get( deviceId, "DIMMER_LEVEL" )
		formerLoadLevel = tonumber( formerLoadLevel ) or 0
		local equipment, mapping = Equipments.getFromDeviceId( deviceId )
		local dimmingStep = tonumber(mapping.device.settings.dimmingStep) or 3
		local msg = "Dim"

		if ( params.isLongPress and not Device.isDimmable( deviceId ) ) then
			-- Long press handled by a switch
			return Device.setStatus( deviceId, nil, params )

		elseif ( loadLevel == nil ) then
			-- Toggle dim
			loadLevel = formerLoadLevel
			if ( params.direction == nil ) then
				params.direction = Variable.getOrInit( deviceId, "DIMMER_DIRECTION", "up" )
				if ( os.difftime( os.time(), lastLoadLevelChangeTime ) > 2 ) then
					-- Toggle direction after 2 seconds of inactivity
					msg = "Toggle dim"
					if ( params.direction == "down" ) then
						params.direction = "up"
						Variable.set( deviceId, "DIMMER_DIRECTION", "up" )
					else
						params.direction = "down"
						Variable.set( deviceId, "DIMMER_DIRECTION", "down" )
					end
				end
			end
			if ( params.direction == "down" ) then
				loadLevel = loadLevel - dimmingStep
				msg = msg .. "-" .. tostring(dimmingStep)
			else
				loadLevel = loadLevel + dimmingStep
				msg = msg .. "+" .. tostring(dimmingStep)
			end
		end

		-- Update load level variable
		if ( loadLevel < dimmingStep ) then
			loadLevel = 0
		elseif ( loadLevel > 100 ) then
			loadLevel = 100
		end

		-- Has load level changed ?
		if ( loadLevel == formerLoadLevel ) then
			debug( msg .. " - Load level has not changed", "Device.setLoadLevel" )
			return
		end

		debug( msg .. " device #" .. tostring( deviceId ) .. " at " .. tostring( loadLevel ) .. "%", "Device.setLoadLevel" )
		Variable.set( deviceId, "DIMMER_LEVEL_TARGET", loadLevel )
		Variable.set( deviceId, "DIMMER_LEVEL", loadLevel )
		if ( loadLevel > 0 ) then
			Variable.set( deviceId, "SWITCH_POWER", "1" )
		else
			Variable.set( deviceId, "SWITCH_POWER", "0" )
		end

		-- Send command to the linked equipment if needed
		if ( mapping.device.settings.receiver and not ( params.noAction == true ) ) then
			if ( loadLevel > 0 ) then
				if not Device.isDimmable( deviceId ) then
					if ( loadLevel == 100 ) then
						Equipment.setStatus( equipment, "1", mapping )
					else
						debug( "This device does not support DIM", "Device.setLoadLevel" )
					end
				else
					Equipment.setLoadLevel( equipment, loadLevel, mapping )
				end
			else
				Equipment.setStatus( equipment, "0", mapping )
			end
		end

		-- Propagate to associated devices
		Association.propagate( mapping.device.association, nil, loadLevel, params.isLongPress )

		return loadLevel
	end,

	-- Set armed
	setArmed = function( deviceId, armed )
		if not Variable.isSupported( deviceId, "ARMED" ) then
			return
		end
		armed = tostring( armed or "0" )
		if ( armed == "1" ) then
			debug( "Arm device #" .. tostring( deviceId ), "Device.setArmed" )
		else
			debug( "Disarm device #" .. tostring( deviceId ), "Device.setArmed" )
		end
		Variable.set( deviceId, "ARMED", armed )
		if ( armed == "0" ) then
			Variable.set( deviceId, "ARMED_TRIPPED", "0" )
		end
	end,

	-- Set tripped
	setTripped = function( deviceId, tripped )
		if not Variable.isSupported( deviceId, "TRIPPED" ) then
			return
		end
		tripped = tostring( tripped or "0" )
		local formerTripped = Variable.get( deviceId, "TRIPPED" ) or "0"
		local equipment, mapping = Equipments.getFromDeviceId( deviceId )
		if ( tripped ~= formerTripped ) then
			debug( "Device #" .. tostring( deviceId ) .. " is " .. ( ( tripped == "1" ) and "tripped" or "untripped" ), "Device.setTripped" )
			Variable.set( deviceId, "TRIPPED", tripped )
			if ( ( tripped == "1" ) and ( Variable.get( deviceId, "ARMED" ) == "1" ) ) then
				Variable.set( deviceId, "ARMED_TRIPPED", "1" )
			else
				Variable.set( deviceId, "ARMED_TRIPPED", "0" )
			end
			-- Propagate to associated devices
			Association.propagate( mapping.device.association, tripped )
		end

		-- Momentary
		local isMomentary = ( mapping.device.settings.momentary == true )
		if ( isMomentary and ( tripped == "1" ) ) then
			local timeout = tonumber(mapping.device.settings.timeout) or 0
			if ( timeout > 0 ) then
				debug( "Device #" .. tostring( deviceId ) .. " will be untripped in " .. tostring(timeout) .. "s", "Device.setTripped" )
				Variable.set( deviceId, "NEXT_SCHEDULE", os.time() + timeout )
				luup.call_delay( _NAME .. ".Device.setTrippedAfterTimeout", timeout, deviceId )
			end
		end
	end,

	setTrippedAfterTimeout = function( deviceId )
		deviceId = tonumber( deviceId )
		local nextSchedule = tonumber((Variable.get( deviceId, "NEXT_SCHEDULE" ))) or 0
		if ( os.time() >= nextSchedule ) then
			Device.setTripped( deviceId, "0" )
		end
	end,

	-- Set a variable value
	setVariable = function( deviceId, variableName, value, unit )
		if not Variable.isSupported( deviceId, variableName ) then
			return
		end
		debug( "Set device #" .. tostring(deviceId) .. " " .. variableName .. " to " .. tostring( value ) .. ( unit or "" ), "Device.setVariable" )
		Variable.set( deviceId, variableName, value )
	end,

	-- Set atmospheric pressure
	setPressure = function( deviceId, pressure )
		--[[if not Variable.isSupported( deviceId, "PRESSURE" ) then
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
		debug( "Set device #" .. tostring(deviceId) .. " pressure to " .. tostring( pressure ) .. "hPa and forecast to " .. forecast, "Device.setPressure" )
		Variable.set( deviceId, "PRESSURE", pressure )
		Variable.set( deviceId, "FORECAST", forecast )
	end,

	-- Set battery level
	setBatteryLevel = function( deviceId, batteryLevel )
		local batteryLevel = tonumber(batteryLevel) or 0
		if (batteryLevel < 0) then
			batteryLevel = 0
		elseif (batteryLevel > 100) then
			batteryLevel = 100
		end
		debug("Set device #" .. tostring(deviceId) .. " battery level to " .. tostring(batteryLevel) .. "%", "Device.setBatteryLevel")
		Variable.set( deviceId, "BATTERY_LEVEL", batteryLevel )
	end

}

-- **************************************************
-- ZiGate Messages
-- **************************************************

ATTR_TYPES = {
	boolean = 0x10,
	bitmap = 0x18,
	uint8 = 0x20,
	uint16 = 0x21,
	uint32 = 0x22,
	uint48 = 0x25,
	uint64 = 0x27, -- ??
	int8 = 0x28,
	int16 = 0x29,
	int32 = 0x2A,
	IEEE754 = 0x39,
	string = 0x42,
	-- Custom types
	hex16 = 0xF1,
	hex64 = 0xF7
}

ZIGBEE_STATUS = {
	["0"] = "Success",
	["1"] = "Incorrect parameters",
	["2"] = "Unhandled command",
	["3"] = "Command failed",
	["4"] = "Busy",
	["5"] = "Stack already started"
}

-- https://stackoverflow.com/questions/14416734/lua-packing-ieee754-single-precision-floating-point-numbers
function UnpackIEEE754(packed)
    local b1, b2, b3, b4 = string.byte(packed, 1, 4)
    local exponent = (b1 % 0x80) * 0x02 + math.floor(b2 / 0x80)
    local mantissa = math.ldexp(((b2 % 0x80) * 0x100 + b3) * 0x100 + b4, -23)
    if exponent == 0xFF then
        if mantissa > 0 then
            return 0 / 0
        else
            mantissa = math.huge
            exponent = 0x7F
        end
    elseif exponent > 0 then
        mantissa = mantissa + 1
    else
        exponent = exponent + 1
    end
    if b1 >= 0x80 then
        mantissa = -mantissa
    end
    return math.ldexp(mantissa, exponent - 0x7F)
end

function _getAttrValue( attrType, strData )
	if ( attrType == ATTR_TYPES.boolean ) then
		return ( strData:byte() == 0x01 )

	elseif ( attrType == ATTR_TYPES.bitmap ) then
		return tostring(strData) -- TODO

	elseif ( attrType == ATTR_TYPES.uint8 ) then
		return strData:byte( 1 )

	elseif ( attrType == ATTR_TYPES.uint16 ) then
		return bit.lshift( strData:byte( 1 ), 8 ) + strData:byte( 2 )

	elseif ( attrType == ATTR_TYPES.uint32 ) then
		return bit.lshift( strData:byte( 1 ), 24 ) + bit.lshift( strData:byte( 2 ), 16 ) + bit.lshift( strData:byte( 3 ), 8 ) + strData:byte( 4 )

	elseif ( attrType == ATTR_TYPES.uint64 ) then
		-- Seems to raise arithmetic overflow
		return bit.lshift( strData:byte( 1 ), 56 ) + bit.lshift( strData:byte( 2 ), 48 ) + bit.lshift( strData:byte( 3 ), 40 ) + bit.lshift( strData:byte( 4 ), 32 ) + bit.lshift( strData:byte( 5 ), 24 ) + bit.lshift( strData:byte( 6 ), 16 ) + bit.lshift( strData:byte( 7 ), 8 ) + strData:byte( 8 )

	elseif ( attrType == ATTR_TYPES.hex16 ) then
		local result = ""
		for i = 1, 2 do
			result = result .. number_toHex( strData:byte( i ) )
		end
		return result

	elseif ( attrType == ATTR_TYPES.hex64 ) then
		local result = ""
		for i = 1, 8 do
			result = result .. number_toHex( strData:byte( i ) )
		end
		return result

	elseif ( attrType == ATTR_TYPES.int8 ) then
		return strData:byte( 1 )

	elseif ( attrType == ATTR_TYPES.int16 ) then
		return bit.lshift( strData:byte( 1 ), 8 ) + strData:byte( 2 )

	elseif ( attrType == ATTR_TYPES.IEEE754 ) then
		return UnpackIEEE754( strData )

	elseif ( attrType == ATTR_TYPES.string ) then
		return strData

	else
		warning( "Unknown data type: " .. tostring(attrType), "getAttrValue" )
		return ""
	end
end

ZIGATE_MESSAGE = {

	-- Equipment announce
	["004D"] = function( payload, quality )
		--local address = number_toHex( _getAttrValue( ATTR_TYPES.uint16, payload:sub( 1, 2 ) ) )
		local address = _getAttrValue( ATTR_TYPES.hex16, payload:sub( 1, 2 ) )
		--local IEEEAddress = number_toHex( _getAttrValue( ATTR_TYPES.uint64, payload:sub( 3, 10 ) ) )
		local IEEEAddress = _getAttrValue( ATTR_TYPES.hex64, payload:sub( 3, 10 ) )
		local capability = _getAttrValue( ATTR_TYPES.uint8, payload:sub( 11, 11 ) )
		local isBatteryPowered = ( bit.band( capability, 4 ) == 0 )
		debug( "Equipment announce: (id:0x" .. tostring(IEEEAddress) .. "), (address:0x" .. number_toHex(address) .. "), (isBatteryPowered:" .. tostring(isBatteryPowered) .. ")", "Network.receive" )
		local equipment = Equipments.get( "ZIGBEE", IEEEAddress )
		if equipment then
			equipment.isBatteryPowered = isBatteryPowered
			-- Check if address has changed
			if ( equipment.address ~= address ) then
				Equipments.changeAddress( equipment, address )
				Equipments.retrieve()
			end
		else
			DiscoveredEquipments.add( "ZIGBEE", IEEEAddress, address, nil, { isBatteryPowered = isBatteryPowered } )
		end
		return true
	end,

	-- Status
	["8000"] = function( payload, quality )
		local status = _getAttrValue( ATTR_TYPES.uint8, payload:sub( 1, 1 ) )
		local sequenceNumber = _getAttrValue( ATTR_TYPES.uint8, payload:sub( 2, 2 ) )
		local paquetType = _getAttrValue( ATTR_TYPES.uint16, payload:sub( 3, 4 ) )
		-- TODO : paquetType = la demande
		local errorInformation = payload:sub( 5 )
		debug( "(status:" .. tostring(ZIGBEE_STATUS[tostring(status)]) .. "), (sqn:" .. tostring(sequenceNumber) .. ")", "Network.receive" )
		if ( status > 0 ) then
			error( "ZigBee error : (status:" .. tostring(ZIGBEE_STATUS[tostring(status)]) .. "),(paquetType:" .. tostring(paquetType) .. ") " .. tostring(errorInformation), "Network.receive" )
		end
		return true
	end,

	-- Version
	["8010"] = function( payload, quality )
		SETTINGS.system.majorVersion = _getAttrValue( ATTR_TYPES.uint16, payload:sub( 1, 2 ) )
		SETTINGS.system.installerVersion = _getAttrValue( ATTR_TYPES.uint16, payload:sub( 3, 4 ) )
		debug( "(version:" .. tostring(SETTINGS.system.majorVersion) .. "." .. number_toHex(SETTINGS.system.installerVersion) .. ")", "Network.receive" )
		return true
	end,

	-- "Permit join" status response
	["8014"] = function( payload, quality )
		local isJoinPermited = _getAttrValue( ATTR_TYPES.boolean, payload:sub( 1, 1 ) )
		if not isJoinPermited then
			error( "Permit Join is Off", "Network.receive" )
		end
		return true
	end,

	-- Device list
	["8015"] = function( payload, quality )
		debug( "Get equipment list", "Network.receive" )
		local i, iMax = 1, string.len(payload)
		local hasAddressChanged = false
		local deviceStr
		while ( i < iMax ) do
			deviceStr = payload:sub( i, i + 12 )
			local pos = _getAttrValue( ATTR_TYPES.uint8, deviceStr:sub( 1, 1 ) )
			--local address = number_toHex( _getAttrValue( ATTR_TYPES.uint16, deviceStr:sub( 2, 3 ) ) )
			local address = _getAttrValue( ATTR_TYPES.hex16, deviceStr:sub( 2, 3 ) )
			--local IEEEAddress = number_toHex( _getAttrValue( ATTR_TYPES.uint64, deviceStr:sub( 4, 11 ) ) )
			local IEEEAddress = _getAttrValue( ATTR_TYPES.hex64, deviceStr:sub( 4, 11 ) )
			local isBatteryPowered = not _getAttrValue( ATTR_TYPES.boolean, deviceStr:sub( 12, 12 ) )
			local quality = number_toHex( _getAttrValue( ATTR_TYPES.uint8, deviceStr:sub( 13, 13 ) ) )
			debug( "Equipment (pos:" .. tostring(pos) .. "), (id:0x" .. tostring(IEEEAddress) .. "), (address:0x" .. tostring(address) .. "), (isBatteryPowered:" .. tostring(isBatteryPowered) .. ")", "Network.receive" )
			i = i + 13

			local equipment = Equipments.get( "ZIGBEE", IEEEAddress )
			if equipment then
				equipment.isKnown = true
				-- Check if address has changed
				if ( equipment.address ~= address ) then
					Equipments.changeAddress( equipment, address )
					hasAddressChanged = true
				end
			else
				-- Equipment is not known for HA system
				DiscoveredEquipments.add( "ZIGBEE", IEEEAddress, address, nil, { isBatteryPowered = isBatteryPowered, quality = quality } )
			end
		end
		if hasAddressChanged then
			Equipments.retrieve()
		end
		return true
	end,

	-- Attribute Report
	["8102"] = function( payload, quality )
		local sqn = payload:byte( 1 )
		local address = string_toHex( payload:sub( 2, 3 ) ) -- ZigBee address
		local endpointId = string_toHex( payload:sub( 4, 4 ) )
		local msg = "Attribute Report: (address:0x".. address .. "), (endpoint:0x" .. endpointId .. ")"
		local clusterId = string_toHex( payload:sub( 5, 6 ) )
		local attrId = string_toHex( payload:sub( 7, 8 ) )
		local attrStatus = payload:byte( 9 )
		local attrType = payload:byte( 10 )
		local attrSize = _getAttrValue( ATTR_TYPES.uint16, payload:sub( 11, 12 ) )
		local attrData = payload:sub( 13, 12 + attrSize )
		local attrValue = _getAttrValue( attrType, attrData )
		local clusterInfos = CAPABILITIES[ clusterId ]
		if clusterInfos then
			msg = msg .. ", (cluster:0x" .. clusterId .. ")"
			local attrInfos = clusterInfos.attributes[ endpointId .. "-" .. attrId ] or clusterInfos.attributes[ attrId ]
			if attrInfos then
				msg = msg .. ", (attrId:0x" .. attrId .. ";" .. tostring(attrInfos.name) .. ")"
				local cmds = attrInfos.getCommands( attrValue )
				if ( cmds and #cmds > 0 ) then
					--debug( tostring(#cmds) .. " command(s)", "Network.receive" )
					for i, cmd in ipairs( cmds ) do
						if ( cmd.name ~= "not_implemented" ) then
							debug( msg .. ", (command:" .. tostring(cmd.name) .. ( cmd.broadcast and " BROADCAST" or "" ) .. "), (data:" .. tostring(cmd.data) .. "), (info:" .. tostring(cmd.info) .. ")", "Network.receive" )
							Tools.pcall( Commands.add, "ZIGBEE", nil, address, endpointId, { capability = { name = attrInfos.name, modelings = attrInfos.modelings }, quality = quality }, cmd )
						else
							warning( msg .. " - Not implemented" , "Network.receive" )
						end
					end
					Commands.process()
				else
					error( msg .. " - No command for (value:" .. tostring(attrValue) .. ")", "Network.receive" )
					return false
				end
			else
				warning( msg .. " - (attrId:0x" .. attrId .. ") is not handled" , "Network.receive" )
				return false
			end
		else
			warning( msg .. " - (cluster:0x" .. clusterId .. ") is not handled", "Network.receive" )
			return false
		end
		return true
	end,

	-- Router Discover
	["8701"] = function( payload, quality )
		local status = _getAttrValue( ATTR_TYPES.uint8, payload:sub( 1, 1 ) )
		local networkStatus = _getAttrValue( ATTR_TYPES.uint8, payload:sub( 2, 2 ) )
		debug( "Router Discover: (status:" .. tostring(ZIGBEE_STATUS[tostring(status)]) .. "), (networkStatus:" .. tostring(networkStatus) .. ")", "Network.receive" )
		return true
	end
}


-- **************************************************
-- Commands
-- **************************************************

local _commandsToProcess = {}
local _isProcessingCommand = false

Commands = {

	process = function()
		if ( #_commandsToProcess > 0 ) then
			luup.call_delay( _NAME .. ".Commands.deferredProcess", 0 )
		end
	end,

	add = function( protocol, equipmentId, address, endpointId, infos, cmd )
		cmd.name = string.lower(cmd.name or "")
		local msg = "Equipment " .. Tools.getEquipmentInfo( protocol, equipmentId, address, endpointId )
		if string_isEmpty(cmd.name) then
			error( msg .. " : no given command", "Commands.add" )
			return false
		end
		local equipment, feature, devices = Equipments.get( protocol, equipmentId, address, ( cmd.broadcast == true and "all" or endpointId ), cmd.name ) -- cmd.name = feature
		if equipment then
			equipment.frequency = infos.frequency
			equipment.quality = infos.quality
			if string_isEmpty(equipmentId) then
				equipmentId = equipment.id
				msg = "Equipment " .. Tools.getEquipmentInfo( protocol, equipmentId, address, endpointId )
			end
			if equipment.isNew then
				-- No command on a new equipment (not yet handled by the home automation controller)
				debug( msg .. " is new : do nothing", "Commands.add" )
				return true
			end
			if feature then
				-- Equipment is known for this feature
				cmd.elapsedTime = os.difftime( os.time(), feature.lastUpdate or os.time() )
				cmd.lastData = feature.data
				feature.data = cmd.data
				feature.unit = cmd.unit
				feature.lastUpdate = os.time()
				equipment.lastUpdate = os.time()
				table.insert( _commandsToProcess, { devices, cmd } )
			else
				-- Equipment is known (but not for this feature)
				if ( cmd.name == "battery" ) then
					Device.setBatteryLevel( equipment.mainDeviceId, cmd.data )
				end
			end
		end

		if ( not cmd.broadcast and ( cmd.name ~= "battery" ) and ( not equipment or not feature ) ) then
			-- Add this equipment or feature to the discovered equipments (but not yet known)
			msg = msg .. ",(command:" .. cmd.name .. ")"
			local hasBeenAdded, hasCapabilityBeenAdded, isFeatureKnown = DiscoveredEquipments.add( protocol, equipmentId, address, endpointId, infos, cmd.name, cmd.data, cmd.unit )
			if hasBeenAdded then
				debug( msg .. " was unknown", "Commands.add" )
			elseif hasCapabilityBeenAdded then
				debug( msg .. " was unknown for this command", "Commands.add" )
			elseif not isFeatureKnown then
				error( msg .. ": feature '" .. cmd.name .. "' is not known", "Commands.add" )
				return false
			else
				debug( msg .. " is already discovered", "Commands.add" )
			end
		end
		return true
	end,

	deferredProcess = function()
		if _isProcessingCommand then
			debug( "Processing is already in progress", "Commands.deferredProcess" )
			return
		end
		_isProcessingCommand = true
		while _commandsToProcess[1] do
			local status, err = pcall( Commands.protectedProcess )
			if err then
				error( "Error: " .. tostring( err ), "Commands.deferredProcess" )
			end
			table.remove( _commandsToProcess, 1 )
		end
		_isProcessingCommand = false
	end,

	protectedProcess = function()
		local devices, cmd = unpack( _commandsToProcess[1] )
		for _, device in pairs( devices ) do
			local msg = "Device #" .. tostring(device.id)
			local deviceInfos = Device.getInfos( device.id )
			if ( deviceInfos == nil ) then
				error( msg .. " - Type is unknown", "Commands.protectedProcess" )
			elseif ( deviceInfos.commands[ cmd.name ] ~= nil ) then
				if ( type(cmd.data) == "table" ) then
					debug( msg .. " - Do command '" .. cmd.name .. "' with data '" .. json.encode(cmd.data) .. "'", "Commands.protectedProcess" )
				else
					debug( msg .. " - Do command '" .. cmd.name .. "' with data '" .. tostring(cmd.data) .. "'", "Commands.protectedProcess" )
				end
				deviceInfos.commands[ cmd.name ]( device.id, cmd.data, { unit = cmd.unit, lastData = cmd.lastData, elapsedTime = cmd.elapsedTime } )
				if cmd.info then
					Variable.set( device.id, "LAST_INFO", cmd.info )
				end
			else
				warning( msg .. " - Command '" .. cmd.name .. "' not yet implemented for this device type " .. tostring(deviceInfos.type), "Commands.protectedProcess" )
			end
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

	receive = function( lul_data )
		local rxByte = string.byte( lul_data )

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
			elseif ZIGATE_MESSAGE[msgType] then
				--debug( "(type:0x" .. tostring(msgType) .. "), (payload:" .. string_formatToHex(payload) .. ")", "Network.receive" )
				if not ZIGATE_MESSAGE[msgType]( payload, quality ) then
					warning( "Problem with message (type:0x" .. tostring(msgType) .. "), (payload:" .. string_formatToHex(payload) .. ")", "Network.receive" )
				end
			else
				warning( "Unknown message (type:0x" .. tostring(msgType) .. "), (payload:" .. string_formatToHex(payload) .. ")", "Network.receive" )
			end

		elseif ( rxByte == 2 ) then
			_transcodage = true
		else
			if _transcodage then
				rxByte = bit.bxor( rxByte, 0x10 )
				_buffer = _buffer .. string.char( rxByte )
				_transcodage = false
			else
				_buffer = _buffer .. lul_data
			end
		end
	end,

	-- Send a message (add to send queue)
	send = function( hexCmd, hexData )
		if ( luup.attr_get( "disabled", DEVICE_ID ) == "1" ) then
			warning( "Can not send message: " .. _NAME .. " is disabled", "Network.send" )
			return
		end

		local command = string_fromHex( hexCmd )
		local payload = string_fromHex( hexData or "" )
		local length = string_fromHex( string.format( "%04X", string.len( payload ) ) )
		--debug("chk: ".. tostring(_getChecksum( command .. length .. payload )), "Network.send")
		local packet = string.char(1) .. _transcode( command .. length .. string.char( _getChecksum( command .. length .. payload ) ) .. payload ) .. string.char(3)

		debug( "(type:0x" .. tostring(hexCmd) .. "), (payload:" .. tostring(hexData) .. ")", "Network.send" )
		table.insert( _messageToSendQueue, packet )
		if not _isSendingMessage then
			Network.flush()
		end
	end,

	-- Send the packets in the queue to dongle
	flush = function ()
		if ( luup.attr_get( "disabled", DEVICE_ID ) == "1" ) then
			debug( "Can not send message: " .. _NAME .. " is disabled", "Network.send" )
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
				_isSendingMessage = false
				return
			end
			table.remove( _messageToSendQueue, 1 )
		end

		_isSendingMessage = false
	end
}


-- **************************************************
-- Poll engine
-- **************************************************

local _isPollingActivated = false

PollEngine = {
	start = function()
		log( "Start poll", "PollEngine.start" )
		_isPollingActivated = true
		if ( ( SETTINGS.system.majorVersion == 1 ) and ( SETTINGS.system.installerVersion < 0x30D ) ) then
			log( "Get Network State command not supported by this firmware", "PollEngine.start" )
			return
		end
		luup.call_delay( _NAME .. ".PollEngine.poll", SETTINGS.plugin.pollInterval )
	end,

	poll = function()
		if _isPollingActivated then
			log( "Start poll", "PollEngine.poll" )
			-- Get network state
			Network.send( "0009", "" )
			-- Prepare next polling
			luup.call_delay( _NAME .. ".PollEngine.poll", SETTINGS.plugin.pollInterval )
		end
	end
}


-- **************************************************
-- Tools
-- **************************************************

Tools = {
	fileExists = function( name )
		local f = io.open( name, "r" )
		if ( f ~= nil ) then
			io.close( f )
			return true
		else
			return false
		end
	end,

	getEquipmentInfo = function( protocol, equipmentId, address, endpointId, featureNames, deviceId )
		local info = "(protocol:" .. protocol .. "),(id:" .. tostring(equipmentId) ..")"
		if not string_isEmpty(address) then
			info = info .. ",(address:" .. tostring(address) .. ")"
		end
		if not string_isEmpty(endpointId) then
			info = info .. ",(endpointId:" .. tostring(endpointId) .. ")"
		end
		if ( type(featureNames) == "table" ) then
			info = info .. ",(features:" .. table.concat( featureNames, "," ) .. ")"
		end
		if deviceId then
			info = info .. ",(deviceId:" .. tostring( deviceId ) .. ")"
		end
		return info
	end,

	getEquipmentSummary = function( equipment, mapping )
		local info
		if mapping then
			info = Tools.getEquipmentInfo( equipment.protocol, equipment.id, equipment.address, mapping.endpointId, table_getKeys( mapping.features ), mapping.device.id )
		else
			info = Tools.getEquipmentInfo( equipment.protocol, equipment.id, equipment.address )
		end
		return info
	end,

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

	updateSystemStatus = function( infos )
		local status = Tools.extractInfos( infos )
		debug( "Status:" .. json.encode( status ), "Tools.updateSystemStatus" )
		Variable.set( DEVICE_ID, VARIABLE.ZIGATE_VERSION, status.Version )
		Variable.set( DEVICE_ID, VARIABLE.ZIGATE_MAC,     status.Mac )
	end,

	pcall = function( method, ... )
		local isOk, result = pcall( method, unpack(arg) )
		if not isOk then
			error( "Error: " .. tostring( result ), "Tools.pcall" )
		end
		return isOk, result
	end,

	getSettings = function( encodedSettings )
		local settings = {}
		for _, encodedSetting in ipairs( string_split( encodedSettings or "", "," ) ) do
			local settingName, value = string.match( encodedSetting, "([^=]*)=?(.*)" )
			if not string_isEmpty( settingName ) then
				-- Backward compatibility
				if ( settingName == "pulse" ) then
					settingName = "momentary"
				end
				settings[ settingName ] = not string_isEmpty( value ) and ( tonumber(value) or value ) or true
			end
		end
		return settings
	end

}


-- **************************************************
-- Association
-- **************************************************

Association = {
	-- Get association from string
	get = function( strAssociation )
		local association = {}
		for _, encodedAssociation in pairs( string_split( strAssociation or "", "," ) ) do
			local linkedId, level, isScene, isEquipment = nil, 1, false, false
			while ( encodedAssociation ) do
				local firstCar = string.sub( encodedAssociation, 1 , 1 )
				if ( firstCar == "*" ) then
					isScene = true
					encodedAssociation = string.sub( encodedAssociation, 2 )
				elseif ( firstCar == "%" ) then
					isEquipment = true
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
						error( "Associated scene #" .. tostring( linkedId ) .. " is unknown", "Association.get" )
					end
				elseif isEquipment then
					if ( luup.devices[ linkedId ] ) then
						if ( association.equipments == nil ) then
							association.equipments = { {}, {} }
						end
						table.insert( association.equipments[ level ], linkedId )
					else
						error( "Associated equipment #" .. tostring( linkedId ) .. " is unknown", "Association.get" )
					end
				else
					if ( luup.devices[ linkedId ] ) then
						if ( association.devices == nil ) then
							association.devices = { {}, {} }
						end
						table.insert( association.devices[ level ], linkedId )
					else
						error( "Associated device #" .. tostring( linkedId ) .. " is unknown", "Association.get" )
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
		if association.equipments then
			table_append( result, _getEncodedAssociations( association.equipments, "%" ) )
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
-- Discovered Equipments
-- **************************************************

local _discoveredEquipments = {}
local _indexDiscoveredEquipmentsByProtocolEquipmentId = {}
local _indexDiscoveredEquipmentsByProtocolAddress = {}

DiscoveredEquipments = {

	add = function( protocol, equipmentId, address, endpointId, infos, featureName, data, unit, comment )
		local hasBeenAdded = false
		if ( string_isEmpty(equipmentId) and string_isEmpty(address) ) then
			error( "equipmentId or address has to be set", "DiscoveredEquipments.add" )
			return false
		end
		local discoveredEquipment
		if not string_isEmpty(equipmentId) then
			discoveredEquipment = _indexDiscoveredEquipmentsByProtocolEquipmentId[ protocol .. ";" .. equipmentId ]
		elseif not string_isEmpty(address) then
			discoveredEquipment = _indexDiscoveredEquipmentsByProtocolAddress[ protocol .. ";" .. address ]
		end
		-- Add discovered equipment if not already known
		if ( discoveredEquipment == nil ) then
			discoveredEquipment = {
				protocol = protocol,
				frequency = infos.frequency,
				comment = comment,
				capabilities = {}
			}
			table.insert( _discoveredEquipments, discoveredEquipment )
			if not string_isEmpty(equipmentId) then
				discoveredEquipment.id = equipmentId
				_indexDiscoveredEquipmentsByProtocolEquipmentId[ protocol .. ";" .. equipmentId ] = discoveredEquipment
			end
			if not string_isEmpty(address) then
				discoveredEquipment.address = address
				_indexDiscoveredEquipmentsByProtocolAddress[ protocol .. ";" .. address ] = discoveredEquipment
			end
			hasBeenAdded = true
			debug( "New discovered equipment " .. Tools.getEquipmentSummary(discoveredEquipment), "DiscoveredEquipments.add" )
		end
		discoveredEquipment.quality = tonumber( infos.quality )

		-- Capability
		local isFeatureKnown, hasCapabilityBeenAdded = false, false
		if infos.capability then
			local capabilityName = ( not string_isEmpty(endpointId) and ( endpointId .. "-" ) or "" ) .. ( infos.capability.name or "Unknown" )
			local capability = discoveredEquipment.capabilities[ capabilityName ]
			if ( capability == nil ) then
				capability = {
					name = capabilityName,
					endpointId = endpointId,
					modelings = table_extend( {}, infos.capability.modelings ) -- Clone the modelings
				}
				discoveredEquipment.capabilities[ capabilityName ] = capability
				hasCapabilityBeenAdded = true
			end

			-- Feature
			for _, modeling in ipairs( capability.modelings ) do
				for _, mapping in ipairs( modeling.mappings ) do
					local feature = mapping.features[ featureName ]
					if feature then
						-- This mapping contains our feature
						isFeatureKnown = true
						if mapping.deviceTypes then
							mapping.isUsed = true
							feature.data = data
							feature.unit = unit
							modeling.isUsed = true
						end
						-- The features are unique in each modeling
						break
					end
				end
			end
		end

		discoveredEquipment.lastUpdate = os.time()
		if hasBeenAdded then
			Variable.set( DEVICE_ID, "LAST_DISCOVERED", os.time() )
			UI.show( "New equipment discovered" )
		end
		if ( isFeatureKnown and hasCapabilityBeenAdded ) then
			debug( "Discovered equipment " .. Tools.getEquipmentSummary(discoveredEquipment) .. " has a new feature '" .. featureName .. "'", "DiscoveredEquipments.add" )
		end
		return hasBeenAdded, hasCapabilityBeenAdded, isFeatureKnown
	end,

	get = function( protocol, equipmentId )
		if ( not string_isEmpty(protocol) and not string_isEmpty(equipmentId) ) then
			local key = protocol .. ";" .. equipmentId
			return _indexDiscoveredEquipmentsByProtocolEquipmentId[ key ]
		else
			return _discoveredEquipments
		end
	end,

	remove = function( protocol, equipmentId )
		if ( not string_isEmpty(protocol) and not string_isEmpty(equipmentId) ) then
			local key = protocol .. ";" .. equipmentId
			local discoveredEquipment = _indexDiscoveredEquipmentsByProtocolEquipmentId[ key ]
			for i, equipment in ipairs( _discoveredEquipments ) do
				if ( equipment == discoveredEquipment ) then
					local address = equipment.address
					table.remove( _discoveredEquipments, i )
					_indexDiscoveredEquipmentsByProtocolEquipmentId[ key ] = nil
					if address then
						_indexDiscoveredEquipmentsByProtocolAddress[ protocol .. ";" .. address ] = nil
					end
					break
				end
			end
		end
	end
}


-- **************************************************
-- Equipments
-- **************************************************

local _equipments = {} -- The list of all our child devices
local _indexEquipmentsByProtocolEquipmentId = {}
local _indexEquipmentsByProtocolAddress = {}
local _indexEquipmentsAndMappingsByDeviceId = {}
local _indexFeaturesAndDevicesByProtocolEquipmentIdAndFeatureEndpoint = {}
-- TODO : list device sinon crash

Equipments = {

	-- Get a list with all our child devices.
	retrieve = function()
		local formerEquipments = _equipments
		_equipments = {}
		Equipments.clearIndexes()
		for deviceId, luDevice in pairs( luup.devices ) do
			if ( luDevice.device_num_parent == DEVICE_ID ) then
				local protocol, equipmentId, deviceNum = unpack( string_split( luDevice.id or "", ";" ) )
				deviceNum = tonumber(deviceNum) or 1
				if ( ( protocol == nil ) or ( equipmentId == nil ) or ( deviceNum == nil ) ) then
					debug( "Found child device #".. tostring( deviceId ) .."(".. luDevice.description .."), but id '" .. tostring( luDevice.id ) .. "' does not match pattern '[0-9]+;[0-9]+;[0-9]+'", "Equipments.retrieve" )
				else
					-- Address
					local address = Variable.get( deviceId, "ADDRESS" )
					-- Endpoint
					local endpointId = Variable.get( deviceId, "ENDPOINT" )
					-- Features
					local featureNames = string_split( Variable.get( deviceId, "FEATURE" ) or "default", "," )
					-- Settings
					local settings = Tools.getSettings( Variable.get( deviceId, "SETTING" ) )
					-- Association
					association = Association.get( Variable.get( deviceId, "ASSOCIATION" ) )
					-- Add the device
					Equipments.add( protocol, equipmentId, address, endpointId, featureNames, deviceNum, luDevice.device_type, deviceId, luDevice.room_num, settings, association, false )
				end
			end
		end

		-- Retrieve former data
		for _, formerEquipment in ipairs( formerEquipments ) do
			local equipment = Equipments.get( formerEquipment.protocol, formerEquipment.id, formerEquipment.address )
			if ( equipment ) then
				-- This former equipment has been retrieved
				formerEquipment.lastUpdate = equipment.lastUpdate
				for _, formerMapping in ipairs( formerEquipment.mappings ) do
					for _, formerFeature in ipairs( formerMapping.features ) do
						local _, feature, devices = Equipments.get( formerEquipment.protocol, formerEquipment.id, formerEquipment.address, formerMapping.endpointId, formerFeature.featureName )
						if feature then
							feature.data = formerFeature.data
							feature.lastUpdate = formerFeature.lastUpdate
						end
					end
				end
			elseif ( formerEquipment.isNew ) then
				-- Add newly created Equipment (not present in luup.devices until a reload of the luup engine)
				table.insert( _equipments, formerEquipment )
				-- Add to indexes
				Equipments.addToIndexes( formerEquipment )
			end
		end
		formerEquipments = nil

		log("Found " .. tostring(#_equipments) .. " equipment(s)", "Equipments.retrieve")

		-- Get devices list from the controller (to check with our children)
		Network.send( "0015", "" )
	end,

	-- Add a device
	add = function( protocol, equipmentId, address, endpointId, featureNames, deviceNum, deviceType, deviceId, deviceRoomId, settings, association, isNew )
		local key = tostring(protocol) .. ";" .. tostring(equipmentId)
		local deviceInfos = Device.getInfos( deviceId )
		local deviceTypeName = deviceInfos and deviceInfos.name or "unknown"
		debug( "Add equipment " .. Tools.getEquipmentInfo( protocol, equipmentId, address, endpointId, featureNames, deviceId ) .. ",(deviceNum:" .. tostring(deviceNum) .. ",(type:" .. deviceTypeName .. ")", "Equipments.add" )
		local device = {
			id = deviceId,
			settings = settings or {},
			association = association or {}
		}
		local equipment = _indexEquipmentsByProtocolEquipmentId[ key ]
		if ( equipment == nil ) then
			equipment = {
				protocol = protocol,
				id = equipmentId,
				address = address,
				frequency = -1,
				quality = -1,
				mappings = {},
				maxDeviceNum = 0,
				isKnown = false
			}
			if isNew then
				equipment.isNew = true
			end
			table.insert( _equipments, equipment )
		end
		-- TODO : control num
		-- Update the device max number
		if ( deviceNum > equipment.maxDeviceNum ) then
			equipment.maxDeviceNum = deviceNum
		end
		-- Main device
		if ( ( deviceNum == 1 ) or not equipment.mainDeviceId ) then
			-- Main device
			equipment.mainDeviceId = deviceId
			equipment.mainRoomId = deviceRoomId
		end
		-- Mapping
		local _, mapping = Equipments.getFromDeviceId( deviceId, true )
		if ( mapping == nil ) then
			-- Device not already mapped
			mapping = {
				endpointId = endpointId,
				features = {},
				device = device
			}
			table.insert( equipment.mappings, mapping )
		end
		-- Features
		for _, featureName in ipairs( featureNames ) do
			local _, feature = Equipments.get( protocol, equipmentId, address, endpointId, featureName )
			if ( feature == nil ) then
				feature = {
					name = featureName
				}
			end
			mapping.features[featureName] = feature
		end
		-- Add to indexes
		Equipments.addToIndexes( equipment )
	end,

	clearIndexes = function()
		_indexEquipmentsByProtocolEquipmentId = {}
		_indexEquipmentsByProtocolAddress = {}
		_indexEquipmentsAndMappingsByDeviceId = {}
		_indexFeaturesAndDevicesByProtocolEquipmentIdAndFeatureEndpoint = {}
	end,

	addToIndexes = function( equipment )
		local key = tostring(equipment.protocol) .. ";" .. tostring(equipment.id)
		if ( _indexEquipmentsByProtocolEquipmentId[ key ] == nil ) then
			_indexEquipmentsByProtocolEquipmentId[ key ] = equipment
		end
		if ( equipment.address and ( _indexEquipmentsByProtocolAddress[ tostring(equipment.protocol) .. ";" .. tostring(equipment.address) ] == nil ) ) then
			_indexEquipmentsByProtocolAddress[ tostring(equipment.protocol) .. ";" .. tostring(equipment.address) ] = equipment
		end
		if ( _indexFeaturesAndDevicesByProtocolEquipmentIdAndFeatureEndpoint[ key ] == nil ) then
			_indexFeaturesAndDevicesByProtocolEquipmentIdAndFeatureEndpoint[ key ] = {}
		end
		for _, mapping in ipairs( equipment.mappings ) do
			if ( _indexEquipmentsAndMappingsByDeviceId[ tostring( mapping.device.id ) ] == nil ) then
				for featureName, feature in pairs( mapping.features ) do
					local _indexFeaturesAndDevicesFromIdAndFeatureByEndpoint = _indexFeaturesAndDevicesByProtocolEquipmentIdAndFeatureEndpoint[ key ][ featureName ]
					if ( _indexFeaturesAndDevicesFromIdAndFeatureByEndpoint == nil ) then
						_indexFeaturesAndDevicesByProtocolEquipmentIdAndFeatureEndpoint[ key ][ featureName ] = {}
						_indexFeaturesAndDevicesFromIdAndFeatureByEndpoint = _indexFeaturesAndDevicesByProtocolEquipmentIdAndFeatureEndpoint[ key ][ featureName ]
					end
					local endpointId = string_isEmpty(mapping.endpointId) and "none" or mapping.endpointId
					if ( _indexFeaturesAndDevicesFromIdAndFeatureByEndpoint[ endpointId ] == nil ) then
						_indexFeaturesAndDevicesFromIdAndFeatureByEndpoint[ endpointId ] = { feature, {} }
					end
					table.insert( _indexFeaturesAndDevicesFromIdAndFeatureByEndpoint[ endpointId ][ 2 ], mapping.device )
				end
				_indexEquipmentsAndMappingsByDeviceId[ tostring( mapping.device.id ) ] = { equipment, mapping }
			end
		end
	end,

	get = function( protocol, equipmentId, address, endpointId, featureName )
		if not string_isEmpty(protocol) then
			local equipment
			if not string_isEmpty(equipmentId) then
				equipment = _indexEquipmentsByProtocolEquipmentId[ protocol .. ";" .. equipmentId ]
			elseif not string_isEmpty(address) then
				equipment = _indexEquipmentsByProtocolAddress[ protocol .. ";" .. address ]
			end
			if ( ( equipment ~= nil ) and featureName ) then
				local key = tostring(protocol) .. ";" .. tostring(equipment.id)
				local _indexFeaturesAndDevicesFromIdAndFeatureByEndpoint = _indexFeaturesAndDevicesByProtocolEquipmentIdAndFeatureEndpoint[ key ][ tostring(featureName) ]
				if _indexFeaturesAndDevicesFromIdAndFeatureByEndpoint then
					local feature, devices
					if ( endpointId == "all" ) then
						-- Used during broadcast
						-- TODO : get all the endpoints and not just the first for this feature name
						for endpointId, featureAndDevices in pairs(_indexFeaturesAndDevicesFromIdAndFeatureByEndpoint) do
							feature, devices = unpack( featureAndDevices )
							break
						end
					else
						endpointId = string_isEmpty(endpointId) and "none" or endpointId
						feature, devices = unpack( _indexFeaturesAndDevicesFromIdAndFeatureByEndpoint[ endpointId ] or {} )
					end
					if ( feature ~= nil ) then
						return equipment, feature, devices
					end
				end
			end
			return equipment
		else
			return _equipments
		end
	end,

	getFromDeviceId = function( deviceId, noWarningIfUnknown )
		local equipment, mapping = unpack( _indexEquipmentsAndMappingsByDeviceId[ tostring( deviceId ) ] or {} )
		if mapping then
			return equipment, mapping
		elseif ( noWarningIfUnknown ~= true ) then
			warning( "Equipment with deviceId #" .. tostring( deviceId ) .. "' is unknown", "Equipments.getFromDeviceId" )
		end
		return nil
	end,

	changeAddress = function( equipment, newAddress )
		local formerAddress = equipment.address
		debug( "Change address of " .. Tools.getEquipmentSummary(equipment) .. " to " .. tostring(newAddress), "Equipments.changeAddress" )
		for _, mapping in ipairs( equipment.mappings ) do
			Variable.set( mapping.device.id, "ADDRESS", newAddress )
		end
	end
}


-- **************************************************
-- Equipment management
-- **************************************************

Equipment = {
	setStatus = function( equipment, status, parameters )
		parameters = parameters or {}
		local cmd
		if ( tostring(status) == "0" ) then
			cmd = "00"
		elseif ( tostring(status) == "1" ) then
			cmd = "01"
		else
			-- Toogle
			cmd = "02"
		end
		-- TODO : endpoint sur 2 lettres
		Network.send( "0092", "02" .. equipment.id .. "01" .. parameters.endpointId .. cmd )
	end,

	setLoadLevel = function( equipment, loadLevel, parameters )
		Network.send( "0081", "02" .. equipment.id .. "01" .. parameters.endpointId .. cmd )
		--Network.send( "ZIA++DIM " .. equipment.protocol .. " ID " .. equipment.id .. " %" .. tostring(loadLevel) .. qualifier .. burst )
	end


}

-- **************************************************
-- Serial connection
-- **************************************************

SerialConnection = {
	-- Check IO connection
	isValid = function()
		if not luup.io.is_connected( DEVICE_ID ) then
			-- Try to connect by ip (openLuup)
			local ip = luup.attr_get( "ip", DEVICE_ID )
			if not string_isEmpty( ip ~= nil ) then
				local ipaddr, port = string.match( ip, "(.-):(.*)" )
				if ( port == nil ) then
					ipaddr = ip
					port = 80
				end
				log( "Open connection on ip " .. ipaddr .. " and port " .. port, "SerialConnection.isValid" )
				luup.io.open( DEVICE_ID, ipaddr, tonumber( port ) )
			end
		end
		if not luup.io.is_connected( DEVICE_ID ) then
			error( "Serial port not connected. First choose the serial port and restart the lua engine.", "SerialConnection.isValid", false )
			UI.showError( "Choose the Serial Port" )
			return false
		else
			local ioDevice = tonumber(( Variable.get( DEVICE_ID, "IO_DEVICE" ) ))
			if ioDevice then
				-- Check serial settings
				local baudRate = Variable.get( ioDevice, "BAUD" ) or "9600"
				log( "Baud rate is " .. baudRate, "SerialConnection.isValid" )
				if ( baudRate ~= _SERIAL.baudRate ) then
					error( "Incorrect setup of the serial port. Select " .. _SERIAL.baudRate .. " bauds.", "SerialConnection.isValid", false )
					UI.showError( "Select " .. _SERIAL.baudRate .. " bauds for the Serial Port" )
					return false
				end
				

				-- TODO : Check Parity none / Data bits 8 / Stop bit 1
			end
		end
		log( "Serial port is connected", "SerialConnection.isValid" )
		return true
	end
}


-- **************************************************
-- HTTP request handler
-- **************************************************

local REQUEST_TYPE = {
	["default"] = function( params, outputFormat )
		return "Unknown command '" .. tostring( params["command"] ) .. "'", "text/plain"
	end,

	["getEquipmentsInfos"] = function( params, outputFormat )
		result = { equipments = Equipments.get(), discoveredEquipments = DiscoveredEquipments.get() }
		return tostring( json.encode( result ) ), "application/json"
	end,

	["getSettings"] = function( params, outputFormat )
		return tostring( json.encode( SETTINGS ) ), "application/json"
	end,

	["getErrors"] = function( params, outputFormat )
		return tostring( json.encode( _errors ) ), "application/json"
	end
}
setmetatable( REQUEST_TYPE, {
	__index = function( t, command, outputFormat )
		log( "No handler for command '" ..  tostring(command) .. "'", "handler" )
		return REQUEST_TYPE["default"]
	end
})

local function _handleRequest( lul_request, lul_parameters, lul_outputformat )
	local command = lul_parameters["command"] or "default"
	--debug( "Get handler for command '" .. tostring(command) .."'", "handleRequest" )
	return REQUEST_TYPE[command]( lul_parameters, lul_outputformat )
end


-- **************************************************
-- Action implementations for childs
-- **************************************************

Child = {

	setTarget = function( childDeviceId, newTargetValue )
		if not Equipments.getFromDeviceId( childDeviceId ) then
			error( "Device #" .. tostring( childDeviceId ) .. " is not linked to an equipment", "Child.setTarget" )
			return JOB_STATUS.ERROR
		end
		Device.setStatus( childDeviceId, newTargetValue )
		return JOB_STATUS.DONE
	end,

	setLoadLevelTarget = function( childDeviceId, newLoadlevelTarget )
		if not Equipments.getFromDeviceId( childDeviceId ) then
			error( "Device #" .. tostring( childDeviceId ) .. " is not linked to an equipment", "Child.setLoadLevelTarget" )
			return JOB_STATUS.ERROR
		end
		Device.setLoadLevel( childDeviceId, newLoadlevelTarget )
		return JOB_STATUS.DONE
	end,

	setArmed = function( childDeviceId, newArmedValue )
		if not Equipments.getFromDeviceId( childDeviceId ) then
			error( "Device #" .. tostring( childDeviceId ) .. " is not linked to an equipment", "Child.setArmed" )
			return JOB_STATUS.ERROR
		end
		Device.setArmed( childDeviceId, newArmedValue or "0" )
		return JOB_STATUS.DONE
	end,

	moveShutter = function( childDeviceId, direction )
		if not Equipments.getFromDeviceId( childDeviceId ) then
			error( "Device #" .. tostring( childDeviceId ) .. " is not linked to an equipment", "Child.moveShutter" )
			return JOB_STATUS.ERROR
		end
		Device.moveShutter( childDeviceId, direction )
		return JOB_STATUS.DONE
	end,

	setModeStatus = function( childDeviceId, newModeStatus, option )
		if not Equipments.getFromDeviceId( childDeviceId ) then
			error( "Device #" .. tostring( childDeviceId ) .. " is not linked to an equipment", "Child.setModeStatus" )
			return JOB_STATUS.ERROR
		end
		Device.setModeStatus( childDeviceId, newModeStatus, option )
		return JOB_STATUS.DONE
	end,

	setSetPoint = function( childDeviceId, newSetpoint, option )
		if not Equipments.getFromDeviceId( childDeviceId ) then
			error( "Device #" .. tostring( childDeviceId ) .. " is linked to an equipment", "Child.setCurrentSetPoint" )
			return JOB_STATUS.ERROR
		end
		Device.setSetPoint( childDeviceId, newSetpoint, option )
		return JOB_STATUS.DONE
	end

}


-- **************************************************
-- Main action implementations
-- **************************************************

Main = {

	startJob = function( method, ... )
		local isOk = Tools.pcall( method, ... )
		return isOk and JOB_STATUS.DONE or JOB_STATUS.ERROR
	end,

	refresh = function()
		debug( "Refresh equipments", "Main.refresh" )
		Equipments.retrieve()
	end,

	-- Creates devices linked to equipements
	createDevices = function( jsonMappings )
		local decodeSuccess, mappings, _, jsonError = pcall( json.decode, string_decodeURI(jsonMappings) )
		if ( decodeSuccess and mappings ) then
			debug( "Create devices " .. json.encode(mappings), "Main.createDevices" )
		else
			error( "JSON error: " .. tostring( jsonError ), "Main.createDevices" )
			return
		end
		local hasBeenCreated = false
		local roomId = luup.devices[ DEVICE_ID ].room_num or 0
		for _, mapping in ipairs( mappings ) do
			if ( string_isEmpty( mapping.protocol ) or string_isEmpty( mapping.equipmentId ) or string_isEmpty( mapping.deviceType ) ) then
				error( "'protocol', 'equipmentId' or 'deviceType' can not be empty in " .. json.encode(mapping), "Main.createDevices" )
			else
				local msg = "Equipment " .. Tools.getEquipmentInfo( mapping.protocol, mapping.equipmentId, mapping.address, mapping.endpointId, mapping.featureNames )
				local deviceInfos = Device.getInfos( mapping.deviceType or "BINARY_LIGHT" )
				if not deviceInfos then
					error( msg .. " - Device infos are missing", "Main.createDevices" )
				elseif not Device.fileExists( deviceInfos ) then
					error( msg .. " - Definition file for device type '" .. deviceInfos.name .. "' is missing", "Main.createDevices" )
				else
					-- Compute device number (critical)
					local deviceNum = 1
					local equipment = Equipments.get( mapping.protocol, mapping.equipmentId )
					if equipment then
						debug( msg .. " already exists", "Main.createDevices" )
						deviceNum = equipment.maxDeviceNum + 1
					end
					-- Device name
					local deviceName = mapping.deviceName or ( mapping.protocol .. "-" .. mapping.equipmentId .. "/" .. tostring(deviceNum) )
					-- Device parameters
					local parameters = Device.getEncodedParameters( deviceInfos )
					parameters = parameters .. Variable.getEncodedValue( "ADDRESS", mapping.address ) .. "\n"
					parameters = parameters .. Variable.getEncodedValue( "ENDPOINT", mapping.endpointId ) .. "\n"
					parameters = parameters .. Variable.getEncodedValue( "FEATURE", table.concat( mapping.featureNames or {}, "," ) ) .. "\n"
					parameters = parameters .. Variable.getEncodedValue( "ASSOCIATION", "" ) .. "\n"
					parameters = parameters .. Variable.getEncodedValue( "SETTING", table.concat( mapping.settings or {}, "," ) ) .. "\n"
					if deviceInfos.category then
						parameters = parameters .. ",category_num=" .. tostring(deviceInfos.category) .. "\n"
					end
					if deviceInfos.subCategory then
						parameters = parameters .. ",subcategory_num=" .. tostring(deviceInfos.subCategory) .. "\n"
					end
					--[[
					if ( mapping.isBatteryPowered ) then -- TODO
						parameters = parameters .. Variable.getEncodedValue( "BATTERY_LEVEL", "" ) .. "=\n"
					end
					--]]
					-- Add new device in the home automation controller
					local internalId = mapping.protocol .. ";" .. mapping.equipmentId .. ";" .. tostring(deviceNum)
					debug( msg .. " - Add device '" .. internalId .. "', type '" .. deviceInfos.name .. "', file '" .. deviceInfos.file .. "'", "Main.createDevices" )
					local newDeviceId = luup.create_device(
						'', -- device_type
						internalId,
						deviceName,
						deviceInfos.file,
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
					debug( msg .. " - Device #" .. tostring(newDeviceId) .. "(" .. deviceName .. ") has been created", "Main.createDevices" )
					hasBeenCreated = true

					-- Add or update linked equipment
					Equipments.add( mapping.protocol, mapping.equipmentId, mapping.address, mapping.endpointId, mapping.featureNames or {}, deviceNum, nil, newDeviceId, roomId, nil, nil, true )
					-- Remove from discovered equipments
					DiscoveredEquipments.remove( mapping.protocol, mapping.equipmentId )
				end
			end
		end

		if hasBeenCreated then
			Equipments.retrieve()
			Variable.set( DEVICE_ID, "LAST_UPDATE", os.time() )
		end

	end,

	-- Start inclusion (permit joining) during 30 seconds
	startInclusion = function()
		debug( "Permit joining during 30 secondes", "Main.startInclusion" )
		Network.send( "0049", "FFFC1E" ); -- FFFC = mask, 1E = 30 seconds
	end,

	setParam = function( paramName, paramValue )
		debug( "Set param '" .. tostring(paramName) .. "' to '" .. tostring(paramValue) .. "'", "Main.setParam" )
		-- TODO
	end,

	-- DEBUG METHOD
	sendMessage = function( msgType, data )
		debug( "Send message - type:" .. tostring(msgType) .. ", data:" .. tostring(data), "Main.sendMessage" )
		Network.send( msgType, data )
	end

}


-- **************************************************
-- Startup
-- **************************************************

-- Init plugin instance
local function _initPluginInstance()
	log( "Init", "initPluginInstance" )

	-- Update the Debug Mode
	debugMode = ( Variable.getOrInit( DEVICE_ID, "DEBUG_MODE", "0" ) == "1" ) and true or false
	if debugMode then
		log( "DebugMode is enabled", "init" )
		debug = log
	else
		log( "DebugMode is disabled", "init" )
		debug = function() end
	end

	Variable.set( DEVICE_ID, "PLUGIN_VERSION", _VERSION )
	Variable.set( DEVICE_ID, "LAST_UPDATE", os.time() )
	Variable.set( DEVICE_ID, "LAST_MESSAGE", "" )
	Variable.getOrInit( DEVICE_ID, "LAST_DISCOVERED", "" )
end

-- Register with ALTUI once it is ready
local function _registerWithALTUI()
	for deviceId, luDevice in pairs( luup.devices ) do
		if ( luDevice.device_type == "urn:schemas-upnp-org:device:altui:1" ) then
			if luup.is_ready( deviceId ) then
				log( "Register with ALTUI main device #" .. tostring( deviceId ), "registerWithALTUI" )
				luup.call_action(
					"urn:upnp-org:serviceId:altui1",
					"RegisterPlugin",
					{
						newDeviceType = "urn:schemas-upnp-org:device:" .. _NAME .. ":1",
						newScriptFile = "J_" .. _NAME .. "1.js",
						newDeviceDrawFunc = _NAME .. ".ALTUI_drawDevice"
					},
					deviceId
				)
			else
				log( "ALTUI main device #" .. tostring( deviceId ) .. " is not yet ready, retry to register in 10 seconds...", "registerWithALTUI" )
				luup.call_delay( _NAME .. ".registerWithALTUI", 10 )
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

	--if ( type( json ) == "string" ) then
	if not hasJson then
		UI.showError( "No JSON decoder" )
	elseif SerialConnection.isValid() then
		-- Get the list of the child devices
		Equipments.retrieve()

		-- Get ZiGate version
		Network.send( "0010", "" )
		-- Start ZigBee network
		Network.send( "0024", "" )
		-- Start polling engine
		-- TODO enchainer en attendant les réponses
		--PollEngine.start()
	end

	-- Watch setting changes
	Variable.watch( DEVICE_ID, VARIABLE.DEBUG_MODE, _NAME .. ".initPluginInstance" )

	-- HTTP requests handler
	log( "Register handler " .. _NAME, "init" )
	luup.register_handler( _NAME .. ".handleRequest", _NAME )

	-- Register with ALTUI
	luup.call_delay( _NAME .. ".registerWithALTUI", 10 )

	if ( luup.version_major >= 7 ) then
		luup.set_failure( 0, DEVICE_ID )
	end

	log( "Startup successful", "init" )
	return true, "Startup successful", _NAME
end


-- Promote the functions used by Vera's luup.xxx functions to the global name space
_G[_NAME .. ".handleRequest"] = _handleRequest
_G[_NAME .. ".Commands.deferredProcess"] = Commands.deferredProcess
_G[_NAME .. ".Device.setStatusAfterTimeout"] = Device.setStatusAfterTimeout
_G[_NAME .. ".Device.setTrippedAfterTimeout"] = Device.setTrippedAfterTimeout
_G[_NAME .. ".Network.send"] = Network.send
_G[_NAME .. ".PollEngine.poll"] = PollEngine.poll

_G[_NAME .. ".initPluginInstance"] = _initPluginInstance
_G[_NAME .. ".registerWithALTUI"] = _registerWithALTUI
