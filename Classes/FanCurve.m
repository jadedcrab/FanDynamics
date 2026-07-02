/*
 *	FanControl
 *
 *	Copyright (c) 2026 smcFanControl Community Edition contributors
 *
 *	FanCurve.m - temperature→RPM curve model for automatic fan control
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

#import "FanCurve.h"

@implementation FanCurve

+ (nullable instancetype)curveWithPoints:(NSArray<NSDictionary *> *)points {
    // Drop malformed entries (missing keys / wrong types).
    NSMutableArray<NSDictionary *> *valid = [NSMutableArray array];
    for (id entry in points) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        id t = entry[CURVE_POINT_TEMP];
        id r = entry[CURVE_POINT_RPM];
        if (![t isKindOfClass:[NSNumber class]] || ![r isKindOfClass:[NSNumber class]]) continue;
        [valid addObject:@{CURVE_POINT_TEMP: t, CURVE_POINT_RPM: r}];
    }
    if ([valid count] < 2) return nil;

    [valid sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[CURVE_POINT_TEMP] compare:b[CURVE_POINT_TEMP]];
    }];

    FanCurve *curve = [[FanCurve alloc] init];
    curve->_points = [valid copy];
    return curve;
}

+ (instancetype)defaultCurveWithMinRPM:(int)hwMin maxRPM:(int)hwMax {
    if (hwMin <= 0) hwMin = 800;
    if (hwMax <= hwMin) hwMax = hwMin + 4000;
    return [self curveWithPoints:@[
        @{CURVE_POINT_TEMP: @50.0f, CURVE_POINT_RPM: @(hwMin)},
        @{CURVE_POINT_TEMP: @85.0f, CURVE_POINT_RPM: @(hwMax)},
    ]];
}

- (int)rpmForTemperature:(float)tempC {
    NSArray<NSDictionary *> *pts = _points;
    NSUInteger n = [pts count];

    // Clamp outside the curve's temperature range.
    if (tempC <= [pts[0][CURVE_POINT_TEMP] floatValue]) {
        return [pts[0][CURVE_POINT_RPM] intValue];
    }
    if (tempC >= [pts[n - 1][CURVE_POINT_TEMP] floatValue]) {
        return [pts[n - 1][CURVE_POINT_RPM] intValue];
    }

    // Find the segment containing tempC and interpolate linearly.
    for (NSUInteger i = 1; i < n; i++) {
        float t1 = [pts[i][CURVE_POINT_TEMP] floatValue];
        if (tempC > t1) continue;
        float t0 = [pts[i - 1][CURVE_POINT_TEMP] floatValue];
        int r0 = [pts[i - 1][CURVE_POINT_RPM] intValue];
        int r1 = [pts[i][CURVE_POINT_RPM] intValue];
        if (t1 <= t0) return r1; // duplicate temps — take the later point
        float frac = (tempC - t0) / (t1 - t0);
        return r0 + (int)lroundf(frac * (float)(r1 - r0));
    }
    return [pts[n - 1][CURVE_POINT_RPM] intValue]; // unreachable
}

- (NSArray<NSDictionary *> *)serialize {
    return _points;
}

@end
