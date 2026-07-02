/*
 *	FanControl
 *
 *	Copyright (c) 2006-2012 Hendrik Holtmann
 *  Portions Copyright (c) 2013 Michael Wilber
 *
 *	FanControl.m - MacBook(Pro) FanControl application
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
 

#import "FanControl.h"
#import "MachineDefaults.h"
#import "SleepWakeFix.h"
#import "OCLPHelper.h"
#import "FanCurve.h"
#import "CurveEditorController.h"
#import <Security/Authorization.h>
#import <Security/AuthorizationDB.h>
#import <Security/AuthorizationTags.h>
#include <signal.h>
// Sparkle removed — dead update server (eidac.de), will add GitHub-based updates later

@interface FanControl ()
+ (void)copyMachinesIfNecessary;
+ (void)terminateIfNoFans;
@property (NS_NONATOMIC_IOSONLY, getter=isInAutoStart, readonly) BOOL inAutoStart;
- (void)setStartAtLogin:(BOOL)enabled;
+ (BOOL)smcBinaryHasCorrectPermissions;
+ (void)checkRightStatus:(OSStatus)status;
@end

@implementation FanControl

// Number of fans reported by the hardware.
int g_numFans = 0;


NSUserDefaults *defaults;

#pragma mark **Init-Methods**

+(void) initialize {
    
	//avoid Zombies when starting external app
	signal(SIGCHLD, SIG_IGN);

	//check owner and suid rights
	[FanControl setRights];

	//talk to smc
	[smcWrapper init];

	[FanControl terminateIfNoFans];

	[FanControl copyMachinesIfNecessary];

	//app in foreground for update notifications
	[[NSApplication sharedApplication] activateIgnoringOtherApps:YES];

}

+(void) terminateIfNoFans {
    int fan_num = [smcWrapper get_fan_num];
    if (fan_num <= 0) {
        NSLog(@"Exiting as %d fans were detected for Model Identifier: %@", fan_num, [MachineDefaults computerModel]);
        [[NSApplication sharedApplication] terminate:self];
    }
}

+(void)copyMachinesIfNecessary
{
    NSString *path = [[[NSFileManager defaultManager] applicationSupportDirectory] stringByAppendingPathComponent:@"Machines.plist"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] copyItemAtPath:[[NSBundle mainBundle] pathForResource:@"Machines" ofType:@"plist"] toPath:path error:nil];
    }
}

-(void)upgradeFavorites
{
	//upgrade favorites
	NSArray *rfavorites = [FavoritesController arrangedObjects];
	int j;
	int i;
	for (i=0;i<[rfavorites count];i++)
	{
		BOOL selected = NO;
		NSArray *fans = rfavorites[i][PREF_FAN_ARRAY];
		for (j=0;j<[fans count];j++) {
			if ([fans[j][PREF_FAN_SHOWMENU] boolValue] == YES ) {
				selected = YES;
			}
		}
		if (selected==NO) {
			rfavorites[i][PREF_FAN_ARRAY][0][PREF_FAN_SHOWMENU] = @YES;
		}
	}
	
}

-(void) awakeFromNib {
    
	pw=[[Power alloc] init];
	[pw setDelegate:self];
	[pw registerForSleepWakeNotification];
	[pw registerForPowerChange];
	

    //load defaults

    [DefaultsController setAppliesImmediately:NO];

	mdefaults=[[MachineDefaults alloc] init:nil];

    self.machineDefaultsDict=[[NSMutableDictionary alloc] initWithDictionary:[mdefaults get_machine_defaults]];

    // Preferences window foreground handling is done via openPreferences: IBAction
    // wired from the menu item in init_statusitem (replaces notification approach).

    NSMutableArray *favorites = [[NSMutableArray alloc] init];
    
    NSMutableDictionary *defaultFav = [[NSMutableDictionary alloc] initWithObjectsAndKeys:@"Default", PREF_FAN_TITLE,
                                  [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:[[mdefaults get_machine_defaults] objectForKey:@"Fans"]]], PREF_FAN_ARRAY,nil];

    [favorites addObject:defaultFav];
    
    
	NSRange range=[[MachineDefaults computerModel] rangeOfString:@"MacBook"];
	if (range.length>0) {
		//for macbooks add a second default
		NSMutableDictionary *higherFav=[[NSMutableDictionary alloc] initWithObjectsAndKeys:@"Higher RPM", PREF_FAN_TITLE,
                                        [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:[[mdefaults get_machine_defaults] objectForKey:@"Fans"]]], PREF_FAN_ARRAY,nil];
		for (NSUInteger i=0;i<[_machineDefaultsDict[@"Fans"] count];i++) {
            
            int min_value=([[[[_machineDefaultsDict objectForKey:@"Fans"] objectAtIndex:i] objectForKey:PREF_FAN_MINSPEED] intValue])*2;
            [[[higherFav objectForKey:PREF_FAN_ARRAY] objectAtIndex:i] setObject:[NSNumber numberWithInt:min_value] forKey:PREF_FAN_SELSPEED];
		}
        [favorites addObject:higherFav];

	}

	//sync option for Macbook Pro's
	NSRange range_mbp=[[MachineDefaults computerModel] rangeOfString:@"MacBookPro"];
	if (range_mbp.length>0  && [_machineDefaultsDict[@"Fans"] count] == 2) {
		[sync setHidden:NO];
	}

	//load user defaults
	defaults = [NSUserDefaults standardUserDefaults];

	[defaults registerDefaults:
		[NSMutableDictionary dictionaryWithObjectsAndKeys:
			@0, PREF_SELECTION_DEFAULT,
			@NO,PREF_AUTOSTART_ENABLED,
			@NO,PREF_AUTOMATIC_CHANGE,
			@0, PREF_BATTERY_SELECTION,
			@0, PREF_AC_SELECTION,
			@0, PREF_CHARGING_SELECTION,
			@2, PREF_MENU_DISPLAYMODE,
            @"TC0D",PREF_TEMPERATURE_SENSOR,
            @0, PREF_NUMBEROF_LAUNCHES,
			[NSKeyedArchiver archivedDataWithRootObject:[NSColor blackColor] requiringSecureCoding:NO error:nil],PREF_MENU_TEXTCOLOR,
			favorites,PREF_FAVORITES_ARRAY,
	nil]];
	
	

	g_numFans = [smcWrapper get_fan_num];
	s_menus=[[NSMutableArray alloc] init];
	int i;
	for(i=0;i<g_numFans;i++){
		NSMenuItem *mitem=[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Fan: %d",i] action:NULL keyEquivalent:@""];
		[mitem setTag:(i+1)*10];
		[s_menus insertObject:mitem atIndex:i];
	}
	
	[FavoritesController bind:@"content"
             toObject:[NSUserDefaultsController sharedUserDefaultsController]
          withKeyPath:[@"values." stringByAppendingString:PREF_FAVORITES_ARRAY]
              options:nil];
	[FavoritesController setEditable:YES];
	
	// set slider sync - only for MBP
	for (i=0;i<[[FavoritesController arrangedObjects] count];i++) {
		if([[FavoritesController arrangedObjects][i][PREF_FAN_SYNC] boolValue]==YES) {
			[FavoritesController setSelectionIndex:i];
			[self syncBinder:[[FavoritesController arrangedObjects][i][PREF_FAN_SYNC] boolValue]];
		}
	}

	//init statusitem
	[self init_statusitem];

	
	[programinfo setStringValue: [NSString stringWithFormat:@"%@ %@",[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"]
	,[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ]];
	//
	[copyright setStringValue:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSHumanReadableCopyright"]];

	
	//power controls only available on portables
	if (range.length>0) {
		[autochange setEnabled:true];
	} else {
		[autochange setEnabled:false];
	}
	[faqText replaceCharactersInRange:NSMakeRange(0,0) withRTF: [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"F.A.Q" ofType:@"rtf"]]];
	// Apply saved per-fan RPM settings (replaces old favorites-based apply)
	[self applyPerFanSettings];
	// Start the auto-curve control loop if it was enabled last session
	[self updateAutoCurveState];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(fanCurvesChanged:)
	                                             name:NOTE_FAN_CURVES_CHANGED
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(autoCurveStateChanged:)
	                                             name:NOTE_AUTOCURVE_STATE_CHANGED
	                                           object:nil];
	// SIGTERM (pkill, logout, shutdown) doesn't run the menu Quit path, which
	// would leave the fans in forced mode. Route it through terminate: so the
	// SMC gets handed back its fans.
	signal(SIGTERM, SIG_IGN);
	static dispatch_source_t sSigTermSource;
	sSigTermSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
	__weak typeof(self) weakSelf = self;
	dispatch_source_set_event_handler(sSigTermSource, ^{
		[weakSelf terminate:nil];
	});
	dispatch_resume(sSigTermSource);
	// Check for OCLP and prompt for boot daemon on first launch
	[OCLPHelper checkAndPromptForDaemonInstall];
	[[sliderCell dataCell] setControlSize:NSControlSizeSmall];
	[self changeMenu:nil];
	
	//seting toolbar image — prefer SF Symbol on macOS 11+, fall back to PNG
    if (@available(macOS 11.0, *)) {
        NSImage *fanIcon = [NSImage imageWithSystemSymbolName:@"fan.fill" accessibilityDescription:@"Fan Control"];
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightRegular];
        fanIcon = [fanIcon imageWithSymbolConfiguration:config];
        [fanIcon setTemplate:YES];
        menu_image = fanIcon;
        menu_image_alt = fanIcon;
    } else {
        menu_image = [[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"smc" ofType:@"png"]];
        menu_image_alt  = [[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"smcover" ofType:@"png"]];
        if ([menu_image respondsToSelector:@selector(setTemplate:)]) {
            [menu_image setTemplate:YES];
            [menu_image_alt setTemplate:YES];
        }
    }

	//add timer for reading to RunLoop — use slow interval for icon-only mode
	{
		int initMode = [[defaults objectForKey:PREF_MENU_DISPLAYMODE] intValue];
		NSTimeInterval interval = (initMode == 2) ? 60.0 : 4.0;
		_readTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(readFanData:) userInfo:nil repeats:YES];
		if ([_readTimer respondsToSelector:@selector(setTolerance:)]) {
			[_readTimer setTolerance:(initMode == 2) ? 10.0 : 2.0];
		}
	}
	[_readTimer fire];
    
	//autoapply settings if valid
	[self upgradeFavorites];
    
    //autostart
    [[NSUserDefaults standardUserDefaults] setValue:@([self isInAutoStart]) forKey:PREF_AUTOSTART_ENABLED];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(readFanData:) name:@"AppleInterfaceThemeChangedNotification" object:nil];

    // Modernize preferences window — transparent titlebar, follow system appearance
    if (mainwindow) {
        [(NSWindow *)mainwindow setTitlebarAppearsTransparent:YES];
        [(NSWindow *)mainwindow setTitleVisibility:NSWindowTitleHidden];
    }

    // Repurpose the old PayPal donate text field in the About window to show a Ko-fi link.
    // The About window (nib id 377) has a text field at y~59 that contained the old
    // PayPal/donation message.  Replace its content with a clickable Ko-fi link.
    for (NSWindow *win in [NSApp windows]) {
        if (win == (NSWindow *)mainwindow) continue;  // skip preferences window
        if (win == (NSWindow *)faqWindow) continue;    // skip FAQ window
        if (win == (NSWindow *)newfavoritewindow) continue;
        // The About window title varies by locale but always contains "smcFanControl".
        if (![[win title] containsString:@"smcFanControl"]) continue;
        for (NSView *subview in [[win contentView] subviews]) {
            if (![subview isKindOfClass:[NSTextField class]]) continue;
            NSTextField *tf = (NSTextField *)subview;
            NSString *text = [tf stringValue] ?: @"";
            NSString *lower = [text lowercaseString];
            BOOL hasDonateText = ([lower containsString:@"donat"] ||
                                  [lower containsString:@"paypal"] ||
                                  [lower containsString:@"spende"]);
            BOOL isEmptyDonateField = (text.length == 0 &&
                                       NSMinY(subview.frame) >= 50 &&
                                       NSMinY(subview.frame) <= 70 &&
                                       NSHeight(subview.frame) >= 40 &&
                                       NSHeight(subview.frame) <= 60);
            if (hasDonateText || isEmptyDonateField) {
                // Replace with clickable Ko-fi link
                [tf setAllowsEditingTextAttributes:YES];
                [tf setSelectable:YES];
                NSString *linkText = @"Support smcFanControl CE on Ko-fi";
                NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc]
                    initWithString:linkText];
                NSURL *kofiURL = [NSURL URLWithString:@"https://ko-fi.com/wolffcatskyy"];
                [attrStr addAttribute:NSLinkAttributeName value:kofiURL
                                range:NSMakeRange(0, linkText.length)];
                [attrStr addAttribute:NSFontAttributeName
                                value:[NSFont systemFontOfSize:11]
                                range:NSMakeRange(0, linkText.length)];
                NSMutableParagraphStyle *pstyle = [[NSMutableParagraphStyle alloc] init];
                [pstyle setAlignment:NSTextAlignmentCenter];
                [attrStr addAttribute:NSParagraphStyleAttributeName value:pstyle
                                range:NSMakeRange(0, linkText.length)];
                [tf setAttributedStringValue:attrStr];
                [tf setHidden:NO];
            }
        }
    }

    // Hide the temperature unit preference controls (C/F radio buttons and label).
    // Temperature unit now comes solely from the system locale — no user override.
    // The controls are in the preferences window: a label "Temperature unit:" (nib id 537)
    // and a radio matrix (nib id 538) bound to values.Unit.
    if (mainwindow) {
        // Walk the preferences window subview tree to find and hide the controls.
        NSView *contentView = [(NSWindow *)mainwindow contentView];
        NSMutableArray *stack = [NSMutableArray arrayWithObject:contentView];
        while (stack.count > 0) {
            NSView *v = stack.lastObject;
            [stack removeLastObject];
            [stack addObjectsFromArray:v.subviews];

            // Hide "Temperature unit:" label
            if ([v isKindOfClass:[NSTextField class]]) {
                NSTextField *tf = (NSTextField *)v;
                if ([[tf stringValue] containsString:@"Temperature unit"] ||
                    [[tf stringValue] containsString:@"Temperatur"]) {
                    [tf setHidden:YES];
                }
            }
            // Hide the C/F radio button matrix bound to values.Unit
            if ([v isKindOfClass:[NSMatrix class]]) {
                NSMatrix *matrix = (NSMatrix *)v;
                NSArray *cells = [matrix cells];
                if (cells.count == 2) {
                    NSString *t0 = [[cells objectAtIndex:0] title] ?: @"";
                    NSString *t1 = [[cells objectAtIndex:1] title] ?: @"";
                    if ([t0 containsString:@"°C"] && [t1 containsString:@"°F"]) {
                        [matrix setHidden:YES];
                    }
                }
            }
        }
    }

    // Hide favorites UI elements in preferences window (favorites are obsolete in CE).
    // Walk the view hierarchy and hide: "Favorite:" / "Default" labels, the favorites
    // popup button, and Add/Remove buttons near the favorites section.
    if (mainwindow) {
        NSView *prefContent = [(NSWindow *)mainwindow contentView];
        NSMutableArray *prefStack = [NSMutableArray arrayWithObject:prefContent];
        while (prefStack.count > 0) {
            NSView *v = prefStack.lastObject;
            [prefStack removeLastObject];
            [prefStack addObjectsFromArray:v.subviews];

            // Hide labels containing "Favorite" or showing "Default"
            if ([v isKindOfClass:[NSTextField class]]) {
                NSTextField *tf = (NSTextField *)v;
                NSString *text = [tf stringValue] ?: @"";
                NSString *lower = [text lowercaseString];
                if ([lower containsString:@"favorite"] ||
                    [lower containsString:@"favorit"] ||  // German: Favorit
                    [text isEqualToString:@"Default"] ||
                    [text isEqualToString:@"Standard"]) { // German localization
                    [tf setHidden:YES];
                }
            }

            // Hide NSPopUpButton (favorites dropdown) — the only popup in prefs is favorites
            if ([v isKindOfClass:[NSPopUpButton class]]) {
                NSPopUpButton *popup = (NSPopUpButton *)v;
                // Check if any item title matches favorites-related text
                BOOL isFavPopup = NO;
                for (NSMenuItem *item in [popup itemArray]) {
                    NSString *itemTitle = [[item title] lowercaseString];
                    if ([itemTitle containsString:@"default"] ||
                        [itemTitle containsString:@"favorite"] ||
                        [itemTitle containsString:@"higher rpm"]) {
                        isFavPopup = YES;
                        break;
                    }
                }
                if (isFavPopup) {
                    [popup setHidden:YES];
                }
            }

            // Hide NSComboBox if used for favorites
            if ([v isKindOfClass:[NSComboBox class]]) {
                [v setHidden:YES];
            }

            // Hide Add (+) / Remove (-) buttons near favorites
            if ([v isKindOfClass:[NSButton class]]) {
                NSButton *btn = (NSButton *)v;
                NSString *title = [[btn title] lowercaseString];
                // Match "+", "-", "Add", "Remove", or segmented add/remove controls
                if ([title isEqualToString:@"+"] ||
                    [title isEqualToString:@"-"] ||
                    [title isEqualToString:@"add"] ||
                    [title isEqualToString:@"remove"]) {
                    [btn setHidden:YES];
                }
            }

            // Hide NSSegmentedControl (often used for +/- buttons in nibs)
            if ([v isKindOfClass:[NSSegmentedControl class]]) {
                NSSegmentedControl *seg = (NSSegmentedControl *)v;
                if ([seg segmentCount] == 2) {
                    NSString *s0 = [seg labelForSegment:0] ?: @"";
                    NSString *s1 = [seg labelForSegment:1] ?: @"";
                    if (([s0 isEqualToString:@"+"] && [s1 isEqualToString:@"-"]) ||
                        ([s0 isEqualToString:@"-"] && [s1 isEqualToString:@"+"])) {
                        [seg setHidden:YES];
                    }
                }
            }
        }
    }

    // Hide advanced preferences that aren't needed in the simplified UI.
    // Keep: Start at login checkbox, menu bar display mode, OCLP toggle.
    // Hide: auto-change power settings, color selector, fan table, sync checkbox.
    if (mainwindow) {
        // Hide the auto-change checkbox and its associated power-source popups
        if (autochange) [(NSView *)autochange setHidden:YES];
        if (colorSelector) [(NSView *)colorSelector setHidden:YES];
        if (syncslider) [(NSView *)syncslider setHidden:YES];

        // Hide the fan table (old per-fan settings table from nib) — replaced by menu sliders
        NSView *prefContent2 = [(NSWindow *)mainwindow contentView];
        NSMutableArray *stack2 = [NSMutableArray arrayWithObject:prefContent2];
        while (stack2.count > 0) {
            NSView *v = stack2.lastObject;
            [stack2 removeLastObject];
            [stack2 addObjectsFromArray:v.subviews];

            // Hide the fan table scroll view
            if ([v isKindOfClass:[NSScrollView class]]) {
                NSScrollView *sv = (NSScrollView *)v;
                // Check if this scroll view contains a table (the fan table)
                if ([sv.documentView isKindOfClass:[NSTableView class]]) {
                    [sv setHidden:YES];
                }
            }

            // Hide labels related to auto-change power settings
            if ([v isKindOfClass:[NSTextField class]]) {
                NSTextField *tf = (NSTextField *)v;
                NSString *text = [tf stringValue] ?: @"";
                NSString *lower = [text lowercaseString];
                if ([lower containsString:@"battery"] ||
                    [lower containsString:@"batterie"] ||  // German
                    [lower containsString:@"power source"] ||
                    [lower containsString:@"charging"] ||
                    [lower containsString:@"laden"] ||     // German: charging
                    [lower containsString:@"stromquelle"] || // German: power source
                    [lower containsString:@"color"] ||
                    [lower containsString:@"farbe"] ||     // German: color
                    [lower containsString:@"couleur"]) {   // French: color
                    [tf setHidden:YES];
                }
            }

            // Hide power-source popup buttons (Battery/AC/Charging favorites selectors)
            if ([v isKindOfClass:[NSPopUpButton class]] && ![v isHidden]) {
                NSPopUpButton *popup = (NSPopUpButton *)v;
                // These popups are bound to battery/AC/charging selection prefs
                for (NSDictionary *binding in @[@{@"key": @"selectedIndex"}]) {
                    NSDictionary *info = [popup infoForBinding:@"selectedIndex"];
                    if (info) {
                        NSString *keyPath = info[NSObservedKeyPathKey] ?: @"";
                        if ([keyPath containsString:@"selbatt"] ||
                            [keyPath containsString:@"selac"] ||
                            [keyPath containsString:@"selload"]) {
                            [popup setHidden:YES];
                        }
                    }
                }
            }

            // Hide the "Autoapply favorite when powersource changes" checkbox
            if ([v isKindOfClass:[NSButton class]]) {
                NSButton *btn = (NSButton *)v;
                NSString *title = [[btn title] lowercaseString];
                if ([title containsString:@"autoapply"] ||
                    [title containsString:@"powersource"] ||
                    [title containsString:@"power source"] ||
                    [title containsString:@"automatisch"] ||  // German
                    [title containsString:@"stromquelle"]) {  // German
                    [btn setHidden:YES];
                }
            }
        }
    }

}


-(void)init_statusitem{
	statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength: NSVariableStatusItemLength];

    // Build the menu entirely in code — ignore the nib menu items for the dropdown.
    // We keep theMenu as the IBOutlet but clear it and rebuild.
    [theMenu removeAllItems];
    [theMenu setDelegate:self];
    [statusItem setMenu:theMenu];

    if ([statusItem respondsToSelector:@selector(button)]) {
        [statusItem.button setTitle:@"fan..."];
    } else {
        [statusItem setEnabled: YES];
        [statusItem setHighlightMode:YES];
        [statusItem setTitle:@"fan..."];
    }

    // The pull-down stays minimal: the two quick toggles, Preferences, and
    // Quit. Everything else (sliders, curve editor, Sleep/Wake Fix, OCLP
    // daemon) lives in the settings window.
    _fanSliderViews = [[NSMutableArray alloc] init];
    _fanSliders = [[NSMutableArray alloc] init];
    _fanRPMLabels = [[NSMutableArray alloc] init];
    _fanMenuItems = [[NSMutableArray alloc] init];

    // --- Show Temp & RPM in Menu Bar toggle ---
    NSMenuItem *menuInfoItem = [[NSMenuItem alloc]
        initWithTitle:@"Show Temp & RPM in Menu Bar"
               action:@selector(toggleMenuInfo:)
        keyEquivalent:@""];
    [menuInfoItem setTarget:self];
    [menuInfoItem setTag:9902]; // synced with the Status tab checkbox
    if ([[defaults objectForKey:PREF_MENU_DISPLAYMODE] intValue] != 2) {
        [menuInfoItem setState:NSOnState];
    }
    [theMenu addItem:menuInfoItem];

    // --- Auto Fan Curves toggle ---
    NSMenuItem *autoCurveItem = [[NSMenuItem alloc]
        initWithTitle:@"Auto Fan Curves"
               action:@selector(toggleAutoCurves:)
        keyEquivalent:@""];
    [autoCurveItem setTarget:self];
    [autoCurveItem setTag:9901]; // found by autoCurveStateChanged: to sync the checkmark
    if ([[defaults objectForKey:PREF_AUTOCURVE_ENABLED] boolValue]) {
        [autoCurveItem setState:NSOnState];
    }
    [theMenu addItem:autoCurveItem];

    // --- Preferences... ---
    NSMenuItem *prefsItem = [[NSMenuItem alloc]
        initWithTitle:@"Preferences..."
               action:@selector(openPreferences:)
        keyEquivalent:@""];
    [prefsItem setTarget:self];
    [theMenu addItem:prefsItem];

    // --- Separator ---
    [theMenu addItem:[NSMenuItem separatorItem]];

    // --- Quit ---
    NSMenuItem *quitItem = [[NSMenuItem alloc]
        initWithTitle:@"Quit FanDynamics"
               action:@selector(terminate:)
        keyEquivalent:@""];
    [quitItem setTarget:self];
    [theMenu addItem:quitItem];
}

#pragma mark **OCLP Toggle**

#pragma mark **Slider Menu Actions**

/// Called when user drags a fan slider in the menu.
-(void)fanSliderChanged:(id)sender {
    NSSlider *slider = (NSSlider *)sender;
    int fanIndex = (int)[slider tag];
    int newRPM = (int)[slider integerValue];

    // Update the RPM label next to the slider
    if (fanIndex < (int)[_fanRPMLabels count]) {
        NSTextField *label = _fanRPMLabels[fanIndex];
        [label setStringValue:[NSString stringWithFormat:@"%d rpm", newRPM]];
    }

    [FanControl setRights];

    // Determine hardware minimum to decide auto vs forced mode
    int hwMin = [smcWrapper get_min_speed:fanIndex];
    if (hwMin <= 0) hwMin = 800;

    if (newRPM <= hwMin) {
        // Return this fan to automatic mode — clear its force bit in FS!
        [self setForcedMode:NO forFan:fanIndex];
    } else {
        // Force this fan to the requested speed
        [self setForcedMode:YES forFan:fanIndex];
        // Set target speed (fpe2 encoded)
        [smcWrapper setKey_external:[NSString stringWithFormat:@"F%dTg", fanIndex]
                              value:[@(newRPM) tohex]];
    }

    // Also set the minimum as a floor
    [smcWrapper setKey_external:[NSString stringWithFormat:@"F%dMn", fanIndex]
                          value:[@(newRPM) tohex]];

    // Persist to NSUserDefaults
    NSString *prefKey = [NSString stringWithFormat:@"fan_%d_min_rpm", fanIndex];
    [[NSUserDefaults standardUserDefaults] setInteger:newRPM forKey:prefKey];

    // Sync to boot daemon plist so next boot uses updated settings
    [OCLPHelper syncFanSettingsWithDaemon];
}

/// Set or clear forced mode for a specific fan by manipulating the FS!  bitmask.
-(void)setForcedMode:(BOOL)forced forFan:(int)fanIndex {
    // Read current FS!  value (ui16 — 2 bytes, big-endian bitmask)
    // Bit 0 = fan 0, bit 1 = fan 1, etc.
    // We try the F{n}Md key first (older Macs), fall back to FS!  (newer Macs).
    int fanMode = [smcWrapper get_mode:fanIndex];
    if (fanMode >= 0) {
        // This Mac has per-fan mode keys (F0Md, F1Md, ...)
        [smcWrapper setKey_external:[NSString stringWithFormat:@"F%dMd", fanIndex]
                              value:forced ? @"01" : @"00"];
    } else {
        // Use the global FS!  bitmask (ui16)
        // Read current bitmask — we encode it as a 4-hex-digit string
        // Unfortunately we can't read FS!  easily through smcWrapper (no API for it),
        // so we maintain a local cache of which fans are forced.
        static UInt16 sForceBitmask = 0;
        if (forced) {
            sForceBitmask |= (1 << fanIndex);
        } else {
            sForceBitmask &= ~(1 << fanIndex);
        }
        NSString *hexVal = [NSString stringWithFormat:@"%04x", sForceBitmask];
        [smcWrapper setKey_external:@"FS! " value:hexVal];
    }
}

/// Apply saved per-fan RPM values to SMC (used on launch and wake).
/// Sets both forced mode + target speed (for real control) and minimum floor.
-(void)applyPerFanSettings {
    [FanControl setRights];
    for (int i = 0; i < g_numFans; i++) {
        int hwMin = [smcWrapper get_min_speed:i];
        int hwMax = [smcWrapper get_max_speed:i];
        if (hwMin <= 0) hwMin = 800;
        if (hwMax <= hwMin) hwMax = hwMin + 4000;

        NSString *prefKey = [NSString stringWithFormat:@"fan_%d_min_rpm", i];
        int savedRPM = (int)[[NSUserDefaults standardUserDefaults] integerForKey:prefKey];
        if (savedRPM < hwMin || savedRPM > hwMax) savedRPM = hwMin;

        // Set the minimum floor
        [smcWrapper setKey_external:[NSString stringWithFormat:@"F%dMn", i]
                              value:[@(savedRPM) tohex]];

        // If user has set a speed above the hardware minimum, force the fan
        if (savedRPM > hwMin) {
            [self setForcedMode:YES forFan:i];
            [smcWrapper setKey_external:[NSString stringWithFormat:@"F%dTg", i]
                                  value:[@(savedRPM) tohex]];
        } else {
            [self setForcedMode:NO forFan:i];
        }

        // Also update slider position if sliders exist
        if (i < (int)[_fanSliders count]) {
            [(NSSlider *)_fanSliders[i] setIntegerValue:savedRPM];
        }
        if (i < (int)[_fanRPMLabels count]) {
            [(NSTextField *)_fanRPMLabels[i] setStringValue:
                [NSString stringWithFormat:@"%d rpm", savedRPM]];
        }
    }
}

/// Update slider RPM labels with actual current fan speeds from SMC.
-(void)updateSliderRPMLabels {
    for (int i = 0; i < g_numFans && i < (int)[_fanRPMLabels count]; i++) {
        int actualRPM = [smcWrapper get_fan_rpm:i];
        NSTextField *label = _fanRPMLabels[i];
        [label setStringValue:[NSString stringWithFormat:@"%d rpm", actualRPM]];
    }
}


#pragma mark **Automatic Fan Curves**

// Control-loop tuning. The loop runs every kAutoCurveInterval seconds; the
// sensor temperature is smoothed with an exponential moving average
// (kAutoCurveEMAAlpha) so short load spikes don't spin the fans up, and a
// new RPM is only written to the SMC when it differs from the last written
// value by at least kAutoCurveDeadbandRPM, so the fans don't hunt.
static const NSTimeInterval kAutoCurveInterval = 5.0;
static const float kAutoCurveEMAAlpha = 0.35f;
static const int kAutoCurveDeadbandRPM = 75;

/// The fan's real hardware minimum. F0Mn is a writable register that this
/// app itself sets (slider, boot daemon, and formerly this loop), so reading
/// it back via get_min_speed cannot be trusted as the hardware floor — that
/// poisons the clamp and pins the fan at whatever was last written. The
/// machine-defaults snapshot was taken before anything wrote to the SMC.
-(int)trueMinSpeedForFan:(int)fanIndex {
    NSArray *fans = _machineDefaultsDict[@"Fans"];
    if ([fans isKindOfClass:[NSArray class]] && fanIndex < (int)[fans count]) {
        int v = [fans[fanIndex][PREF_FAN_MINSPEED] intValue];
        if (v > 0) return v;
    }
    int v = [smcWrapper get_min_speed:fanIndex];
    return (v > 0) ? v : 800;
}

/// Load per-fan curves from defaults, falling back to a conservative
/// default curve based on each fan's hardware limits.
-(void)loadFanCurves {
    _fanCurves = [NSMutableArray arrayWithCapacity:g_numFans];
    for (int i = 0; i < g_numFans; i++) {
        int hwMin = [self trueMinSpeedForFan:i];
        int hwMax = [smcWrapper get_max_speed:i];
        NSArray *saved = [defaults objectForKey:[NSString stringWithFormat:PREF_FAN_CURVE_FMT, i]];
        FanCurve *curve = saved ? [FanCurve curveWithPoints:saved] : nil;
        NSLog(@"autocurve: loadFanCurves fan=%d saved=%@ parsed=%@ hwMin=%d hwMax=%d", i, saved, curve, hwMin, hwMax);
        if (!curve) {
            curve = [FanCurve defaultCurveWithMinRPM:hwMin maxRPM:hwMax];
        }
        [_fanCurves addObject:curve];
    }
}

/// Start or stop the control loop to match PREF_AUTOCURVE_ENABLED.
-(void)updateAutoCurveState {
    BOOL enabled = [[defaults objectForKey:PREF_AUTOCURVE_ENABLED] boolValue];
    NSLog(@"autocurve: updateAutoCurveState enabled=%d timer=%p", enabled, _autoCurveTimer);
    if (enabled && !_autoCurveTimer) {
        [self loadFanCurves];
        _autoLastWrittenRPM = [NSMutableArray arrayWithCapacity:g_numFans];
        for (int i = 0; i < g_numFans; i++) {
            [_autoLastWrittenRPM addObject:@(-1)];
        }
        _autoHasSmoothedTemp = NO;
        // Repair the minimum-speed floor before taking control: a previous
        // session (or another fan tool) may have left F0Mn raised.
        [FanControl setRights];
        for (int i = 0; i < g_numFans; i++) {
            [smcWrapper setKey_external:[NSString stringWithFormat:@"F%dMn", i]
                                  value:[@([self trueMinSpeedForFan:i]) tohex]];
        }
        // NSRunLoopCommonModes: default-mode timers freeze while a modal
        // alert is up or the status menu is tracking — the control loop
        // must keep running through both.
        _autoCurveTimer = [NSTimer timerWithTimeInterval:kAutoCurveInterval
                                                  target:self
                                                selector:@selector(autoCurveTick:)
                                                userInfo:nil
                                                 repeats:YES];
        [_autoCurveTimer setTolerance:1.0];
        [[NSRunLoop currentRunLoop] addTimer:_autoCurveTimer forMode:NSRunLoopCommonModes];
        [_autoCurveTimer fire];
    } else if (!enabled && _autoCurveTimer) {
        [_autoCurveTimer invalidate];
        _autoCurveTimer = nil;
        // Hand control back to the user's saved per-fan settings.
        [self applyPerFanSettings];
    }
}

/// One iteration of the control loop: read the sensor, smooth it, map it
/// through each fan's curve, and write RPM targets that changed enough.
-(void)autoCurveTick:(id)caller {
    if (_machineDefaultsDict == nil || g_numFans <= 0) {
        NSLog(@"autocurve: tick skipped (defaults=%p fans=%d)", _machineDefaultsDict, g_numFans);
        return;
    }

    // Tolerate transient sensor failures, but never hold a forced RPM on a
    // sensor that's gone dark — after 3 consecutive failures hand the fans
    // back to SMC automatic control until reads recover.
    static int sBadReads = 0;
    float tempC = [smcWrapper get_maintemp];
    if (tempC <= 0.0f) {
        sBadReads++;
        NSLog(@"autocurve: tick skipped (bad temp %.1f, consecutive=%d)", tempC, sBadReads);
        if (sBadReads == 3) {
            NSLog(@"autocurve: sensor dark — releasing fans to SMC automatic control");
            [FanControl setRights];
            for (int i = 0; i < g_numFans; i++) {
                [self setForcedMode:NO forFan:i];
                _autoLastWrittenRPM[i] = @(-1);
            }
            _autoHasSmoothedTemp = NO;
        }
        return;
    }
    sBadReads = 0;
    if (!_autoHasSmoothedTemp) {
        _autoSmoothedTemp = tempC;
        _autoHasSmoothedTemp = YES;
    } else {
        _autoSmoothedTemp += kAutoCurveEMAAlpha * (tempC - _autoSmoothedTemp);
    }

    for (int i = 0; i < g_numFans && i < (int)[_fanCurves count]; i++) {
        FanCurve *curve = _fanCurves[i];
        int target = [curve rpmForTemperature:_autoSmoothedTemp];

        // Clamp to hardware limits — never below Apple's default minimum.
        // hwMin must come from the machine-defaults snapshot: F0Mn is
        // writable and reading it back here poisons the clamp (pins the
        // fan at whatever was last written).
        int hwMin = [self trueMinSpeedForFan:i];
        int hwMax = [smcWrapper get_max_speed:i];
        if (hwMax <= hwMin) hwMax = hwMin + 4000;
        if (target < hwMin) target = hwMin;
        if (target > hwMax) target = hwMax;

        int lastWritten = [_autoLastWrittenRPM[i] intValue];
        if (lastWritten >= 0 && abs(target - lastWritten) < kAutoCurveDeadbandRPM) {
            continue;
        }
        NSLog(@"autocurve: fan %d temp=%.1f smoothed=%.1f target=%d last=%d", i, tempC, _autoSmoothedTemp, target, lastWritten);

        [FanControl setRights];
        if (target <= hwMin) {
            // At the bottom of the curve let the SMC manage the fan itself.
            [self setForcedMode:NO forFan:i];
        } else {
            [self setForcedMode:YES forFan:i];
            [smcWrapper setKey_external:[NSString stringWithFormat:@"F%dTg", i]
                                  value:[@(target) tohex]];
        }
        _autoLastWrittenRPM[i] = @(target);
    }
}

/// Curves or the sensor selection changed (posted by the curve editor).
/// Reload and re-evaluate immediately: reset the deadband history so new
/// targets are written, and reseed the EMA in case the sensor changed.
-(void)fanCurvesChanged:(NSNotification *)note {
    if (!_autoCurveTimer) {
        return;
    }
    [self loadFanCurves];
    for (NSUInteger i = 0; i < [_autoLastWrittenRPM count]; i++) {
        _autoLastWrittenRPM[i] = @(-1);
    }
    _autoHasSmoothedTemp = NO;
    [self autoCurveTick:nil];
}

#pragma mark **Settings Window**

// Every pane is laid out on this canvas; the window is fixed-size and the
// panes are top-centered inside the tab area.
static const CGFloat kPaneWidth = 460.0;
static const CGFloat kPaneHeight = 640.0;

/// Host a fixed-size pane top-centered inside an auto-resizing container,
/// so the fixed window's tab area can be slightly larger than the pane.
-(NSView *)wrappedPane:(NSView *)pane {
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPaneWidth + 16, kPaneHeight + 8)];
    [container setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    NSRect f = [pane frame];
    f.origin.x = ([container frame].size.width - f.size.width) / 2.0;
    f.origin.y = [container frame].size.height - f.size.height;
    [pane setFrame:f];
    [pane setAutoresizingMask:(NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin)];
    [container addSubview:pane];
    return container;
}

/// Build the unified tabbed settings window. Fixed size, no per-tab
/// resizing. Everything reachable from the menu bar pull-down also lives
/// here: Status (live readings + manual sliders + menu bar toggle),
/// Fan Curves (editor + enable toggle), General (the nib preferences
/// content), Maintenance (Sleep/Wake Fix, OCLP boot daemon).
-(void)buildSettingsWindowIfNeeded {
    if (_settingsWindow) return;

    // Adopt the nib preferences content as the General tab.
    NSView *generalView = [(NSWindow *)mainwindow contentView];
    [(NSWindow *)mainwindow setContentView:[[NSView alloc] initWithFrame:NSZeroRect]];

    _settingsWindow = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, kPaneWidth + 40, kPaneHeight + 64)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [_settingsWindow setTitle:@"FanDynamics"];
    [_settingsWindow setReleasedWhenClosed:NO];

    _settingsTabs = [[NSTabView alloc] initWithFrame:[[_settingsWindow contentView] bounds]];
    [_settingsTabs setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_settingsTabs setDelegate:self];

    NSTabViewItem *statusTab = [[NSTabViewItem alloc] initWithIdentifier:@"status"];
    [statusTab setLabel:@"Status"];
    [statusTab setView:[self wrappedPane:[self buildStatusPane]]];
    [_settingsTabs addTabViewItem:statusTab];

    NSTabViewItem *curvesTab = [[NSTabViewItem alloc] initWithIdentifier:@"fancurves"];
    [curvesTab setLabel:@"Fan Curves"];
    [curvesTab setView:[self wrappedPane:[[CurveEditorController shared] editorView]]];
    [_settingsTabs addTabViewItem:curvesTab];

    NSTabViewItem *generalTab = [[NSTabViewItem alloc] initWithIdentifier:@"general"];
    [generalTab setLabel:@"General"];
    [generalTab setView:[self wrappedPane:generalView]];
    [_settingsTabs addTabViewItem:generalTab];

    NSTabViewItem *maintTab = [[NSTabViewItem alloc] initWithIdentifier:@"maintenance"];
    [maintTab setLabel:@"Maintenance"];
    [maintTab setView:[self wrappedPane:[self buildMaintenancePane]]];
    [_settingsTabs addTabViewItem:maintTab];

    [[_settingsWindow contentView] addSubview:_settingsTabs];
    [_settingsWindow center];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(settingsWindowWillClose:)
                                                 name:NSWindowWillCloseNotification
                                               object:_settingsWindow];
}

-(void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    if (tabView != _settingsTabs) return;
    NSString *ident = [tabViewItem identifier];
    if ([ident isEqualToString:@"fancurves"]) {
        [[CurveEditorController shared] prepareForDisplay];
    } else if ([ident isEqualToString:@"status"]) {
        [self refreshStatusPane];
    } else if ([ident isEqualToString:@"maintenance"]) {
        [self syncOCLPUI];
    }
}

-(void)openSettingsTab:(NSString *)identifier {
    [self buildSettingsWindowIfNeeded];
    // nil identifier → open on whatever tab was last selected.
    NSInteger idx = identifier ? [_settingsTabs indexOfTabViewItemWithIdentifier:identifier] : NSNotFound;
    if (idx != NSNotFound) {
        [_settingsTabs selectTabViewItemAtIndex:idx];
    }
    // The delegate only fires on a tab *change* — refresh the landing tab too.
    [self tabView:_settingsTabs didSelectTabViewItem:[_settingsTabs selectedTabViewItem]];
    if (!_statusTimer) {
        _statusTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                        target:self
                                                      selector:@selector(statusTimerTick:)
                                                      userInfo:nil
                                                       repeats:YES];
        [_statusTimer setTolerance:1.0];
    }
    // LSUIElement app — needs explicit activation since it has no Dock icon.
    [NSApp activateIgnoringOtherApps:YES];
    [_settingsWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

-(void)settingsWindowWillClose:(NSNotification *)note {
    [[CurveEditorController shared] displayDidHide];
    [_statusTimer invalidate];
    _statusTimer = nil;
}

#pragma mark **Status Pane**

-(NSTextField *)statusLabel:(NSString *)text frame:(NSRect)frame size:(CGFloat)fontSize bold:(BOOL)bold {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    [label setStringValue:text];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setFont:bold ? [NSFont boldSystemFontOfSize:fontSize] : [NSFont systemFontOfSize:fontSize]];
    return label;
}

/// Live readings (temp + per-fan RPM/target), the manual minimum-speed
/// sliders from the menu, and the menu bar readout toggle.
-(NSView *)buildStatusPane {
    NSView *pane = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPaneWidth, kPaneHeight)];
    NSColor *gray = nil;
    if (@available(macOS 10.14, *)) gray = [NSColor secondaryLabelColor];

    CGFloat y = kPaneHeight - 40;

    _statusSensorLabel = [self statusLabel:@"Temperature" frame:NSMakeRect(20, y, 420, 16) size:11 bold:NO];
    if (gray) [_statusSensorLabel setTextColor:gray];
    [pane addSubview:_statusSensorLabel];
    y -= 44;

    _statusTempLabel = [self statusLabel:@"—" frame:NSMakeRect(20, y, 420, 42) size:34 bold:YES];
    [pane addSubview:_statusTempLabel];
    y -= 34;

    _statusFanRPMLabels = [NSMutableArray array];
    _statusFanTargetLabels = [NSMutableArray array];
    _statusFanSliders = [NSMutableArray array];

    for (int i = 0; i < g_numFans; i++) {
        NSString *descr = [smcWrapper get_fan_descr:i];
        if ([descr length] == 0) descr = [NSString stringWithFormat:@"Fan %d", i];

        NSTextField *name = [self statusLabel:descr frame:NSMakeRect(20, y, 280, 16) size:11 bold:NO];
        if (gray) [name setTextColor:gray];
        [pane addSubview:name];
        y -= 26;

        NSTextField *rpm = [self statusLabel:@"—" frame:NSMakeRect(20, y, 200, 24) size:20 bold:YES];
        [pane addSubview:rpm];
        [_statusFanRPMLabels addObject:rpm];

        NSTextField *target = [self statusLabel:@"" frame:NSMakeRect(230, y + 2, 210, 16) size:11 bold:NO];
        if (gray) [target setTextColor:gray];
        [target setAlignment:NSTextAlignmentRight];
        [pane addSubview:target];
        [_statusFanTargetLabels addObject:target];
        y -= 40;
    }

    y -= 8;
    NSTextField *slidersHeader = [self statusLabel:@"Manual minimum speed" frame:NSMakeRect(20, y, 420, 16) size:11 bold:NO];
    if (gray) [slidersHeader setTextColor:gray];
    [pane addSubview:slidersHeader];
    y -= 30;

    for (int i = 0; i < g_numFans; i++) {
        int hwMin = [self trueMinSpeedForFan:i];
        int hwMax = [smcWrapper get_max_speed:i];
        if (hwMax <= hwMin) hwMax = hwMin + 4000;
        NSString *prefKey = [NSString stringWithFormat:@"fan_%d_min_rpm", i];
        int saved = (int)[defaults integerForKey:prefKey];
        if (saved < hwMin || saved > hwMax) saved = hwMin;

        NSTextField *name = [self statusLabel:[NSString stringWithFormat:@"Fan %d", i]
                                        frame:NSMakeRect(20, y, 60, 16) size:11 bold:NO];
        [pane addSubview:name];

        NSSlider *slider = [[NSSlider alloc] initWithFrame:NSMakeRect(84, y - 2, 270, 20)];
        [slider setMinValue:hwMin];
        [slider setMaxValue:hwMax];
        [slider setIntegerValue:saved];
        [slider setTag:i];
        [slider setContinuous:NO];
        [slider setTarget:self];
        [slider setAction:@selector(statusSliderChanged:)];
        [pane addSubview:slider];
        [_statusFanSliders addObject:slider];
        y -= 30;
    }

    _statusSliderHint = [self statusLabel:@"Sliders are disabled while automatic fan curves are on."
                                    frame:NSMakeRect(20, y, 420, 14) size:10 bold:NO];
    if (gray) [_statusSliderHint setTextColor:gray];
    [pane addSubview:_statusSliderHint];

    _statusMenuInfoCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(20, 20, 300, 20)];
    [_statusMenuInfoCheckbox setButtonType:NSButtonTypeSwitch];
    [_statusMenuInfoCheckbox setTitle:@"Show temp && RPM in menu bar"];
    [_statusMenuInfoCheckbox setTarget:self];
    [_statusMenuInfoCheckbox setAction:@selector(toggleMenuInfo:)];
    [pane addSubview:_statusMenuInfoCheckbox];

    [self syncStatusControls];
    return pane;
}

/// Slider on the Status tab moved: route through the shared handler (tag =
/// fan index), then reflect the resulting RPM in the readout.
-(void)statusSliderChanged:(id)sender {
    [self fanSliderChanged:sender];
    [self refreshStatusPane];
}

-(void)statusTimerTick:(id)caller {
    if (![_settingsWindow isVisible]) return;
    if (![[[_settingsTabs selectedTabViewItem] identifier] isEqualToString:@"status"]) return;
    [self refreshStatusPane];
}

-(void)refreshStatusPane {
    if (!_statusTempLabel) return;

    NSString *sensor = [defaults objectForKey:PREF_TEMPERATURE_SENSOR] ?: @"—";
    [_statusSensorLabel setStringValue:[NSString stringWithFormat:@"Temperature (%@)", sensor]];

    float tempC = [smcWrapper get_maintemp];
    BOOL useF;
    id unitPref = [defaults objectForKey:PREF_CURVE_EDITOR_FAHRENHEIT];
    if (unitPref) {
        useF = [unitPref boolValue];
    } else {
        NSString *tempUnit = [[NSLocale currentLocale] objectForKey:@"kCFLocaleTemperatureUnitKey"];
        useF = tempUnit ? [tempUnit isEqualToString:@"Fahrenheit"]
                        : ![[[NSLocale currentLocale] objectForKey:NSLocaleUsesMetricSystem] boolValue];
    }
    if (tempC > 0) {
        float shown = useF ? (tempC * 9.0f / 5.0f + 32.0f) : tempC;
        [_statusTempLabel setStringValue:[NSString stringWithFormat:@"%.1f °%@", shown, useF ? @"F" : @"C"]];
    } else {
        [_statusTempLabel setStringValue:@"—"];
    }

    BOOL autoOn = (_autoCurveTimer != nil);
    for (int i = 0; i < g_numFans && i < (int)[_statusFanRPMLabels count]; i++) {
        [(NSTextField *)_statusFanRPMLabels[i] setStringValue:
            [NSString stringWithFormat:@"%d rpm", [smcWrapper get_fan_rpm:i]]];
        NSString *targetText = @"manual / SMC automatic";
        if (autoOn) {
            int target = (i < (int)[_autoLastWrittenRPM count]) ? [_autoLastWrittenRPM[i] intValue] : -1;
            targetText = (target > 0)
                ? [NSString stringWithFormat:@"curve target: %d rpm", target]
                : @"curve active";
        }
        [(NSTextField *)_statusFanTargetLabels[i] setStringValue:targetText];
    }
    [self syncStatusControls];
}

/// Enable/disable the manual sliders based on auto-curve state and sync the
/// menu bar checkbox.
-(void)syncStatusControls {
    BOOL autoOn = [[defaults objectForKey:PREF_AUTOCURVE_ENABLED] boolValue];
    for (NSSlider *slider in _statusFanSliders) {
        [slider setEnabled:!autoOn];
    }
    [_statusSliderHint setHidden:!autoOn];
    [_statusMenuInfoCheckbox setState:
        ([[defaults objectForKey:PREF_MENU_DISPLAYMODE] intValue] != 2) ? NSOnState : NSOffState];
}

#pragma mark **Maintenance Pane**

/// Sleep/Wake Fix and (on OCLP Macs) the boot fan daemon toggle.
-(NSView *)buildMaintenancePane {
    NSView *pane = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPaneWidth, kPaneHeight)];
    NSColor *gray = nil;
    if (@available(macOS 10.14, *)) gray = [NSColor secondaryLabelColor];

    CGFloat y = kPaneHeight - 40;

    NSTextField *swHeader = [self statusLabel:@"Sleep/Wake" frame:NSMakeRect(20, y, 420, 16) size:11 bold:NO];
    if (gray) [swHeader setTextColor:gray];
    [pane addSubview:swHeader];
    y -= 22;

    NSTextField *swText = [self statusLabel:@"Fixes kernel panics on sleep for OCLP-patched Macs."
                                      frame:NSMakeRect(20, y, 420, 16) size:12 bold:NO];
    [pane addSubview:swText];
    y -= 34;

    NSButton *swButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 180, 28)];
    [swButton setTitle:@"Sleep/Wake Fix..."];
    [swButton setBezelStyle:NSBezelStyleRounded];
    [swButton setTarget:[SleepWakeFix class]];
    [swButton setAction:@selector(showFixWindowFromMenu:)];
    [pane addSubview:swButton];
    y -= 56;

    if ([OCLPHelper isOCLPMac]) {
        NSTextField *oclpHeader = [self statusLabel:@"Boot Fan Control" frame:NSMakeRect(20, y, 420, 16) size:11 bold:NO];
        if (gray) [oclpHeader setTextColor:gray];
        [pane addSubview:oclpHeader];
        y -= 22;

        NSTextField *oclpText = [self statusLabel:@"Applies fan settings at boot, before login (OCLP daemon)."
                                            frame:NSMakeRect(20, y, 420, 16) size:12 bold:NO];
        [pane addSubview:oclpText];
        y -= 30;

        _maintOCLPButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 300, 20)];
        [_maintOCLPButton setButtonType:NSButtonTypeSwitch];
        [_maintOCLPButton setTitle:@"Boot-time fan control enabled"];
        [_maintOCLPButton setTarget:self];
        [_maintOCLPButton setAction:@selector(toggleOCLPFromSettings:)];
        [pane addSubview:_maintOCLPButton];
        [self syncOCLPUI];
    }

    return pane;
}

-(void)toggleOCLPFromSettings:(id)sender {
    if ([OCLPHelper isDaemonInstalled]) {
        [OCLPHelper uninstallDaemon];
    } else {
        if (![OCLPHelper installDaemon]) {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Installation Failed"];
            [alert setInformativeText:@"Could not install the boot fan control daemon. Admin access may be required."];
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
        }
    }
    [self syncOCLPUI];
}

/// Sync the maintenance checkbox with the actual daemon state.
-(void)syncOCLPUI {
    [_maintOCLPButton setState:[OCLPHelper isDaemonInstalled] ? NSOnState : NSOffState];
}

/// Menu action: open the settings window on the Fan Curves tab.
-(void)openCurveEditor:(id)sender {
    [self openSettingsTab:@"fancurves"];
}

/// Menu action: toggle the temp + RPM readout next to the menu bar icon.
/// Flips between display mode 1 (temp + rpm) and 2 (icon only); modes 3/4
/// (temp-only / rpm-only, set via Preferences) count as "on" and toggle off.
-(void)toggleMenuInfo:(id)sender {
    int mode = [[defaults objectForKey:PREF_MENU_DISPLAYMODE] intValue];
    int newMode = (mode == 2) ? 1 : 2;
    [defaults setObject:@(newMode) forKey:PREF_MENU_DISPLAYMODE];
    // Re-arms the read timer for the new mode and fires it, refreshing the display.
    [self updateTimerForDisplayMode:newMode];
    // Sync both surfaces (menu item + Status tab checkbox) from the pref.
    [[theMenu itemWithTag:9902] setState:(newMode != 2) ? NSOnState : NSOffState];
    [self syncStatusControls];
}

/// Menu action: toggle automatic fan curves on/off. The settings checkbox
/// flips the same pref; both surfaces converge in autoCurveStateChanged:.
-(void)toggleAutoCurves:(id)sender {
    BOOL enabled = ![[defaults objectForKey:PREF_AUTOCURVE_ENABLED] boolValue];
    [defaults setObject:@(enabled) forKey:PREF_AUTOCURVE_ENABLED];
    [[NSNotificationCenter defaultCenter] postNotificationName:NOTE_AUTOCURVE_STATE_CHANGED object:nil];
}

/// The enabled pref changed from any UI: start/stop the loop and resync
/// the menu checkmark and the settings checkbox.
-(void)autoCurveStateChanged:(NSNotification *)note {
    [self updateAutoCurveState];
    BOOL enabled = [[defaults objectForKey:PREF_AUTOCURVE_ENABLED] boolValue];
    [[theMenu itemWithTag:9901] setState:enabled ? NSOnState : NSOffState];
    [[CurveEditorController shared] syncEnableState];
    [self syncStatusControls]; // manual sliders disable while the loop runs
}

/// Menu action: open the settings window on its last-selected tab
/// (Status, the dashboard, on first open).
- (void)openPreferences:(id)sender {
    [self openSettingsTab:nil];
}

#pragma mark **Action-Methods**
- (IBAction)loginItem:(id)sender{
	if ([sender state]==NSOnState) {
		[self setStartAtLogin:YES];
	} else {
        [self setStartAtLogin:NO];
	}
}

- (IBAction)add_favorite:(id)sender{
	[[NSApplication sharedApplication] beginSheet:newfavoritewindow
								   modalForWindow: mainwindow
									modalDelegate: nil
								   didEndSelector: nil
									  contextInfo: nil];
}

- (IBAction)close_favorite:(id)sender{
	[newfavoritewindow close];
	[[NSApplication sharedApplication] endSheet:newfavoritewindow];
}

- (IBAction)save_favorite:(id)sender{
	MachineDefaults *msdefaults=[[MachineDefaults alloc] init:nil];
	if ([[newfavorite_title stringValue] length]>0) {
		NSMutableDictionary *toinsert=[[NSMutableDictionary alloc] initWithObjectsAndKeys:[newfavorite_title stringValue],@"Title",[msdefaults get_machine_defaults][@"Fans"],PREF_FAN_ARRAY,nil]; //default as template
		[toinsert setValue:@0 forKey:@"Standard"];
		[FavoritesController addObject:toinsert];
		[newfavoritewindow close];
		[[NSApplication sharedApplication] endSheet:newfavoritewindow];
	}
	[self upgradeFavorites];
}


-(void) check_deletion:(id)combo{
 if ([FavoritesController selectionIndex]==[[defaults objectForKey:combo] intValue]) {
	 [defaults setObject:@0 forKey:combo];
 }
}



- (void) deleteAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
{
    if (returnCode==NSAlertSecondButtonReturn) {
		//delete favorite, but resets presets before
		[self check_deletion:PREF_BATTERY_SELECTION];
		[self check_deletion:PREF_AC_SELECTION];
		[self check_deletion:PREF_CHARGING_SELECTION];
        [FavoritesController removeObjects:[FavoritesController selectedObjects]];
	}
}

- (IBAction)delete_favorite:(id)sender{
	
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedString(@"Delete favorite",nil)];
    [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Do you really want to delete the favorite %@?",nil), [FavoritesController arrangedObjects][[FavoritesController selectionIndex]][@"Title"]]];
    [alert addButtonWithTitle:NSLocalizedString(@"No",nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Yes",nil)];
    
    [alert beginSheetModalForWindow:mainwindow modalDelegate:self didEndSelector:@selector(deleteAlertDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}


// Called via a timer mechanism. This is where all the temp / RPM reading is done.
//reads fan data and updates the gui
-(void) readFanData:(id)caller{
	
    int i = 0;
	
	//on init handling
	if (_machineDefaultsDict==nil) {
		return;
	}
    
    // Determine what data is actually needed to keep the energy impact
    // as low as possible.
    bool bNeedTemp = false;
    bool bNeedRpm = false;
    const int menuBarSetting = [[defaults objectForKey:PREF_MENU_DISPLAYMODE] intValue];
    switch (menuBarSetting) {
        default:
        case 1:
            bNeedTemp = true;
            bNeedRpm = true;
            break;

        case 2:
            // Icon only — no SMC reads needed for display.
            bNeedTemp = false;
            bNeedRpm = false;
            break;

        case 3:
            bNeedTemp = true;
            bNeedRpm = false;
            break;

        case 4:
            bNeedTemp = false;
            bNeedRpm = true;
            break;
    }

    NSString *temp = nil;
	NSString *fan = nil;
    float c_temp = 0.0f;
    int selectedRpm = 0;
    
    if (bNeedRpm == true) {
        // Read the current fan speed for fan 0 (primary) for display in the menubar.
        if (g_numFans > 0) {
            selectedRpm = [smcWrapper get_fan_rpm:0];
        }
        
        NSNumberFormatter *nc=[[NSNumberFormatter alloc] init];
        //avoid jumping in menu bar
        [nc setFormat:@"000;000;-000"];
        
        fan = [NSString stringWithFormat:@"%@rpm",[nc stringForObjectValue:[NSNumber numberWithFloat:selectedRpm]]];
    }
    
    if (bNeedTemp == true) {
        // Read current temperature and format text for the menubar.
        c_temp = [smcWrapper get_maintemp];
        
        // Detect temperature unit from system locale (no user preference).
        BOOL useFahrenheit;
        {
            NSString *tempUnit = [[NSLocale currentLocale] objectForKey:@"kCFLocaleTemperatureUnitKey"];
            if (tempUnit) {
                useFahrenheit = [tempUnit isEqualToString:@"Fahrenheit"];
            } else {
                useFahrenheit = ![[[NSLocale currentLocale] objectForKey:NSLocaleUsesMetricSystem] boolValue];
            }
        }
        if (!useFahrenheit) {
            temp = [NSString stringWithFormat:@"%@%CC",@(c_temp),(unsigned short)0xb0];
        } else {
            NSNumberFormatter *ncf=[[NSNumberFormatter alloc] init];
            [ncf setFormat:@"00;00;-00"];
            temp = [NSString stringWithFormat:@"%@%CF",[ncf stringForObjectValue:[@(c_temp) celsius_fahrenheit]],(unsigned short)0xb0];
        }
    }
    
    // Update the temp and/or fan speed text in the menubar.
    NSMutableAttributedString *s_status = nil;
    NSMutableParagraphStyle *paragraphStyle = nil;
    
    NSColor *menuColor = nil;
    BOOL setColor = NO;
    if (@available(macOS 10.14, *)) {
        // Use system label color that automatically adapts to dark/light mode
        menuColor = [NSColor labelColor];
        setColor = YES;
    } else {
        menuColor = (NSColor*)[NSKeyedUnarchiver unarchivedObjectOfClass:[NSColor class] fromData:[defaults objectForKey:PREF_MENU_TEXTCOLOR] error:nil];
        if (!([[menuColor colorUsingColorSpaceName:
                  NSCalibratedWhiteColorSpace] whiteComponent] == 0.0) || ![statusItem respondsToSelector:@selector(button)]) setColor = YES;

        NSString *osxMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"];
        if (osxMode && !setColor) {
            menuColor = [NSColor whiteColor];
            setColor = YES;
        }
    }
    
    switch (menuBarSetting) {
        default:
        case 1: {
            int fsize = 0;
            NSString *add = nil;
            if (menuBarSetting==0) {
                add=@"\n";
                fsize=9;
                [statusItem setLength:73];
            } else {
                add=@" ";
                fsize=11;
                [statusItem setLength:116];
            }

            s_status=[[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@%@%@",temp,add,fan]];
            paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
            [paragraphStyle setAlignment:NSLeftTextAlignment];
            NSFont *menuFont;
            if (@available(macOS 10.15, *)) {
                menuFont = [NSFont monospacedSystemFontOfSize:fsize weight:NSFontWeightMedium];
            } else {
                menuFont = [NSFont systemFontOfSize:fsize];
            }
            [s_status addAttribute:NSFontAttributeName value:menuFont range:NSMakeRange(0,[s_status length])];
            [s_status addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:NSMakeRange(0,[s_status length])];

            if (setColor) [s_status addAttribute:NSForegroundColorAttributeName value:menuColor  range:NSMakeRange(0,[s_status length])];


            if ([statusItem respondsToSelector:@selector(button)]) {
                [statusItem.button setAttributedTitle:s_status];
                [statusItem.button setImage:menu_image];
                [statusItem.button setImagePosition:NSImageLeft];
            } else {
                [statusItem setAttributedTitle:s_status];
                [statusItem setImage:menu_image];
            }
            break;
        }

        case 2:
            // Icon only — show the icon with no text and no tooltip.
            // No SMC reads are performed in this mode to minimize energy impact.
            [statusItem setLength:26];
            if ([statusItem respondsToSelector:@selector(button)]) {
                [statusItem.button setTitle:nil];
                [statusItem.button setToolTip:nil];
                [statusItem.button setImage:menu_image];
                [statusItem.button setAlternateImage:menu_image_alt];
            } else {
                [statusItem setTitle:nil];
                [statusItem setToolTip:nil];
                [statusItem setImage:menu_image];
                [statusItem setAlternateImage:menu_image_alt];
            }
            break;

        case 3:
            [statusItem setLength:66];
            s_status=[[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@",temp]];
            {
                NSFont *tempFont;
                if (@available(macOS 10.15, *)) {
                    tempFont = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightMedium];
                } else {
                    tempFont = [NSFont systemFontOfSize:12];
                }
                [s_status addAttribute:NSFontAttributeName value:tempFont range:NSMakeRange(0,[s_status length])];
            }
            if (setColor) [s_status addAttribute:NSForegroundColorAttributeName value:menuColor  range:NSMakeRange(0,[s_status length])];
            if ([statusItem respondsToSelector:@selector(button)]) {
                [statusItem.button setAttributedTitle:s_status];
                [statusItem.button setImage:menu_image];
                [statusItem.button setImagePosition:NSImageLeft];
            } else {
                [statusItem setAttributedTitle:s_status];
                [statusItem setImage:menu_image];
            }
            break;

        case 4:
            [statusItem setLength:85];
            s_status=[[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@",fan]];
            {
                NSFont *rpmFont;
                if (@available(macOS 10.15, *)) {
                    rpmFont = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightMedium];
                } else {
                    rpmFont = [NSFont systemFontOfSize:12];
                }
                [s_status addAttribute:NSFontAttributeName value:rpmFont range:NSMakeRange(0,[s_status length])];
            }
            if (setColor) [s_status addAttribute:NSForegroundColorAttributeName value:menuColor  range:NSMakeRange(0,[s_status length])];
            if ([statusItem respondsToSelector:@selector(button)]) {
                [statusItem.button setAttributedTitle:s_status];
                [statusItem.button setImage:menu_image];
                [statusItem.button setImagePosition:NSImageLeft];
            } else {
                [statusItem setAttributedTitle:s_status];
                [statusItem setImage:menu_image];
            }
            break;
    }
    
}


- (IBAction)savePreferences:(id)sender{
	[(NSUserDefaultsController *)DefaultsController save:sender];
	[defaults synchronize];
	[_settingsWindow ? _settingsWindow : mainwindow close];
	[self applyPerFanSettings];
	[OCLPHelper syncFanSettingsWithDaemon];
	undo_dic=[NSDictionary dictionaryWithDictionary:[defaults dictionaryRepresentation]];
}



- (IBAction)closePreferences:(id)sender{
	[_settingsWindow ? _settingsWindow : mainwindow close];
	[DefaultsController revert:sender];
	// Restore timer interval in case user changed display mode then cancelled.
	[self updateTimerForDisplayMode:[[defaults objectForKey:PREF_MENU_DISPLAYMODE] intValue]];
}

//set the new fan settings

-(void)apply_settings:(id)sender controllerindex:(int)cIndex{
	int i;
	[FanControl setRights];
	[FavoritesController setSelectionIndex:cIndex];
    
    for (i=0;i<[[FavoritesController arrangedObjects][cIndex][PREF_FAN_ARRAY] count];i++) {
        int fan_mode = [smcWrapper get_mode:i];
        // Auto/forced mode is not available
        if (fan_mode < 0) {
            [smcWrapper setKey_external:[NSString stringWithFormat:@"F%dMn",i] value:[[FanController arrangedObjects][i][PREF_FAN_SELSPEED] tohex]];
        } else {
            bool is_auto = [[FanController arrangedObjects][i][PREF_FAN_AUTO] boolValue];
            [smcWrapper setKey_external:[NSString stringWithFormat:@"F%dMd",i] value:is_auto ? @"00" : @"01"];
            float f_val = [[FanController arrangedObjects][i][PREF_FAN_SELSPEED] floatValue];
            uint8 *vals = (uint8*)&f_val;
            //NSString str_val = ;
            [smcWrapper setKey_external:[NSString stringWithFormat:@"F%dTg",i] value:[NSString stringWithFormat:@"%02x%02x%02x%02x",vals[0],vals[1],vals[2],vals[3]]];
        }
    }
    
	NSMenu *submenu = [[NSMenu alloc] init];
	
	for(i=0;i<[[FavoritesController arrangedObjects] count];i++){
		NSMenuItem *submenuItem = [[NSMenuItem alloc] initWithTitle:[FavoritesController arrangedObjects][i][@"Title"] action:@selector(apply_quickselect:) keyEquivalent:@""];
		[submenuItem setTag:i*100]; //for later manipulation
		[submenuItem setEnabled:YES];
		[submenuItem setTarget:self];
		[submenuItem setRepresentedObject:[FavoritesController arrangedObjects][i]];
		[submenu addItem:submenuItem];
	}
	
	[[theMenu itemWithTag:1] setSubmenu:submenu];
	for (i=0;i<[[[theMenu itemWithTag:1] submenu] numberOfItems];i++) {
		[[[[theMenu itemWithTag:1] submenu] itemAtIndex:i] setState:NSOffState];
	}
	[[[[theMenu itemWithTag:1] submenu] itemAtIndex:cIndex] setState:NSOnState];
	[defaults setObject:@(cIndex) forKey:PREF_SELECTION_DEFAULT];
	//change active setting display
	[[theMenu itemWithTag:1] setTitle:[NSString stringWithFormat:@"%@: %@",NSLocalizedString(@"Active Setting",nil),[FavoritesController arrangedObjects][[FavoritesController selectionIndex]][PREF_FAN_TITLE] ]];
}



-(void)apply_quickselect:(id)sender{
	int i;
	[FanControl setRights];
	//set all others items to off
	for (i=0;i<[[[theMenu itemWithTag:1] submenu] numberOfItems];i++) {
		[[[[theMenu itemWithTag:1] submenu] itemAtIndex:i] setState:NSOffState];
	}
	[sender setState:NSOnState];
	[[theMenu itemWithTag:1] setTitle:[NSString stringWithFormat:@"%@: %@",NSLocalizedString(@"Active Setting",nil),[sender title]]];
	[self apply_settings:sender controllerindex:[[[theMenu itemWithTag:1] submenu] indexOfItem:sender]];
}


-(void)terminate:(id)sender{
	//get last active selection
	[defaults synchronize];
	// Return all fans to automatic mode on quit (unless OCLP daemon will manage them)
	if (![OCLPHelper isDaemonInstalled]) {
		[FanControl setRights];
		for (int i = 0; i < g_numFans; i++) {
			[self setForcedMode:NO forFan:i];
		}
	}
	[smcWrapper cleanUp];
	[_readTimer invalidate];
	[_autoCurveTimer invalidate];
	[pw deregisterForSleepWakeNotification];
	[pw deregisterForPowerChange];
	[[NSApplication sharedApplication] terminate:self];
}



- (IBAction)syncSliders:(id)sender{
	if ([sender state]) {
		[self syncBinder:YES];
	} else {
		[self syncBinder:NO];
	}
}


- (IBAction) changeMenu:(id)sender{
	int mode = [[[[NSUserDefaultsController sharedUserDefaultsController] values] valueForKey:PREF_MENU_DISPLAYMODE] intValue];
	if (mode == 2) {
		// Icon only — disable color selector and slow the polling timer to 60s.
		[colorSelector setEnabled:NO];
		[self updateTimerForDisplayMode:2];
	} else {
		[colorSelector setEnabled:YES];
		[self updateTimerForDisplayMode:mode];
	}

}

/// Adjust the polling timer interval based on the display mode.
/// Icon-only mode (2) uses a 60-second interval since no data is displayed.
/// All other modes use a 4-second interval to keep the menubar current.
- (void)updateTimerForDisplayMode:(int)mode {
	NSTimeInterval desired = (mode == 2) ? 60.0 : 4.0;
	if (_readTimer && [_readTimer timeInterval] == desired) return;
	[_readTimer invalidate];
	_readTimer = [NSTimer scheduledTimerWithTimeInterval:desired target:self selector:@selector(readFanData:) userInfo:nil repeats:YES];
	if ([_readTimer respondsToSelector:@selector(setTolerance:)]) {
		[_readTimer setTolerance:(mode == 2) ? 10.0 : 2.0];
	}
	[_readTimer fire];
}

- (IBAction)menuSelect:(id)sender{
	//deactivate all other radio buttons
	int i;
	for (i=0;i<[[FanController arrangedObjects] count];i++) {
		if (i!=[sender selectedRow]) {
			[[FanController arrangedObjects][i] setValue:@NO forKey:PREF_FAN_SHOWMENU];
		}	
	}
}

// Called when user clicks on smcFanControl status bar item.
// Update the RPM labels in the slider views with actual fan speeds.
- (void)menuNeedsUpdate:(NSMenu*)menu {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (theMenu == menu) {
            [self updateSliderRPMLabels];
        }
    });
}



#pragma mark **Helper-Methods**

//just a helper to bringt update-info-window to the front
-(IBAction)visitHomepage:(id)sender{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://wolffcatskyy.dev/smcfancontrol"]];
}

- (IBAction)updateCheck:(id)sender{
    // TODO: Implement GitHub Releases-based update check
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Check for Updates"];
    [alert setInformativeText:@"Visit the GitHub releases page to check for updates."];
    [alert addButtonWithTitle:@"Open GitHub"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/wolffcatskyy/smcFanControl/releases"]];
    }
}


-(void)performReset
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSError *error;
    NSString *machinesPath = [[fileManager applicationSupportDirectory] stringByAppendingPathComponent:@"Machines.plist"];
    [fileManager removeItemAtPath:machinesPath error:&error];
    if (error) {
        NSLog(@"Error deleting %@",machinesPath);
    }
    error = nil;
    // Return all fans to automatic mode on reset
    for (int i=0; i<g_numFans; i++) {
        [self setForcedMode:NO forFan:i];
    }

    NSString *domainName = [[NSBundle mainBundle] bundleIdentifier];
    [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:domainName];
    
    
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedString(@"Shutdown required",nil)];
    [alert setInformativeText:NSLocalizedString(@"Please shutdown your computer now to return to default fan settings.",nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"OK",nil)];
    NSModalResponse code=[alert runModal];
    if (code == NSAlertFirstButtonReturn) {
        [[NSApplication sharedApplication] terminate:self];
    }
}

- (IBAction)resetSettings:(id)sender
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedString(@"Reset Settings",nil)];
    [alert setInformativeText:NSLocalizedString(@"Do you want to reset smcFanControl to default settings? Favorites will be deleted and fans will return to default speed.",nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Yes",nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"No",nil)];
    NSModalResponse code=[alert runModal];
    if (code == NSAlertFirstButtonReturn) {
        [self performReset];
    }

}

-(void) syncBinder:(Boolean)bind{
	//in case plist is corrupt, don't bind
	if ([[FanController arrangedObjects] count]>1 ) {
		if (bind==YES) {
			[[FanController arrangedObjects][1] bind:PREF_FAN_SELSPEED toObject:[FanController arrangedObjects][0] withKeyPath:PREF_FAN_SELSPEED options:nil];
			[[FanController arrangedObjects][0] bind:PREF_FAN_SELSPEED toObject:[FanController arrangedObjects][1] withKeyPath:PREF_FAN_SELSPEED options:nil];
		} else {
			[[FanController arrangedObjects][1] unbind:PREF_FAN_SELSPEED];
			[[FanController arrangedObjects][0] unbind:PREF_FAN_SELSPEED];
		}
	}	
}


#pragma mark **Power Watchdog-Methods**

- (void)systemWillSleep:(id)sender{
}

- (void)systemDidWakeFromSleep:(id)sender{
	[self applyPerFanSettings];
}


- (void)powerChangeToBattery:(id)sender{
	// With simplified slider UI, just re-apply the saved per-fan settings.
	[self applyPerFanSettings];
}

- (void)powerChangeToAC:(id)sender{
	[self applyPerFanSettings];
}

- (void)powerChangeToACLoading:(id)sender{
	[self applyPerFanSettings];
}


#pragma mark -
#pragma mark Start-at-login control

- (BOOL)isInAutoStart
{
	BOOL found = NO;
	LSSharedFileListRef loginItems = LSSharedFileListCreate(kCFAllocatorDefault, kLSSharedFileListSessionLoginItems, /*options*/ NULL);
	NSString *path = [[NSBundle mainBundle] bundlePath];
	CFURLRef URLToToggle = (__bridge CFURLRef)[NSURL fileURLWithPath:path];
	//LSSharedFileListItemRef existingItem = NULL;
	
	UInt32 seed = 0U;
    NSArray *currentLoginItems = CFBridgingRelease(LSSharedFileListCopySnapshot(loginItems, &seed));
	
	for (id itemObject in currentLoginItems) {
		LSSharedFileListItemRef item = (__bridge LSSharedFileListItemRef)itemObject;
		
		UInt32 resolutionFlags = kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes;
		CFURLRef URL = NULL;
		OSStatus err = LSSharedFileListItemResolve(item, resolutionFlags, &URL, /*outRef*/ NULL);
		if (err == noErr) {
			Boolean foundIt = CFEqual(URL, URLToToggle);
			CFRelease(URL);
			
			if (foundIt) {
				//existingItem = item;
				found = YES;
				break;
			}
		}
	}
	return found;
}

