/*
 *	FanControl
 *
 *	Copyright (c) 2026 smcFanControl Community Edition contributors
 *
 *	CurveEditorController.m - editor window for automatic fan curves
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

#import "CurveEditorController.h"
#import "FanCurve.h"
#import "smcWrapper.h"
#import "MachineDefaults.h"
#import "Constants.h"

// Temperature range shown on the preview's x-axis.
static const float kPreviewTempMin = 30.0f;
static const float kPreviewTempMax = 105.0f;

#pragma mark - CurvePreviewView

/// Draws the curve as the control loop interprets it: flat before the
/// first point, linear between points, flat after the last point. A
/// vertical marker shows the sensor's current (raw) temperature.
@interface CurvePreviewView : NSView
@property (nonatomic, copy) NSArray<NSDictionary *> *points; // sorted
@property (nonatomic, assign) float currentTemp;             // <=0 → hidden
@property (nonatomic, assign) int hwMax;                     // scales y-axis
@property (nonatomic, assign) BOOL useFahrenheit;            // axis labels only — geometry stays °C
@end

@implementation CurvePreviewView

- (float)maxRPMForScale {
    float maxRPM = (float)_hwMax;
    for (NSDictionary *p in _points) {
        float rpm = [p[CURVE_POINT_RPM] floatValue];
        if (rpm > maxRPM) maxRPM = rpm;
    }
    if (maxRPM < 1000.0f) maxRPM = 1000.0f;
    return maxRPM * 1.08f;
}

- (NSPoint)plotPointForTemp:(float)temp rpm:(float)rpm inRect:(NSRect)plot {
    float fx = (temp - kPreviewTempMin) / (kPreviewTempMax - kPreviewTempMin);
    float fy = rpm / [self maxRPMForScale];
    if (fx < 0.0f) fx = 0.0f;
    if (fx > 1.0f) fx = 1.0f;
    if (fy < 0.0f) fy = 0.0f;
    if (fy > 1.0f) fy = 1.0f;
    return NSMakePoint(NSMinX(plot) + fx * NSWidth(plot),
                       NSMinY(plot) + fy * NSHeight(plot));
}

- (void)drawRect:(NSRect)dirtyRect {
    NSColor *axisColor, *gridColor, *lineColor, *textColor, *markerColor;
    if (@available(macOS 10.14, *)) {
        axisColor = [NSColor secondaryLabelColor];
        gridColor = [[NSColor secondaryLabelColor] colorWithAlphaComponent:0.15];
        textColor = [NSColor secondaryLabelColor];
        lineColor = [NSColor controlAccentColor];
        markerColor = [NSColor systemRedColor];
    } else {
        axisColor = [NSColor grayColor];
        gridColor = [[NSColor grayColor] colorWithAlphaComponent:0.15];
        textColor = [NSColor grayColor];
        lineColor = [NSColor blueColor];
        markerColor = [NSColor redColor];
    }

    NSDictionary *labelAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:9],
        NSForegroundColorAttributeName: textColor,
    };

    // Margins leave room for axis labels.
    NSRect plot = NSInsetRect([self bounds], 0, 0);
    plot.origin.x += 40; plot.size.width -= 48;
    plot.origin.y += 18; plot.size.height -= 26;

    // Grid + labels: every 10°C, four horizontal divisions.
    float maxRPM = [self maxRPMForScale];
    for (float t = 40.0f; t < kPreviewTempMax; t += 10.0f) {
        NSPoint bottom = [self plotPointForTemp:t rpm:0 inRect:plot];
        NSBezierPath *line = [NSBezierPath bezierPath];
        [line moveToPoint:bottom];
        [line lineToPoint:NSMakePoint(bottom.x, NSMaxY(plot))];
        [gridColor setStroke];
        [line stroke];
        float shown = _useFahrenheit ? (t * 9.0f / 5.0f + 32.0f) : t;
        NSString *label = [NSString stringWithFormat:@"%.0f°", shown];
        [label drawAtPoint:NSMakePoint(bottom.x - 8, NSMinY(plot) - 14) withAttributes:labelAttrs];
    }
    for (int i = 1; i <= 4; i++) {
        float rpm = maxRPM * i / 4.0f;
        NSPoint left = [self plotPointForTemp:kPreviewTempMin rpm:rpm inRect:plot];
        NSBezierPath *line = [NSBezierPath bezierPath];
        [line moveToPoint:left];
        [line lineToPoint:NSMakePoint(NSMaxX(plot), left.y)];
        [gridColor setStroke];
        [line stroke];
        NSString *label = [NSString stringWithFormat:@"%.0f", rpm];
        [label drawAtPoint:NSMakePoint(NSMinX(plot) - 38, left.y - 5) withAttributes:labelAttrs];
    }

    // Axes.
    NSBezierPath *axes = [NSBezierPath bezierPath];
    [axes moveToPoint:NSMakePoint(NSMinX(plot), NSMaxY(plot))];
    [axes lineToPoint:NSMakePoint(NSMinX(plot), NSMinY(plot))];
    [axes lineToPoint:NSMakePoint(NSMaxX(plot), NSMinY(plot))];
    [axisColor setStroke];
    [axes stroke];

    if ([_points count] < 2) return;

    // Curve polyline with flat clamped extensions at both ends.
    NSBezierPath *curve = [NSBezierPath bezierPath];
    [curve setLineWidth:2.0];
    float firstTemp = [_points[0][CURVE_POINT_TEMP] floatValue];
    float firstRPM = [_points[0][CURVE_POINT_RPM] floatValue];
    [curve moveToPoint:[self plotPointForTemp:kPreviewTempMin rpm:firstRPM inRect:plot]];
    [curve lineToPoint:[self plotPointForTemp:firstTemp rpm:firstRPM inRect:plot]];
    for (NSDictionary *p in _points) {
        [curve lineToPoint:[self plotPointForTemp:[p[CURVE_POINT_TEMP] floatValue]
                                              rpm:[p[CURVE_POINT_RPM] floatValue]
                                           inRect:plot]];
    }
    float lastRPM = [[_points lastObject][CURVE_POINT_RPM] floatValue];
    [curve lineToPoint:[self plotPointForTemp:kPreviewTempMax rpm:lastRPM inRect:plot]];
    [lineColor setStroke];
    [curve stroke];

    // Point markers.
    [lineColor setFill];
    for (NSDictionary *p in _points) {
        NSPoint c = [self plotPointForTemp:[p[CURVE_POINT_TEMP] floatValue]
                                       rpm:[p[CURVE_POINT_RPM] floatValue]
                                    inRect:plot];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - 3.5, c.y - 3.5, 7, 7)] fill];
    }

    // Current temperature marker.
    if (_currentTemp > kPreviewTempMin && _currentTemp < kPreviewTempMax) {
        NSPoint bottom = [self plotPointForTemp:_currentTemp rpm:0 inRect:plot];
        NSBezierPath *marker = [NSBezierPath bezierPath];
        [marker moveToPoint:bottom];
        [marker lineToPoint:NSMakePoint(bottom.x, NSMaxY(plot))];
        CGFloat dashes[] = {4.0, 3.0};
        [marker setLineDash:dashes count:2 phase:0];
        [markerColor setStroke];
        [marker stroke];
    }
}

@end

#pragma mark - CurveEditorController

static CurveEditorController *sSharedEditor = nil;

@implementation CurveEditorController

+ (CurveEditorController *)shared {
    if (!sSharedEditor) {
        sSharedEditor = [[CurveEditorController alloc] init];
    }
    return sSharedEditor;
}

- (NSView *)editorView {
    if (!_view) {
        [self buildView];
    }
    return _view;
}

- (NSUserDefaults *)defaults {
    return [NSUserDefaults standardUserDefaults];
}

#pragma mark Pane construction

- (void)buildView {
    const CGFloat W = 460, H = 640;
    _view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, W, H)];
    NSView *content = _view;

    // --- Enable toggle (same pref the menu item flips) ---
    _enableCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(20, H - 36, 300, 20)];
    [_enableCheckbox setButtonType:NSButtonTypeSwitch];
    [_enableCheckbox setTitle:@"Automatic fan curves enabled"];
    [_enableCheckbox setTarget:self];
    [_enableCheckbox setAction:@selector(toggleEnabled:)];
    [content addSubview:_enableCheckbox];
    [self syncEnableState];

    // Display unit: explicit pref wins, otherwise follow the locale (same
    // detection the menu bar readout uses).
    id unitPref = [[self defaults] objectForKey:PREF_CURVE_EDITOR_FAHRENHEIT];
    if (unitPref) {
        _useFahrenheit = [unitPref boolValue];
    } else {
        NSString *tempUnit = [[NSLocale currentLocale] objectForKey:@"kCFLocaleTemperatureUnitKey"];
        if (tempUnit) {
            _useFahrenheit = [tempUnit isEqualToString:@"Fahrenheit"];
        } else {
            _useFahrenheit = ![[[NSLocale currentLocale] objectForKey:NSLocaleUsesMetricSystem] boolValue];
        }
    }

    // --- Fan picker ---
    [content addSubview:[self labelWithText:@"Fan:" frame:NSMakeRect(20, H - 84, 60, 20)]];
    _fanPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(86, H - 88, W - 106, 26) pullsDown:NO];
    int numFans = [smcWrapper get_fan_num];
    for (int i = 0; i < numFans; i++) {
        NSString *descr = [smcWrapper get_fan_descr:i];
        if ([descr length] == 0) descr = [NSString stringWithFormat:@"Fan %d", i];
        [_fanPopup addItemWithTitle:[NSString stringWithFormat:@"%d — %@", i, descr]];
    }
    [_fanPopup setTarget:self];
    [_fanPopup setAction:@selector(fanSelected:)];
    [content addSubview:_fanPopup];

    // --- Sensor picker ---
    [content addSubview:[self labelWithText:@"Sensor:" frame:NSMakeRect(20, H - 118, 60, 20)]];
    _sensorPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(86, H - 122, W - 106, 26) pullsDown:NO];
    [self populateSensorPopup];
    [_sensorPopup setTarget:self];
    [_sensorPopup setAction:@selector(sensorSelected:)];
    [content addSubview:_sensorPopup];

    // --- Temperature unit toggle ---
    [content addSubview:[self labelWithText:@"Units:" frame:NSMakeRect(20, H - 152, 60, 20)]];
    _unitsSeg = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(86, H - 154, 130, 24)];
    [_unitsSeg setSegmentCount:2];
    [_unitsSeg setLabel:@"°C" forSegment:0];
    [_unitsSeg setLabel:@"°F" forSegment:1];
    [_unitsSeg setSelectedSegment:_useFahrenheit ? 1 : 0];
    [_unitsSeg setTarget:self];
    [_unitsSeg setAction:@selector(unitsChanged:)];
    [content addSubview:_unitsSeg];

    // --- Curve preview ---
    _preview = [[CurvePreviewView alloc] initWithFrame:NSMakeRect(20, 292, W - 40, 182)];
    [_preview setUseFahrenheit:_useFahrenheit];
    [content addSubview:_preview];

    // --- Points table ---
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 126, W - 40, 156)];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSBezelBorder];
    _pointsTable = [[NSTableView alloc] initWithFrame:[[scroll contentView] bounds]];

    NSTableColumn *tempCol = [[NSTableColumn alloc] initWithIdentifier:@"temp"];
    [[tempCol headerCell] setStringValue:[self tempColumnTitle]];
    [tempCol setWidth:190];
    [tempCol setEditable:YES];
    [_pointsTable addTableColumn:tempCol];

    NSTableColumn *rpmCol = [[NSTableColumn alloc] initWithIdentifier:@"rpm"];
    [[rpmCol headerCell] setStringValue:@"Fan speed (RPM)"];
    [rpmCol setWidth:190];
    [rpmCol setEditable:YES];
    [_pointsTable addTableColumn:rpmCol];

    [_pointsTable setDataSource:self];
    [_pointsTable setDelegate:self];
    [scroll setDocumentView:_pointsTable];
    [content addSubview:scroll];

    // --- Selected-point editors (fields + steppers) ---
    [content addSubview:[self labelWithText:@"Selected:" frame:NSMakeRect(20, 95, 66, 18)]];
    [content addSubview:[self labelWithText:@"Temp" frame:NSMakeRect(92, 95, 40, 18)]];
    _selTempField = [[NSTextField alloc] initWithFrame:NSMakeRect(134, 91, 60, 24)];
    [_selTempField setTarget:self];
    [_selTempField setAction:@selector(selTempFieldChanged:)];
    [content addSubview:_selTempField];
    _selTempStepper = [[NSStepper alloc] initWithFrame:NSMakeRect(196, 89, 19, 27)];
    [_selTempStepper setIncrement:1.0];
    [_selTempStepper setValueWraps:NO];
    [_selTempStepper setTarget:self];
    [_selTempStepper setAction:@selector(selTempStepperChanged:)];
    [content addSubview:_selTempStepper];
    [content addSubview:[self labelWithText:@"RPM" frame:NSMakeRect(234, 95, 36, 18)]];
    _selRPMField = [[NSTextField alloc] initWithFrame:NSMakeRect(272, 91, 66, 24)];
    [_selRPMField setTarget:self];
    [_selRPMField setAction:@selector(selRPMFieldChanged:)];
    [content addSubview:_selRPMField];
    _selRPMStepper = [[NSStepper alloc] initWithFrame:NSMakeRect(340, 89, 19, 27)];
    [_selRPMStepper setMinValue:0];
    [_selRPMStepper setMaxValue:30000];
    [_selRPMStepper setIncrement:100];
    [_selRPMStepper setValueWraps:NO];
    [_selRPMStepper setTarget:self];
    [_selRPMStepper setAction:@selector(selRPMStepperChanged:)];
    [content addSubview:_selRPMStepper];
    [self updateStepperRanges];
    [self updateSelectedPointUI];

    // --- Add / remove point buttons ---
    [content addSubview:[self labelWithText:@"Points:" frame:NSMakeRect(20, 56, 50, 18)]];
    NSButton *addBtn = [self buttonWithTitle:@"+" frame:NSMakeRect(72, 52, 32, 26) action:@selector(addPoint:)];
    [addBtn setToolTip:@"Add a point to the curve"];
    [content addSubview:addBtn];
    NSButton *removeBtn = [self buttonWithTitle:@"−" frame:NSMakeRect(106, 52, 32, 26) action:@selector(removePoint:)];
    [removeBtn setToolTip:@"Remove the selected point (a curve needs at least two)"];
    [content addSubview:removeBtn];

    // --- Preset picker (replaces the old Restore Default button) ---
    NSPopUpButton *presetPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(W - 200, 52, 180, 26) pullsDown:YES];
    [presetPopup addItemWithTitle:@"Load Preset…"]; // pull-down title item
    for (NSString *name in [FanCurve presetNames]) {
        [presetPopup addItemWithTitle:name];
    }
    [presetPopup setToolTip:@"Replace this fan's curve with a pre-built one (scaled to the fan's hardware limits)"];
    [presetPopup setTarget:self];
    [presetPopup setAction:@selector(loadPreset:)];
    [content addSubview:presetPopup];

    // --- Hint ---
    NSTextField *hint = [self labelWithText:@"Changes apply immediately while Auto Fan Curves is enabled."
                                      frame:NSMakeRect(20, 16, W - 40, 16)];
    [hint setFont:[NSFont systemFontOfSize:10]];
    if (@available(macOS 10.14, *)) [hint setTextColor:[NSColor secondaryLabelColor]];
    [content addSubview:hint];

    _selectedFan = 0;
    [self loadPointsForSelectedFan];
}

#pragma mark Temperature units

- (NSString *)tempColumnTitle {
    return _useFahrenheit ? @"Temperature (°F)" : @"Temperature (°C)";
}

/// Storage is always °C; these convert for display and input.
- (float)displayFromCelsius:(float)c {
    return _useFahrenheit ? (c * 9.0f / 5.0f + 32.0f) : c;
}

- (float)celsiusFromDisplay:(float)v {
    return _useFahrenheit ? ((v - 32.0f) * 5.0f / 9.0f) : v;
}

- (void)updateStepperRanges {
    // Temp clamp is 0–110°C; express it in the display unit.
    [_selTempStepper setMinValue:[self displayFromCelsius:0.0f]];
    [_selTempStepper setMaxValue:[self displayFromCelsius:110.0f]];
}

- (void)unitsChanged:(id)sender {
    _useFahrenheit = ([_unitsSeg selectedSegment] == 1);
    [[self defaults] setObject:@(_useFahrenheit) forKey:PREF_CURVE_EDITOR_FAHRENHEIT];
    [[[_pointsTable tableColumnWithIdentifier:@"temp"] headerCell] setStringValue:[self tempColumnTitle]];
    [[_pointsTable headerView] setNeedsDisplay:YES];
    [_preview setUseFahrenheit:_useFahrenheit];
    [self updateStepperRanges];
    [self populateSensorPopup];
    [self refreshViews];
    [self updateSelectedPointUI];
}

- (NSTextField *)labelWithText:(NSString *)text frame:(NSRect)frame {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    [label setStringValue:text];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    return label;
}

- (NSButton *)buttonWithTitle:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    [button setTitle:title];
    [button setBezelStyle:NSBezelStyleRounded];
    [button setTarget:self];
    [button setAction:action];
    return button;
}

#pragma mark Sensor popup

/// Known Intel SMC CPU temperature keys — same set readTempSensors probes.
+ (NSArray<NSString *> *)knownSensors {
    return @[@"TC0D", @"TC0P", @"TC0H", @"TC0F", @"TCAD", @"TCAH", @"TCBH"];
}

+ (NSString *)sensorDisplayName:(NSString *)key {
    NSDictionary *names = @{
        @"TC0D": @"CPU Die",
        @"TC0P": @"CPU Proximity",
        @"TC0H": @"CPU Heatsink",
        @"TC0F": @"CPU",
        @"TCAD": @"CPU A Die",
        @"TCAH": @"CPU A Heatsink",
        @"TCBH": @"CPU B Heatsink",
    };
    return names[key] ?: key;
}

- (void)populateSensorPopup {
    [_sensorPopup removeAllItems];
    NSString *current = [[self defaults] objectForKey:PREF_TEMPERATURE_SENSOR];

    NSMutableArray *keys = [[[self class] knownSensors] mutableCopy];
    if (current && ![keys containsObject:current]) [keys insertObject:current atIndex:0];

    for (NSString *key in keys) {
        float temp = [smcWrapper get_temp_for_sensor:key];
        BOOL valid = (temp > 0 && floor(temp) != 129);
        // Skip sensors this machine doesn't have, but never hide the active one.
        if (!valid && ![key isEqualToString:current]) continue;
        NSString *title = valid
            ? [NSString stringWithFormat:@"%@ — %@ (%.0f°%@)", key, [[self class] sensorDisplayName:key],
               [self displayFromCelsius:temp], _useFahrenheit ? @"F" : @"C"]
            : [NSString stringWithFormat:@"%@ — %@ (n/a)", key, [[self class] sensorDisplayName:key]];
        [_sensorPopup addItemWithTitle:title];
        [[_sensorPopup lastItem] setRepresentedObject:key];
        if ([key isEqualToString:current]) [_sensorPopup selectItem:[_sensorPopup lastItem]];
    }
}

- (void)sensorSelected:(id)sender {
    NSString *key = [[_sensorPopup selectedItem] representedObject];
    if (!key) return;
    [[self defaults] setObject:key forKey:PREF_TEMPERATURE_SENSOR];
    [[NSNotificationCenter defaultCenter] postNotificationName:NOTE_FAN_CURVES_CHANGED object:nil];
    [self refreshLiveReading];
}

#pragma mark Points model

/// The fan's real hardware minimum from the machine-defaults snapshot.
/// F0Mn is writable (the app itself sets it), so get_min_speed can't be
/// trusted — same reasoning as FanControl's trueMinSpeedForFan:.
- (int)trueMinSpeedForFan:(int)fanIndex {
    static NSDictionary *sMachineDefaults = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sMachineDefaults = [[[MachineDefaults alloc] init:nil] get_machine_defaults];
    });
    NSArray *fans = sMachineDefaults[@"Fans"];
    if ([fans isKindOfClass:[NSArray class]] && fanIndex < (int)[fans count]) {
        int v = [fans[fanIndex][PREF_FAN_MINSPEED] intValue];
        if (v > 0) return v;
    }
    int v = [smcWrapper get_min_speed:fanIndex];
    return (v > 0) ? v : 800;
}

- (void)loadPointsForSelectedFan {
    NSArray *saved = [[self defaults] objectForKey:
        [NSString stringWithFormat:PREF_FAN_CURVE_FMT, _selectedFan]];
    FanCurve *curve = saved ? [FanCurve curveWithPoints:saved] : nil;
    if (!curve) {
        curve = [FanCurve defaultCurveWithMinRPM:[self trueMinSpeedForFan:_selectedFan]
                                          maxRPM:[smcWrapper get_max_speed:_selectedFan]];
    }
    _points = [[curve serialize] mutableCopy];
    [self refreshViews];
}

/// Sort in place, persist to defaults, and tell the control loop.
- (void)persistPoints {
    [_points sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[CURVE_POINT_TEMP] compare:b[CURVE_POINT_TEMP]];
    }];
    if ([FanCurve curveWithPoints:_points]) {
        [[self defaults] setObject:[_points copy]
                            forKey:[NSString stringWithFormat:PREF_FAN_CURVE_FMT, _selectedFan]];
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTE_FAN_CURVES_CHANGED object:nil];
    }
    [self refreshViews];
}

- (void)refreshViews {
    [_pointsTable reloadData];
    [_preview setPoints:_points];
    int hwMax = [smcWrapper get_max_speed:_selectedFan];
    [_preview setHwMax:(hwMax > 0 ? hwMax : 6000)];
    [_preview setNeedsDisplay:YES];
    [self updateSelectedPointUI];
}

- (void)refreshLiveReading {
    NSString *sensor = [[self defaults] objectForKey:PREF_TEMPERATURE_SENSOR];
    float temp = sensor ? [smcWrapper get_temp_for_sensor:sensor] : -1;
    [_preview setCurrentTemp:((temp > 0 && floor(temp) != 129) ? temp : -1)];
    [_preview setNeedsDisplay:YES];
}

#pragma mark Actions

- (void)fanSelected:(id)sender {
    _selectedFan = (int)[_fanPopup indexOfSelectedItem];
    [self loadPointsForSelectedFan];
}

- (void)addPoint:(id)sender {
    // New point 5°C / 200 RPM past the current top of the curve.
    NSDictionary *last = [_points lastObject];
    float temp = last ? [last[CURVE_POINT_TEMP] floatValue] + 5.0f : 60.0f;
    int rpm = last ? [last[CURVE_POINT_RPM] intValue] + 200 : 2000;
    if (temp > 110.0f) temp = 110.0f;
    [_points addObject:@{CURVE_POINT_TEMP: @(temp), CURVE_POINT_RPM: @(rpm)}];
    [self persistPoints];
    [_pointsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:[_points count] - 1]
              byExtendingSelection:NO];
}

- (void)removePoint:(id)sender {
    NSInteger row = [_pointsTable selectedRow];
    if (row < 0 || [_points count] <= 2) {
        NSBeep(); // a curve needs at least two points
        return;
    }
    [_points removeObjectAtIndex:row];
    [self persistPoints];
}

- (void)loadPreset:(id)sender {
    NSString *name = [[(NSPopUpButton *)sender selectedItem] title];
    FanCurve *curve = [FanCurve presetCurveNamed:name
                                          minRPM:[self trueMinSpeedForFan:_selectedFan]
                                          maxRPM:[smcWrapper get_max_speed:_selectedFan]];
    if (!curve) return; // title item or unknown name
    _points = [[curve serialize] mutableCopy];
    [self persistPoints];
}

#pragma mark Table data source

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [_points count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSDictionary *p = _points[row];
    if ([[column identifier] isEqualToString:@"temp"]) {
        return [NSString stringWithFormat:@"%.1f", [self displayFromCelsius:[p[CURVE_POINT_TEMP] floatValue]]];
    }
    return [NSString stringWithFormat:@"%d", [p[CURVE_POINT_RPM] intValue]];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if ([[column identifier] isEqualToString:@"temp"]) {
        [self setTemp:[self celsiusFromDisplay:[value floatValue]] forPointAtRow:row];
    } else {
        [self setRPM:[value intValue] forPointAtRow:row];
    }
}

#pragma mark Selected-point editing

/// Update one point's temperature (°C), persist, and keep it selected even
/// though persisting re-sorts the array.
- (void)setTemp:(float)tempC forPointAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)[_points count]) return;
    if (tempC < 0.0f) tempC = 0.0f;
    if (tempC > 110.0f) tempC = 110.0f;
    NSMutableDictionary *p = [_points[row] mutableCopy];
    p[CURVE_POINT_TEMP] = @(tempC);
    _points[row] = p;
    [self persistPointsKeepingSelectionOn:p];
}

- (void)setRPM:(int)rpm forPointAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)[_points count]) return;
    if (rpm < 0) rpm = 0;
    if (rpm > 30000) rpm = 30000;
    NSMutableDictionary *p = [_points[row] mutableCopy];
    p[CURVE_POINT_RPM] = @(rpm);
    _points[row] = p;
    [self persistPointsKeepingSelectionOn:p];
}

- (void)persistPointsKeepingSelectionOn:(NSDictionary *)point {
    [self persistPoints];
    NSUInteger newRow = [_points indexOfObjectIdenticalTo:point];
    if (newRow != NSNotFound) {
        [_pointsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:newRow]
                  byExtendingSelection:NO];
    }
    [self updateSelectedPointUI];
}

/// Mirror the selected table row into the field/stepper editors.
- (void)updateSelectedPointUI {
    NSInteger row = [_pointsTable selectedRow];
    BOOL has = (row >= 0 && row < (NSInteger)[_points count]);
    [_selTempField setEnabled:has];
    [_selTempStepper setEnabled:has];
    [_selRPMField setEnabled:has];
    [_selRPMStepper setEnabled:has];
    if (!has) {
        [_selTempField setStringValue:@""];
        [_selRPMField setStringValue:@""];
        return;
    }
    NSDictionary *p = _points[row];
    float dispTemp = [self displayFromCelsius:[p[CURVE_POINT_TEMP] floatValue]];
    int rpm = [p[CURVE_POINT_RPM] intValue];
    [_selTempField setStringValue:[NSString stringWithFormat:@"%.1f", dispTemp]];
    [_selTempStepper setDoubleValue:dispTemp];
    [_selRPMField setStringValue:[NSString stringWithFormat:@"%d", rpm]];
    [_selRPMStepper setIntValue:rpm];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateSelectedPointUI];
}

- (void)selTempFieldChanged:(id)sender {
    [self setTemp:[self celsiusFromDisplay:[_selTempField floatValue]]
        forPointAtRow:[_pointsTable selectedRow]];
}

- (void)selTempStepperChanged:(id)sender {
    [self setTemp:[self celsiusFromDisplay:(float)[_selTempStepper doubleValue]]
        forPointAtRow:[_pointsTable selectedRow]];
}

- (void)selRPMFieldChanged:(id)sender {
    [self setRPM:[_selRPMField intValue] forPointAtRow:[_pointsTable selectedRow]];
}

- (void)selRPMStepperChanged:(id)sender {
    [self setRPM:[_selRPMStepper intValue] forPointAtRow:[_pointsTable selectedRow]];
}

#pragma mark Enable toggle

- (void)syncEnableState {
    [_enableCheckbox setState:
        [[[self defaults] objectForKey:PREF_AUTOCURVE_ENABLED] boolValue] ? NSOnState : NSOffState];
}

- (void)toggleEnabled:(id)sender {
    BOOL enabled = ([_enableCheckbox state] == NSOnState);
    [[self defaults] setObject:@(enabled) forKey:PREF_AUTOCURVE_ENABLED];
    [[NSNotificationCenter defaultCenter] postNotificationName:NOTE_AUTOCURVE_STATE_CHANGED object:nil];
}

#pragma mark Display lifecycle

- (void)prepareForDisplay {
    [self editorView]; // make sure the pane exists
    [self syncEnableState];
    [_fanPopup selectItemAtIndex:_selectedFan];
    [self loadPointsForSelectedFan];
    [self populateSensorPopup];
    [self refreshLiveReading];
    if (!_refreshTimer) {
        _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                         target:self
                                                       selector:@selector(refreshTick:)
                                                       userInfo:nil
                                                        repeats:YES];
    }
}

- (void)refreshTick:(id)caller {
    // The pane may be in a hidden tab or closed window — skip SMC reads then.
    if (![[_view window] isVisible]) {
        return;
    }
    [self refreshLiveReading];
}

- (void)displayDidHide {
    [_refreshTimer invalidate];
    _refreshTimer = nil;
}

@end
