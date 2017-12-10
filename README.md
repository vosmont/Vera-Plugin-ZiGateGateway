# <img align="left" src="media/zigate_gateway_logo.png"> Vera-Plugin-ZiGateGateway

**Control your ZigBee devices from your Vera**

<br/>

Designed for [Vera Control, Ltd.](http://getvera.com) Home Controllers (UI7) and [openLuup](https://github.com/akbooer/openLuup).


## Introduction

This plugin is a gateway to [ZiGate](http://zigate.fr), and brings compatibility with the ZigBee network.

The plugin creates new devices (switches, dimmers, sensors, ...) in your Vera corresponding to your ZigBee network.
These devices appear in the User Interface as the others (e.g. Z-wave devices) and can be used in scenes.

For specific manipulations (settings, association), the plugin has its own User Interface.


## Requirements

Plug the ZiGate USB dongle into an Vera's USB port.


## Installation

#### Get the plugin
- Mios Marketplace

  This plugin is not available on the Mios Marketplace for the moment. This could change if Vera Control, Ltd. makes it more "developper friendly".

- Alternate App Store on ALTUI

- Github
  
  Upload the files in "luup files" in the Vera (by the standard UI in "Apps-->Develop Apps-->Luup files").
  
  Create a new device in "Apps-->Develop Apps-->Create device", and set "Upnp Device Filename" to "D_ZiGateGateway1.xml".

#### Set the serial connection on legacy Vera

Assign the serial port of the dongle to the plugin : go to "Apps/Develop Apps/Serial Port Configuration" and select from "Used by device" drop down list the "Edisio Gateway".
Set the following parameters :

```
Baud Rate : 9600
Data bits : 8
Parity    : none
Stop bits : 1
```

You will certainly need to set the baud parameter on another value, save, and then on 9600. It seems that default values are not saved

#### Set the serial connection on openLuup

TODO

## Add your ZigBee devices

TODO

## Association

You can define a link between your ZigBee device and another device in your Vera. It allows you to bind devices without having to use scenes.

From the tab "Devices" in the plugin, click on the action "Associate" of the device you wish to link.
Then select the compatible devices and validate.

Association means that changes on the edisio device will be passed on the associated device (e.g. if the ZigBee device is switched on, the associated device is switched on too).


## Logs

You can control your rules execution in the logs. Just set the variable "DebugMode" to 1.
Then in a ssh terminal :

- on legacy Vera :
```
tail -f /var/log/cmh/LuaUPnP.log | grep "^01\|ZiGateGateway"
```

- on openLuup :
```
tail -F {openLuup folder}/cmh-ludl/logs/LuaUPnP.log | grep "ERROR\|ZiGateGateway"
```