- (void) setStartAtLogin:(BOOL)enabled {
    
	LSSharedFileListRef loginItems = LSSharedFileListCreate(kCFAllocatorDefault, kLSSharedFileListSessionLoginItems, /*options*/ NULL);
    
	
	NSString *path = [[NSBundle mainBundle] bundlePath];
	
	OSStatus status;
	CFURLRef URLToToggle = (__bridge CFURLRef)[NSURL fileURLWithPath:path];
	LSSharedFileListItemRef existingItem = NULL;
	
	UInt32 seed = 0U;
    NSArray *currentLoginItems = CFBridgingRelease(LSSharedFileListCopySnapshot(loginItems, &seed));
	
	for (id itemObject in currentLoginItems) {
		LSSharedFileListItemRef item = (__bridge LSSharedFileListItemRef)itemObject;
		
		UInt32 resolutionFlags = kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes;
		CFURLRef URL = NULL;
		OSStatus err = LSSharedFileListItemResolve(item, resolutionFlags, &URL, /*outRef*/ NULL);
		if (err == noErr) {
			Boolean foundIt = CFEqual(URL, URLToToggle);
			CFRelease(URL);
			
			if (foundIt) {
				existingItem = item;
				break;
			}
		}
	}
	
	if (enabled && (existingItem == NULL)) {
		NSString *displayName = [[NSFileManager defaultManager] displayNameAtPath:path];
		IconRef icon = NULL;
		FSRef ref;
		Boolean gotRef = CFURLGetFSRef(URLToToggle, &ref);
		if (gotRef) {
			status = GetIconRefFromFileInfo(&ref,
											/*fileNameLength*/ 0, /*fileName*/ NULL,
											kFSCatInfoNone, /*catalogInfo*/ NULL,
											kIconServicesNormalUsageFlag,
											&icon,
											/*outLabel*/ NULL);
			if (status != noErr)
				icon = NULL;
		}
		
		LSSharedFileListInsertItemURL(loginItems, kLSSharedFileListItemBeforeFirst, (__bridge CFStringRef)displayName, icon, URLToToggle, /*propertiesToSet*/ NULL, /*propertiesToClear*/ NULL);
	} else if (!enabled && (existingItem != NULL))
		LSSharedFileListItemRemove(loginItems, existingItem);
}


