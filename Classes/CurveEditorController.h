/*
 *	FanControl
 *
 *	Copyright (c) 2026 smcFanControl Community Edition contributors
 *
 *	CurveEditorController.h - editor pane for automatic fan curves
 *
 *	This program is free software; you can redistribute it and/or modify
 *	it under the terms of the GNU General Public License as published by
 *	the Free Software Foundation; either version 2 of the License, or
 *	(at your option) any later version.
 *
 *	This program is distributed in the hope that it will be useful,
 *	but WITHOUT ANY WARRANTY; without even the implied warranty of
 *	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *	GNU General Public License for more details.
 *
 *	You should have received a copy of the GNU General Public License
 *	along with this program; if not, write to the Free Software
 *	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#import <Cocoa/Cocoa.h>

@class CurvePreviewView;

/// Editor pane for per-fan temperature→RPM curves: enable toggle, fan and
/// sensor pickers, live preview, and a point table with steppers. Built
/// programmatically — the app's nibs predate this feature. The pane is a
/// plain NSView hosted as a tab of the unified settings window.
///
/// Edits are saved to NSUserDefaults immediately and announced via
/// NOTE_FAN_CURVES_CHANGED so a running control loop picks them up.
@interface CurveEditorController : NSObject <NSTableViewDataSource, NSTableViewDelegate>
{
	NSView *_view;
	NSButton *_enableCheckbox;       // mirrors PREF_AUTOCURVE_ENABLED
	NSPopUpButton *_fanPopup;
	NSPopUpButton *_sensorPopup;
	NSSegmentedControl *_unitsSeg;   // °C / °F display toggle
	CurvePreviewView *_preview;
	NSTableView *_pointsTable;
	NSTimer *_refreshTimer;      // live sensor readout while the pane is visible

	// Selected-point editors (fields + up/down steppers)
	NSTextField *_selTempField;
	NSStepper *_selTempStepper;
	NSTextField *_selRPMField;
	NSStepper *_selRPMStepper;

	int _selectedFan;
	BOOL _useFahrenheit;         // display only — storage is always °C
	NSMutableArray *_points;     // mutable copy of the selected fan's curve points
}

+ (CurveEditorController *)shared;

/// The pane's view (460×640), built on first access.
- (NSView *)editorView;

/// Call when the pane is about to be shown: refreshes pickers, points, and
/// the live reading, and starts the readout timer.
- (void)prepareForDisplay;

/// Call when the hosting window closes: stops the readout timer.
- (void)displayDidHide;

/// Resync the enable checkbox from PREF_AUTOCURVE_ENABLED (e.g. after the
/// menu item toggled it).
- (void)syncEnableState;

@end
