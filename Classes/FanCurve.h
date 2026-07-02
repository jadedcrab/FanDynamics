/*
 *	FanControl
 *
 *	Copyright (c) 2026 smcFanControl Community Edition contributors
 *
 *	FanCurve.h - temperature→RPM curve model for automatic fan control
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Dictionary keys for serialized curve points.
#define CURVE_POINT_TEMP @"temp"
#define CURVE_POINT_RPM  @"rpm"

/// A piecewise-linear temperature→RPM curve for one fan.
///
/// Points are (tempC, rpm) pairs kept sorted by temperature. Between two
/// points the RPM is linearly interpolated; below the first point the first
/// point's RPM applies, above the last point the last point's RPM applies.
///
/// The curve itself knows nothing about hardware limits — the controller is
/// responsible for clamping the returned RPM to [hwMin, hwMax] before
/// writing to the SMC.
@interface FanCurve : NSObject

/// Sorted array of curve points, each @{CURVE_POINT_TEMP: NSNumber(float),
/// CURVE_POINT_RPM: NSNumber(int)}. Never empty for a valid curve.
@property (nonatomic, readonly, copy) NSArray<NSDictionary *> *points;

/// Create a curve from serialized points (e.g. out of NSUserDefaults).
/// Points are sorted by temperature on init; malformed entries are dropped.
/// Returns nil if fewer than 2 valid points remain.
+ (nullable instancetype)curveWithPoints:(NSArray<NSDictionary *> *)points;

/// A conservative default curve for a fan with the given hardware limits:
/// hwMin below 50°C ramping linearly to hwMax at 85°C.
+ (instancetype)defaultCurveWithMinRPM:(int)hwMin maxRPM:(int)hwMax;

/// Piecewise-linear interpolation of the curve at the given temperature.
- (int)rpmForTemperature:(float)tempC;

/// Serialized representation suitable for NSUserDefaults.
- (NSArray<NSDictionary *> *)serialize;

@end

NS_ASSUME_NONNULL_END