/// Check if the smc binary already has correct owner (root), group (admin), and
/// setuid/setgid permissions (octal 6555 = decimal 3437).
+(BOOL)smcBinaryHasCorrectPermissions {
	NSString *smcpath = [[NSBundle mainBundle] pathForResource:@"smc" ofType:@""];
	if (!smcpath) return NO;

	NSFileManager *fmanage = [NSFileManager defaultManager];
	NSDictionary *fdic = [fmanage attributesOfItemAtPath:smcpath error:nil];
	if (!fdic) return NO;

	BOOL ownerIsRoot = [[fdic valueForKey:@"NSFileOwnerAccountName"] isEqualToString:@"root"];
	BOOL groupIsAdmin = [[fdic valueForKey:@"NSFileGroupOwnerAccountName"] isEqualToString:@"admin"];
	BOOL permsCorrect = ([[fdic valueForKey:@"NSFilePosixPermissions"] intValue] == 3437);

	return (ownerIsRoot && groupIsAdmin && permsCorrect);
}

+(void) checkRightStatus:(OSStatus) status
{
    if (status != errAuthorizationSuccess) {
        // If authorization failed but the binary already has correct permissions
        // (e.g. pre-set during build/install), skip the fatal error.
        // AuthorizationExecuteWithPrivileges is deprecated and fails with
        // errAuthorizationDenied (-60007) on modern macOS even with lowered SIP.
        if ([self smcBinaryHasCorrectPermissions]) {
            NSLog(@"smcFanControl: Authorization returned %d but smc binary already has correct permissions — continuing.", (int)status);
            return;
        }

        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Authorization failed"];
        [alert setInformativeText:[NSString stringWithFormat:@"Authorization failed with code %d. The smc binary needs to be owned by root:admin with setuid permissions (6555). You can fix this manually:\n\nsudo chown root:admin <path-to-smc>\nsudo chmod 6555 <path-to-smc>",status]];
        [alert addButtonWithTitle:@"Quit"];
        [alert setAlertStyle:NSAlertStyleCritical];
        NSInteger result = [alert runModal];

        if (result == NSAlertFirstButtonReturn) {
            [[NSApplication sharedApplication] terminate:self];
        }
    }
}

