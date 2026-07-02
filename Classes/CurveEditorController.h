/*
 *	FanControl
 *
 *	Copyright (c) 2026 smcFanControl Community Edition contributors
 *
 *	CurveEditorController.h - editor window for automatic fan curves
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

/// Window for editing per-fan temperature→RPM curves and picking the
/// temperature sensor the control loop reads. Built programmatically —
/// the app's nibs predate this feature.
///
/// Edits are saved to NSUserDefaults immediately and announced via
/// NOTE_FAN_CURVES_CHANGED so a running control loop picks them up.
@interface CurveEditorController : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
{
	NSWindow *_window;
	NSPopUpButton *_fanPopup;
	NSPopUpButton *_sensorPopup;
	CurvePreviewView *_preview;
	NSTableView *_pointsTable;
	NSTimer *_refreshTimer;      // live sensor readout while window is open

	int _selectedFan;
	NSMutableArray *_points;     // mutable copy of the selected fan's curve points
}

/// Show the shared editor window, creating it on first use.
+ (void)showEditor;

@end
