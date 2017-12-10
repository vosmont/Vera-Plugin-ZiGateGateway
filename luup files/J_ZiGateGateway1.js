//# sourceURL=J_ZiGateGateway1.js

/**
 * This file is part of the plugin ZiGateGateway.
 * https://github.com/vosmont/Vera-Plugin-ZiGateGateway
 * Copyright (c) 2017 Vincent OSMONT
 * This code is released under the MIT License, see LICENSE.
 */


/**
 * UI7 enhancement
 */
( function( $ ) {
	// UI7 fix
	Utils.getDataRequestURL = function() {
		var dataRequestURL = api.getDataRequestURL();
		if ( dataRequestURL.indexOf( "?" ) === -1 ) {
			dataRequestURL += "?";
		}
		return dataRequestURL;
	};
	Utils.performActionOnDevice = function( deviceId, service, action, actionArguments ) {
		var d = $.Deferred();
		try {
			if ( $.isPlainObject( actionArguments ) ) {
				$.each( actionArguments, function( key, value ) {
					if ( !value ) {
						delete actionArguments[ key ];
					}
				});
			}
			api.performActionOnDevice( deviceId, service, action, {
				actionArguments: actionArguments,
				onSuccess: function( response ) {
					var result;
					try {
						result = JSON.parse( response.responseText );
					} catch( err ) {
					}
					if ( !$.isPlainObject( result )
						|| !$.isPlainObject( result[ "u:" + action + "Response" ] )
						|| (
							( result[ "u:" + action + "Response" ].OK !== "OK" )
							&& ( typeof( result[ "u:" + action + "Response" ].JobID ) === "undefined" )
						)
					) {
						Utils.logError( "[Utils.performActionOnDevice] ERROR on action '" + action + "': " + response.responseText );
						d.reject();
					} else {
						d.resolve();
					}
				},
				onFailure: function( response ) {
					Utils.logDebug( "[Utils.performActionOnDevice] ERROR(" + response.status + "): " + response.responseText );
					d.reject();
				}
			} );
		} catch( err ) {
			Utils.logError( "[Utils.performActionOnDevice] ERROR: " + JSON.parse( err ) );
			d.reject();
		}
		return d.promise();
	};
	Utils.setDeviceStateVariablePersistent = function( deviceId, service, variable, value ) {
		var d = $.Deferred();
		api.setDeviceStateVariablePersistent( deviceId, service, variable, value, {
			onSuccess: function() {
				d.resolve();
			},
			onFailure: function() {
				Utils.logDebug( "[Utils.setDeviceStateVariablePersistent] ERROR" );
				d.reject();
			}
		});
		return d.promise();
	};

	function getQueryStringValue( key ) {  
		return unescape(window.location.search.replace(new RegExp("^(?:.*[&\\?]" + escape(key).replace(/[\.\+\*]/g, "\\$&") + "(?:\\=([^&]*))?)?.*$", "i"), "$1"));  
	}
	Utils.getLanguage = function() {
		var language = getQueryStringValue( "lang_code" ) || getQueryStringValue( "lang" ) || window.navigator.userLanguage || window.navigator.language;
		return language.substring( 0, 2 );
	};

	Utils.initTokens = function( tokens ) {
		if ( window.Localization ) {
			window.Localization.init( tokens );
		} else if ( window.langJson ) {
			window.langJson.Tokens = $.extend( window.langJson.Tokens, tokens );
		}
	};

	var _resourceLoaded = {};
	Utils.loadResourcesAsync = function( fileNames ) {
		var d = $.Deferred();
		if ( typeof fileNames === 'string' ) {
			fileNames = [ fileNames ];
		}
		if ( !$.isArray( fileNames ) ) {
			return;
		}
		// Prepare loaders
		var loaders = [];
		$.each( fileNames, function( index, fileName ) {
			var parts = fileName.split(";");
			var name = parts[0].trim();
			var fileName = ( parts[1] ? parts[1] : parts[0] ).trim();
			if ( fileName.indexOf( "/" ) !== 0 ) {
				// Local file on the Vera
				fileName = api.getDataRequestURL().replace( "/data_request", "/" ) + fileName;
			}
			if ( !_resourceLoaded[ name ] ) {
				var parts = name.split(".");
				switch( parts.pop() ) {
					case 'css':
						var cssLink = $( "<link rel='stylesheet' type='text/css' href='" + fileName + "'>" );
						$( "head" ).append( cssLink );
						_resourceLoaded[ name ] = true;
						break;
					case 'js':
						loaders.push(
							$.ajax( {
								url: fileName,
								dataType: "script",
								beforeSend: function( jqXHR, settings ) {
									jqXHR.name = name;
								}
							} )
						);
				}
			}
		} );
		// Execute loaders
		$.when.apply( $, loaders )
			.done( function( xml, textStatus, jqxhr ) {
				if (loaders.length === 1) {
					_resourceLoaded[ jqxhr.name ] = true;
				} else if (loaders.length > 1) {
					// arguments : [ [ xml, textStatus, jqxhr ], ... ]
					for (var i = 0; i < arguments.length; i++) {
						jqxhr = arguments[ i ][ 2 ];
						_resourceLoaded[ jqxhr.name ] = true;
					}
				}
				d.resolve();
			} )
			.fail( function( jqxhr, textStatus, errorThrown  ) {
				Utils.logError( 'Load "' + jqxhr.name + '" : ' + textStatus + ' - ' + errorThrown );
				d.reject();
			} );
		return d.promise();
	};

	if ( !String.prototype.format ) {
		String.prototype.format = function() {
			var content = this;
			for (var i=0; i < arguments.length; i++) {
				var replacement = new RegExp('\\{' + i + '\\}', 'g');
				content = content.replace(replacement, arguments[i]);  
			}
			return content;
		};
	}

} ) ( jQuery );


/**
 * ALTUI fixes
 */
( function( $ ) {
	if ( window.Localization ) {
		Utils.getLangString = function( token, defaultValue ) { return _T(token) || defaultValue; };
	}
} ) ( jQuery );


/**
 * Plugin
 */