#pragma mark **SMC-Binary Owner/Right Check**
//call smc binary with sudo rights and apply
+(void)setRights{
	// First check: if the binary already has correct permissions, skip authorization entirely.
	// This avoids calling the deprecated AuthorizationExecuteWithPrivileges, which fails
	// with errAuthorizationDenied (-60007) on modern macOS.
	if ([self smcBinaryHasCorrectPermissions]) {
		return;
	}

	NSString *smcpath = [[NSBundle mainBundle] pathForResource:@"smc" ofType:@""];
	if (!smcpath) {
		NSLog(@"smcFanControl: Could not find smc binary in bundle Resources.");
		return;
	}

	NSLog(@"smcFanControl: smc binary does not have correct permissions, attempting to fix...");

	// Try AuthorizationExecuteWithPrivileges (deprecated but may work on older macOS / lowered SIP).
	FILE *commPipe;
	AuthorizationRef authorizationRef;
	AuthorizationItem gencitem = { "system.privilege.admin", 0, NULL, 0 };
	AuthorizationRights gencright = { 1, &gencitem };
	int flags = kAuthorizationFlagExtendRights | kAuthorizationFlagInteractionAllowed;
	OSStatus status = AuthorizationCreate(&gencright, kAuthorizationEmptyEnvironment, flags, &authorizationRef);

	[self checkRightStatus:status];

	NSString *tool = @"/usr/sbin/chown";
	NSArray *argsArray = @[@"root:admin", smcpath];
	int i;
	char *args[255];
	for(i = 0; i < [argsArray count]; i++){
		args[i] = (char *)[argsArray[i] UTF8String];
	}
	args[i] = NULL;
	status = AuthorizationExecuteWithPrivileges(authorizationRef, [tool UTF8String], 0, args, &commPipe);

	[self checkRightStatus:status];

	// Second call for suid-bit
	tool = @"/bin/chmod";
	argsArray = @[@"6555", smcpath];
	for(i = 0; i < [argsArray count]; i++){
		args[i] = (char *)[argsArray[i] UTF8String];
	}
	args[i] = NULL;
	status = AuthorizationExecuteWithPrivileges(authorizationRef, [tool UTF8String], 0, args, &commPipe);

	[self checkRightStatus:status];
}


-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
}

@end




@implementation NSNumber (NumberAdditions)

- (NSString*) tohex{
	return [NSString stringWithFormat:@"%0.4x",[self intValue]<<2];
}


- (NSNumber*) celsius_fahrenheit{
	float celsius=[self floatValue];
	float fahrenheit=(celsius*9)/5+32;
	return @(fahrenheit);
}

@end



