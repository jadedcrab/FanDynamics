//
//  Constants.h
//  smcFanControl
//
//  Created by Hendrik Holtmann on 16/10/16.
//
//

#define PREF_SELECTION_DEFAULT @"SelDefault"
#define PREF_AUTOSTART_ENABLED @"AutoStart"
#define PREF_AUTOMATIC_CHANGE @"AutomaticChange"
#define PREF_BATTERY_SELECTION @"selbatt"
#define PREF_AC_SELECTION @"selac"
#define PREF_CHARGING_SELECTION @"selload"
#define PREF_MENU_DISPLAYMODE @"MenuBar"
#define PREF_TEMPERATURE_SENSOR @"TSensor"
#define PREF_NUMBEROF_LAUNCHES @"NumLaunches"
#define PREF_MENU_TEXTCOLOR @"MenuColor"
#define PREF_FAVORITES_ARRAY @"Favorites"

// Automatic fan curves (temp→RPM). Curve points for fan N live under
// the key [NSString stringWithFormat:PREF_FAN_CURVE_FMT, N].
#define PREF_AUTOCURVE_ENABLED @"AutoCurveEnabled"
#define PREF_FAN_CURVE_FMT @"fan_%d_curve"
// Posted by the curve editor after curves or the sensor selection change,
// so the running control loop reloads them.
#define NOTE_FAN_CURVES_CHANGED @"SMCFanCurvesChanged"
// Curve editor temperature display unit (bool; absent → follow locale).
#define PREF_CURVE_EDITOR_FAHRENHEIT @"CurveEditorFahrenheit"

#define PREF_FAN_ARRAY @"FanData"
#define PREF_FAN_TITLE @"Title"
#define PREF_FAN_MINSPEED  @"Minspeed"
#define PREF_FAN_SELSPEED @"selspeed"
#define PREF_FAN_SYNC @"sync"
#define PREF_FAN_SHOWMENU @"menu"
#define PREF_FAN_AUTO @"auto"