var ZiGateGateway = ( function( api, $ ) {
	var _prefix = "zigate";
	var _pluginName = "ZiGateGateway";
	var _uuid = "c434706c-ddfd-404c-bd50-8bd35e05d6ab";
	var PLUGIN_SID = "urn:upnp-org:serviceId:ZiGateGateway1";
	var PLUGIN_CHILD_SID = "urn:upnp-org:serviceId:ZiGateDevice1";
	var _deviceId = null;
	var _lastUpdate = 0;
	var _indexFeatures = {}, _indexDevices = {};
	var _selectedProductId = "";
	var _selectedFeatureName = "";
	var _formerScrollTopPosition = 0;
	var _devicesTimeout, _discoveredDevicesTimeout;
	var _devicesLastRefresh = 0, _discoveredDevicesLastRefresh = 0;

	/**
	 * Resources
	 */
	function _loadResourcesAsync() {
		var resources = [ 'J_' + _pluginName + '1.css' ];
		if ( $( 'link[rel="stylesheet"][href*="font-awesome"]' ).length === 0 ) {
			resources.push( 'font-awesome.css;//maxcdn.bootstrapcdn.com/font-awesome/4.7.0/css/font-awesome.min.css' );
		}
		return Utils.loadResourcesAsync( resources )
	}

	/**
	 * Localization
	 */
	function _loadLocalizationAsync() {
		var d = $.Deferred();
		Utils.loadResourcesAsync( 'J_' + _pluginName + '1_loc_' + Utils.getLanguage() + '.js' )
			.done( function() {
				d.resolve();
			})
			.fail( function() {
				if ( Utils.getLanguage() !== 'en' ) {
					// Fallback
					Utils.loadResourcesAsync( 'J_' + _pluginName + '1_loc_en.js' )
						.done( function() {
							d.resolve();
						});
				} else {
					d.reject();
				}
			});
		return d.promise();
	}

	/**
	 * Get informations on external devices
	 */
	function _getDevicesInfosAsync() {
		var d = $.Deferred();
		$.ajax( {
			url: Utils.getDataRequestURL() + "id=lr_" + _pluginName + "&command=getDevicesInfos&output_format=json#",
			dataType: "json"
		} )
		.done( function( devicesInfos ) {
			if ( $.isPlainObject( devicesInfos ) ) {
				d.resolve( devicesInfos );
			} else {
				Utils.logError( "No devices infos" );
				d.reject();
			}
		} )
		.fail( function( jqxhr, textStatus, errorThrown ) {
			Utils.logError( "Get " + _pluginName + " devices infos error : " + errorThrown );
			d.reject();
		} );
		return d.promise();
	}

	/**
	 * Convert timestamp to locale string
	 */
	function _convertTimestampToLocaleString( timestamp ) {
		if ( typeof( timestamp ) === "undefined" ) {
			return "";
		}
		var t = new Date( parseInt( timestamp, 10 ) * 1000 );
		var localeString = t.toLocaleString();
		return localeString;
	}

	function _showReload( message, onSuccess ) {
		var html = '<div id="' + _prefix + '-reload">'
			+			( message ? '<div>' + message + '</div>' : '' )
			+			'<div>' + Utils.getLangString( _prefix + "_reload_has_to_be_done" ) + '</div>'
			+			'<div>'
			+				'<button type="button" class="' + _prefix + '-reload">Reload Luup engine</button>'
			+			'</div>'
			+		'</div>';
		api.ui.showMessagePopup( html, 0, 0, { onSuccess: onSuccess } );

		$( "#" + _prefix + "-reload" ).click( function() {
			$.when( api.luReload() )
				.done( function() {
					$( "#" + _prefix + "-reload" ).css({ "display": "none" });
				});
			$( this ).prop( "disabled", true );
		});
	}

	/**
	 * Settings
	 */

	function _getSettingHtml( setting ) {
		var className = _prefix + "-setting-value" + ( setting.className ? " " + setting.className : "" );
		var html = '<div class="' + _prefix + '-setting ui-widget-content ui-corner-all">'
			+			'<span>' + setting.name + '</span>';
		if ( setting.type == "checkbox" ) {
			html += '<input type="checkbox"'
				+		( ( setting.value === true ) ? ' checked="checked"' : '' )
				+		( ( setting.isReadOnly === true ) ? ' disabled="disabled"' : '' )
				+		' class="' + className + '" data-setting="' + setting.variable  + '">';
		} else if ( setting.type == "string" ) {
			var value = ( setting.value ? setting.value : ( setting.defaultValue ? setting.defaultValue : '' ) );
			html +=	'<input type="text" value="' + value + '" class="' + className + '" data-setting="' + setting.variable  + '">';
		} else if ( setting.type == "select" ) {
			html +=	'<select class="' + className + '" data-setting="' + setting.variable + '">';
			$.each( setting.values, function( i, value ) {
				var isSelected = false;
				if ( typeof setting.value === "string" ) {
					if ( value === setting.value ) {
						isSelected = true;
					}
				} else if ( i === 0 ) {
					isSelected = true;
				}
				html +=	'<option value="' + value + '"' + ( isSelected ? ' selected' : '' ) + '>' + value + '</option>';
			} );
			html +=	'</select>';
		}
		html +=	'</div>';
		return html;
	}

	// *************************************************************************************************
	// External devices
	// *************************************************************************************************

	function _stopDevicesRefresh() {
		if ( _devicesTimeout ) {
			window.clearTimeout( _devicesTimeout );
		}
		_devicesTimeout = null;
	}
	function _resumeDevicesRefresh() {
		if ( _devicesTimeout == null ) {
			var timeout = 3000 - ( Date.now() - _devicesLastRefresh );
			if ( timeout < 0 ) {
				timeout = 0;
			}
			_devicesTimeout = window.setTimeout( _drawDevicesList, timeout );
		}
	}

	function _getAssociationHtml( associationType, association, level ) {
		if ( association && ( association[ level ].length > 0 ) ) {
			var pressType = "short";
			if ( level === 1 ) {
				pressType = "long";
			}
			return	'<span class="' + _prefix + '-association ' + _prefix + '-association-' + associationType + '" title="' + associationType + ' associated with ' + pressType + ' press">'
				+		'<span class="ziblue-' + pressType + '-press">'
				+			association[ level ].join( "," )
				+		'</span>'
				+	'</span>';
		}
		return "";
	}

	/**
	 * Draw and manage external device list
	 */
	function _drawDevicesList() {
		_stopDevicesRefresh();
		if ( $( "#" + _prefix + "-known-devices" ).length === 0 ) {
			return;
		}
		_indexFeatures = {}; _indexDevices = {};
		$.when( _getDevicesInfosAsync() )
			.done( function( devicesInfos ) {
				if ( devicesInfos.devices.length > 0 ) {
					$.each( devicesInfos.devices, function( i, device ) {
						var room = api.getRoomObject( device.mainRoomId );
						device.roomName = room ? room.name : 'unknown';
					});
					// Sort the devices by room / name
					devicesInfos.devices.sort( function( a, b ) {
						if ( a.protocol === b.protocol ) {
							var x = a.roomName.toLowerCase(), y = b.roomName.toLowerCase();
							return x < y ? -1 : x > y ? 1 : 0;
						}
						return a.protocol < b.protocol ? -1 : a.protocol > b.protocol ? 1 : 0;
					});
					
					var html =	'<table><tr>'
						+			'<th>' + Utils.getLangString( _prefix + "_room" ) + '</th>'
						+			'<th>' + Utils.getLangString( _prefix + "_address" ) + '</th>'
						+			'<th>' + Utils.getLangString( _prefix + "_endpoint" ) + '</th>'
						+			'<th>' + Utils.getLangString( _prefix + "_signal_quality" ) + '</th>'
						+			'<th>' + Utils.getLangString( _prefix + "_last_update" ) + '</th>'
						+			'<th>' + Utils.getLangString( _prefix + "_feature" ) + '</th>'
						+			'<th>' + Utils.getLangString( _prefix + "_device" ) + '</th>'
						+			'<th>' + Utils.getLangString( _prefix + "_association" ) + '</th>'
						+			'<th>' + Utils.getLangString( _prefix + "_action" ) + '</th>'
						+		'</tr>';
					$.each( devicesInfos.devices, function( i, device ) {
						var rowSpan = ( device.features.length > 1 ? ' rowspan="' + device.features.length + '"' : '' );
						html += '<tr>'
							+		'<td class="' + _prefix + '-room-name"' + rowSpan + '>' + device.roomName + '</td>'
							+		'<td class="' + _prefix + '-address"' + rowSpan + '>' + device.address + '</td>'
							+		'<td' + rowSpan + '>' + device.endPoint + '</td>'
							+		'<td' + rowSpan + '>' + ( device.quality >= 0 ? device.quality : '' ) + '</td>'
							+		'<td' + rowSpan + '>' + _convertTimestampToLocaleString( device.lastUpdate ) + '</td>';
						var isFirstRow = true;

						device.features.sort( function( a, b ) {
							if ( a.deviceName < b.deviceName ) {
								return -1;
							} else if ( a.deviceName > b.deviceName ) {
								return 1;
							}
							return 0;
						});

						var countDevices = {};
						$.each( device.features, function( i, feature ) {
							countDevices[ feature.deviceId.toString() ] = countDevices[ feature.deviceId.toString() ]  != null ? countDevices[ feature.deviceId.toString() ] + 1 : 1;
						});

						var lastDeviceId = -1;
						var deviceRowSpan = '1';
						$.each( device.features, function( i, feature ) {
							var productId = device.address + ';' + device.endPoint;
							_indexFeatures[ productId + ';' + feature.name ] = feature;
							_indexDevices[ feature.deviceId.toString() ] = device.protocol;
							if ( !feature.settings ) {
								feature.settings = {};
							}
							/*feature.settings = {};
							$.each( ( api.getDeviceStateVariable( feature.deviceId, PLUGIN_CHILD_SID, "Setting", { dynamic: false } ) || "" ).split( "," ), function( i, settingName ) {
								feature.settings[ settingName ] = true;
							} );*/
							if ( !isFirstRow ) {
								html += '<tr>';
							}
							html +=	'<td>'
								+		'<div class="' + _prefix + '-feature-name">' + feature.name + '</div>'
								+		( feature.data ? '<div class="' + _prefix + '-feature-data">' + feature.data + '</div>' : '' )
								+	'</td>';

							if ( feature.deviceId != lastDeviceId ) {
								lastDeviceId = feature.deviceId;
								deviceRowSpan = ' rowspan="' + countDevices[ feature.deviceId.toString() ] + '"';
								html +=	'<td' + deviceRowSpan +'>'
									//+			'<div class="' + _prefix + '-device-type">'
									+		'<div><span class="' + _prefix + '-device-name">' + feature.deviceName + '</span> (#' + feature.deviceId + ')</div>'
									+		'<div>'
									+				Utils.getLangString( feature.deviceTypeName )
									+				( device.isNew ? ' <span style="color:red">NEW</span>' : '' )
									+				( feature.settings.pulse ? ' PULSE' : '' )
									+				( feature.settings.toggle ? ' TOGGLE' : '' )
									+		'</div>'
									//+		'</div>'
									+	'</td>'
									+	'<td' + deviceRowSpan +'>'
									+		_getAssociationHtml( "device", feature.association.devices, 0 )
									//+		_getAssociationHtml( "device", feature.association.devices, 1 )
									+		_getAssociationHtml( "scene", feature.association.scenes, 0 )
									//+		_getAssociationHtml( "scene", feature.association.scenes, 1 )
									+		_getAssociationHtml( "ziblue-device", feature.association.ziGateDevices, 0 )
									+	'</td' + deviceRowSpan +'>'
									+	'<td' + deviceRowSpan +' align="center">'
									//+		( !device.isNew && ( feature.settings.button || feature.settings.receiver ) ?
									+		( !device.isNew ?
												'<i class="' + _prefix + '-actions fa fa-caret-down fa-lg" aria-hidden="true" data-product-id="' + productId + '" data-feature-name="' + feature.name + '"></i>'
												: '' )
									+	'</td>';
							}
							html +=	'</tr>';
							isFirstRow = false;
						} );
					});
					html += '</table>';
					$("#" + _prefix + "-known-devices").html( html );
				} else {
					$("#" + _prefix + "-known-devices").html( Utils.getLangString( _prefix + "_no_device" ) );
				}
				_devicesLastRefresh = Date.now();
				_resumeDevicesRefresh();
			} );
	}

	/**
	 * Show the actions that can be done on an external device
	 */
	function _showDeviceActions( position, settings ) {
		_stopDevicesRefresh();
		var html = '<table>'
				+		'<tr>'
				+			'<td>'
				+				( settings.button ?
								'<button type="button" class="' + _prefix + '-show-association">Associate</button>'
								: '')
				+				'<button type="button" class="' + _prefix + '-show-params">Params</button>'
				+			'</td>';
		/*
		if ( settings.receiver ) {
			html +=			'<td bgcolor="#FF0000">'
				+				'<button type="button" class="' + _prefix + '-teach">Teach in</button>'
				//+				'<button type="button" class="' + _prefix + '-clear">Clear</button>'
				+			'</td>';
		}
		*/
		html +=			'</tr>'
			+		'</table>';
		var $actions = $( "#" + _prefix + "-device-actions" );
		$actions
			.html( html )
			.css( {
				"display": "block",
				"left": ( position.left - $actions.width() + 5 ),
				"top": ( position.top - $actions.height() / 2 )
			} );
	}

	/**
	 * Show all devices and scene that can be associated and manage associations
	 */
	function _showDeviceAssociation( productId, feature ) {
		_stopDevicesRefresh();
		var html = '<h1>' + Utils.getLangString( _prefix + "_association" ) + '</h1>'
				+	'<h3>' + productId + ' - ' + feature.name + ' - ' + feature.deviceName + ' (#' + feature.deviceId + ')</h3>'
				+	'<div class="scenes_section_delimiter"></div>'
				+	'<div class="' + _prefix + '-toolbar">'
				+		'<button type="button" class="' + _prefix + '-help"><i class="fa fa-question fa-lg text-info" aria-hidden="true"></i>&nbsp;' + Utils.getLangString( _prefix + "_help" ) + '</button>'
				+	'</div>'
				+	'<div class="' + _prefix + '-explanation ' + _prefix + '-hidden">'
				+		Utils.getLangString( _prefix + "_explanation_association" )
				+	'</div>';

		// Get compatible devices
		var protocol = _indexDevices[ feature.deviceId.toString() ];
		var devices = [];
		$.each( api.getListOfDevices(), function( i, device ) {
			if ( device.id == feature.deviceId ) {
				return;
			}
			// Check if device is an external device
			var isExternal = false;
			if ( device.id_parent === _deviceId ) {
				if ( _indexDevices[ device.id.toString() ] == protocol ) {
					isExternal = true;
				}
			}
			// Check if device is compatible
			var isCompatible = false;
			for ( var j = 0; j < device.states.length; j++ ) {
				if ( ( device.states[j].service === SWP_SID ) || ( device.states[j].service === SWD_SID ) ) {
					// Device can be switched or dimmed
					isCompatible = true;
					break;
				}
			}
			if ( !isExternal && !isCompatible ) {
				return;
			}
			
			var room = ( device.room ? api.getRoomObject( device.room ) : null );
			if ( isExternal ) {
				devices.push( {
					"id": device.id,
					"roomName": ( room ? room.name : "_No room" ),
					"name": "(ZiGate) " + device.name,
					"type": 3,
					"isExternal": isExternal
				} );
			} else {
				devices.push( {
					"id": device.id,
					"roomName": ( room ? room.name : "_No room" ),
					"name": device.name,
					"type": 2,
					"isExternal": isExternal
				} );
			}
		} );
		// Get scenes
		$.each( jsonp.ud.scenes, function( i, scene ) {
			var room = ( scene.room ? api.getRoomObject( scene.room ) : null );
			devices.push( {
				"id": scene.id,
				"roomName": ( room ? room.name : "_No room" ),
				"name": "(Scene) " + scene.name,
				"type": 1
			} );
		} );

		// Sort devices/scenes by Room/Type/name
		devices.sort( function( d1, d2 ) {
			var r1 = d1.roomName.toLowerCase();
			var r2 = d2.roomName.toLowerCase();
			if (r1 < r2) return -1;
			if (r1 > r2) return 1;
			var n1 = d1.name.toLowerCase();
			var n2 = d2.name.toLowerCase();
			if (n1 < n2) return -1;
			if (n1 > n2) return 1;
			return 0;
		} );

		function _getCheckboxHtml( deviceId, association, level ) {
			var pressType = "short";
			if ( level === 1 ) {
				pressType = "long";
			}
			return	'<span class="ziblue-' + pressType + '-press" title="' + pressType + ' press">'
				+		'<input type="checkbox"' + ( association && ( $.inArray( parseInt( deviceId, 10 ), association[level] ) > -1 ) ? ' checked="checked"' : '' ) + '>'
				+	'</span>';
		}

		var currentRoomName = "";
		$.each( devices, function( i, device ) {
			if ( device.roomName !== currentRoomName ) {
				currentRoomName = device.roomName;
				html += '<div class="' + _prefix + '-association-room">' +  device.roomName + '</div>';
			}
			if ( device.type === 1 ) {
				// Scene
				html += '<div class="' + _prefix + '-association ' + _prefix + '-association-scene" data-scene-id="' + device.id + '">'
					+		'<label>'
					+			_getCheckboxHtml( device.id, feature.association.scenes, 0 )
					//+			_getCheckboxHtml( device.id, feature.association.scenes, 1 )
					+			'&nbsp;' + device.name + ' (#' + device.id + ')'
					+		'</label>'
					+	'</div>';
			} else {
				// Classic device (e.g. Z-wave)
				html += '<div class="' + _prefix + '-association ' + _prefix + '-association-device" data-device-id="' + device.id + '">'
					+		'<label>'
					+			_getCheckboxHtml( device.id, feature.association.devices, 0 )
					//+			_getCheckboxHtml( device.id, feature.association.devices, 1 )
					+			'&nbsp;' + device.name + ' (#' + device.id + ')'
					+		'</label>'
					+	'</div>';
			}
		} );

		html += '<div class="' + _prefix + '-toolbar">'
			+		'<button type="button" class="' + _prefix + '-cancel"><i class="fa fa-times fa-lg text-danger" aria-hidden="true"></i>&nbsp;'  + Utils.getLangString( _prefix + "_cancel" ) + '</button>'
			+		'<button type="button" class="' + _prefix + '-associate"><i class="fa fa-check fa-lg text-success" aria-hidden="true"></i>&nbsp;'  + Utils.getLangString( _prefix + "_confirm" ) + '</button>'
			+	'</div>';

		$( "#" + _prefix + "-device-association" )
			.html( html )
			.css( {
				"display": "block"
			} );

		_formerScrollTopPosition = $( window ).scrollTop();
		$( window ).scrollTop( $( "#" + _prefix + "-known-panel" ).offset().top - 150 );
	}
	function _hideDeviceAssociation() {
		$( "#" + _prefix + "-device-association" )
			.css( {
				"display": "none",
				"min-height": $( "#" + _prefix + "-known-panel" ).height()
			} );
		if ( _formerScrollTopPosition > 0 ) {
			$( window ).scrollTop( _formerScrollTopPosition );
		}
	}
	function _setDeviceAssociation() {
		function _getEncodedAssociation() {
			var associations = [];
			$("#" + _prefix + "-device-association ." + _prefix + "-association-device input:checked").each( function() {
				var deviceId = $( this ).parents( "." + _prefix + "-association-device" ).data( "device-id" );
				if ( $( this ).parent().hasClass( "ziblue-long-press" ) ) {
					associations.push( "+" + deviceId );
				} else {
					associations.push( deviceId );
				}
			});
			$("#" + _prefix + "-device-association ." + _prefix + "-association-scene input:checked").each( function() {
				var sceneId = $( this ).parents( "." + _prefix + "-association-scene" ).data( "scene-id" );
				if ( $( this ).parent().hasClass( "ziblue-long-press" ) ) {
					associations.push( "+*" + sceneId );
				} else {
					associations.push( "*" + sceneId );
				}
			});
			$("#" + _prefix + "-device-association ." + _prefix + "-association-zibluedevice input:checked").each( function() {
				var deviceId = $( this ).parents( "." + _prefix + "-association-zibluedevice" ).data( "device-id" );
				associations.push( "%" + deviceId );
			});
			return associations.join( "," );
		}

		var params = _selectedProductId.split( ";" );
		$.when( _performActionAssociate( params[0], params[1], _selectedFeatureName, _getEncodedAssociation() ) )
			.done( function() {
				_resumeDevicesRefresh();
				_hideDeviceAssociation();
			});
	}

	/**
	 * Show parameters for an external device
	 */
	function _showDeviceParams( productId, feature ) {
		_stopDevicesRefresh();
		var html = '<h1>' + Utils.getLangString( _prefix + "_param" ) + '</h1>'
				+	'<h3>' + productId + ' - ' + feature.deviceName + ' (#' + feature.deviceId + ')</h3>'
				+	'<div class="scenes_section_delimiter"></div>'
				+	'<div class="' + _prefix + '-toolbar">'
				+		'<button type="button" class="' + _prefix + '-help"><i class="fa fa-question fa-lg text-info" aria-hidden="true"></i>&nbsp;' + Utils.getLangString( _prefix + "_help" ) + '</button>'
				+	'</div>'
				+	'<div class="' + _prefix + '-explanation ' + _prefix + '-hidden">'
				+		Utils.getLangString( _prefix + "_explanation_param" )
				+	'</div>';

		// Button
		html += '<h3>'
			+		_getSettingHtml({
						type: "checkbox",
						className: _prefix + "-hider",
						variable: "button",
						name: "Button",
						value: feature.settings.button
					})
			+	'</h3>'
			+	'<div class="' + _prefix + '-hideable"' + ( !feature.settings.button ? ' style="display: none;"' : '' ) + '>';
		$.each( [ [ 'pulse', 'Pulse' ], [ 'toggle', 'Toggle' ] ], function( i, param ) {
			html += _getSettingHtml({
				type: "checkbox",
				variable: param[0],
				name: param[1],
				value: feature.settings[ param[0] ]
			});
		});
		html += '</div>';

		// Receiver
		html += '<h3>'
			+		_getSettingHtml({
						type: "checkbox",
						className: _prefix + "-hider",
						variable: "receiver",
						name: "Receiver",
						value: feature.settings.receiver
					})
			+	'</h3>'
			+	'<div class="' + _prefix + '-hideable"' + ( !feature.settings.receiver ? ' style="display: none;"' : '' ) + '>';
		html += '</div>';

		// Specific
		var specificHtml = '';
		$.each( feature.settings, function( paramName, paramValue ) {
			if ( $.inArray( paramName, [ 'button', 'pulse', 'toggle', 'receiver', 'qualifier', 'burst' ] ) === -1 ) {
				specificHtml += _getSettingHtml({
					type: ( ( typeof paramValue == "boolean" ) ? "checkbox" : "string" ),
					isReadOnly: true,
					variable: paramName,
					name: paramName,
					value: paramValue
				});
			}
		});
		if ( specificHtml != '' ) {
			html += '<h3>'
			+			'<div class="' + _prefix + '-setting ui-widget-content ui-corner-all">'
			+				'Specific'
			+			'</div>'
			+		'</h3>'
			+		specificHtml;
		}

		html += '<div class="' + _prefix + '-toolbar">'
			+		'<button type="button" class="' + _prefix + '-cancel"><i class="fa fa-times fa-lg text-danger" aria-hidden="true"></i>&nbsp;' + Utils.getLangString( _prefix + "_cancel" ) + '</button>'
			+		'<button type="button" class="' + _prefix + '-set"><i class="fa fa-check fa-lg text-success" aria-hidden="true"></i>&nbsp;'  + Utils.getLangString( _prefix + "_confirm" ) + '</button>'
			+	'</div>';

		$( "#" + _prefix + "-device-params" )
			.html( html )
			.data( 'feature', feature )
			.css( {
				"display": "block",
				"min-height": $( "#" + _prefix + "-known-panel" ).height()
			} )
			.on( "change", "." + _prefix + "-hider", function() {
				var hasToBeVisible = $( this ).is( ':checkbox' ) ? $( this ).is( ':checked' ) : true;
				$( this ).parent().parent()
					.next( "." + _prefix + "-hideable" )
						.css({ 'display': ( hasToBeVisible ? "block": "none" ) });
			});

		_formerScrollTopPosition = $( window ).scrollTop();
		$( window ).scrollTop( $( "#" + _prefix + "-known-panel" ).offset().top - 150 );
	}
	function _hideDeviceParams() {
		$( "#" + _prefix + "-device-params" )
			.css( {
				"display": "none"
			} );
		if ( _formerScrollTopPosition > 0 ) {
			$( window ).scrollTop( _formerScrollTopPosition );
		}
	}
	function _setDeviceParams() {
		var feature = $( "#" + _prefix + "-device-params" ).data( "feature" );
		feature.settings = {};
		$( "#" + _prefix + "-device-params ." + _prefix + "-setting-value:visible" ).each( function() {
			var settingName = $( this ).data( "setting" );
			var settingValue = $( this ).is( ":checkbox" ) ? $( this ).is( ":checked" ) : $( this ).val();
			if ( settingName && ( settingValue !== "" ) ) {
				feature.settings[ settingName ] = settingValue;
			}
		});
		var setting = $.map( feature.settings, function( value, key ) {
			if ( typeof value == "boolean" ) {
				return ( value === true ) ? key : null;
			} else {
				return key + "=" + value;
			}
		});
		$.when(
			Utils.setDeviceStateVariablePersistent( feature.deviceId, PLUGIN_CHILD_SID, "Setting", setting.join( "," ) ),
			_performActionRefresh()
		)
			.done( function() {
				_resumeDevicesRefresh();
				_hideDeviceParams();
			});
	}

	/**
	 * Show external devices
	 */
	function _showDevices( deviceId ) {
		if ( deviceId ) {
			_deviceId = deviceId;
		}
		try {
			$.when( _loadResourcesAsync(), _loadLocalizationAsync() ).then( function() {
				api.setCpanelContent(
						'<div id="' + _prefix + '-known-panel" class="' + _prefix + '-panel">'
					+		'<h1>' + Utils.getLangString( _prefix + "_managed_devices" ) + '</h1>'
					+		'<div class="scenes_section_delimiter"></div>'
					+		'<div class="' + _prefix + '-toolbar">'
					+			'<button type="button" class="' + _prefix + '-help"><i class="fa fa-question fa-lg text-info" aria-hidden="true"></i>&nbsp;' + Utils.getLangString( _prefix + "_help" ) + '</button>'
					+			'<button type="button" class="' + _prefix + '-refresh"><i class="fa fa-refresh fa-lg" aria-hidden="true"></i>&nbsp;' + Utils.getLangString( _prefix + "_refresh" ) + '</button>'
					+		'</div>'
					+		'<div class="' + _prefix + '-explanation ' + _prefix + '-hidden">'
					+			Utils.getLangString( _prefix + "_explanation_known_devices" )
					+		'</div>'
					+		'<div id="' + _prefix + '-known-devices" class="' + _prefix + '-devices">'
					+			Utils.getLangString( _prefix + "_loading" )
					+		'</div>'
					+		'<div id="' + _prefix + '-device-actions" style="display: none;"></div>'
					+		'<div id="' + _prefix + '-device-association" style="display: none;"></div>'
					+		'<div id="' + _prefix + '-device-params" style="display: none;"></div>'
					+	'</div>'
				);

				// Manage UI events
				$( "#" + _prefix + "-known-panel" )
					.on( "click", "." + _prefix + "-help", function() {
						$( this ).parent().next( "." + _prefix + "-explanation" ).toggleClass( _prefix + "-hidden" );
					} )
					.on( "click", "." + _prefix + "-refresh", function() {
						$.when( _performActionRefresh() )
							.done( function() {
								_drawDevicesList();
							});
					} )
					.click( function() {
						$( "#" + _prefix + "-device-actions" ).css( "display", "none" );
					} )
					.on( "click", "." + _prefix + "-actions", function( e ) {
						var position = $( this ).position();
						position.left = position.left + $( this ).outerWidth();
						_selectedProductId = $( this ).data( "product-id" );
						_selectedFeatureName = $( this ).data( "feature-name" );
						var selectedFeature = _indexFeatures[ _selectedProductId + ";" + _selectedFeatureName ];
						if ( selectedFeature ) {
							_showDeviceActions( position, selectedFeature.settings );
						}
						e.stopPropagation();
					} )
					.on( "click", "." + _prefix + "-show-association", function() {
						_showDeviceAssociation( _selectedProductId, _indexFeatures[ _selectedProductId + ";" + _selectedFeatureName ] );
					} )
					.on( "click", "." + _prefix + "-show-params", function() {
						_showDeviceParams( _selectedProductId, _indexFeatures[ _selectedProductId + ";" + _selectedFeatureName ] );
					} )
					.on( "click", "." + _prefix + "-cancel", function() {
						_hideDeviceAssociation();
						_hideDeviceParams();
						_resumeDevicesRefresh();
					} )
					// Association event
					.on( "click", "." + _prefix + "-associate", _setDeviceAssociation )
					// Parameters event
					.on( "click", "." + _prefix + "-set", _setDeviceParams );

				// Show devices infos
				_drawDevicesList();
			});
		} catch (err) {
			Utils.logError( "Error in " + _pluginName + ".showDevices(): " + err );
		}
	}

	// *************************************************************************************************
	// Discovered external devices
	// *************************************************************************************************

	function _stopDiscoveredDevicesRefresh() {
		if ( _discoveredDevicesTimeout ) {
			window.clearTimeout( _discoveredDevicesTimeout );
		}
		_discoveredDevicesTimeout = null;
	}
	function _resumeDiscoveredDevicesRefresh() {
		if ( _discoveredDevicesTimeout == null ) {
			var timeout = 3000 - ( Date.now() - _discoveredDevicesLastRefresh );
			if ( timeout < 0 ) {
				timeout = 0;
			}
			_discoveredDevicesTimeout = window.setTimeout( _drawDiscoveredDevicesList, timeout );
		}
	}

	/**
	 * Draw and manage discovered ziblue device list
	 */
	function _drawDiscoveredDevicesList() {
		_stopDiscoveredDevicesRefresh();
		if ( $( "#" + _prefix + "-discovered-devices" ).length === 0 ) {
			return;
		}
		$.when( _getDevicesInfosAsync() )
			.done( function( devicesInfos ) {
				if ( devicesInfos.discoveredDevices.length > 0 ) {
					// Sort the discovered ziblue devices by last update
					devicesInfos.discoveredDevices.sort( function( d1, d2 ) {
						return d2.lastUpdate - d1.lastUpdate;
					});
					var html =	'<table><tr>'
						+			'<th>' + Utils.getLangString( _prefix + "_address" ) + '</th>'
						+			'<th>' + Utils.getLangString( _prefix + "_endpoint" ) + '</th>'
						+			'<th>' + Utils.getLangString( _prefix + "_signal_quality" ) + '</th>'
						+			'<th>' + Utils.getLangString( _prefix + "_last_update" ) + '</th>'
						+			'<th>' + Utils.getLangString( _prefix + "_feature" ) + '</th>'
						+			'<th></th>'
						+		'</tr>';
					$.each( devicesInfos.discoveredDevices, function( i, discoveredDevice ) {
						html += '<tr class="' + _prefix + '-discovered-device" data-address="' + discoveredDevice.address + '" data-end-point="' + discoveredDevice.endPoint + '">'
							+		'<td>' + discoveredDevice.address + '</td>'
							+		'<td>' + discoveredDevice.endPoint + '</td>'
							+		'<td>' + ( discoveredDevice.quality >= 0 ? discoveredDevice.quality : '' ) + '</td>'
							+		'<td>' + _convertTimestampToLocaleString( discoveredDevice.lastUpdate ) + '</td>'
							+		'<td>'
							+			'<table class="' + _prefix + '-feature">';
						$.each( discoveredDevice.features, function( featureName, feature ) {
							html +=			'<tr>'
								+				'<td>'
								+					'<div class="font-weight-bold">' + featureName + '</div>'
								+					( feature.data ? '<div class="' + _prefix + '-feature-data">' + feature.data + '</div>' : '' )
								+				'</td><td width="40%">';
							if ( feature.deviceTypes && ( feature.deviceTypes.length > 0 ) ) {
								html +=				'<div class="' + _prefix + '-device-type" data-feature-name="' + featureName + '" data-settings="' + ( feature.settings ? feature.settings : '' ) + '">';
								if ( feature.deviceTypes.length > 1 ) {
									html +=				'<select>';
									$.each( feature.deviceTypes, function( k, deviceType ) {
										html +=				'<option value="' + deviceType + '">' + deviceType + '</option>';
									} );
									html +=				'</select>';
								} else {
									html +=	feature.deviceTypes[0];
								}
								html +=				'</div>';
							}
							html +=				'</td>'
								+			'</tr>';
						} );
						html +=			'</table>'
							+		'</td>'
							+		'<td>'
							+			'<input type="checkbox">'
							+		'</td>'
							+	'</tr>';
					});
					html += '</table>';
					$("#" + _prefix + "-discovered-devices").html( html );
				} else {
					$("#" + _prefix + "-discovered-devices").html( Utils.getLangString( "zigate_no_discovered_device" ) );
				}
				_discoveredDevicesLastRefresh = Date.now();
				_resumeDiscoveredDevicesRefresh();
			} );
	}

	/**
	 * Show ziblue discovered devices
	 */
	function _showDiscoveredDevices( deviceId ) {
		if ( deviceId ) {
			_deviceId = deviceId;
		}
		try {
			$.when( _loadResourcesAsync(), _loadLocalizationAsync() ).then( function() {
				api.setCpanelContent(
						'<div id="' + _prefix + '-discovered-panel" class="' + _prefix + '-panel">'
					+		'<h1>' + Utils.getLangString( _prefix + "_discovered_devices" ) + '</h1>'
					+		'<div class="scenes_section_delimiter"></div>'
					+		'<div class="' + _prefix + '-toolbar">'
					+			'<button type="button" class="' + _prefix + '-inclusion"><i class="fa fa-sign-in fa-lg fa-rotate-90 text-danger" aria-hidden="true"></i>&nbsp;' + Utils.getLangString( _prefix + "_inclusion" ) + '</button>'
					+			'<button type="button" class="' + _prefix + '-help"><i class="fa fa-question fa-lg text-info" aria-hidden="true"></i>&nbsp;' + Utils.getLangString( _prefix + "_help" ) + '</button>'
					+			'<button type="button" class="' + _prefix + '-learn"><i class="fa fa-plus fa-lg" aria-hidden="true"></i>&nbsp;' + Utils.getLangString( _prefix + "_learn" ) + '</button>'
					+		'</div>'
					+		'<div class="' + _prefix + '-explanation ' + _prefix + '-hidden">'
					+			Utils.getLangString( _prefix + "_explanation_discovered_devices" )
					+		'</div>'
					+		'<div id="' + _prefix + '-discovered-devices" class="' + _prefix + '-devices">'
					+			Utils.getLangString( _prefix + "_loading" )
					+		'</div>'
					+	'</div>'
				);

				function _getSelectedItems() {
					var items = [];
					$( "#" + _prefix + "-discovered-devices input:checked:visible" ).each( function() {
						var $device = $( this ).parents( "." + _prefix + "-discovered-device" );
						var address = $device.data( "address" );
						var endPoint = $device.data( "end-point" );
						var features = [];
						$device.find( "." + _prefix + "-device-type" )
							.each( function( index ) {
								var featureName = $( this ).data( 'feature-name' );
								var $select = $( this ).find( "select" );
								var deviceType = ( $select.length > 0 ) ? $select.val() : $( this ).text();
								features.push( { "names": [ featureName ], "deviceType": deviceType, "settings": $( this ).data( 'settings' ) || "" } );
							});
						items.push( { "address": address, "endPoint": endPoint, "features": features } );
					});
					return items;
				}

				// Manage UI events
				$( "#" + _prefix + "-discovered-panel" )
					.on( "click", "." + _prefix + "-inclusion", function() {
						$.when( _performActionInclusion() )
							.done( function() {
								$( "#" + _prefix + "-discovered-panel ." + _prefix + "-inclusion" ).prop( "disabled", true );
								$( "#" + _prefix + "-discovered-panel ." + _prefix + "-inclusion i" )
									.removeClass( "fa-sign-in" )
									.addClass( "fa-spinner fa-pulse");
								setTimeout( function(){
									$( "#" + _prefix + "-discovered-panel ." + _prefix + "-inclusion i" )
										.removeClass( "fa-spinner fa-pulse")
										.addClass( "fa-sign-in" );
								}, 30000);
							});
					} )
					.on( "click", "." + _prefix + "-help", function() {
						$( "." + _prefix + "-explanation" ).toggleClass( _prefix + "-hidden" );
					} )
					.on( "click", "." + _prefix + "-learn", function( e ) {
						var items = _getSelectedItems();
						if ( items.length === 0 ) {
							api.ui.showMessagePopup( Utils.getLangString( _prefix + "_select_device" ), 1 );
						} else {
							api.ui.showMessagePopup( Utils.getLangString( _prefix + "_confirmation_learning_devices" ) + " <pre>" + JSON.stringify( items, undefined, 2 ) + "</pre>", 4, 0, {
								onSuccess: function() {
									$.when( _performActionCreateDevices( items ) )
										.done( function() {
											_showReload( Utils.getLangString( _prefix + "_devices_have_been_created" ), function() {
												_showDevices();
											});
										});
									return true;
								}
							});
						}
					} )
					.on( "click", "." + _prefix + "-ignore", function( e ) {
						alert( "TODO" );
					})
					.on( "focus", "select", function( e ) {
						_stopDiscoveredDevicesRefresh();
					})
					.on( "blur", "select", function( e ) {
						if ( $( "#" + _prefix + "-discovered-panel input:checked" ).length === 0 ) {
							_resumeDiscoveredDevicesRefresh();
						}
					})
					.on( "change", "select", function( e ) {
						if ( $( "#" + _prefix + "-discovered-panel input:checked" ).length === 0 ) {
							_resumeDiscoveredDevicesRefresh();
						}
					})
					.on( "change", "input:checkbox", function( e ) {
						if ( $( "#" + _prefix + "-discovered-panel input:checked" ).length > 0 ) {
							_stopDiscoveredDevicesRefresh();
						} else {
							_resumeDiscoveredDevicesRefresh();
						}
					})
					;

				// Show discovered devices infos
				_drawDiscoveredDevicesList();
			});
		} catch (err) {
			Utils.logError( "Error in " + _pluginName + ".showDevices(): " + err );
		}
	}

	// *************************************************************************************************
	// Actions
	// *************************************************************************************************

	/**
	 * 
	 */
	function _performActionRefresh() {
		Utils.logDebug( "[" + _pluginName + ".performActionRefresh] Refresh the list of external devices" );
		return Utils.performActionOnDevice(
			_deviceId, PLUGIN_SID, "Refresh", {
				output_format: "json"
			}
		);
	}

	/**
	 * 
	 */
	function _performActionCreateDevices( items ) {
		var jsonItems = JSON.stringify( items );
		Utils.logDebug( "[" + _pluginName + ".performActionCreateDevices] Create external product/features '" + jsonItems + "'" );
		return Utils.performActionOnDevice(
			_deviceId, PLUGIN_SID, "CreateDevices", {
				output_format: "json",
				items: encodeURIComponent( jsonItems )
			}
		);
	}

	/**
	 * Start inclusion mode
	 */
	function _performActionInclusion() {
		Utils.logDebug( "[" + _pluginName + ".performActionInclusion] Start inclusion mode" );
		return Utils.performActionOnDevice(
			_deviceId, PLUGIN_SID, "Inclusion", {
				output_format: "json"
			}
		);
	}

	/**
	 * Associate external device to Vera devices
	 */
	function _performActionAssociate( address, endPoint, featureName, encodedAssociation ) {
		Utils.logDebug( "[" + _pluginName + ".performActionAssociate] Associate external product/feature '" + address + ";" + endPoint + "/" + featureName + "' with " + encodedAssociation );
		return Utils.performActionOnDevice(
			_deviceId, PLUGIN_SID, "Associate", {
				output_format: "json",
				address: address,
				endPoint: endPoint,
				feature: featureName,
				association: encodeURIComponent( encodedAssociation )
			}
		);
	}

	// *************************************************************************************************
	// Errors
	// *************************************************************************************************

	/**
	 * Get errors
	 */
	function _getErrorsAsync() {
		var d = $.Deferred();
		api.showLoadingOverlay();
		$.ajax( {
			url: Utils.getDataRequestURL() + "id=lr_" + _pluginName + "&command=getErrors&output_format=json#",
			dataType: "json"
		} )
		.done( function( errors ) {
			api.hideLoadingOverlay();
			if ( $.isArray( errors ) ) {
				d.resolve( errors );
			} else {
				Utils.logError( "No errors" );
				d.reject();
			}
		} )
		.fail( function( jqxhr, textStatus, errorThrown ) {
			api.hideLoadingOverlay();
			Utils.logError( "Get errors error : " + errorThrown );
			d.reject();
		} );
		return d.promise();
	}

	/**
	 * Draw errors list
	 */
	function _drawErrorsList() {
		if ( $( "#" + _prefix + "-errors" ).length === 0 ) {
			return;
		}
		$.when( _getErrorsAsync() )
			.done( function( errors ) {
				if ( errors.length > 0 ) {
					var html = '<table><tr><th>Date</th><th>Method<th>Error</th></tr>';
					$.each( errors, function( i, error ) {
						html += '<tr>'
							+		'<td>' + _convertTimestampToLocaleString( error[0] ) + '</td>'
							+		'<td>' + error[1] + '</td>'
							+		'<td>' + error[2] + '</td>'
							+	'</tr>';
					} );
					html += '</table>';
					$( "#" + _prefix + "-errors" ).html( html );
				} else {
					$( "#" + _prefix + "-errors" ).html( Utils.getLangString( _prefix + "_no_error" ) );
				}
			} );
	}

	/**
	 * Show errors tab
	 */
	function _showErrors( deviceId ) {
		_deviceId = deviceId;
		try {
			$.when( _loadResourcesAsync(), _loadLocalizationAsync() ).then( function() {
				api.setCpanelContent(
						'<div id="' + _prefix + '-errors-panel" class="' + _prefix + '-panel">'
					+		'<h1>' + Utils.getLangString( _prefix + "_errors" ) + '</h1>'
					+		'<div class="scenes_section_delimiter"></div>'
					/*+		'<div class="' + _prefix + '-toolbar">'
					+			'<button type="button" class="' + _prefix + '-help"><i class="fa fa-question fa-lg text-info" aria-hidden="true"></i>&nbsp;' + Utils.getLangString( _prefix + "_help" ) + '</button>'
					+		'</div>'
					+		'<div class="' + _prefix + '-explanation ' + _prefix + '-hidden">'
					+			Utils.getLangString( _prefix + "_explanation_errors" )
					+		'</div>'*/
					+		'<div id="' + _prefix + '-errors">'
					+			Utils.getLangString( _prefix + "_loading" )
					+		'</div>'
					+	'</div>'
				);
				// Manage UI events
				/*$( "#" + _prefix + "-errors-panel" )
					.on( "click", "." + _prefix + "-help" , function() {
						$( "." + _prefix + "-explanation" ).toggleClass( _prefix + "-hidden" );
					} );*/
				// Display the errors
				_drawErrorsList();
			});
		} catch ( err ) {
			Utils.logError( "Error in " + _pluginName + ".showErrors(): " + err );
		}
	}

	// *************************************************************************************************
	// Donate
	// *************************************************************************************************

	function _showDonate( deviceId ) {
		var donateHtml = '\
<form action="https://www.paypal.com/cgi-bin/webscr" method="post" target="_blank">\
<input type="hidden" name="cmd" value="_s-xclick">\
<input type="hidden" name="encrypted" value="-----BEGIN PKCS7-----\
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\
-----END PKCS7-----">\
<input type="image" src="https://www.paypalobjects.com/en_US/FR/i/btn/btn_donateCC_LG.gif" border="0" name="submit" alt="PayPal - The safer, easier way to pay online!">\
<img alt="" border="0" src="https://www.paypalobjects.com/fr_FR/i/scr/pixel.gif" width="1" height="1">\
</form>';
		$.when( _loadResourcesAsync(), _loadLocalizationAsync() ).then( function() {
			api.setCpanelContent(
					'<div id="' + _prefix + '-donate-panel" class="' + _prefix + '-panel">'
				+		'<div id="' + _prefix + '-donate">'
				+			'<span>' + Utils.getLangString( _prefix + "_donate" ) + '</span>'
				+			donateHtml
				+		'</div>'
				+	'</div>'
			);
		});
	}

	// *************************************************************************************************
	// Main
	// *************************************************************************************************

	myModule = {
		uuid: _uuid,
		showDevices: _showDevices,
		showDiscoveredDevices: _showDiscoveredDevices,
		showErrors: _showErrors,
		showDonate: _showDonate,

		ALTUI_drawDevice: function( device ) {
			var version = MultiBox.getStatus( device, PLUGIN_SID, "PluginVersion" );
			return '<div class="panel-content">'
				+		'<div class="btn-group" role="group" aria-label="...">'
				+			'v' + version
				+		'</div>'
				+	'</div>';
		}
	};

	return myModule;

})( api, jQuery );
